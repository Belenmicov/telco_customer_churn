-- ============================================================
-- TELCO CUSTOMER CHURN ANALYSIS
-- Tool: MySQL
-- Dataset: Telco Customer Churn (Kaggle)
-- Table: customers
-- ============================================================


-- ============================================================
-- PHASE 1 — DATA EXPLORATION & CLEANING
-- ============================================================


-- Preview the first 10 rows to verify import and column structure

SELECT * 
FROM customers
LIMIT 10;


-- Confirm total record count

SELECT COUNT(*) AS total_rows 
FROM customers;


-- Check for NULL values across key columns

SELECT
    SUM(CASE WHEN customerID IS NULL THEN 1 ELSE 0 END)     AS null_customerID,
    SUM(CASE WHEN Churn IS NULL THEN 1 ELSE 0 END)          AS null_churn,
    SUM(CASE WHEN tenure IS NULL THEN 1 ELSE 0 END)         AS null_tenure,
    SUM(CASE WHEN MonthlyCharges IS NULL THEN 1 ELSE 0 END) AS null_monthly,
    SUM(CASE WHEN TotalCharges IS NULL THEN 1 ELSE 0 END)   AS null_total
FROM customers;


-- TotalCharges was imported as text and contains blank strings
-- for customers with tenure = 0. Identify affected rows.

SELECT customerID, tenure, TotalCharges
FROM customers
WHERE TotalCharges = '' OR TRIM(TotalCharges) = '';


-- Convert blank strings to NULL for correct numerical handling

UPDATE customers
SET TotalCharges = NULL
WHERE TRIM(TotalCharges) = '';


-- The Churn column contains Windows carriage return characters (\r)
-- appended to each value, causing all churn-based aggregations
-- to return 0. Confirmed via HEX inspection.

SELECT DISTINCT Churn, HEX(Churn), LENGTH(Churn)
FROM customers;

-- Remove carriage return characters

UPDATE customers
SET Churn = REPLACE(Churn, '\r', '');

-- Verify the fix

SELECT DISTINCT Churn, HEX(Churn), LENGTH(Churn)
FROM customers;


-- Distribution of key categorical dimensions

SELECT Contract, COUNT(*) AS total FROM customers GROUP BY Contract;

SELECT PaymentMethod, COUNT(*) AS total FROM customers GROUP BY PaymentMethod;

SELECT InternetService, COUNT(*) AS total FROM customers GROUP BY InternetService;

SELECT Churn, COUNT(*) AS total FROM customers GROUP BY Churn;


-- Customer distribution by tenure group

SELECT
    CASE
        WHEN tenure BETWEEN 0  AND 12 THEN '0-12 months'
        WHEN tenure BETWEEN 13 AND 24 THEN '13-24 months'
        WHEN tenure BETWEEN 25 AND 48 THEN '25-48 months'
        WHEN tenure BETWEEN 49 AND 60 THEN '49-60 months'
        ELSE '60+ months'
    END AS tenure_group,
    COUNT(*) AS total_customers
FROM customers
GROUP BY tenure_group
ORDER BY MIN(tenure);


-- ============================================================
-- PHASE 2 — CORE CHURN ANALYSIS
-- ============================================================


-- Overall churn rate

