-- ============================================================
-- TELCO CUSTOMER CHURN ANALYSIS
-- Dataset: Telco Customer Churn (Kaggle) · 7,043 customers · 21 columns
-- Tool: MySQL
--
-- Client:   Head of Customer Retention (simulated)
-- Decision: which customer segments and levers to focus retention on,
--           with a limited budget that cannot cover every customer
--
-- Business questions
--   Q1. Which types of customers churn the most?
--   Q2. Do customers with certain services churn less?
--   Q3. Do contract and payment conditions affect churn?
--   Q4. Do customers who pay more churn more?
--   Q5. How much monthly revenue is lost per segment?
-- ============================================================

-- ============================================================
-- 1. SETUP
-- ============================================================

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

LOAD DATA LOCAL INFILE 'path/to/WA_Fn-UseC_-Telco-Customer-Churn.csv'
INTO TABLE telco_customer
FIELDS TERMINATED BY ','
LINES TERMINATED BY '\n'
IGNORE 1 LINES;


-- ============================================================
-- 2. DATA PROFILING
-- ============================================================

-- Preview the dataset
SELECT *
FROM telco_customer
LIMIT 10;

-- How many customers are there?
SELECT COUNT(*) AS total_customers
FROM telco_customer;

-- Are there duplicate customer IDs?
SELECT customerID,
       COUNT(*) AS occurrences
FROM telco_customer
GROUP BY customerID
HAVING COUNT(*) > 1;

-- What values exist in each categorical column, and how many customers in each?
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

-- What range do the numeric columns cover?
SELECT MIN(tenure)         AS min_tenure,
       MAX(tenure)         AS max_tenure,
       MIN(MonthlyCharges) AS min_monthly_charges,
       MAX(MonthlyCharges) AS max_monthly_charges
FROM telco_customer;

-- Finding: 7,043 customers, no duplicates. All categories are spelled
-- consistently and the smallest group has 682 customers, enough to trust
-- the rates. Tenure ranges from 0 to 72 months and monthly charges from
-- $18.25 to $118.75, all plausible.
-- 'No internet service' and 'No phone service' are not errors: they are
-- customers who cannot have that service, excluded when analysing it.


-- ============================================================
-- 3. DATA CLEANING
-- ============================================================

-- Are there missing values in TotalCharges?
SELECT SUM(CASE WHEN TotalCharges IS NULL THEN 1 ELSE 0 END)    AS null_values,
       SUM(CASE WHEN TRIM(TotalCharges) = '' THEN 1 ELSE 0 END) AS blank_values,
       SUM(CASE WHEN tenure = 0 THEN 1 ELSE 0 END)              AS zero_tenure
FROM telco_customer;

-- Finding: 11 blank values (a space, not NULL), matching exactly the
-- 11 customers with zero tenure: new customers not billed yet.
-- They are set to 0 rather than NULL, since the amount is known.

UPDATE telco_customer
SET TotalCharges = '0'
WHERE TRIM(TotalCharges) = '';

ALTER TABLE telco_customer
MODIFY TotalCharges DECIMAL(10,2);

-- Why does the churn rate return 0% when there are 1,869 churners?
SELECT DISTINCT Churn,
       LENGTH(Churn) AS value_length
FROM telco_customer;

-- Finding: 'Yes' has 4 characters instead of 3. A Windows carriage return
-- (\r) was attached to every Churn value during the CSV import, so any
-- filter on Churn = 'Yes' returned no rows.

UPDATE telco_customer
SET Churn = TRIM(TRAILING '\r' FROM Churn);


-- ============================================================
-- 4. OVERALL CHURN RATE
-- Baseline that every segment is compared to
-- ============================================================

SELECT COUNT(*) AS total_customers,
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) AS churned_customers,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate
FROM telco_customer;

-- Finding: 1,869 of 7,043 customers churned: 26.54%, just over 1 in 4.


-- ============================================================
-- 5. Q1. CUSTOMER PROFILE
-- Which types of customers churn the most?
-- ============================================================

