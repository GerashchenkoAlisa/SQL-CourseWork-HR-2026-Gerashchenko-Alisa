-- =============================================
-- ЗАГРУЗКА ДАННЫХ В OLTP
-- Онлайн-магазин одежды
-- =============================================

SET search_path TO online_store;

-- Создаём helper функцию
DROP FUNCTION IF EXISTS show_table_count(TEXT);

CREATE OR REPLACE FUNCTION show_table_count(p_table TEXT) RETURNS VOID AS $$
DECLARE
    cnt INTEGER;
BEGIN
    EXECUTE format('SELECT COUNT(*) FROM %I', p_table) INTO cnt;
    RAISE NOTICE 'Table %: % rows', p_table, cnt;
EXCEPTION
    WHEN undefined_table THEN
        RAISE NOTICE 'Table %: does not exist yet', p_table;
END;
$$ LANGUAGE plpgsql;

-- ====================== MAIN LOADING ======================
DO $$
DECLARE 
    base_path TEXT := 'C:/SQL_Lab/oltp/data/';
BEGIN
    RAISE NOTICE '=== OLTP Data Loading Started ===';
    RAISE NOTICE 'Data path: %', base_path;

    -- 1. Category
    RAISE NOTICE '=== Loading Category ===';
    CREATE TEMP TABLE IF NOT EXISTS temp_category (
        CategoryName VARCHAR(50), 
        Logo VARCHAR(50)
    );
    EXECUTE format('COPY temp_category FROM ''%scategory.csv'' DELIMITER '','' CSV HEADER', base_path);
    INSERT INTO category (CategoryName, Logo)
    SELECT CategoryName, Logo FROM temp_category
    WHERE CategoryName IS NOT NULL AND CategoryName != ''
    AND NOT EXISTS (
		SELECT 1 FROM category c 
		WHERE c.CategoryName = temp_category.CategoryName
	);
    DROP TABLE IF EXISTS temp_category;
    PERFORM show_table_count('category');

    -- 2. Subcategory
    RAISE NOTICE '=== Loading Subcategory ===';
    CREATE TEMP TABLE IF NOT EXISTS temp_subcategory (
        CategoryID INT,
        SubcategoryName VARCHAR(50)
    );
    EXECUTE format('COPY temp_subcategory FROM ''%ssubcategory.csv'' DELIMITER '','' CSV HEADER ENCODING ''UTF8''', base_path);    
    INSERT INTO subcategory (CategoryID, SubcategoryName)
    SELECT t.CategoryID, t.SubcategoryName
    FROM temp_subcategory t
    WHERE t.SubcategoryName IS NOT NULL AND t.SubcategoryName != ''
    AND t.CategoryID IS NOT NULL
    AND EXISTS (
		SELECT 1 FROM category c 
		WHERE c.CategoryID = t.CategoryID
	)
    AND NOT EXISTS (
		SELECT 1 FROM subcategory s 
		WHERE s.SubcategoryName = t.SubcategoryName
	);
    DROP TABLE IF EXISTS temp_subcategory;
    PERFORM show_table_count('subcategory');

    -- 3. Product
    RAISE NOTICE '=== Loading Product ===';
    CREATE TEMP TABLE IF NOT EXISTS temp_product (
        PublicID VARCHAR(12), 
        ProductName VARCHAR(100), 
        Description VARCHAR(5000),
        Price DECIMAL(20,4), 
        Stock INT, 
        SubcategoryID INT
    );
    EXECUTE format('COPY temp_product FROM ''%sproduct.csv'' DELIMITER '','' CSV HEADER', base_path);
    INSERT INTO product (PublicID, ProductName, Description, Price, Stock, SubcategoryID)
    SELECT t.PublicID, t.ProductName, t.Description, t.Price, t.Stock, t.SubcategoryID
    FROM temp_product t
    WHERE t.PublicID IS NOT NULL
    AND EXISTS (
		SELECT 1 FROM subcategory s 
		WHERE s.SubcategoryID = t.SubcategoryID
	)
    AND NOT EXISTS (
		SELECT 1 FROM product p 
		WHERE p.PublicID = t.PublicID
	);
    DROP TABLE IF EXISTS temp_product;
    PERFORM show_table_count('product');

    -- 4. Address
	RAISE NOTICE '=== Loading Address ===';
	CREATE TEMP TABLE IF NOT EXISTS temp_address (
	    Type VARCHAR(50), 
	    Country VARCHAR(50), 
    	State VARCHAR(50),
	    Town VARCHAR(50), 
    	Zip VARCHAR(20), 
	    AddressLine VARCHAR(100)
	);
	EXECUTE format('COPY temp_address FROM ''%saddress.csv'' DELIMITER '','' CSV HEADER', base_path);
	INSERT INTO address (Type, Country, State, Town, Zip, AddressLine)
	SELECT Type, Country, State, Town, Zip, AddressLine FROM temp_address
	WHERE AddressLine IS NOT NULL AND AddressLine != '';
	DROP TABLE IF EXISTS temp_address;
	PERFORM show_table_count('address');

    -- 5. Customer
    RAISE NOTICE '=== Loading Customer ===';
    CREATE TEMP TABLE IF NOT EXISTS temp_customer (
        FirstName VARCHAR(50), 
        LastName VARCHAR(50), 
        Email VARCHAR(320),
        Telephone VARCHAR(30),
        DefaultAddressID INT,
        PasswordHash VARCHAR(50)
    );
    EXECUTE format('COPY temp_customer FROM ''%scustomer.csv'' DELIMITER '','' CSV HEADER', base_path);
    INSERT INTO customer (FirstName, LastName, Email, Telephone, DefaultAddressID, PasswordHash)
    SELECT t.FirstName, t.LastName, t.Email, t.Telephone, t.DefaultAddressID, t.PasswordHash
    FROM temp_customer t
    WHERE t.Email IS NOT NULL
    AND (t.DefaultAddressID IS NULL OR EXISTS (SELECT 1 FROM Address a WHERE a.AddressID = t.DefaultAddressID))
    AND NOT EXISTS (
		SELECT 1 FROM customer c 
		WHERE c.Email = t.Email
	);
    DROP TABLE IF EXISTS temp_customer;
    PERFORM show_table_count('customer');

    -- 6. Customer_Addresses
    RAISE NOTICE '=== Loading Customer_Addresses ===';
    CREATE TEMP TABLE IF NOT EXISTS temp_customer_addresses (
        CustomerID INT,
        AddressID INT
    );
    EXECUTE format('COPY temp_customer_addresses FROM ''%scustomer_addresses.csv'' DELIMITER '','' CSV HEADER', base_path);
    INSERT INTO customer_addresses (CustomerID, AddressID)
    SELECT 
        t.CustomerID, 
        t.AddressID
    FROM temp_customer_addresses t
    WHERE EXISTS (
		SELECT 1 FROM customer c 
		WHERE c.CustomerID = t.CustomerID
	)
    AND EXISTS (
		SELECT 1 FROM Address a 
		WHERE a.AddressID = t.AddressID
	)
    AND NOT EXISTS (
		SELECT 1 FROM customer_addresses ca 
        WHERE ca.CustomerID = t.CustomerID 
		AND ca.AddressID = t.AddressID
	);
    DROP TABLE IF EXISTS temp_customer_addresses;
    PERFORM show_table_count('customer_addresses');

    -- 7. Sale
    RAISE NOTICE '=== Loading Sale ===';
    CREATE TEMP TABLE IF NOT EXISTS temp_sale (
        OrderedAt VARCHAR(10), 
        ShippingStatus VARCHAR(30), 
        CustomerID INT,
        AddressID INT,         
        IsPaid VARCHAR(10)
    );
    EXECUTE format('COPY temp_sale FROM ''%ssale.csv'' DELIMITER '','' CSV HEADER', base_path);
    INSERT INTO sale (OrderedAt, ShippingStatus, CustomerID, AddressID, IsPaid)
    SELECT 
        TO_DATE(t.OrderedAt, 'MM/DD/YYYY'),
        t.ShippingStatus,
        t.CustomerID,
        t.AddressID,
        CASE 
            WHEN LOWER(t.IsPaid) IN ('true', 't', '1') THEN TRUE
            WHEN LOWER(t.IsPaid) IN ('false', 'f', '0') THEN FALSE
            ELSE FALSE
        END AS IsPaid
    FROM temp_sale t
    WHERE EXISTS (SELECT 1 FROM customer c WHERE c.CustomerID = t.CustomerID)
    AND EXISTS (SELECT 1 FROM address a WHERE a.AddressID = t.AddressID);
    DROP TABLE IF EXISTS temp_sale;
    PERFORM show_table_count('sale');

    -- 8. Sale_Products
	RAISE NOTICE '=== Loading Sale_Products ===';
	CREATE TEMP TABLE IF NOT EXISTS temp_sale_products (
	    SaleID INT,
    	ProductID INT, 
	    Amount INT, 
    	PricePerPiece DECIMAL(20,4)
	);
	EXECUTE format('COPY temp_sale_products FROM ''%ssale_products.csv'' DELIMITER '','' CSV HEADER', base_path);
	INSERT INTO sale_products (SaleID, ProductID, Amount, PricePerPiece)
	SELECT t.SaleID, t.ProductID, t.Amount, t.PricePerPiece
	FROM temp_sale_products t
	WHERE EXISTS (
		SELECT 1 FROM product p 
		WHERE p.ProductID = t.ProductID
	)
	AND EXISTS (
		SELECT 1 FROM sale s 
		WHERE s.SaleID = t.SaleID
	);
	DROP TABLE IF EXISTS temp_sale_products;
	PERFORM show_table_count('sale_products');

    -- 9. Status_Update
    RAISE NOTICE '=== Loading Status_Update ===';
    CREATE TEMP TABLE IF NOT EXISTS temp_status_update (
        SaleID INT, 
        StatusChange VARCHAR(500), 
        UpdateDate VARCHAR(10)
    );
    EXECUTE format('COPY temp_status_update FROM ''%sstatus_update.csv'' DELIMITER '','' CSV HEADER', base_path);
    INSERT INTO status_update (SaleID, StatusChange, UpdateDate)
    SELECT t.SaleID, t.StatusChange, TO_DATE(t.UpdateDate, 'MM/DD/YYYY')
    FROM temp_status_update t
    WHERE EXISTS (
		SELECT 1 FROM sale s 
		WHERE s.SaleID = t.SaleID
	);
    DROP TABLE IF EXISTS temp_status_update;
    PERFORM show_table_count('status_update');

    RAISE NOTICE '=== ALL DATA LOADED SUCCESSFULLY ===';
END $$;

SELECT 'Загрузка OLTP завершена успешно!' AS status; 