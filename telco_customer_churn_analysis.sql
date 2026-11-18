-- ============================================================================
-- TELCO CUSTOMER CHURN ANALYSIS
-- ----------------------------------------------------------------------------
-- Tool:     MySQL 8
-- Dataset:  Telco Customer Churn (Kaggle) · 7,043 customers · 21 columns
-- Table:    telco_customer
--
-- Business context
--   Client:    Head of Customer Retention (simulated: synthetic dataset)
--   Decision:  which customer segments and which levers to focus retention
--              on, with a limited budget that cannot cover every customer
--
-- Business questions
--   Q1. Which types of customers churn the most?
--   Q2. Do customers with certain services churn less than those without?
--   Q3. Do contract and payment conditions affect churn?
--   Q4. Do customers who pay more churn more?
--   Q5. How many customers and how much monthly revenue are lost per segment?
--
-- Metrics
--   Primary:     churn rate (%)
--   Supporting:  monthly revenue lost
--   Diagnostic:  churn rate by service, contract and payment method
--
-- Structure
--   0. Setup
--   1. Data profiling
--   2. Data validation and cleaning
--   3. Overall churn rate
--   4. Churn analysis by business question (Q1-Q5)
--   5. High-risk customer profile
-- ============================================================================


-- ============================================================================
-- 0. SETUP
-- ============================================================================

-- TotalCharges is loaded as text on purpose: the raw CSV contains blank values
-- in that column. Loading it as text keeps them visible so they can be checked
-- and fixed before converting the column to a number (see section 2).

CREATE TABLE telco_customer (
    customerID       VARCHAR(20),
    gender           VARCHAR(10),
    SeniorCitizen    INT,
    Partner          VARCHAR(5),
    Dependents       VARCHAR(5),
    tenure           INT,
    PhoneService     VARCHAR(5),
    MultipleLines    VARCHAR(25),
    InternetService  VARCHAR(20),
    OnlineSecurity   VARCHAR(25),
    OnlineBackup     VARCHAR(25),
    DeviceProtection VARCHAR(25),
    TechSupport      VARCHAR(25),
    StreamingTV      VARCHAR(25),
    StreamingMovies  VARCHAR(25),
    Contract         VARCHAR(20),
    PaperlessBilling VARCHAR(5),
    PaymentMethod    VARCHAR(30),
    MonthlyCharges   DECIMAL(8,2),
    TotalCharges     VARCHAR(20),
    Churn            VARCHAR(10)
);

-- Replace the path with the location of the CSV file.
-- If local_infile is disabled: SET GLOBAL local_infile = 1;

LOAD DATA LOCAL INFILE 'path/to/WA_Fn-UseC_-Telco-Customer-Churn.csv'
INTO TABLE telco_customer
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
IGNORE 1 LINES;


-- ============================================================================
-- 1. DATA PROFILING
-- ============================================================================

-- 1.1 Preview the data

SELECT *
FROM telco_customer
LIMIT 10;


-- 1.2 Total row count
-- Result: 7,043 rows, matching the source.

SELECT COUNT(*) AS total_rows
FROM telco_customer;


-- 1.3 Duplicate customer IDs
-- Result: no rows returned, so no duplicates.

SELECT customerID, COUNT(*) AS occurrences
FROM telco_customer
GROUP BY customerID
HAVING COUNT(*) > 1;


-- 1.4 Values and group sizes of every categorical column
-- Checks: misspelled categories, groups too small to trust, special values.
-- Result:
--   - All categories are spelled consistently.
--   - Smallest group: PhoneService = 'No' (682 customers), large enough.
--   - 'No internet service' (1,526) appears in the six internet add-on
--     services and 'No phone service' (682) in MultipleLines. These are
--     customers who cannot have that service, not errors. They are excluded
--     with WHERE when analysing those services.

