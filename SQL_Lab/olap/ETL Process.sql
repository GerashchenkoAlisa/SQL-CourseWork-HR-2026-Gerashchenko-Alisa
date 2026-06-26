-- =============================================
-- ETL: Загрузка данных из OLTP в OLAP
-- =============================================

SET search_path TO online_store_olap, public;

-- Отключаем предыдущее подключение
DO $$
BEGIN
    PERFORM online_store_olap.dblink_disconnect('oltp_conn');
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Подключение не было активно';
END $$;

-- Подключаемся к OLTP
SELECT online_store_olap.dblink_connect('oltp_conn', 'host=localhost port=5432 dbname=''Online store oltp'' user=postgres password=0812');

-- =============================================
-- 1. ЗАГРУЗКА ИЗМЕРЕНИЙ
-- =============================================

-- 1.1 Dim_Category
DO $$
BEGIN
    RAISE NOTICE '=== 1. Загрузка Dim_Category ===';
    
    INSERT INTO online_store_olap.Dim_Category (CategoryName, CategoryGroup)
    SELECT DISTINCT 
        CategoryName,
        CASE
            WHEN CategoryName ILIKE '%cloth%' OR CategoryName ILIKE '%fashion%' 
                 OR CategoryName ILIKE '%men%' OR CategoryName ILIKE '%women%' THEN 'Fashion'
            WHEN CategoryName ILIKE '%electro%' OR CategoryName ILIKE '%tech%' 
                 OR CategoryName ILIKE '%mobile%' OR CategoryName ILIKE '%laptop%' THEN 'Technology'
            WHEN CategoryName ILIKE '%book%' OR CategoryName ILIKE '%fiction%' 
                 OR CategoryName ILIKE '%non-fiction%' THEN 'Media'
            WHEN CategoryName ILIKE '%home%' OR CategoryName ILIKE '%kitchen%' 
                 OR CategoryName ILIKE '%furniture%' THEN 'Home'
            WHEN CategoryName ILIKE '%toy%' OR CategoryName ILIKE '%game%' 
                 OR CategoryName ILIKE '%action%' THEN 'Entertainment'
            ELSE 'Other'
        END AS CategoryGroup
    FROM online_store_olap.dblink('oltp_conn', 'SELECT CategoryName FROM online_store.category') 
        AS t(CategoryName VARCHAR(50))
    WHERE NOT EXISTS (
        SELECT 1 FROM online_store_olap.Dim_Category dc WHERE dc.CategoryName = t.CategoryName
    );
    
    RAISE NOTICE 'Dim_Category: % записей', (SELECT COUNT(*) FROM online_store_olap.Dim_Category);
END $$;