-- Churn by tenure band
SELECT CASE
           WHEN tenure BETWEEN 0  AND 12 THEN '0-12 months'
           WHEN tenure BETWEEN 13 AND 24 THEN '13-24 months'
           WHEN tenure BETWEEN 25 AND 36 THEN '25-36 months'
           WHEN tenure BETWEEN 37 AND 48 THEN '37-48 months'
           WHEN tenure BETWEEN 49 AND 60 THEN '49-60 months'
           ELSE '61-72 months'
       END AS tenure_band,
       COUNT(*) AS total_customers,
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) AS churned_customers,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate
FROM telco_customer
GROUP BY tenure_band
ORDER BY tenure_band;

-- Finding: First-year customers churn at 47.44% (55% of churners).
-- Churn falls steadily with tenure, down to 6.61% after five years.

-- Is first-year churn explained by the contract type?
SELECT CASE WHEN tenure <= 12 THEN 'First year' ELSE 'More than one year' END AS tenure_group,
       Contract,
       COUNT(*) AS total_customers,
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) AS churned_customers,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate
FROM telco_customer
GROUP BY Contract, tenure_group
ORDER BY Contract, tenure_group;

-- Finding: 91% of new customers are on month-to-month contracts, but
-- within that contract new customers still churn 18 points more
-- (51.35% vs 33.55%). On one-year contracts there is no difference.

-- When do new month-to-month customers leave?
SELECT CASE
           WHEN tenure BETWEEN 0 AND 3 THEN '01-03 months'
           WHEN tenure BETWEEN 4 AND 6 THEN '04-06 months'
           WHEN tenure BETWEEN 7 AND 9 THEN '07-09 months'
           ELSE '10-12 months'
       END AS tenure_band,
       COUNT(*) AS total_customers,
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) AS churned_customers,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate
FROM telco_customer
WHERE Contract = 'Month-to-month'
  AND tenure <= 12
GROUP BY tenure_band
ORDER BY tenure_band;

-- Finding: Months 1-3 have the highest rate (58.05%) and 595 of the
-- group's 1,024 churners. Churn stays above 40% for the whole first year.

-- Which protection services matter most for new month-to-month customers?
SELECT 'OnlineSecurity' AS service, OnlineSecurity AS value, COUNT(*) AS customers,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate
FROM telco_customer
WHERE Contract = 'Month-to-month' AND tenure <= 12 AND OnlineSecurity <> 'No internet service'
GROUP BY OnlineSecurity
UNION ALL
SELECT 'TechSupport', TechSupport, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer
WHERE Contract = 'Month-to-month' AND tenure <= 12 AND TechSupport <> 'No internet service'
GROUP BY TechSupport
UNION ALL
SELECT 'OnlineBackup', OnlineBackup, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer
WHERE Contract = 'Month-to-month' AND tenure <= 12 AND OnlineBackup <> 'No internet service'
GROUP BY OnlineBackup
UNION ALL
SELECT 'DeviceProtection', DeviceProtection, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer
WHERE Contract = 'Month-to-month' AND tenure <= 12 AND DeviceProtection <> 'No internet service'
GROUP BY DeviceProtection;

-- Finding: Online security (23 points) and tech support (18 points) make
-- the biggest difference, and only about 15% of these customers have them.

-- Churn by demographics
SELECT 'SeniorCitizen' AS variable,
       CASE WHEN SeniorCitizen = 1 THEN 'Senior' ELSE 'Non-senior' END AS value,
       COUNT(*) AS customers,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate
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

-- Finding: Seniors (41.68%), customers without dependents (31.28%) and
-- without a partner (32.96%) churn more. Gender shows no difference.
-- Demographics are not levers: they help decide whom to target.


-- ============================================================
-- 6. Q2. SERVICES
-- Do customers with certain services churn less?
-- ============================================================

-- Churn and average monthly charge by internet service
SELECT InternetService,
       COUNT(*) AS total_customers,
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) AS churned_customers,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate,
       ROUND(AVG(MonthlyCharges), 2) AS avg_monthly_charge
FROM telco_customer
GROUP BY InternetService;

