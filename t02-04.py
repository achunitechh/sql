from datetime import datetime, timedelta
print("[1] 正在匯入必要的模組...")
import pymysql
import random
import time
from faker import Faker

"""
單元四：五百萬級數據生成腳本 (包含使用者與商品表)
功能：
1. 自動建立 users、products、orders_partitioned 三張表。
2. 預先生成基礎數據，並在 orders_partitioned 中實現邏輯關聯。
3. 批量寫入 5,000,000 筆訂單資料。
"""

# 資料庫連線設定
DB_CONFIG = {
    'host': '10.167.223.49',
    'port': 3306,
    'user': 'mydba',
    'password': 'Letmepasslala@123',
    'database': 'ecommerce',
    'charset': 'utf8mb4'
}

# 初始化 Faker
fake = Faker()

def create_partitioned_table(cursor):
    print("正在建立所有資料表 (users, products, orders_partitioned)...")
    
    # 依照關聯順序刪除舊表
    cursor.execute("DROP TABLE IF EXISTS orders_partitioned")
    cursor.execute("DROP TABLE IF EXISTS users")
    cursor.execute("DROP TABLE IF EXISTS products")
    
    # 建立使用者表
    cursor.execute("""
    CREATE TABLE users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        email VARCHAR(255) NOT NULL UNIQUE,
        name VARCHAR(100) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB;
    """)
    
    # 建立商品表
    cursor.execute("""
    CREATE TABLE products (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        price DECIMAL(10, 2) NOT NULL,
        stock INT DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) ENGINE=InnoDB;
    """)
    
    # 建立訂單分區表 (包含你新增的所有欄位與關聯欄位)
    sql = """
    CREATE TABLE orders_partitioned (
        id INT AUTO_INCREMENT,
        user_id INT NOT NULL,                  -- 邏輯關聯 users.id
        product_id INT NOT NULL,               -- 邏輯關聯 products.id
        customer_name VARCHAR(50),
        amount DECIMAL(10, 2),                 -- 這裡代表單筆購買的總金額 (單價 * 數量)
        quantity INT NOT NULL DEFAULT 1,       -- 新增欄位
        status ENUM('PENDING', 'PAID', 'SHIPPED', 'CANCELLED') DEFAULT 'PENDING', -- 新增欄位
        price_at_purchase DECIMAL(10, 2) NOT NULL, -- 新增欄位
        order_date DATETIME NOT NULL,
        address VARCHAR(100),
        PRIMARY KEY (id, order_date) -- 注意：分區鍵必須包含在主鍵內
    )
    PARTITION BY RANGE (YEAR(order_date)) (
        PARTITION p2023 VALUES LESS THAN (2023),
        PARTITION p2024 VALUES LESS THAN (2024),
        PARTITION p2025 VALUES LESS THAN (2025),
        PARTITION p_future VALUES LESS THAN MAXVALUE
    );
    """
    cursor.execute(sql)

