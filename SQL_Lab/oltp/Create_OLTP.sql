-- =============================================
-- OLTP Schema - Онлайн-магазин одежды
-- 9 таблиц в 3NF
-- =============================================

-- Создаем отдельную схему для вашего проекта
DROP SCHEMA IF EXISTS online_store CASCADE;
CREATE SCHEMA online_store;

-- Устанавливаем схему по умолчанию
SET search_path TO online_store;

-- Удаление таблиц в правильном порядке (сначала дочерние)
DROP TABLE IF EXISTS status_update CASCADE;
DROP TABLE IF EXISTS sale_product CASCADE;
DROP TABLE IF EXISTS sale CASCADE;
DROP TABLE IF EXISTS customer_address CASCADE;
DROP TABLE IF EXISTS customer CASCADE;
DROP TABLE IF EXISTS address CASCADE;
DROP TABLE IF EXISTS product CASCADE;
DROP TABLE IF EXISTS subcategory CASCADE;
DROP TABLE IF EXISTS category CASCADE;

CREATE TABLE IF NOT EXISTS category (
    CategoryID SERIAL PRIMARY KEY,
    CategoryName VARCHAR(50) UNIQUE NOT NULL,
    Logo VARCHAR(50)
);

CREATE TABLE IF NOT EXISTS subcategory (
    SubcategoryID SERIAL PRIMARY KEY,
    CategoryID INT NOT NULL REFERENCES Category(CategoryID),
    SubcategoryName VARCHAR(50) UNIQUE NOT NULL
);

CREATE TABLE IF NOT EXISTS product (
    ProductID SERIAL PRIMARY KEY,
    PublicID VARCHAR(12) UNIQUE,
    ProductName VARCHAR(100) NOT NULL,
    Description VARCHAR(5000) NOT NULL,
    Price DECIMAL(20,4) NOT NULL,
    Stock INT NOT NULL,
    SubcategoryID INT NOT NULL REFERENCES Subcategory(SubcategoryID)
);

CREATE TABLE IF NOT EXISTS address (
    AddressID SERIAL PRIMARY KEY,
    Type VARCHAR(50) NOT NULL,
    Country VARCHAR(50) NOT NULL,
    State VARCHAR(50) NOT NULL,
    Town VARCHAR(50) NOT NULL,
    Zip VARCHAR(20) NOT NULL,
    AddressLine VARCHAR(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS customer (
    CustomerID SERIAL PRIMARY KEY,
    FirstName VARCHAR(50) NOT NULL,
    LastName VARCHAR(50) NOT NULL,
    Email VARCHAR(320) UNIQUE NOT NULL,
    Telephone VARCHAR(30) NOT NULL,
    DefaultAddressID INT REFERENCES Address(AddressID),
    PasswordHash VARCHAR(50) NOT NULL,
    CONSTRAINT unique_customer_email UNIQUE (Email)
);

CREATE TABLE IF NOT EXISTS customer_addresses (
    CustomerID INT REFERENCES Customer(CustomerID),
    AddressID INT REFERENCES Address(AddressID),
    PRIMARY KEY (CustomerID, AddressID)
);

CREATE TABLE IF NOT EXISTS sale (
    SaleID SERIAL PRIMARY KEY,
    OrderedAt DATE DEFAULT CURRENT_DATE,
    ShippingStatus VARCHAR(30) DEFAULT 'Not sent' NOT NULL,
    CustomerID INT NOT NULL REFERENCES Customer(CustomerID),
    AddressID INT NOT NULL REFERENCES Address(AddressID),
    IsPaid BOOLEAN DEFAULT FALSE NOT NULL
);

CREATE TABLE IF NOT EXISTS sale_products (
    SaleID INT REFERENCES Sale(SaleID),
    ProductID INT REFERENCES Product(ProductID),
    Amount INT NOT NULL,
    PricePerPiece DECIMAL(20,4) NOT NULL,
    PRIMARY KEY (SaleID, ProductID)
);

CREATE TABLE IF NOT EXISTS status_update (
    StatusUpdateID SERIAL PRIMARY KEY,
    SaleID INT NOT NULL REFERENCES Sale(SaleID),
    StatusChange VARCHAR(500) NOT NULL,
    UpdateDate DATE DEFAULT CURRENT_DATE
);

CREATE INDEX IF NOT EXISTS idx_product_subcategory ON Product(SubcategoryID);
CREATE INDEX IF NOT EXISTS idx_sale_customer ON Sale(CustomerID);
CREATE INDEX IF NOT EXISTS idx_sale_address ON Sale(AddressID);
CREATE INDEX IF NOT EXISTS idx_sale_products_product ON Sale_Products(ProductID);
CREATE INDEX IF NOT EXISTS idx_status_update_sale ON Status_Update(SaleID);
CREATE INDEX IF NOT EXISTS idx_customer_addresses_address ON Customer_Addresses(AddressID);

DO $$
BEGIN
    RAISE NOTICE 'OLTP Schema создана. Таблиц в схеме online_store: %', 
    (SELECT COUNT(*) FROM information_schema.tables 
     WHERE table_schema = 'online_store' 
     AND table_type = 'BASE TABLE');
END $$; 