SELECT 'gender' AS column_name, gender AS value, COUNT(*) AS customers FROM telco_customer GROUP BY gender
UNION ALL SELECT 'SeniorCitizen',    SeniorCitizen,    COUNT(*) FROM telco_customer GROUP BY SeniorCitizen
UNION ALL SELECT 'Partner',          Partner,          COUNT(*) FROM telco_customer GROUP BY Partner
UNION ALL SELECT 'Dependents',       Dependents,       COUNT(*) FROM telco_customer GROUP BY Dependents
UNION ALL SELECT 'PhoneService',     PhoneService,     COUNT(*) FROM telco_customer GROUP BY PhoneService
UNION ALL SELECT 'MultipleLines',    MultipleLines,    COUNT(*) FROM telco_customer GROUP BY MultipleLines
UNION ALL SELECT 'InternetService',  InternetService,  COUNT(*) FROM telco_customer GROUP BY InternetService
UNION ALL SELECT 'OnlineSecurity',   OnlineSecurity,   COUNT(*) FROM telco_customer GROUP BY OnlineSecurity
UNION ALL SELECT 'OnlineBackup',     OnlineBackup,     COUNT(*) FROM telco_customer GROUP BY OnlineBackup
UNION ALL SELECT 'DeviceProtection', DeviceProtection, COUNT(*) FROM telco_customer GROUP BY DeviceProtection
UNION ALL SELECT 'TechSupport',      TechSupport,      COUNT(*) FROM telco_customer GROUP BY TechSupport
UNION ALL SELECT 'StreamingTV',      StreamingTV,      COUNT(*) FROM telco_customer GROUP BY StreamingTV
UNION ALL SELECT 'StreamingMovies',  StreamingMovies,  COUNT(*) FROM telco_customer GROUP BY StreamingMovies
UNION ALL SELECT 'Contract',         Contract,         COUNT(*) FROM telco_customer GROUP BY Contract
UNION ALL SELECT 'PaperlessBilling', PaperlessBilling, COUNT(*) FROM telco_customer GROUP BY PaperlessBilling
UNION ALL SELECT 'PaymentMethod',    PaymentMethod,    COUNT(*) FROM telco_customer GROUP BY PaymentMethod
UNION ALL SELECT 'Churn',            Churn,            COUNT(*) FROM telco_customer GROUP BY Churn;


-- ============================================================================
-- 2. DATA VALIDATION AND CLEANING
-- ============================================================================

-- 2.1 Out-of-range values in numeric columns
-- Result: tenure 0-72 months, MonthlyCharges 18.25-118.75. All plausible.

SELECT
    MIN(tenure)         AS min_tenure,
    MAX(tenure)         AS max_tenure,
    MIN(MonthlyCharges) AS min_monthly_charges,
    MAX(MonthlyCharges) AS max_monthly_charges
FROM telco_customer;


-- 2.2 Missing values in TotalCharges
-- A plain check (TotalCharges = '') returns 0: the blank cells contain a
-- space, so TRIM() is needed to detect them.
-- Result: 0 NULLs, 11 blank values, 11 customers with tenure = 0.
-- The blanks are exactly the new customers who have not been billed yet.

SELECT
    SUM(CASE WHEN TotalCharges IS NULL THEN 1 ELSE 0 END)    AS null_values,
    SUM(CASE WHEN TRIM(TotalCharges) = '' THEN 1 ELSE 0 END) AS blank_values,
    SUM(CASE WHEN tenure = 0 THEN 1 ELSE 0 END)              AS zero_tenure
FROM telco_customer;


-- 2.3 Fix: set the 11 blanks to 0 and convert the column to a number
-- 0 rather than NULL: the amount is not unknown, these customers have paid
-- nothing yet. The UPDATE must run before the ALTER (a blank cannot be
-- converted to a number).
-- If safe update mode blocks the UPDATE: SET SQL_SAFE_UPDATES = 0;

UPDATE telco_customer
SET TotalCharges = '0'
WHERE TRIM(TotalCharges) = '';

ALTER TABLE telco_customer
MODIFY TotalCharges DECIMAL(10,2);


-- ============================================================================
-- 3. OVERALL CHURN RATE
-- ============================================================================

-- 3.1 First attempt
-- Result: 7,043 customers, 0 churned, 0.00% churn rate.
-- This contradicts the profiling (1,869 customers with Churn = 'Yes').

SELECT
    COUNT(*)                                                                    AS total_customers,
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END)                              AS churned_customers,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate_pct
FROM telco_customer;


-- 3.2 Diagnosis
-- COUNT(*) works, so the problem is the filter Churn = 'Yes'.
-- Result: 'No' has length 3 and 'Yes' has length 4: one hidden character.
-- It is a Windows carriage return (\r): the CSV lines end in \r\n and the
-- file was loaded with LINES TERMINATED BY '\n', so \r stayed attached to
-- the last column of every row (Churn).