def generate_data(total_rows=5000000): # 這裡直接設為 5,000,000 筆
    conn = pymysql.connect(**DB_CONFIG)
    cursor = conn.cursor()
    
    try:
        # === 階段 1: 建立資料表 ===
        table_start = time.time()
        create_partitioned_table(cursor)
        conn.commit()
        table_time = time.time() - table_start
        print(f"✓ 資料表建立完成 ({table_time:.2f} 秒)")
        
        # === 階段 2: 預先生成樣本與基礎資料 (關鍵優化!) ===
        print("\n正在預先生成獨立基礎數據與樣本資料...")
        sample_start = time.time()
        
        # 1. 產生 5000 筆使用者基礎數據 (確保 email 不重複)
        user_emails = set()
        while len(user_emails) < 5000:
            user_emails.add(fake.unique.email())
        users_data = [(email, fake.name()) for email in user_emails]
        cursor.executemany("INSERT INTO users (email, name) VALUES (%s, %s)", users_data)
        
        # 2. 產生 500 筆商品基礎數據
        products_data = [(fake.catch_phrase(), round(random.uniform(50, 2000), 2), random.randint(10, 1000)) for _ in range(500)]
        cursor.executemany("INSERT INTO products (name, price, stock) VALUES (%s, %s, %s)", products_data)
        conn.commit()
        
        # 3. 撈回產生的關聯 ID 與商品價格，放入記憶體供快取使用
        cursor.execute("SELECT id, name FROM users")
        user_samples = cursor.fetchall()  # [(id, name), ...]
        
        cursor.execute("SELECT id, price FROM products")
        product_samples = cursor.fetchall()  # [(id, price), ...]
        
        # 4. 地址與狀態樣本
        sample_size = 1000
        address_samples = [fake.address().replace('\n', ', ')[:100] for _ in range(sample_size)]
        status_samples = ['PENDING', 'PAID', 'SHIPPED', 'CANCELLED']
        
        sample_time = time.time() - sample_start
        print(f"✓ 樣本與基礎數據準備完成 ({sample_time:.2f} 秒)")
        
        print(f"\n開始生成 {total_rows:,} 筆資料...")
        print("=" * 60)
        
        # 優化設定
        cursor.execute("SET autocommit=0")
        cursor.execute("SET unique_checks=0")
        cursor.execute("SET foreign_key_checks=0")
        
        batch_size = 20000  # 衝 500 萬筆，加大單次寫入批次以提升速度
        buffer = []
        total_start = time.time()
        
        # 設定日期範圍 (2023-01-01 到 2025-12-31)
        start_date = datetime(2023, 1, 1)
        end_date = datetime(2025, 12, 31)
        total_days = (end_date - start_date).days
        
        # 計時變數
        last_report_time = time.time()
        last_report_count = 0
        
        # === 階段 3: 循環生成 500 萬筆資料 ===
        for i in range(total_rows):
            # 隨機抽樣基礎欄位
            random_days = random.randint(0, total_days)
            order_date = start_date + timedelta(days=random_days)
            address = address_samples[random.randint(0, sample_size - 1)]
            
            # 建立關聯：隨機抽一個使用者、一個商品
            user_id, customer_name = random.choice(user_samples)
            product_id, base_price = random.choice(product_samples)
            
            # 計算你新要求的欄位
            quantity = random.randint(1, 5)                  # 購買數量 1~5
            status = random.choice(status_samples)            # 隨機狀態
            price_at_purchase = base_price                   # 購買當下的單價
            amount = round(price_at_purchase * quantity, 2)  # 原本表的總金額 = 單價 * 數量
            
            # 依據資料表順序放入 buffer
            buffer.append((user_id, product_id, customer_name, amount, quantity, status, price_at_purchase, order_date, address))
            
            # 批量寫入
            if len(buffer) >= batch_size:
                cursor.executemany("""
                    INSERT INTO orders_partitioned 
                    (user_id, product_id, customer_name, amount, quantity, status, price_at_purchase, order_date, address)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                """, buffer)
                buffer = []
                
                # 每 500,000 筆 commit 一次並顯示進度 (適合 500 萬筆大數據)
                if (i + 1) % 500000 == 0:
                    conn.commit()
                    
                    current_time = time.time()
                    interval_time = current_time - last_report_time
                    interval_count = (i + 1) - last_report_count
                    speed = interval_count / interval_time if interval_time > 0 else 0
                    elapsed = current_time - total_start
                    
                    print(f"進度: {i + 1:,} / {total_rows:,} "
                          f"| 速度: {speed:,.0f} 筆/秒 "
                          f"| 已耗時: {elapsed:.1f} 秒")
                    
                    last_report_time = current_time
                    last_report_count = i + 1
        
        # === 寫入剩餘資料 ===
        if buffer:
            cursor.executemany("""
                INSERT INTO orders_partitioned 
                (user_id, product_id, customer_name, amount, quantity, status, price_at_purchase, order_date, address)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, buffer)
        
        conn.commit()
        
        # 恢復設定
        cursor.execute("SET unique_checks=1")
        cursor.execute("SET foreign_key_checks=1")
        cursor.execute("SET autocommit=1")
        
        # === 總結報告 ===
        total_time = time.time() - total_start
        avg_speed = total_rows / total_time if total_time > 0 else 0
        
        print("=" * 60)
        print(f"✅ 完成！")
        print(f"\n📊 效能統計:")
        print(f"  • 總筆數: {total_rows:,} 筆")
        print(f"  • 總耗時: {total_time:.2f} 秒")
        print(f"  • 平均速度: {avg_speed:,.0f} 筆/秒")
        print(f"  • 全表建立與樣本準備: {sample_time + table_time:.2f} 秒")
        
    except Exception as e:
        print(f"❌ 發生錯誤: {e}")
        conn.rollback()
    finally:
        cursor.close()
        conn.close()

if __name__ == "__main__":
    generate_data() # 500萬筆