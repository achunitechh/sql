-- Active: 1779845189157@@10.167.223.49@3306@ecommerce
USE ecommerce;
-- ============================================
# A. 基本查詢練習
-- ============================================
    -- 1. 查詢特定客戶的訂單
    SELECT *
    FROM
        orders_partitioned AS o
    WHERE
        o.user_id = '466';
        
    -- 2. 查詢特定日期範圍的訂單統計 => WHERE COUNT
    SELECT
        COUNT(id) AS total_counts,
        SUM(price_at_purchase) AS total_price
    FROM
        orders_partitioned AS o
    WHERE
        order_date BETWEEN '2023-01-01' AND '2025-12-31'; -- 不要使用BETWEEN 2023 AND 2025，YEAR()會變全表掃描

    -- 2.1 查詢特定日期範圍的訂單統計，依年份統計
    SELECT 
        YEAR(order_date) AS order_year,
        COUNT(id) AS total_counts
    FROM 
        orders_partitioned AS o
    WHERE 
        order_date BETWEEN '2023-01-01' AND '2025-12-31'
    GROUP BY 
        YEAR(order_date) -- 加上YEAR，因為原本的order_date是日期
    ORDER BY 
        order_year;

    -- 3. 按狀態統計訂單數量和金額
    SELECT
        o.status,
        COUNT(o.id) AS total_ids,
        SUM(o.price_at_purchase) AS total_sales
    FROM
        orders_partitioned AS o
    GROUP BY
        status;
        
    -- 4. 查詢金額最高的訂單
    SELECT
        o.id,
        SUM(price_at_purchase) AS total_sales
    FROM
        orders_partitioned AS o
    GROUP BY
        o.id
    ORDER BY
        total_sales DESC
    LIMIT 1;

    -- 4.1 查詢金額最高的訂單 => 有可能有並列情況，用DENSE_RANK
    SELECT
        name,
        price_at_purchase AS max_spent
    FROM(
        SELECT
            u.name,
            o.price_at_purchase,
            DENSE_RANK() OVER(ORDER BY price_at_purchase DESC) AS price_rank
        FROM
            orders_partitioned AS o
        LEFT JOIN
            users AS u
            ON o.user_id = u.id
        WHERE
            status = 'SHIPPED' or status = 'PAID'
    ) AS ranked_table
    WHERE
        price_rank = 1;

-- ============================================
# B. 關聯查詢練習
-- ============================================
    -- 1. 使用 JOIN 查詢訂單與商品資訊
    SELECT
        o.user_id,
        o.product_id,
        p.name,
        o.quantity,
        o.status,
        o.price_at_purchase,
        o.order_date,
        o.address
    FROM
        orders_partitioned AS o
    JOIN
        products AS p
        ON o.product_id = p.id;

    -- 2. 統計各商品的銷售情況（訂單數、總收入、平均金額）
    SELECT
        o.product_id,
        p.name,
        COUNT(o.id) AS total_id,
        SUM(o.price_at_purchase) AS total_sales,
        AVG(o.price_at_purchase) AS avg_sales
    FROM orders_partitioned AS o
    LEFT JOIN
        products AS p
        ON o.product_id = p.id
    GROUP BY
        o.product_id,
        p.name;

    -- 3. 查詢購買次數最多的客戶
    SELECT
        o.user_id,
        u.name,
        COUNT(*) AS bought_count
    FROM
        orders_partitioned AS o
    LEFT JOIN
        users AS u
        ON o.user_id = u.id
    WHERE
        o.status = 'SHIPPED' or status = 'PAID'
    GROUP BY
        o.user_id,
        u.name
    HAVING
        bought_count>=1
    ORDER BY
        bought_count DESC
    LIMIT 1;

    -- 4. 對比商品庫存與銷售情況
    SELECT
        o.product_id,
        p.name,
        IFNULL(SUM(o.quantity), 0) AS total_sales
    FROM
        products as p
    LEFT JOIN
        orders_partitioned AS o
        ON p.id = o.product_id
    WHERE
        status = 'SHIPPED' or status = 'PAID'
    GROUP BY
        o.product_id
    ORDER BY
        total_sales DESC;