SELECT DISTINCT Churn, LENGTH(Churn) AS value_length
FROM telco_customer;


-- 3.3 Fix: remove the carriage return
-- TRIM() alone only removes spaces, so the character must be specified.
-- Equivalent alternative: SET Churn = REPLACE(Churn, '\r', '');
-- Result: 7,043 rows changed (every row was affected).

UPDATE telco_customer
SET Churn = TRIM(TRAILING '\r' FROM Churn);


-- 3.4 Overall churn rate (baseline for every segment)
-- Result: 1,869 of 7,043 customers churned: 26.54%, just over 1 in 4.

SELECT
    COUNT(*)                                                                    AS total_customers,
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END)                              AS churned_customers,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate_pct
FROM telco_customer;


-- ============================================================================
-- 4. CHURN ANALYSIS BY BUSINESS QUESTION
-- ----------------------------------------------------------------------------
-- Every query compares churn rate between groups against the 26.54% baseline.
-- "Share of churners" = churned customers in the group / 1,869.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Q1. WHICH TYPES OF CUSTOMERS CHURN THE MOST?
-- ----------------------------------------------------------------------------

-- Q1.1 Churn by tenure band
-- Result: first year 47.4% churn (55% of churners). Churn falls steadily with
-- tenure, down to 6.6% after 5 years.

SELECT
    CASE
        WHEN tenure BETWEEN 0  AND 12 THEN '0-12 months'
        WHEN tenure BETWEEN 13 AND 24 THEN '13-24 months'
        WHEN tenure BETWEEN 25 AND 36 THEN '25-36 months'
        WHEN tenure BETWEEN 37 AND 48 THEN '37-48 months'
        WHEN tenure BETWEEN 49 AND 60 THEN '49-60 months'
        ELSE '61-72 months'
    END                                                                         AS tenure_band,
    COUNT(*)                                                                    AS total_customers,
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END)                              AS churned_customers,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate_pct
FROM telco_customer
GROUP BY tenure_band
ORDER BY tenure_band;


-- Q1.2 First year x contract type
-- Is first-year churn just a contract effect? 91% of new customers are on a
-- monthly contract.
-- Result: within month-to-month contracts, first-year customers still churn
-- 18 points more (51.4% vs 33.6%). On one-year contracts there is no
-- difference. First year + monthly = 55% of all churners.
-- Note: only 68 new customers have a two-year contract, too few to conclude.

SELECT
    CASE WHEN tenure <= 12 THEN 'First year' ELSE 'More than one year' END     AS tenure_group,
    Contract,
    COUNT(*)                                                                    AS total_customers,
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END)                              AS churned_customers,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate_pct
FROM telco_customer
GROUP BY Contract, tenure_group
ORDER BY Contract, tenure_group;


-- Q1.3 When do new month-to-month customers leave?
-- Result: months 1-3 have the highest rate (58%) and 595 of the group's
-- 1,024 churners, more than the rest of the year combined. Churn stays above
-- 40% for the whole first year.

SELECT
    CASE
        WHEN tenure BETWEEN 0 AND 3 THEN '01-03 months'
        WHEN tenure BETWEEN 4 AND 6 THEN '04-06 months'
        WHEN tenure BETWEEN 7 AND 9 THEN '07-09 months'
        ELSE '10-12 months'
    END                                                                         AS tenure_band,
    COUNT(*)                                                                    AS total_customers,
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END)                              AS churned_customers,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate_pct
FROM telco_customer
WHERE Contract = 'Month-to-month'
  AND tenure <= 12
GROUP BY tenure_band
ORDER BY tenure_band;


-- Q1.4 Demographics
-- Result: seniors 41.7% vs 23.6%; no dependents 31.3% vs 15.5%;
-- no partner 33.0% vs 19.7%; gender shows no difference (26.9% vs 26.2%).
-- Demographics are not levers: they help decide whom to target.

SELECT
    'SeniorCitizen'                                                             AS variable,
    CASE WHEN SeniorCitizen = 1 THEN 'Senior' ELSE 'Non-senior' END            AS value,
    COUNT(*)                                                                    AS total_customers,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate_pct