-- Finding: Fiber churns at 41.89%, more than double DSL (18.96%), while
-- paying about $33 more per month. It accounts for 69% of churners.

-- Is fiber churn explained by the contract type?
SELECT InternetService,
       Contract,
       COUNT(*) AS total_customers,
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) AS churned_customers,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate
FROM telco_customer
GROUP BY InternetService, Contract
ORDER BY Contract, InternetService;

-- Finding: Fiber churns more than DSL under every contract
-- (+22 points month-to-month, +10 one year, +5 two year), so fiber has
-- its own problem. Fiber + month-to-month: 54.61% churn, 62% of churners.

-- Churn by tech support
SELECT TechSupport,
       COUNT(*) AS total_customers,
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) AS churned_customers,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate
FROM telco_customer
GROUP BY TechSupport;

-- Is the tech support effect explained by the contract type?
SELECT TechSupport,
       Contract,
       COUNT(*) AS total_customers,
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) AS churned_customers,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate
FROM telco_customer
WHERE TechSupport <> 'No internet service'
GROUP BY Contract, TechSupport
ORDER BY Contract, TechSupport;

-- Finding: Without tech support 41.64% vs 15.17% with it. Part of the gap
-- comes from contract type (customers with tech support tend to have long
-- contracts), but among month-to-month customers it holds at 20 points.

-- Churn with and without the remaining services
SELECT 'OnlineSecurity' AS service, OnlineSecurity AS value, COUNT(*) AS customers,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate
FROM telco_customer WHERE OnlineSecurity <> 'No internet service' GROUP BY OnlineSecurity
UNION ALL
SELECT 'OnlineBackup', OnlineBackup, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer WHERE OnlineBackup <> 'No internet service' GROUP BY OnlineBackup
UNION ALL
SELECT 'DeviceProtection', DeviceProtection, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer WHERE DeviceProtection <> 'No internet service' GROUP BY DeviceProtection
UNION ALL
SELECT 'StreamingTV', StreamingTV, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer WHERE StreamingTV <> 'No internet service' GROUP BY StreamingTV
UNION ALL
SELECT 'StreamingMovies', StreamingMovies, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer WHERE StreamingMovies <> 'No internet service' GROUP BY StreamingMovies
UNION ALL
SELECT 'PhoneService', PhoneService, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer GROUP BY PhoneService
UNION ALL
SELECT 'MultipleLines', MultipleLines, COUNT(*),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2)
FROM telco_customer WHERE MultipleLines <> 'No phone service' GROUP BY MultipleLines;

-- Finding: Protection services make the difference: online security
-- (41.77% vs 14.61%), online backup and device protection (17-18 points).
-- Streaming, phone and multiple lines show 2-4 points, not meaningful.


-- ============================================================
-- 7. Q3. CONTRACT AND PAYMENT
-- Do contract and payment conditions affect churn?
-- ============================================================

-- Churn by contract type
SELECT Contract,
       COUNT(*) AS total_customers,
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) AS churned_customers,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate
FROM telco_customer
GROUP BY Contract;

-- Finding: Month-to-month churns at 42.71%, 15x the two-year rate (2.83%),
-- and accounts for 89% of all churners.

-- Churn by payment method
SELECT PaymentMethod,
       COUNT(*) AS total_customers,
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) AS churned_customers,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate
FROM telco_customer
GROUP BY PaymentMethod
ORDER BY churn_rate DESC;

-- Finding: Electronic check churns at 45.29% vs 15-17% for automatic
-- payment methods, and accounts for 57% of all churners.

-- Churn by paperless billing
SELECT PaperlessBilling,
       COUNT(*) AS total_customers,
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) AS churned_customers,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate
FROM telco_customer
GROUP BY PaperlessBilling;

-- Finding: 33.57% vs 16.33%, but receiving the bill by email is unlikely
-- to cause churn. More likely a marker of a more digital, newer customer.
-- Not treated as a lever.


-- ============================================================
-- 8. Q4. PRICE
-- Do customers who pay more churn more?
-- ============================================================