SELECT
    COUNT(*) AS total_customers,
    SUM(CASE WHEN TRIM(Churn) = 'Yes' THEN 1 ELSE 0 END) AS churned_customers,
    ROUND(
        SUM(CASE WHEN TRIM(Churn) = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
    2) AS churn_rate_pct
FROM customers;


-- Churn rate by contract type

SELECT
    Contract,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN TRIM(Churn) = 'Yes' THEN 1 ELSE 0 END) AS churned,
    ROUND(
        SUM(CASE WHEN TRIM(Churn) = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
    2) AS churn_rate_pct
FROM customers
GROUP BY Contract
ORDER BY churn_rate_pct DESC;


-- Churn rate by tenure group

SELECT
    CASE
        WHEN tenure BETWEEN 0  AND 12 THEN '0-12 months'
        WHEN tenure BETWEEN 13 AND 24 THEN '13-24 months'
        WHEN tenure BETWEEN 25 AND 48 THEN '25-48 months'
        WHEN tenure BETWEEN 49 AND 60 THEN '49-60 months'
        ELSE '60+ months'
    END AS tenure_group,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN TRIM(Churn) = 'Yes' THEN 1 ELSE 0 END) AS churned,
    ROUND(
        SUM(CASE WHEN TRIM(Churn) = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
    2) AS churn_rate_pct
FROM customers
GROUP BY tenure_group
ORDER BY MIN(tenure);


-- Churn rate by internet service type

SELECT
    InternetService,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN TRIM(Churn) = 'Yes' THEN 1 ELSE 0 END) AS churned,
    ROUND(
        SUM(CASE WHEN TRIM(Churn) = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
    2) AS churn_rate_pct
FROM customers
GROUP BY InternetService
ORDER BY churn_rate_pct DESC;


-- Churn rate by payment method

SELECT
    PaymentMethod,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN TRIM(Churn) = 'Yes' THEN 1 ELSE 0 END) AS churned,
    ROUND(
        SUM(CASE WHEN TRIM(Churn) = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
    2) AS churn_rate_pct
FROM customers
GROUP BY PaymentMethod
ORDER BY churn_rate_pct DESC;


-- Average monthly and total charges by churn status

SELECT
    TRIM(Churn) AS churn_status,
    ROUND(AVG(MonthlyCharges), 2)                       AS avg_monthly_charges,
    ROUND(AVG(CAST(TotalCharges AS DECIMAL(10,2))), 2)  AS avg_total_charges
FROM customers
GROUP BY TRIM(Churn);


-- ============================================================
-- PHASE 2 — SUPPLEMENTARY ANALYSIS
-- ============================================================


-- Churn rate by senior citizen status

SELECT
    CASE WHEN SeniorCitizen = 1 THEN 'Senior' ELSE 'Non-Senior' END AS senior_status,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN TRIM(Churn) = 'Yes' THEN 1 ELSE 0 END) AS churned,
    ROUND(
        SUM(CASE WHEN TRIM(Churn) = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
    2) AS churn_rate_pct
FROM customers
GROUP BY senior_status;


-- Churn rate by tech support subscription

SELECT
    TechSupport,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN TRIM(Churn) = 'Yes' THEN 1 ELSE 0 END) AS churned,
    ROUND(
        SUM(CASE WHEN TRIM(Churn) = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
    2) AS churn_rate_pct
FROM customers
GROUP BY TechSupport
ORDER BY churn_rate_pct DESC;


-- Churn rate by gender
-- Included for completeness — no meaningful difference found.

SELECT
    gender,
    COUNT(*) AS total_customers,
    SUM(CASE WHEN TRIM(Churn) = 'Yes' THEN 1 ELSE 0 END) AS churned,
    ROUND(
        SUM(CASE WHEN TRIM(Churn) = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
    2) AS churn_rate_pct
FROM customers
GROUP BY gender;


-- High-risk customer profile
-- Filters for customers matching all four primary churn indicators:
-- month-to-month contract, tenure under 12 months,
-- fiber optic internet, and electronic check payment.

SELECT
    COUNT(*) AS high_risk_customers,
    SUM(CASE WHEN TRIM(Churn) = 'Yes' THEN 1 ELSE 0 END) AS churned,
    ROUND(
        SUM(CASE WHEN TRIM(Churn) = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
    2) AS churn_rate_pct
FROM customers
WHERE Contract        = 'Month-to-month'
  AND tenure          BETWEEN 0 AND 12
  AND InternetService = 'Fiber optic'
  AND PaymentMethod   = 'Electronic check';


-- ============================================================
-- END OF ANALYSIS
-- ============================================================