-- 1.2 Dim_Subcategory
DO $$
BEGIN
    RAISE NOTICE '=== 2. Загрузка Dim_Subcategory ===';
    
    INSERT INTO online_store_olap.Dim_Subcategory (SubcategoryName, CategoryKey)
    SELECT DISTINCT 
        t.SubcategoryName, 
        dc.CategoryKey
    FROM online_store_olap.dblink('oltp_conn', '
        SELECT s.SubcategoryName, c.CategoryName 
        FROM online_store.subcategory s 
        JOIN online_store.category c ON c.CategoryID = s.CategoryID
    ') AS t(SubcategoryName VARCHAR(50), CategoryName VARCHAR(50))
    JOIN online_store_olap.Dim_Category dc ON dc.CategoryName = t.CategoryName
    WHERE NOT EXISTS (
        SELECT 1 FROM online_store_olap.Dim_Subcategory ds WHERE ds.SubcategoryName = t.SubcategoryName
    );
    
    RAISE NOTICE 'Dim_Subcategory: % записей', (SELECT COUNT(*) FROM online_store_olap.Dim_Subcategory);
END $$;

-- 1.3 Dim_Product
DO $$
BEGIN
    RAISE NOTICE '=== 3. Загрузка Dim_Product ===';
    
    INSERT INTO online_store_olap.Dim_Product (ProductID, ProductName, SubcategoryKey, Price)
    SELECT 
        t.ProductID, 
        t.ProductName, 
        ds.SubcategoryKey, 
        t.Price
    FROM online_store_olap.dblink('oltp_conn', '
        SELECT p.ProductID, p.ProductName, p.Price, s.SubcategoryName 
        FROM online_store.product p 
        JOIN online_store.subcategory s ON s.SubcategoryID = p.SubcategoryID
    ') AS t(ProductID INT, ProductName VARCHAR(100), Price DECIMAL(20,4), SubcategoryName VARCHAR(50))
    JOIN online_store_olap.Dim_Subcategory ds ON ds.SubcategoryName = t.SubcategoryName
    WHERE NOT EXISTS (
        SELECT 1 FROM online_store_olap.Dim_Product dp WHERE dp.ProductID = t.ProductID
    );
    
    RAISE NOTICE 'Dim_Product: % записей', (SELECT COUNT(*) FROM online_store_olap.Dim_Product);
END $$;

-- 1.4 Dim_Status
DO $$
BEGIN
    RAISE NOTICE '=== 4. Загрузка Dim_Status ===';
    
    INSERT INTO online_store_olap.Dim_Status (StatusCode, StatusGroup, IsFinal)
    SELECT * FROM (VALUES
        ('Not sent', 'Active', FALSE),
        ('Processing', 'Active', FALSE),
        ('Shipped', 'Active', FALSE),
        ('Delivered', 'Completed', TRUE),
        ('Cancelled', 'Cancelled', TRUE)
    ) AS v(StatusCode, StatusGroup, IsFinal)
    WHERE NOT EXISTS (
        SELECT 1 FROM online_store_olap.Dim_Status ds WHERE ds.StatusCode = v.StatusCode
    );
    
    RAISE NOTICE 'Dim_Status: % записей', (SELECT COUNT(*) FROM online_store_olap.Dim_Status);
END $$;

-- 1.5 Dim_Time
DO $$
BEGIN
    RAISE NOTICE '=== 5. Загрузка Dim_Time ===';
    
    INSERT INTO online_store_olap.Dim_Time (FullDate, Year, Quarter, Month, MonthName, Day, DayOfWeek, DayName, WeekNumber, IsWeekend)
    SELECT
        d::DATE,
        EXTRACT(YEAR FROM d)::INT,
        EXTRACT(QUARTER FROM d)::INT,
        EXTRACT(MONTH FROM d)::INT,
        TO_CHAR(d, 'Month'),
        EXTRACT(DAY FROM d)::INT,
        EXTRACT(DOW FROM d)::INT,
        TO_CHAR(d, 'Day'),
        EXTRACT(WEEK FROM d)::INT,
        EXTRACT(DOW FROM d) IN (0, 6)
    FROM generate_series('2025-01-01'::DATE, '2027-12-31'::DATE, '1 day'::INTERVAL) AS d
    WHERE NOT EXISTS (
        SELECT 1 FROM online_store_olap.Dim_Time dt WHERE dt.FullDate = d::DATE
    );
    
    RAISE NOTICE 'Dim_Time: % записей', (SELECT COUNT(*) FROM online_store_olap.Dim_Time);
END $$;

-- 1.6 Dim_Customer (SCD Type 2)
DO $$
DECLARE
    customer_record RECORD;
    existing_record RECORD;
    customer_count INT := 0;
    update_count INT := 0;
BEGIN
    RAISE NOTICE '=== 6. Загрузка Dim_Customer (SCD Type 2) ===';
    
    FOR customer_record IN 
        SELECT * FROM online_store_olap.dblink('oltp_conn', '
            SELECT 
                c.CustomerID,
                c.FirstName,
                c.LastName,
                c.Email,
                c.Telephone,
                COALESCE(a.Town, ''Unknown'') AS City,
                COALESCE(a.State, ''Unknown'') AS State,
                COALESCE(a.Country, ''Unknown'') AS Country
            FROM online_store.customer c 
            LEFT JOIN online_store.address a ON a.AddressID = c.DefaultAddressID
        ') AS t(
            CustomerID INT, 
            FirstName VARCHAR(50), 
            LastName VARCHAR(50), 
            Email VARCHAR(320), 
            Telephone VARCHAR(30), 
            City VARCHAR(50), 
            State VARCHAR(50), 
            Country VARCHAR(50)
        )
    LOOP
        SELECT * INTO existing_record 
        FROM online_store_olap.Dim_Customer 
        WHERE CustomerID = customer_record.CustomerID AND IsCurrent = TRUE;
        
        IF FOUND THEN
            IF existing_record.FullName != customer_record.FirstName || ' ' || customer_record.LastName
               OR existing_record.Email != customer_record.Email
               OR COALESCE(existing_record.Phone, '') != COALESCE(customer_record.Telephone, '')
               OR existing_record.City != customer_record.City
               OR existing_record.State != customer_record.State
               OR existing_record.Country != customer_record.Country THEN
                
                UPDATE online_store_olap.Dim_Customer 
                SET IsCurrent = FALSE, EndDate = CURRENT_DATE
                WHERE CustomerKey = existing_record.CustomerKey;
                
                INSERT INTO online_store_olap.Dim_Customer (
                    CustomerID, FullName, Email, Phone, 
                    City, State, Country, StartDate, EndDate, IsCurrent
                ) VALUES (
                    customer_record.CustomerID,
                    customer_record.FirstName || ' ' || customer_record.LastName,
                    customer_record.Email,
                    customer_record.Telephone,
                    customer_record.City,
                    customer_record.State,
                    customer_record.Country,
                    CURRENT_DATE,
                    '9999-12-31',
                    TRUE
                );
                
                update_count := update_count + 1;
            END IF;
        ELSE
            INSERT INTO online_store_olap.Dim_Customer (
                CustomerID, FullName, Email, Phone, 
                City, State, Country, StartDate, EndDate, IsCurrent
            ) VALUES (
                customer_record.CustomerID,
                customer_record.FirstName || ' ' || customer_record.LastName,
                customer_record.Email,
                customer_record.Telephone,
                customer_record.City,
                customer_record.State,
                customer_record.Country,
                CURRENT_DATE,
                '9999-12-31',
                TRUE
            );
            
            customer_count := customer_count + 1;
        END IF;
    END LOOP;
    
    RAISE NOTICE 'Добавлено: %, обновлено: %', customer_count, update_count;
    RAISE NOTICE 'Dim_Customer: % записей', (SELECT COUNT(*) FROM online_store_olap.Dim_Customer);
END $$;

-- =============================================
-- 2. BRIDGE TABLE
-- =============================================

DO $$
BEGIN
    RAISE NOTICE '=== 7. Загрузка Bridge_Order_Product ===';
    
    INSERT INTO online_store_olap.Bridge_Order_Product (SaleID, ProductKey, CustomerKey, Amount, PricePerPiece)
    SELECT
        sp.SaleID,
        dp.ProductKey,
        dc.CustomerKey,
        sp.Amount,
        sp.PricePerPiece
    FROM online_store_olap.dblink('oltp_conn', '
        SELECT sp.SaleID, sp.ProductID, sp.Amount, sp.PricePerPiece, s.CustomerID
        FROM online_store.sale_products sp
        JOIN online_store.sale s ON s.SaleID = sp.SaleID
    ') AS sp(SaleID INT, ProductID INT, Amount INT, PricePerPiece DECIMAL(20,4), CustomerID INT)
    JOIN online_store_olap.Dim_Product dp ON dp.ProductID = sp.ProductID
    JOIN online_store_olap.Dim_Customer dc ON dc.CustomerID = sp.CustomerID AND dc.IsCurrent = TRUE
    WHERE NOT EXISTS (
        SELECT 1 FROM online_store_olap.Bridge_Order_Product bop 
        WHERE bop.SaleID = sp.SaleID AND bop.ProductKey = dp.ProductKey
    );
    
    RAISE NOTICE 'Bridge_Order_Product: % записей', (SELECT COUNT(*) FROM online_store_olap.Bridge_Order_Product);
END $$;

-- =============================================
-- 3. FACT_SALES
-- =============================================

DO $$
BEGIN
    RAISE NOTICE '=== 8. Загрузка Fact_Sales ===';
    
    WITH latest_status AS (
        SELECT DISTINCT ON (SaleID)
            SaleID, StatusChange
        FROM online_store_olap.dblink('oltp_conn', '
            SELECT SaleID, StatusChange, UpdateDate 
            FROM online_store.status_update
            ORDER BY SaleID, UpdateDate DESC
        ') AS t(SaleID INT, StatusChange VARCHAR(500), UpdateDate DATE)
    )
    INSERT INTO online_store_olap.Fact_Sales (
        SaleID, ProductKey, CustomerKey, DateKey, StatusKey,
        Amount, PricePerPiece, IsPaid, LastUpdated
    )
    SELECT
        s.SaleID,
        dp.ProductKey,
        dc.CustomerKey,
        dt.DateKey,
        COALESCE(dst_status.StatusKey, dst_sale.StatusKey, 1) AS StatusKey,
        sp.Amount,
        sp.PricePerPiece,
        s.IsPaid,
        CURRENT_DATE
    FROM online_store_olap.dblink('oltp_conn', '
        SELECT SaleID, CustomerID, OrderedAt, ShippingStatus, IsPaid 
        FROM online_store.sale
    ') AS s(SaleID INT, CustomerID INT, OrderedAt DATE, ShippingStatus VARCHAR(30), IsPaid BOOLEAN)
    JOIN online_store_olap.dblink('oltp_conn', '
        SELECT SaleID, ProductID, Amount, PricePerPiece 
        FROM online_store.sale_products
    ') AS sp(SaleID INT, ProductID INT, Amount INT, PricePerPiece DECIMAL(20,4)) 
        ON sp.SaleID = s.SaleID
    JOIN online_store_olap.Dim_Product dp ON dp.ProductID = sp.ProductID
    JOIN online_store_olap.Dim_Customer dc ON dc.CustomerID = s.CustomerID AND dc.IsCurrent = TRUE
    JOIN online_store_olap.Dim_Time dt ON dt.FullDate = s.OrderedAt
    LEFT JOIN latest_status ls ON ls.SaleID = s.SaleID
    LEFT JOIN online_store_olap.Dim_Status dst_status ON dst_status.StatusCode = ls.StatusChange
    LEFT JOIN online_store_olap.Dim_Status dst_sale ON dst_sale.StatusCode = s.ShippingStatus
    WHERE NOT EXISTS (
        SELECT 1 FROM online_store_olap.Fact_Sales fs 
        WHERE fs.SaleID = s.SaleID AND fs.ProductKey = dp.ProductKey
    );
    
    RAISE NOTICE 'Fact_Sales: % записей', (SELECT COUNT(*) FROM online_store_olap.Fact_Sales);
END $$;

-- =============================================
-- 4. FACT_DAILY_SALES (агрегация)
-- =============================================

DO $$
BEGIN
    RAISE NOTICE '=== 9. Загрузка Fact_Daily_Sales ===';
    
    INSERT INTO online_store_olap.Fact_Daily_Sales (
        DateKey, CategoryKey, TotalOrders, TotalItemsSold,
        TotalRevenue, AverageOrderValue, UniqueCustomers, 
        PaidRevenue, LastUpdated
    )
    SELECT
        fs.DateKey,
        dc.CategoryKey,
        COUNT(DISTINCT fs.SaleID) AS TotalOrders,
        SUM(fs.Amount) AS TotalItemsSold,
        SUM(fs.Amount * fs.PricePerPiece) AS TotalRevenue,
        ROUND(COALESCE(AVG(fs.Amount * fs.PricePerPiece), 0), 2) AS AverageOrderValue,
        COUNT(DISTINCT fs.CustomerKey) AS UniqueCustomers,
        SUM(CASE WHEN fs.IsPaid = TRUE THEN fs.Amount * fs.PricePerPiece ELSE 0 END) AS PaidRevenue,
        CURRENT_DATE
    FROM online_store_olap.Fact_Sales fs
    JOIN online_store_olap.Dim_Product dp ON dp.ProductKey = fs.ProductKey
    JOIN online_store_olap.Dim_Subcategory dsub ON dsub.SubcategoryKey = dp.SubcategoryKey
    JOIN online_store_olap.Dim_Category dc ON dc.CategoryKey = dsub.CategoryKey
    JOIN online_store_olap.Dim_Time dt ON dt.DateKey = fs.DateKey
    GROUP BY fs.DateKey, dc.CategoryKey;
    
    RAISE NOTICE 'Fact_Daily_Sales: % записей', (SELECT COUNT(*) FROM online_store_olap.Fact_Daily_Sales);
END $$;

-- =============================================
-- ИТОГОВАЯ ПРОВЕРКА
-- =============================================

DO $$ 
BEGIN 
    RAISE NOTICE '========================================';
    RAISE NOTICE 'ETL COMPLETED SUCCESSFULLY!';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'ИТОГОВАЯ СТАТИСТИКА:';
    RAISE NOTICE 'Dim_Category: %', (SELECT COUNT(*) FROM online_store_olap.Dim_Category);
    RAISE NOTICE 'Dim_Subcategory: %', (SELECT COUNT(*) FROM online_store_olap.Dim_Subcategory);
    RAISE NOTICE 'Dim_Product: %', (SELECT COUNT(*) FROM online_store_olap.Dim_Product);
    RAISE NOTICE 'Dim_Customer: %', (SELECT COUNT(*) FROM online_store_olap.Dim_Customer);
    RAISE NOTICE 'Dim_Status: %', (SELECT COUNT(*) FROM online_store_olap.Dim_Status);
    RAISE NOTICE 'Dim_Time: %', (SELECT COUNT(*) FROM online_store_olap.Dim_Time);
    RAISE NOTICE 'Bridge_Order_Product: %', (SELECT COUNT(*) FROM online_store_olap.Bridge_Order_Product);
    RAISE NOTICE 'Fact_Sales: %', (SELECT COUNT(*) FROM online_store_olap.Fact_Sales);
    RAISE NOTICE 'Fact_Daily_Sales: %', (SELECT COUNT(*) FROM online_store_olap.Fact_Daily_Sales);
    RAISE NOTICE '========================================';
END $$;

-- Закрываем подключение
SELECT online_store_olap.dblink_disconnect('oltp_conn');

SELECT ' ETL completed successfully!' AS Status; 
