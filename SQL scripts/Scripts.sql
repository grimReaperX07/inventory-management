 CREATE TABLE customers (
    CustomerID INTEGER PRIMARY KEY,
    Country TEXT
);

TRUNCATE TABLE customers;

INSERT INTO customers (CustomerID, Country)
SELECT DISTINCT ON (CustomerID) CustomerID, Country
FROM RawSalesData
WHERE CustomerID IS NOT NULL;

CREATE TABLE products (
    StockCode TEXT PRIMARY KEY,
    Description TEXT,
    UnitPrice NUMERIC
);

TRUNCATE TABLE products;

INSERT INTO products (StockCode, Description, UnitPrice)
SELECT DISTINCT ON (StockCode) StockCode, Description, UnitPrice
FROM RawSalesData;

CREATE TABLE invoices (
    InvoiceNo TEXT PRIMARY KEY,
    InvoiceDate TIMESTAMP,
    CustomerID INTEGER
);

INSERT INTO invoices (InvoiceNo, InvoiceDate, CustomerID)
SELECT DISTINCT ON (InvoiceNo)
  InvoiceNo,
  TO_TIMESTAMP(InvoiceDate, 'MM/DD/YYYY HH24:MI'),
  CustomerID
FROM RawSalesData
WHERE CustomerID IS NOT NULL;

CREATE TABLE invoicedetails (
    InvoiceNo TEXT,
    StockCode TEXT,
    Quantity INTEGER,
    PRIMARY KEY (InvoiceNo, StockCode),
    FOREIGN KEY (InvoiceNo) REFERENCES invoices(InvoiceNo),
    FOREIGN KEY (StockCode) REFERENCES products(StockCode)
);

INSERT INTO invoicedetails (InvoiceNo, StockCode, Quantity)
SELECT InvoiceNo, StockCode, SUM(Quantity)
FROM RawSalesData
WHERE InvoiceNo IN (SELECT InvoiceNo FROM invoices)
GROUP BY InvoiceNo, StockCode;


SELECT * FROM customers;

SELECT * FROM products;

SELECT * FROM invoices;

SELECT * FROM invoicedetails;