-- Churn by monthly charge band
SELECT CASE
           WHEN MonthlyCharges < 30 THEN '1. Under 30'
           WHEN MonthlyCharges < 50 THEN '2. 30 to 50'
           WHEN MonthlyCharges < 70 THEN '3. 50 to 70'
           WHEN MonthlyCharges < 90 THEN '4. 70 to 90'
           ELSE '5. 90 or more'
       END AS charge_band,
       COUNT(*) AS total_customers,
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) AS churned_customers,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS churn_rate
FROM telco_customer
GROUP BY charge_band
ORDER BY charge_band;

-- Do churners pay more than customers who stay, within the same service?
SELECT InternetService,
       Churn,
       COUNT(*) AS customers,
       ROUND(AVG(MonthlyCharges), 2) AS avg_monthly_charge
FROM telco_customer
GROUP BY InternetService, Churn
ORDER BY InternetService, Churn;

-- Finding: No consistent pattern by charge band. Within the same internet
-- service, churners pay the same or less than customers who stay
-- (fiber $88.13 vs $93.93). Price alone does not explain churn.


-- ============================================================
-- 9. Q5. REVENUE LOST
-- Where should a limited budget start?
-- ============================================================

-- Monthly revenue lost by contract type
SELECT Contract,
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) AS churned_customers,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 0) AS revenue_lost,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) * 100.0 /
             (SELECT SUM(MonthlyCharges) FROM telco_customer WHERE Churn = 'Yes'), 1) AS pct_revenue_lost
FROM telco_customer
GROUP BY Contract;

-- Finding: $139,131 of monthly revenue is lost. Month-to-month accounts
-- for 87% of it.

-- Revenue lost by key segment
SELECT 'First year + month-to-month' AS segment,
       COUNT(*) AS total_customers,
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) AS churned_customers,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS churn_rate,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 0) AS revenue_lost,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) / COUNT(*), 1) AS revenue_lost_per_customer
FROM telco_customer
WHERE tenure <= 12 AND Contract = 'Month-to-month'
UNION ALL
SELECT 'Fiber + month-to-month', COUNT(*),
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 0),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) / COUNT(*), 1)
FROM telco_customer
WHERE InternetService = 'Fiber optic' AND Contract = 'Month-to-month'
UNION ALL
SELECT 'Electronic check', COUNT(*),
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 0),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) / COUNT(*), 1)
FROM telco_customer
WHERE PaymentMethod = 'Electronic check'
UNION ALL
SELECT 'No online security', COUNT(*),
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 0),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) / COUNT(*), 1)
FROM telco_customer
WHERE OnlineSecurity = 'No'
UNION ALL
SELECT 'No tech support', COUNT(*),
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 0),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) / COUNT(*), 1)
FROM telco_customer
WHERE TechSupport = 'No'
UNION ALL
SELECT 'Senior', COUNT(*),
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END), 0),
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN MonthlyCharges ELSE 0 END) / COUNT(*), 1)
FROM telco_customer
WHERE SeniorCitizen = 1
ORDER BY revenue_lost DESC;

-- Finding: Segments without online security or tech support lose the most
-- in total because they are large. Fiber + month-to-month is the most
-- efficient place to start: 54.6% churn and $47.2 at risk per customer
-- contacted, vs $32-36 in the other segments.


-- ============================================================
-- 10. HIGH-RISK PROFILE
-- Does the combined risk profile actually exist?
-- ============================================================

SELECT COUNT(*) AS total_customers,
       SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) AS churned_customers,
       ROUND(SUM(CASE WHEN Churn = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS churn_rate
FROM telco_customer
WHERE Contract = 'Month-to-month'
  AND tenure <= 12
  AND InternetService = 'Fiber optic'
  AND OnlineSecurity = 'No'
  AND TechSupport = 'No'
  AND PaymentMethod = 'Electronic check';

-- Finding: 544 customers match every risk factor and 74.4% of them
-- churned, nearly 3x the company average. They account for 22% of all
-- churners: the first group to target, but not the typical churner.
