-- =============================================
-- OLAP QUERIES - Онлайн-магазин одежды
-- 6 аналитических запросов к OLAP
-- =============================================

SET search_path TO online_store_olap;

-- 1. Продажи по категориям (из Fact_Daily_Sales)
SELECT 
    dc.CategoryName,
    dc.CategoryGroup,
    SUM(fds.TotalOrders) AS TotalOrders,
    SUM(fds.TotalItemsSold) AS TotalItemsSold,
    SUM(fds.TotalRevenue) AS TotalRevenue,
    ROUND(SUM(fds.PaidRevenue) * 100.0 / NULLIF(SUM(fds.TotalRevenue), 0), 2) AS PaidPercentage,
    SUM(fds.UniqueCustomers) AS UniqueCustomers
FROM Fact_Daily_Sales fds
JOIN Dim_Category dc ON dc.CategoryKey = fds.CategoryKey
GROUP BY dc.CategoryName, dc.CategoryGroup
ORDER BY TotalRevenue DESC;

-- 2. Динамика продаж по месяцам
SELECT 
    dt.Year,
    dt.MonthName,
    SUM(fds.TotalOrders) AS TotalOrders,
    SUM(fds.TotalItemsSold) AS TotalItemsSold,
    SUM(fds.TotalRevenue) AS TotalRevenue,
    ROUND(AVG(fds.AverageOrderValue), 2) AS AvgOrderValue,
    SUM(fds.PaidRevenue) AS PaidRevenue
FROM Fact_Daily_Sales fds
JOIN Dim_Time dt ON dt.DateKey = fds.DateKey
GROUP BY dt.Year, dt.Month, dt.MonthName
ORDER BY dt.Year DESC, dt.Month DESC;

-- 3. Топ-10 товаров
SELECT 
    dp.ProductName,
    dc.CategoryName,
    SUM(fs.TotalAmount) AS TotalRevenue,
    SUM(fs.Amount) AS TotalItemsSold,
    COUNT(DISTINCT fs.SaleID) AS NumberOfOrders
FROM Fact_Sales fs
JOIN Dim_Product dp ON dp.ProductKey = fs.ProductKey
JOIN Dim_Subcategory dsub ON dsub.SubcategoryKey = dp.SubcategoryKey
JOIN Dim_Category dc ON dc.CategoryKey = dsub.CategoryKey
GROUP BY dp.ProductName, dc.CategoryName
ORDER BY TotalRevenue DESC
LIMIT 10;

-- 4. Статистика по статусам заказов
SELECT 
    ds.StatusCode,
    ds.StatusGroup,
    COUNT(DISTINCT fs.SaleID) AS TotalOrders,
    SUM(fs.TotalAmount) AS TotalRevenue,
    ROUND(AVG(fs.TotalAmount), 2) AS AvgOrderValue,
    ROUND(SUM(CASE WHEN fs.IsPaid = TRUE THEN fs.TotalAmount ELSE 0 END) * 100.0 / NULLIF(SUM(fs.TotalAmount), 0), 2) AS PaidPercentage
FROM Fact_Sales fs
JOIN Dim_Status ds ON ds.StatusKey = fs.StatusKey
GROUP BY ds.StatusCode, ds.StatusGroup
ORDER BY TotalRevenue DESC;

-- 5. Топ клиентов (SCD Type 2)
SELECT 
    dc.FullName,
    dc.City,
    dc.Country,
    COUNT(DISTINCT fs.SaleID) AS TotalOrders,
    SUM(fs.TotalAmount) AS TotalSpent,
    ROUND(AVG(fs.TotalAmount), 2) AS AvgOrderValue,
    MAX(dt.FullDate) AS LastPurchase
FROM Fact_Sales fs
JOIN Dim_Customer dc ON dc.CustomerKey = fs.CustomerKey
JOIN Dim_Time dt ON dt.DateKey = fs.DateKey
WHERE dc.IsCurrent = TRUE
GROUP BY dc.FullName, dc.City, dc.Country
ORDER BY TotalSpent DESC
LIMIT 15;

-- 6. Продажи по кварталам (Paid vs Total)
SELECT 
    dt.Year,
    dt.Quarter,
    SUM(fds.TotalRevenue) AS TotalRevenue,
    SUM(fds.PaidRevenue) AS PaidRevenue,
    ROUND(SUM(fds.PaidRevenue) * 100.0 / NULLIF(SUM(fds.TotalRevenue), 0), 2) AS PaidPercent
FROM Fact_Daily_Sales fds
JOIN Dim_Time dt ON dt.DateKey = fds.DateKey
GROUP BY dt.Year, dt.Quarter
ORDER BY dt.Year DESC, dt.Quarter DESC; 