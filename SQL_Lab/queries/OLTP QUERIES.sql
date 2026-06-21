-- =============================================
-- OLTP QUERIES - Онлайн-магазин одежды
-- 5 аналитических запросов к OLTP
-- =============================================

SET search_path TO online_store;

-- 1. Продажи по категориям
SELECT
    cat.CategoryName,
    COUNT(DISTINCT s.SaleID) AS OrderCount,
    SUM(sp.Amount) AS ItemsSold,
	
    SUM(sp.Amount * sp.PricePerPiece) AS TotalRevenue,
    ROUND(SUM(sp.Amount * sp.PricePerPiece) / COUNT(DISTINCT s.SaleID), 2) AS AvgOrderValue
FROM category cat
JOIN subcategory sub ON sub.CategoryID = cat.CategoryID
JOIN product p ON p.SubcategoryID = sub.SubcategoryID
JOIN sale_products sp ON sp.ProductID = p.ProductID
JOIN sale s ON s.SaleID = sp.SaleID
GROUP BY cat.CategoryName
ORDER BY TotalRevenue DESC;

-- 2. Заказы по статусам 
WITH order_summary AS (
    SELECT 
        s.SaleID,
        s.ShippingStatus,
        s.CustomerID,
        s.IsPaid,
        SUM(sp.Amount) AS TotalItems,
        SUM(sp.Amount * sp.PricePerPiece) AS OrderTotal
    FROM sale s
    JOIN sale_products sp ON sp.SaleID = s.SaleID
    GROUP BY s.SaleID, s.ShippingStatus, s.CustomerID, s.IsPaid
)
SELECT 
    ShippingStatus,
    COUNT(*) AS OrderCount,
    COUNT(DISTINCT CustomerID) AS UniqueCustomers,
    SUM(TotalItems) AS TotalItems,
    SUM(OrderTotal) AS TotalRevenue,
    ROUND(AVG(OrderTotal), 2) AS AvgOrderValue,
    COUNT(CASE WHEN IsPaid = TRUE THEN 1 END) AS PaidOrders,
    ROUND(COUNT(CASE WHEN IsPaid = TRUE THEN 1 END) * 100.0 / COUNT(*), 2) AS PaidPercentage
FROM order_summary
GROUP BY ShippingStatus
ORDER BY TotalRevenue DESC;

-- 3. Продажи по дням недели
SELECT 
    TO_CHAR(s.OrderedAt, 'Day') AS DayOfWeek,
    EXTRACT(DOW FROM s.OrderedAt) AS DayNumber,
    COUNT(DISTINCT s.SaleID) AS OrderCount,
    SUM(sp.Amount) AS ItemsSold,
    SUM(sp.Amount * sp.PricePerPiece) AS TotalRevenue
FROM sale s
JOIN sale_products sp ON sp.SaleID = s.SaleID
GROUP BY TO_CHAR(s.OrderedAt, 'Day'), EXTRACT(DOW FROM s.OrderedAt)
ORDER BY DayNumber;

-- 4. Топ-10 товаров по выручке
SELECT
    p.ProductName,
    cat.CategoryName,
    sub.SubcategoryName,
    SUM(sp.Amount) AS TotalItemsSold,
    SUM(sp.Amount * sp.PricePerPiece) AS TotalRevenue,
    COUNT(DISTINCT s.SaleID) AS NumberOfOrders
FROM product p
JOIN subcategory sub ON sub.SubcategoryID = p.SubcategoryID
JOIN category cat ON cat.CategoryID = sub.CategoryID
JOIN sale_products sp ON sp.ProductID = p.ProductID
JOIN sale s ON s.SaleID = sp.SaleID
GROUP BY p.ProductName, cat.CategoryName, sub.SubcategoryName
ORDER BY TotalRevenue DESC
LIMIT 10;

-- 5. Динамика продаж по месяцам
SELECT
    EXTRACT(YEAR FROM s.OrderedAt) AS Year,
    EXTRACT(MONTH FROM s.OrderedAt) AS Month,
    TO_CHAR(s.OrderedAt, 'Month') AS MonthName,
    COUNT(DISTINCT s.SaleID) AS TotalOrders,
    SUM(sp.Amount) AS TotalItemsSold,
    SUM(sp.Amount * sp.PricePerPiece) AS TotalRevenue
FROM sale s
JOIN sale_products sp ON sp.SaleID = s.SaleID
GROUP BY Year, Month, MonthName
ORDER BY Year DESC, Month DESC; 