-- ============================================
# C. 分區管理與效能
-- ============================================
    -- 0. 修正
    ALTER TABLE orders_partitioned 
    REORGANIZE PARTITION p2023, p2024, p2025, p_future INTO (
    PARTITION p2023 VALUES LESS THAN (2024), -- 讓 p2023 裝 2023 年(<=2023)
    PARTITION p2024 VALUES LESS THAN (2025), -- 讓 p2024 裝 2024 年(<=2024)
    PARTITION p2025 VALUES LESS THAN (2026), -- 讓 p2025 裝 2025 年(<=2025)
    PARTITION p_future VALUES LESS THAN MAXVALUE
);
    -- 1. 分區修剪驗證
    EXPLAIN 
    SELECT
        * 
    FROM 
        orders_partitioned 
    WHERE 
        order_date = '2024-05-20';

    -- 2. 分區查詢練習
        -- 2.1 統計各年份的訂單數據
    EXPLAIN 
    SELECT 
        YEAR(order_date) AS order_year,
        COUNT(id) AS total_counts
    FROM 
        orders_partitioned AS o
    WHERE 
        order_date BETWEEN '2023-01-01' AND '2025-12-31'
    GROUP BY 
        YEAR(order_date) -- 加上YEAR，因為原本的order_date是日期
    ORDER BY 
        order_year;

        -- 2.2 查詢特定年份2024每月的銷售趨勢
    EXPLAIN
    SELECT
        DATE_FORMAT(order_date, '%Y-%m') AS order_year_month,
        COUNT(id) AS total_counts
    FROM
        orders_partitioned AS o
    WHERE
        order_date BETWEEN '2024-01-01' AND '2024-12-31'
    GROUP BY
        order_year_month
    ORDER BY
        order_year_month;

        -- 2.3 查詢特定年份2025金額最高的客戶
    EXPLAIN
    SELECT
        u.id,
        u.name,
        SUM(price_at_purchase) as total_spent
    FROM
        orders_partitioned AS o
    LEFT JOIN
        users AS u
        ON o.user_id = u.id
    WHERE
        order_date BETWEEN '2025-01-01' AND '2025-12-31'
    GROUP BY
        u.id,
        u.name
    ORDER BY
        total_spent DESC
    LIMIT 1;

    -- 3. 分區維護
        -- 3.1 刪除過期分區（2023 年）
    ALTER TABLE orders_partitioned DROP PARTITION p2023;

        -- 3.2 驗證刪除結果
    SELECT
        YEAR(order_date) AS order_year,
        COUNT(id) AS total_counts
    FROM
        orders_partitioned
    GROUP BY
        order_year;

-- ============================================
# D. 索引優化與查詢效能
-- ============================================
    -- 1. 基準測試
        -- 1.1 在無索引的情況下，查詢特定客戶的訂單
    SELECT *
    FROM
        orders_partitioned AS o
    WHERE
        o.user_id = '4173';
        
        -- 1.2 使用 EXPLAIN 觀察執行計畫
    EXPLAIN
        SELECT *
    FROM
        orders_partitioned AS o
    WHERE
        o.user_id = '4173';

        -- 1.4 SQL_NO_CACHE 避免快取影響
    SELECT 
        SQL_NO_CACHE *
    FROM 
        orders_partitioned AS o
    WHERE 
        o.user_id = '4173';

    -- 2. 索引建立與優化
        -- 2.1 建立複合索引以加速查詢
    CREATE INDEX idx_user ON orders_partitioned(user_id);

        -- 2.2 再次使用 EXPLAIN 觀察執行計畫
    EXPLAIN
    SELECT 
        SQL_NO_CACHE *
    FROM 
        orders_partitioned AS o
    WHERE 
        o.user_id = '4173';
    
    -- 3. 索引應用練習
        -- 3.1 使用索引查詢特定客戶的訂單
    EXPLAIN
    SELECT 
        SQL_NO_CACHE *
    FROM 
        orders_partitioned AS o
    WHERE 
        user_id = '195'
    ORDER BY
        user_id = '195' 
    LIMIT 1;
        
        -- 3.2 使用索引進行範圍查詢
    EXPLAIN
    SELECT 
        SQL_NO_CACHE *
    FROM 
        orders_partitioned AS o
    WHERE 
        order_date BETWEEN '2024-01-01' AND '2025-12-31'
    ORDER BY
        user_id = '195' 
    LIMIT 1;

        -- 3.3 查詢高價值訂單的客戶 => 定義：消費次數↑、消費金額↑
    EXPLAIN
    SELECT 
        o.user_id,
        u.name,
        COUNT(o.id) AS total_orders,
        SUM(o.price_at_purchase) AS total_sales
    FROM 
        orders_partitioned AS o
    LEFT JOIN
        users AS u
        ON o.user_id = u.id
    WHERE 
        order_date BETWEEN '2024-01-01' AND '2025-12-31'
    GROUP BY
        o.user_id,
        u.name
    ORDER BY
        total_sales DESC,
        total_orders DESC
    LIMIT 10;

-- ============================================
# E. MySQL 8.x 新語法
-- ============================================
-- 1. CTE練習
    -- 1.1 使用 CTE 查詢高價值客戶
    -- 1.2 使用 CTE 進行多層聚合
-- 2. WINDOW FUNCTION
    -- 2.1 使用 ROW_NUMBER 進行客戶排名
    -- 2.2 使用 RANK 與 DENSE_RANK 進行排名
    -- 2.3 使用 LAG 查詢訂單金額變化
    -- 2.4 使用 SUM OVER 計算累計金額

-- ============================================
# F. TRIGGER 自動化
-- ============================================
-- 1. TRIGGER 建立
    -- 1.1 建立 TRIGGER 在訂單新增時自動減少庫存

    -- 1.2 建立 TRIGGER 防止庫存變成負數

-- 2. TRIGGER 測試
    -- 2.1 新增訂單並驗證庫存自動減少

    -- 2.2 查看庫存日誌記錄

    -- 2.3 測試庫存不足的情況（應被拒絕）

-- ============================================
# G. STORED PROCEDURE
-- ============================================
-- 1. **PROCEDURE 建立**
    -- 1.1 建立 PROCEDURE 查詢客戶訂單統計
    -- 1.2 建立 PROCEDURE 查詢日期範圍的銷售報表
    -- 1.3 建立 PROCEDURE 查詢商品銷售排名

-- 2. PROCEDURE 測試
    -- 2.1 呼叫各個 PROCEDURE 並驗證結果
    -- 2.2 查看已建立的 PROCEDURE 清單