FROM telco_customer
GROUP BY value
UNION ALL
SELECT 'Partner', Partner, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer
GROUP BY Partner
UNION ALL
SELECT 'Dependents', Dependents, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer
GROUP BY Dependents
UNION ALL
SELECT 'gender', gender, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer
GROUP BY gender;


-- ----------------------------------------------------------------------------
-- Q2. DO CUSTOMERS WITH CERTAIN SERVICES CHURN LESS?
-- ----------------------------------------------------------------------------

-- Q2.1 Churn and average monthly charge by internet service
-- Result: fiber optic 41.9% churn vs 19.0% for DSL (69% of churners), while
-- paying about $33 more per month. Customers without internet: 7.4%.

SELECT
    InternetService,
    COUNT(*)                                                                    AS total_customers,
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END)                              AS churned_customers,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate_pct,
    ROUND(AVG(MonthlyCharges), 2)                                               AS avg_monthly_charge
FROM telco_customer
GROUP BY InternetService;


-- Q2.2 Internet service x contract type
-- Is fiber churn just a contract effect?
-- Result: fiber churns more than DSL under every contract
-- (monthly +22 pts, one year +10, two year +5). Fiber has its own problem.
-- Fiber + month-to-month: 54.6% churn, 62% of all churners.

SELECT
    InternetService,
    Contract,
    COUNT(*)                                                                    AS total_customers,
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END)                              AS churned_customers,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate_pct
FROM telco_customer
GROUP BY InternetService, Contract
ORDER BY Contract, InternetService;


-- Q2.3 Churn by tech support
-- Result: without tech support 41.6% vs 15.2% with it (77% of churners).
-- 'No internet service' customers cannot have tech support and are not
-- part of the comparison.

SELECT
    TechSupport,
    COUNT(*)                                                                    AS total_customers,
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END)                              AS churned_customers,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate_pct
FROM telco_customer
GROUP BY TechSupport;


-- Q2.4 Tech support x contract type
-- Is the tech support effect just a contract effect? 40% of customers with
-- tech support have a two-year contract, vs 7% of those without.
-- Result: the gap shrinks to 1-2 points on long contracts but holds at
-- 20 points on month-to-month (50.4% vs 30.7%).

SELECT
    TechSupport,
    Contract,
    COUNT(*)                                                                    AS total_customers,
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END)                              AS churned_customers,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate_pct
FROM telco_customer
WHERE TechSupport <> 'No internet service'
GROUP BY Contract, TechSupport
ORDER BY Contract, TechSupport;


-- Q2.5 Sweep of the remaining services
-- Customers who cannot have each service are excluded. For internet services
-- the fair baseline is 31.8% (churn among customers with internet).
-- Result: protection services make a large difference
--   OnlineSecurity 41.8% vs 14.6% · OnlineBackup 39.9% vs 21.5%
--   DeviceProtection 39.1% vs 22.5%
-- Streaming, phone and multiple lines: 2-4 points, not meaningful.

SELECT
    'OnlineSecurity'                                                            AS service,
    OnlineSecurity                                                              AS value,
    COUNT(*)                                                                    AS total_customers,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate_pct
FROM telco_customer
WHERE OnlineSecurity <> 'No internet service'
GROUP BY OnlineSecurity
UNION ALL
SELECT 'OnlineBackup', OnlineBackup, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer
WHERE OnlineBackup <> 'No internet service'
GROUP BY OnlineBackup
UNION ALL
SELECT 'DeviceProtection', DeviceProtection, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer
WHERE DeviceProtection <> 'No internet service'
GROUP BY DeviceProtection
UNION ALL
SELECT 'StreamingTV', StreamingTV, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer
WHERE StreamingTV <> 'No internet service'
GROUP BY StreamingTV
UNION ALL
SELECT 'StreamingMovies', StreamingMovies, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer
WHERE StreamingMovies <> 'No internet service'
GROUP BY StreamingMovies
UNION ALL
SELECT 'PhoneService', PhoneService, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer
GROUP BY PhoneService
UNION ALL
SELECT 'MultipleLines', MultipleLines, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer
WHERE MultipleLines <> 'No phone service'
GROUP BY MultipleLines;


-- Q2.6 Protection services among new month-to-month customers
-- What should be offered to the highest-risk group?
-- Result: OnlineSecurity 61.7% vs 38.6% · TechSupport 61.0% vs 42.8%
--         OnlineBackup 60.0% vs 51.3% · DeviceProtection: no difference.
-- Only about 15% of these customers have security or tech support.

