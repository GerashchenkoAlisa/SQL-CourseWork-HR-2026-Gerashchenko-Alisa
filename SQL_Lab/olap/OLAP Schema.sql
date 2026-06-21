-- =============================================
-- OLAP SCHEMA - Онлайн-магазин одежды 
-- =============================================
DROP SCHEMA IF EXISTS online_store_olap CASCADE;
CREATE SCHEMA online_store_olap;
SET search_path TO online_store_olap;

-- ==================== DIMENSIONS ====================
CREATE TABLE IF NOT EXISTS Dim_Category (
    CategoryKey SERIAL PRIMARY KEY,
    CategoryName VARCHAR(50) NOT NULL,
    CategoryGroup VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS Dim_Subcategory (
    SubcategoryKey SERIAL PRIMARY KEY,
    SubcategoryName VARCHAR(50) NOT NULL,
    CategoryKey INT REFERENCES Dim_Category(CategoryKey)
);

CREATE TABLE IF NOT EXISTS Dim_Product (
    ProductKey SERIAL PRIMARY KEY,
    ProductID INT,
    ProductName VARCHAR(100),
    SubcategoryKey INT REFERENCES Dim_Subcategory(SubcategoryKey),
    Price DECIMAL(20,4)
);

CREATE TABLE IF NOT EXISTS Dim_Customer (  -- SCD Type 2
    CustomerKey SERIAL PRIMARY KEY,
    CustomerID INT NOT NULL,
    FullName VARCHAR(100),
    Email VARCHAR(320),
    Phone VARCHAR(30),
    City VARCHAR(50),
    State VARCHAR(50),
    Country VARCHAR(50),
    StartDate DATE DEFAULT CURRENT_DATE,
    EndDate DATE DEFAULT '9999-12-31',
    IsCurrent BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS Dim_Status (
    StatusKey SERIAL PRIMARY KEY,
    StatusCode VARCHAR(30) UNIQUE NOT NULL,
    StatusGroup VARCHAR(50),
    IsFinal BOOLEAN DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS Dim_Time (
    DateKey SERIAL PRIMARY KEY,
    FullDate DATE UNIQUE NOT NULL,
    Year INT, Quarter INT, Month INT, MonthName VARCHAR(20),
    Day INT, DayOfWeek INT, DayName VARCHAR(20),
    WeekNumber INT, IsWeekend BOOLEAN
);

-- ==================== BRIDGE & FACTS ====================
CREATE TABLE IF NOT EXISTS Bridge_Order_Product (
    BridgeKey SERIAL PRIMARY KEY,
    SaleID INT,
    ProductKey INT REFERENCES Dim_Product(ProductKey),
    CustomerKey INT REFERENCES Dim_Customer(CustomerKey),
    Amount INT,
    PricePerPiece DECIMAL(20,4),
    TotalAmount DECIMAL(20,4) GENERATED ALWAYS AS (Amount * PricePerPiece) STORED
);

CREATE TABLE IF NOT EXISTS Fact_Sales (
    SalesKey SERIAL PRIMARY KEY,
    SaleID INT,
    ProductKey INT REFERENCES Dim_Product(ProductKey),
    CustomerKey INT REFERENCES Dim_Customer(CustomerKey),
    DateKey INT REFERENCES Dim_Time(DateKey),
    StatusKey INT REFERENCES Dim_Status(StatusKey),
    Amount INT,
    PricePerPiece DECIMAL(20,4),
    TotalAmount DECIMAL(20,4) GENERATED ALWAYS AS (Amount * PricePerPiece) STORED,
    IsPaid BOOLEAN,
    LastUpdated DATE DEFAULT CURRENT_DATE,
    UNIQUE (SaleID, ProductKey)
);

CREATE TABLE IF NOT EXISTS Fact_Daily_Sales (
    DailySalesKey SERIAL PRIMARY KEY,
    DateKey INT REFERENCES Dim_Time(DateKey),
    CategoryKey INT REFERENCES Dim_Category(CategoryKey),
    TotalOrders INT DEFAULT 0,
    TotalItemsSold INT DEFAULT 0,
    TotalRevenue DECIMAL(20,4) DEFAULT 0,
    AverageOrderValue DECIMAL(20,4) DEFAULT 0,
    UniqueCustomers INT DEFAULT 0,
    PaidRevenue DECIMAL(20,4) DEFAULT 0,
    LastUpdated DATE DEFAULT CURRENT_DATE,
    UNIQUE (DateKey, CategoryKey)
);

-- ==================== ИНДЕКСЫ ====================
CREATE INDEX IF NOT EXISTS idx_dim_customer_current ON Dim_Customer(CustomerID) WHERE IsCurrent = TRUE;
CREATE INDEX IF NOT EXISTS idx_fact_sales_date ON Fact_Sales(DateKey);
CREATE INDEX IF NOT EXISTS idx_bridge_order_product ON Bridge_Order_Product(SaleID, ProductKey);
CREATE INDEX IF NOT EXISTS idx_fact_daily_sales_date ON Fact_Daily_Sales(DateKey);

-- ==================== VIEWS ====================
DROP VIEW IF EXISTS Agg_Sales_By_Category;
CREATE OR REPLACE VIEW Agg_Sales_By_Category AS
SELECT 
    dc.CategoryName,
    dc.CategoryGroup,
    SUM(fds.TotalOrders) AS TotalOrders,
    SUM(fds.TotalItemsSold) AS TotalItemsSold,
    SUM(fds.TotalRevenue) AS TotalRevenue,
    ROUND(AVG(fds.AverageOrderValue), 2) AS AvgOrderValue,
    SUM(fds.UniqueCustomers) AS UniqueCustomers,
    SUM(fds.PaidRevenue) AS PaidRevenue
FROM Fact_Daily_Sales fds
JOIN Dim_Category dc ON dc.CategoryKey = fds.CategoryKey
GROUP BY dc.CategoryName, dc.CategoryGroup
ORDER BY TotalRevenue DESC;

DROP VIEW IF EXISTS Agg_Sales_By_Month;
CREATE OR REPLACE VIEW Agg_Sales_By_Month AS
SELECT 
    dt.Year,
    dt.Month,
    dt.MonthName,
    SUM(fds.TotalOrders) AS TotalOrders,
    SUM(fds.TotalItemsSold) AS TotalItemsSold,
    SUM(fds.TotalRevenue) AS TotalRevenue,
    ROUND(AVG(fds.AverageOrderValue), 2) AS AvgOrderValue,
    SUM(fds.UniqueCustomers) AS UniqueCustomers
FROM Fact_Daily_Sales fds
JOIN Dim_Time dt ON dt.DateKey = fds.DateKey
GROUP BY dt.Year, dt.Month, dt.MonthName
ORDER BY dt.Year DESC, dt.Month DESC;

DROP VIEW IF EXISTS Agg_Top_Products;
CREATE OR REPLACE VIEW Agg_Top_Products AS
SELECT 
    dp.ProductName,
    dc.CategoryName,
    SUM(fs.Amount) AS TotalItemsSold,
    SUM(fs.TotalAmount) AS TotalRevenue,
    COUNT(DISTINCT fs.SaleID) AS NumberOfOrders
FROM Fact_Sales fs
JOIN Dim_Product dp ON dp.ProductKey = fs.ProductKey
JOIN Dim_Subcategory dsub ON dsub.SubcategoryKey = dp.SubcategoryKey
JOIN Dim_Category dc ON dc.CategoryKey = dsub.CategoryKey
GROUP BY dp.ProductName, dc.CategoryName
ORDER BY TotalRevenue DESC
LIMIT 10;

DROP VIEW IF EXISTS Agg_Status_Statistics;
CREATE OR REPLACE VIEW Agg_Status_Statistics AS
SELECT 
    ds.StatusCode,
    ds.StatusGroup,
    ds.IsFinal,
    COUNT(DISTINCT fs.SaleID) AS TotalOrders,
    SUM(fs.TotalAmount) AS TotalRevenue,
    ROUND(AVG(fs.TotalAmount), 2) AS AvgOrderValue
FROM Fact_Sales fs
JOIN Dim_Status ds ON ds.StatusKey = fs.StatusKey
GROUP BY ds.StatusCode, ds.StatusGroup, ds.IsFinal
ORDER BY TotalOrders DESC;

DROP VIEW IF EXISTS Agg_Customer_Statistics;
CREATE OR REPLACE VIEW Agg_Customer_Statistics AS
SELECT 
    dc.CustomerID,
    dc.FullName,
    dc.Email,
    dc.Phone,
    dc.City,
    dc.State,
    COUNT(DISTINCT fs.SaleID) AS TotalOrders,
    SUM(fs.Amount) AS TotalItemsPurchased,
    SUM(fs.TotalAmount) AS TotalSpent,
    ROUND(AVG(fs.TotalAmount), 2) AS AvgOrderValue
FROM Fact_Sales fs
JOIN Dim_Customer dc ON dc.CustomerKey = fs.CustomerKey
WHERE dc.IsCurrent = TRUE
GROUP BY dc.CustomerID, dc.FullName, dc.Email, dc.Phone, dc.City, dc.State
ORDER BY TotalSpent DESC
LIMIT 20;

DROP VIEW IF EXISTS Agg_Dashboard;
CREATE OR REPLACE VIEW Agg_Dashboard AS
SELECT 
    (SELECT COUNT(DISTINCT SaleID) FROM Fact_Sales) AS TotalOrders,
    (SELECT SUM(Amount) FROM Fact_Sales) AS TotalItemsSold,
    (SELECT SUM(TotalAmount) FROM Fact_Sales) AS TotalRevenue,
    (SELECT ROUND(AVG(TotalAmount), 2) FROM Fact_Sales) AS AvgOrderValue,
    (SELECT COUNT(DISTINCT CustomerKey) FROM Fact_Sales) AS UniqueCustomers,
    (SELECT COUNT(DISTINCT ProductKey) FROM Fact_Sales) AS ProductsSold,
    (SELECT COUNT(DISTINCT CASE WHEN IsPaid = TRUE THEN SaleID END) FROM Fact_Sales) AS PaidOrders,
    (SELECT ROUND(SUM(CASE WHEN IsPaid = TRUE THEN TotalAmount ELSE 0 END) * 100.0 / NULLIF(SUM(TotalAmount), 0), 2) 
     FROM Fact_Sales) AS PaidPercentage;

SELECT 'OLAP Schema created successfully!' AS Status; 