/* 🧮 Sales Performance
1.What is the total revenue generated?

-- 💰 Total Revenue Generated
CREATE OR REPLACE VIEW v_total_revenue AS
WITH cte AS (
    SELECT 
        id.InvoiceNo,
        id.StockCode,
        id.Quantity,
        p.UnitPrice,
        (p.UnitPrice * id.Quantity) AS Sales
    FROM Products p
    JOIN InvoiceDetails id 
        ON p.StockCode = id.StockCode
)
SELECT 
    SUM(Sales) AS Total_Revenue
FROM cte;

2.What is the average revenue per invoice? 

-- 💰 AVG Revenue per invoice
CREATE OR REPLACE VIEW v_avg_revenue AS
WITH cte AS (
    SELECT 
        id.InvoiceNo,
        id.StockCode,
        id.Quantity,
        p.UnitPrice,
        (p.UnitPrice * id.Quantity) AS Sales
    FROM Products p
    JOIN InvoiceDetails id 
        ON p.StockCode = id.StockCode
), cte2 as(
SELECT 
        InvoiceNo,
        SUM(Sales) AS invoice_total
    FROM cte
    GROUP BY InvoiceNo
    )
SELECT 
    round(AVG(invoice_total),3) AS avg_revenue_per_invoice
FROM cte2
        
3.What is the highest single invoice amount?

CREATE OR REPLACE VIEW v_highest_single_invoice_amount AS
WITH cte AS (
    SELECT 
        id.InvoiceNo,
        id.StockCode,
        id.Quantity,
        p.UnitPrice,
        (p.UnitPrice * id.Quantity) AS Sales
    FROM Products p
    JOIN InvoiceDetails id 
        ON p.StockCode = id.StockCode
), cte2 as(
SELECT 
        InvoiceNo,
        SUM(Sales) AS invoice_total
    FROM cte
    GROUP BY InvoiceNo
    )
SELECT 
    Max(invoice_total) AS highest_single_invoice_amount
FROM cte2

4.Which days/months/quarters had the highest sales?

CREATE OR REPLACE VIEW v_days_months_quaters_highest_sales AS
WITH cte AS (
    SELECT 
        id.InvoiceNo,
        id.StockCode,
        id.Quantity,
        p.UnitPrice,
        i.InvoiceDate,
        EXTRACT(DAY FROM i.InvoiceDate) AS day_sale,
        EXTRACT(MONTH FROM i.InvoiceDate) AS month_sale,
        EXTRACT(QUARTER FROM i.InvoiceDate) AS quarter_sale,
        (p.UnitPrice * id.Quantity) AS Sales
    FROM Products p
    JOIN InvoiceDetails id ON p.StockCode = id.StockCode
    JOIN Invoices i ON i.InvoiceNo = id.InvoiceNo
),
highest_day_sale AS (
    SELECT day_sale, SUM(Sales) AS total_day_sales
    FROM cte
    GROUP BY day_sale
),
highest_month_sale AS (
    SELECT month_sale, SUM(Sales) AS total_month_sales
    FROM cte
    GROUP BY month_sale
),
highest_quarter_sale AS (
    SELECT quarter_sale, SUM(Sales) AS total_quarter_sales
    FROM cte
    GROUP BY quarter_sale
)

SELECT
    (SELECT MAX(total_day_sales) FROM highest_day_sale) AS highest_sale_in_a_day,
    (SELECT MAX(total_month_sales) FROM highest_month_sale) AS highest_sale_in_a_month,
    (SELECT MAX(total_quarter_sales) FROM highest_quarter_sale) AS highest_sale_in_a_quarter;


5.How does sales vary over time (daily/weekly/monthly trend)?

CREATE OR REPLACE VIEW v_salary_vary_over_time AS
  SELECT 
    DATE(i.InvoiceDate) AS sales_date,
    DATE_TRUNC('week', i.InvoiceDate) AS sales_week,
    DATE_TRUNC('month', i.InvoiceDate) AS sales_month,
    SUM(id.Quantity * p.UnitPrice) AS total_sales
FROM InvoiceDetails id
JOIN Products p ON id.StockCode = p.StockCode
JOIN Invoices i ON id.InvoiceNo = i.InvoiceNo
GROUP BY sales_date,sales_week,sales_month
ORDER BY sales_date,sales_week,sales_month; 

Bonus Question- Sales trend

CREATE OR REPLACE VIEW v_sales_trend AS
SELECT 
    i.InvoiceDate::date AS sales_date,
    SUM(p.UnitPrice * id.Quantity) AS total_sales
FROM Products p
JOIN InvoiceDetails id ON p.StockCode = id.StockCode
JOIN Invoices i ON i.InvoiceNo = id.InvoiceNo
GROUP BY sales_date
ORDER BY sales_date;

📦 Product-Level Analysis
6.What are the top 10 best-selling products by quantity?
CREATE OR REPLACE VIEW v_top10_products_quantity AS
SELECT 
    id.StockCode,
    p.description,
    SUM(id.Quantity) AS total_quantity_sold
FROM InvoiceDetails id
JOIN products p  ON p.stockcode = id.stockcode
WHERE id.Quantity > 0  -- Exclude returns
GROUP BY id.StockCode,p.description
ORDER BY total_quantity_sold DESC
LIMIT 10;

7.What are the top 10 products by revenue?

CREATE OR REPLACE VIEW v_top10_products_revenue AS
WITH cte AS (
  SELECT 
        id.StockCode,
        id.Quantity,
        p.UnitPrice,
        (p.UnitPrice * id.Quantity) AS Sales
    FROM Products p
    JOIN InvoiceDetails id 
        ON p.StockCode = id.StockCode
    WHERE id.Quantity > 0  
)
SELECT 
    stockcode,
    SUM(sales) AS total_sales
FROM cte 
GROUP BY stockcode 
ORDER BY total_sales DESC
LIMIT 10;

8.Which products are frequently returned (if return data exists)? X (Requires a Category column or a ProductCategories table.)

SELECT 
    id.StockCode,
    p.Description,
    COUNT(*) AS return_count,
    SUM(ABS(id.Quantity)) AS total_returned_qty
FROM InvoiceDetails id
JOIN Products p ON p.StockCode = id.StockCode
WHERE id.Quantity < 0
GROUP BY id.StockCode, p.Description
ORDER BY total_returned_qty DESC
LIMIT 10;


9.What is the average unit price by product? 

CREATE OR REPLACE VIEW v_avg_unit_price_product AS
SELECT p.stockcode ,p.description, avg(p.unitprice ) AS avg_unit_price
FROM products p 
JOIN invoicedetails id ON p.stockcode = id.stockcode
GROUP BY p.stockcode, p.description;

10.Which product categories (if applicable) contribute most to revenue? X 

WITH cte AS (
	SELECT  
		id.StockCode,
		p.description,
        id.Quantity,
        p.UnitPrice,
        (p.UnitPrice * id.Quantity) AS Sales
	FROM products p 
	JOIN InvoiceDetails id 
	ON p.StockCode = id.StockCode
			)
SELECT 	
	description, 
	sum(sales) AS total_sales
FROM cte
GROUP BY description
ORDER BY total_sales DESC 

👥 Customer Analysis
11.How many unique customers are there?

CREATE OR REPLACE VIEW v_unique_customers AS
SELECT count(distinct(c.customerid )) AS no_of_unique_customers
FROM customers c 
WHERE c.CustomerID IS NOT NULL

12.Who are the top customers by revenue?

CREATE OR REPLACE VIEW v_top_customers_revenue AS
SELECT c.customerid,c.country,sum(id.quantity * p.unitprice) AS total_sales 
FROM customers c 
JOIN invoices i
ON c.customerid = i.customerid 
JOIN invoicedetails id
ON i.invoiceno = id.invoiceno 
JOIN products p
ON id.stockcode = p.stockcode 
GROUP BY c.customerid,c.country
ORDER BY total_sales DESC
LIMIT 10;

13.What is the average revenue per customer? 

CREATE OR REPLACE VIEW v_avg_revenue_per_customer AS
WITH cte AS (
SELECT c.customerid,sum(id.quantity * p.unitprice) total_sales 
FROM customers c 
JOIN invoices i
ON c.customerid = i.customerid 
JOIN invoicedetails id
ON i.invoiceno = id.invoiceno 
JOIN products p
ON id.stockcode = p.stockcode 
GROUP BY c.customerid
			)
SELECT  customerid, avg(total_sales) AS avg_sales
FROM  cte
GROUP BY customerid 

14.Which countries/states have the highest customer base? 

CREATE OR REPLACE VIEW v_top_countries_customers AS
SELECT c.country,count(*) AS no_of_customers 
FROM customers c 
GROUP BY c.country 
ORDER BY no_of_customers DESC 

15.What’s the customer distribution by country?

CREATE OR REPLACE VIEW v_customer_distribution_country AS
SELECT 
  c.country,
  COUNT(*) AS no_of_customers,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percent_of_total
FROM customers c 
GROUP BY c.country 
ORDER BY no_of_customers DESC;

Bonus: Sales by country and product

CREATE OR REPLACE VIEW v_sales_by_country_product AS
SELECT
  i.InvoiceDate::date         AS sales_date,
  c.country                   AS country,
  p.StockCode                 AS stockcode,
  SUM(id.Quantity)            AS total_quantity,
  SUM(id.Quantity * p.UnitPrice) AS total_sales
FROM InvoiceDetails id
JOIN Invoices i   ON id.InvoiceNo = i.InvoiceNo
JOIN Customers c  ON i.CustomerID = c.CustomerID
JOIN Products p   ON id.StockCode = p.StockCode
GROUP BY sales_date, country, p.StockCode;


🧾 Invoice-Level Analysis
16.What’s the average number of items per invoice (basket size)?

CREATE OR REPLACE VIEW v_avg_items_per_invoice AS
WITH cte AS (
  SELECT 
    i.InvoiceNo,
    id.Quantity
  FROM invoices i 
  JOIN invoicedetails id ON i.invoiceno = id.invoiceno 
)
SELECT
  Round(SUM(quantity) * 1.0 / COUNT(DISTINCT invoiceno),2) AS avg_items_per_invoice
FROM cte

17.Which invoices have unusually high or low total amounts? 

CREATE OR REPLACE VIEW v_unusual_invoices AS
WITH invoice_totals AS (
SELECT id.invoiceno , sum(id.quantity * p.unitprice) AS total_sales
FROM invoicedetails id
JOIN products p  ON id.stockcode  = p.stockcode  
GROUP BY id.invoiceno 
),
stats AS (
  SELECT 
    AVG(total_sales) AS avg_sales,
    STDDEV(total_sales) AS stddev_sales
  FROM invoice_totals
  )
SELECT 
  i.InvoiceNo,
  i.total_sales,
  s.avg_sales,
  s.stddev_sales,
  CASE 
    WHEN i.total_sales > s.avg_sales + 2 * s.stddev_sales THEN 'Unusually High'
    WHEN i.total_sales < s.avg_sales - 2 * s.stddev_sales THEN 'Unusually Low'
    ELSE 'Normal'
  END AS anomaly_status
FROM invoice_totals i
CROSS JOIN stats s
ORDER BY i.total_sales DESC;

[ Logic - Z-Score Method (Standard Deviation Rule) We assume that most invoice totals are 
 	clustered around the average (mean). To find outliers (unusually high or low invoices), 
	we calculate how far an invoice’s total is from the average.

	This is based on the empirical rule from statistics:
	About 95% of values fall within ±2 standard deviations from the mean.
	So anything beyond that is statistically rare = unusual.
	
	🧠 Breakdown:
	avg_sales: average invoice total
	stddev_sales: how spread out the sales values are
	If an invoice is far above or below average, it might be a suspicious transaction, bulk order, or error.]

18.What is the invoice return rate (if returns table exists)? x

SELECT 
  ROUND(
    COUNT(DISTINCT CASE WHEN Quantity < 0 THEN InvoiceNo END) * 100.0 / 
    COUNT(DISTINCT InvoiceNo),
    2
  ) AS invoice_return_rate_percent
FROM InvoiceDetails;

19.How many items are sold per invoice on average?

CREATE OR REPLACE VIEW v_avg_items_sold_per_invoice AS
WITH cte AS (
SELECT id.invoiceno 
,sum(id.quantity) AS total_items
FROM invoicedetails id
JOIN products p  ON id.stockcode  = p.stockcode  
GROUP BY id.invoiceno
)
SELECT 
  ROUND(AVG(total_items), 2) AS avg_items_sold_per_invoice
FROM cte;

📊 Inventory & Stock Movement X (All require an Inventory table with current stock and restock data.)
20.Which products are low in stock? 

SELECT 
  p.stockcode,
  p.description,
  SUM(id.quantity) AS total_quantity_sold
FROM products p
JOIN invoicedetails id ON p.stockcode = id.stockcode
GROUP BY p.stockcode, p.description
ORDER BY total_quantity_sold DESC
LIMIT 10;

--[Fast selling products likely TO GO OUT OF stock, since there IS NO stocks table]

21.What are the most restocked products?

SELECT 
  id.stockcode,
  p.description,
  COUNT(*) AS restock_events,
  SUM(id.quantity) AS total_restocked_quantity
FROM invoicedetails id
JOIN products p ON id.stockcode = p.stockcode
WHERE id.quantity > 100  -- threshold for assuming restock
GROUP BY id.stockcode, p.description
ORDER BY total_restocked_quantity DESC;

[quantity > 100: Assumes large quantities represent incoming stock or restocks.

COUNT(*): Number of times this product was "restocked".

SUM(quantity): Total volume "restocked".]

22.What’s the average inventory holding time?

SELECT 
  id.stockcode,
  p.description,
  COUNT(DISTINCT i.invoiceno) AS times_sold,
  SUM(id.quantity) AS total_quantity_sold,
  MIN(i.invoicedate) AS first_sold_date,
  MAX(i.invoicedate) AS last_sold_date,
 (
    SUM(id.quantity)::numeric / NULLIF(DATE_PART('day', MAX(i.invoicedate) - MIN(i.invoicedate)), 0), 2
  ) AS avg_daily_sales -- proxy for fast or slow moving
FROM invoicedetails id
JOIN invoices i ON id.invoiceno = i.invoiceno
JOIN products p ON id.stockcode = p.stockcode
GROUP BY id.stockcode, p.description
ORDER BY avg_daily_sales DESC;

[A proxy for how fast a product moves (which indirectly tells you holding time).

Products with low avg_daily_sales are likely to stay longer in inventory]

23.Are there products with zero sales but available stock?

SELECT p.stockcode, p.description
FROM products p
LEFT JOIN invoicedetails id ON p.stockcode = id.stockcode
WHERE id.stockcode IS NULL;

[product with zero sales]

📉 Returns & Issues X (Requires a Returns table with return dates and invoice references.)
24.What percentage of sales are returned?

SELECT 
    SUM(CASE WHEN id.quantity > 0 THEN id.quantity * p.unitprice ELSE 0 END) AS total_sales_amount,
    ABS(SUM(CASE WHEN id.quantity < 0 THEN id.quantity * p.unitprice ELSE 0 END)) AS total_returns_amount,
    ROUND(
        ABS(SUM(CASE WHEN id.quantity < 0 THEN id.quantity * p.unitprice ELSE 0 END)) 
        / SUM(CASE WHEN id.quantity > 0 THEN id.quantity * p.unitprice ELSE 0 END) * 100, 2
    ) AS return_percentage
FROM invoicedetails id
JOIN products p 
    ON id.stockcode = p.stockcode;

25.Which products/customers have the highest return rates?

WITH sales AS (
    SELECT 
        p.stockcode,
        c.customerid,
        SUM(CASE WHEN id.quantity > 0 THEN id.quantity ELSE 0 END) AS total_sold,
        ABS(SUM(CASE WHEN id.quantity < 0 THEN id.quantity ELSE 0 END)) AS total_returned
    FROM products p
    JOIN invoicedetails id ON id.stockcode = p.stockcode
    JOIN invoices i ON id.invoiceno = i.invoiceno
    JOIN customers c ON i.customerid = c.customerid
    GROUP BY p.stockcode, c.customerid
)
SELECT
    stockcode,
    customerid,
    total_sold,
    total_returned,
    CASE 
        WHEN total_sold > 0 THEN ROUND((total_returned / total_sold)* 100,2)
        ELSE 0
    END AS return_rate_percentage
FROM sales
ORDER BY return_rate_percentage DESC;

26.What’s the average return time? */