SELECT
    'OnlineSecurity'                                                            AS service,
    OnlineSecurity                                                              AS value,
    COUNT(*)                                                                    AS total_customers,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate_pct
FROM telco_customer
WHERE Contract = 'Month-to-month'
  AND tenure <= 12
  AND OnlineSecurity <> 'No internet service'
GROUP BY OnlineSecurity
UNION ALL
SELECT 'TechSupport', TechSupport, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer
WHERE Contract = 'Month-to-month'
  AND tenure <= 12
  AND TechSupport <> 'No internet service'
GROUP BY TechSupport
UNION ALL
SELECT 'OnlineBackup', OnlineBackup, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer
WHERE Contract = 'Month-to-month'
  AND tenure <= 12
  AND OnlineBackup <> 'No internet service'
GROUP BY OnlineBackup
UNION ALL
SELECT 'DeviceProtection', DeviceProtection, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer
WHERE Contract = 'Month-to-month'
  AND tenure <= 12
  AND DeviceProtection <> 'No internet service'
GROUP BY DeviceProtection;


-- ----------------------------------------------------------------------------
-- Q3. DO CONTRACT AND PAYMENT CONDITIONS AFFECT CHURN?
-- ----------------------------------------------------------------------------

-- Q3.1 Churn by contract type
-- Result: month-to-month 42.7% churn (16 points above baseline, 15x the
-- two-year rate) and 89% of all churners.

SELECT
    Contract,
    COUNT(*)                                                                    AS total_customers,
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END)                              AS churned_customers,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate_pct
FROM telco_customer
GROUP BY Contract;


-- Q3.2 Churn by payment method
-- Result: electronic check 45.3% churn (57% of churners) vs 15-17% for
-- automatic payment methods.

SELECT
    PaymentMethod,
    COUNT(*)                                                                    AS total_customers,
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END)                              AS churned_customers,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate_pct
FROM telco_customer
GROUP BY PaymentMethod;


-- Q3.3 Churn by paperless billing
-- Result: 33.6% vs 16.3%. Unlikely to be a cause (more likely a marker of a
-- more digital, newer customer). Not treated as a lever.

SELECT
    PaperlessBilling,
    COUNT(*)                                                                    AS total_customers,
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END)                              AS churned_customers,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate_pct
FROM telco_customer
GROUP BY PaperlessBilling;


-- ----------------------------------------------------------------------------
-- Q4. DO CUSTOMERS WHO PAY MORE CHURN MORE?
-- ----------------------------------------------------------------------------

-- Q4.1 Churn by monthly charge band
-- Result: no consistent pattern (rates go up and down across bands). Under
-- $30 are mostly customers without internet, who churn the least.

SELECT
    CASE
        WHEN MonthlyCharges < 30 THEN '1. Under 30'
        WHEN MonthlyCharges < 50 THEN '2. 30 to 50'
        WHEN MonthlyCharges < 70 THEN '3. 50 to 70'
        WHEN MonthlyCharges < 90 THEN '4. 70 to 90'
        ELSE '5. 90 or more'
    END                                                                         AS charge_band,
    COUNT(*)                                                                    AS total_customers,
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END)                              AS churned_customers,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate_pct
FROM telco_customer
GROUP BY charge_band
ORDER BY charge_band;


-- Q4.2 Average monthly charge of stayers vs churners, by internet service
-- Result: within the same internet service, churners pay the same or less
-- (fiber $88.13 vs $93.93; DSL $49.08 vs $60.21). Price alone does not
-- explain churn, so a general discount is not recommended.

SELECT
    InternetService,
    Churn,
    COUNT(*)                      AS total_customers,
    ROUND(AVG(MonthlyCharges), 2) AS avg_monthly_charge
FROM telco_customer
GROUP BY InternetService, Churn
ORDER BY InternetService, Churn;


-- ----------------------------------------------------------------------------
-- Q5. HOW MUCH MONTHLY REVENUE IS LOST PER SEGMENT?
-- ----------------------------------------------------------------------------

-- Q5.1 Total monthly revenue lost
-- Result: $139,130.85 per month (about $1.7M per year if those customers
-- had stayed one more year).

