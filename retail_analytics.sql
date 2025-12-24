-- =====================================================
-- DATABASE SETUP
-- =====================================================
CREATE DATABASE retail_analytics;
USE retail_analytics;

-- =====================================================
-- STANDARDIZE TABLE NAMES
-- =====================================================
ALTER TABLE `customer_profiles-1-1714027410` RENAME TO customers;
ALTER TABLE `product_inventory-1-1714027438` RENAME TO product;
ALTER TABLE `sales_transaction-1714027462` RENAME TO sales;

-- =====================================================
-- FIX COLUMN NAMES (ENCODING ISSUES)
-- =====================================================
ALTER TABLE customers RENAME COLUMN ï»¿CustomerID TO CustomerID;
ALTER TABLE product RENAME COLUMN ï»¿ProductID TO ProductID;
ALTER TABLE sales RENAME COLUMN ï»¿TransactionID TO TransactionID;

-- =====================================================
-- CONVERT JOIN DATE TO DATE FORMAT
-- =====================================================
ALTER TABLE customers MODIFY JoinDate DATE;

-- =====================================================
-- IDENTIFY AND REMOVE DUPLICATE TRANSACTIONS
-- =====================================================
SELECT TransactionID, COUNT(*)
FROM sales
GROUP BY TransactionID
HAVING COUNT(*) > 1;

CREATE TABLE sales_nodupe AS
SELECT DISTINCT * FROM sales;

DROP TABLE sales;
ALTER TABLE sales_nodupe RENAME TO sales_transaction;

-- =====================================================
-- FIX PRICE INCONSISTENCIES USING PRODUCT MASTER DATA
-- =====================================================
UPDATE sales_transaction s
SET s.price = (
    SELECT p.price 
    FROM product p 
    WHERE s.ProductID = p.ProductID
)
WHERE s.ProductID IN (
    SELECT p.ProductID 
    FROM product p 
    WHERE p.price <> s.price
);

-- =====================================================
-- HANDLE MISSING LOCATION VALUES
-- =====================================================
UPDATE customers
SET location = 'Unknown'
WHERE location = '';

-- =====================================================
-- TRANSACTION DATE COLUMN (Text to Date)
-- =====================================================
CREATE TABLE transaction_date_updates AS
SELECT *,
STR_TO_DATE(TransactionDate, '%d/%m/%y') AS transaction_date
FROM sales_transaction;

DROP TABLE sales_transaction;
ALTER TABLE transaction_date_updates RENAME TO sales_transaction;
ALTER TABLE sales_transaction DROP COLUMN TransactionDate;


-- =====================================================
-- BUSINESS ANALYSIS QUERIES
-- =====================================================

-- Total sales and quantity per product
SELECT
p.ProductName,
SUM(st.QuantityPurchased) AS Total_Quantity,
ROUND(SUM(st.QuantityPurchased * st.Price),2) AS Total_Sales
FROM sales_transaction st
JOIN product p ON st.ProductID = p.ProductID
GROUP BY p.ProductName
ORDER BY Total_Sales DESC;


-- Purchase frequency per customer
SELECT
CustomerID,
COUNT(TransactionID) AS Total_Transactions,
SUM(QuantityPurchased) AS Total_Purchase
FROM sales_transaction
GROUP BY CustomerID
ORDER BY Total_Transactions DESC;


-- Category-wise sales performance
SELECT
p.Category,
SUM(st.QuantityPurchased) AS Units_Sold,
ROUND(SUM(st.QuantityPurchased * st.Price),2) AS Total_Sales
FROM sales_transaction st
JOIN product p ON st.ProductID = p.ProductID
GROUP BY p.Category
ORDER BY Total_Sales DESC;


-- Daily sales trend
SELECT
transaction_date,
COUNT(TransactionID) AS Transactions,
SUM(QuantityPurchased) AS Units_Sold,
ROUND(SUM(QuantityPurchased * Price),2) AS Total_Sales
FROM sales_transaction
GROUP BY transaction_date
ORDER BY transaction_date DESC;


-- =====================================================
-- BUSINESS ANALYSIS QUERIES (ADVANCED)
-- =====================================================

-- Month-on-Month Growth
WITH MonthlySales AS (
SELECT
MONTHNAME(transaction_date) AS Month,
ROUND(SUM(QuantityPurchased * Price),2) AS TotalSales
FROM sales_transaction
GROUP BY Month
)
SELECT
Month,
TotalSales,
TotalSales - LAG(TotalSales) OVER(ORDER BY Month) AS Growth,
ROUND(
(TotalSales - LAG(TotalSales) OVER(ORDER BY Month)) /
LAG(TotalSales) OVER(ORDER BY Month) * 100, 2
) AS GrowthRate
FROM MonthlySales;


-- Customer loyalty segmentation
WITH PurchaseSummary AS (
SELECT
CustomerID,
COUNT(*) AS TotalPurchases,
MIN(transaction_date) AS FirstPurchase,
MAX(transaction_date) AS LastPurchase,
DATEDIFF(MAX(transaction_date), MIN(transaction_date)) AS RelationshipDuration,
DATEDIFF('2023-07-30', MAX(transaction_date)) AS Recency
FROM sales_transaction
GROUP BY CustomerID
),
LoyaltyScore AS (
SELECT *,
ROUND(RelationshipDuration / NULLIF(TotalPurchases,0),1) AS AvgDaysBetweenPurchases
FROM PurchaseSummary
)
SELECT *,
CASE
WHEN TotalPurchases >= 10 AND Recency <= 30 THEN 'High Loyalty'
WHEN TotalPurchases >= 5 AND Recency <= 60 THEN 'Moderate Loyalty'
ELSE 'Low Loyalty'
END AS LoyaltyTier
FROM LoyaltyScore;