SELECT ROUND(SUM(MonthlyCharges), 2) AS monthly_revenue_lost
FROM telco_customer
WHERE Churn = 'Yes';


-- Q5.2 Revenue lost by contract type
-- Result: month-to-month = 86.9% of revenue lost ($120,847).

SELECT
    Contract,
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END)                       AS churned_customers,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 0) AS monthly_revenue_lost,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) * 100.0 /
          (SELECT SUM(MonthlyCharges) FROM telco_customer WHERE Churn = 'Yes'), 1)
                                                                          AS pct_of_revenue_lost
FROM telco_customer
GROUP BY Contract;


-- Q5.3 Revenue lost by key segment
-- revenue_lost_per_customer = revenue lost / customers in the segment:
-- money at risk per customer contacted (efficiency of a retention budget).
-- Result: segments without security or tech support lose the most in total
-- because they are large, but fiber + month-to-month is the most efficient:
-- 54.6% churn, 72.2% of revenue lost and $47.2 at risk per customer
-- (vs $32-36 for the other segments).

SELECT
    'First year + month-to-month'                                               AS segment,
    COUNT(*)                                                                    AS total_customers,
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END)                              AS churned_customers,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS churn_rate_pct,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 0)       AS monthly_revenue_lost,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) * 100.0 /
          (SELECT SUM(MonthlyCharges) FROM telco_customer WHERE Churn = 'Yes'), 1)
                                                                                AS pct_of_revenue_lost,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) / COUNT(*), 1)
                                                                                AS revenue_lost_per_customer
FROM telco_customer
WHERE tenure <= 12
  AND Contract = 'Month-to-month'

UNION ALL

SELECT
    'Fiber + month-to-month',
    COUNT(*),
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 0),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) * 100.0 /
          (SELECT SUM(MonthlyCharges) FROM telco_customer WHERE Churn = 'Yes'), 1),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) / COUNT(*), 1)
FROM telco_customer
WHERE InternetService = 'Fiber optic'
  AND Contract = 'Month-to-month'

UNION ALL

SELECT
    'Electronic check',
    COUNT(*),
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 0),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) * 100.0 /
          (SELECT SUM(MonthlyCharges) FROM telco_customer WHERE Churn = 'Yes'), 1),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) / COUNT(*), 1)
FROM telco_customer
WHERE PaymentMethod = 'Electronic check'

UNION ALL

SELECT
    'No online security',
    COUNT(*),
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 0),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) * 100.0 /
          (SELECT SUM(MonthlyCharges) FROM telco_customer WHERE Churn = 'Yes'), 1),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) / COUNT(*), 1)
FROM telco_customer
WHERE OnlineSecurity = 'No'

UNION ALL

SELECT
    'No tech support',
    COUNT(*),
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 0),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) * 100.0 /
          (SELECT SUM(MonthlyCharges) FROM telco_customer WHERE Churn = 'Yes'), 1),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) / COUNT(*), 1)
FROM telco_customer
WHERE TechSupport = 'No'

UNION ALL

SELECT
    'Senior',
    COUNT(*),
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 0),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) * 100.0 /
          (SELECT SUM(MonthlyCharges) FROM telco_customer WHERE Churn = 'Yes'), 1),
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) / COUNT(*), 1)
FROM telco_customer
WHERE SeniorCitizen = 1

ORDER BY monthly_revenue_lost DESC;


-- ============================================================================
-- 5. HIGH-RISK CUSTOMER PROFILE
-- ----------------------------------------------------------------------------
-- The findings above were partly analysed separately. This query checks
-- whether the combined profile exists: customers matching every risk factor.
-- Result: 544 customers (7.7% of the base), 405 churned: 74.4% churn,
-- 2.8x the baseline. They account for 22% of all churners: the highest-risk
-- group to prioritise, not the typical churner.
-- ============================================================================

SELECT
    COUNT(*)                                                                    AS total_customers,
    SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END)                              AS churned_customers,
    ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS churn_rate_pct
FROM telco_customer
WHERE Contract        = 'Month-to-month'
  AND tenure          <= 12
  AND InternetService = 'Fiber optic'
  AND OnlineSecurity  = 'No'
  AND TechSupport     = 'No'
  AND PaymentMethod   = 'Electronic check';


-- ============================================================================
-- END OF ANALYSIS
-- ============================================================================