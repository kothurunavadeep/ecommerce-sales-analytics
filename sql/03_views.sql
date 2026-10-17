/* =====================================================================
   OLIST E-COMMERCE ANALYTICS  |  03_views.sql
   ---------------------------------------------------------------------
   KPI DEFINITIONS (used consistently in SQL, Excel and Power BI)
     Revenue (Product Sales) = SUM(price) of items in orders with status = 'delivered'
     Freight Revenue         = SUM(freight_value), same filter
     GMV                     = Revenue + Freight
     Orders                  = distinct delivered orders
     AOV                     = Revenue / Orders
     Active customer         = customer_unique_id with >= 1 delivered order
     Repeat customer         = customer_unique_id with >= 2 delivered orders
     On-time delivery        = delivered date <= estimated delivery date
     Full analysis window    = 2017-01-01 .. 2018-08-31 (complete months only)
   ===================================================================== */

-- ---------- Item-grain flat table: the single source for most analysis ----------
DROP VIEW IF EXISTS vw_order_items_flat;
CREATE VIEW vw_order_items_flat AS
SELECT
    i.order_id,
    i.order_item_id,
    CASE WHEN i.order_item_id = 1 THEN 1 ELSE 0 END      AS is_first_item,   -- count orders with this flag
    o.order_status,
    CASE WHEN o.order_status = 'delivered' THEN 1 ELSE 0 END AS is_revenue,
    o.purchase_date,
    strftime('%Y-%m', o.purchase_date)                   AS year_month,
    CAST(strftime('%Y', o.purchase_date) AS INTEGER)     AS order_year,
    o.delivery_days, o.estimated_days, o.delay_days, o.is_late,
    c.customer_id, c.customer_unique_id, c.city AS customer_city, c.state AS customer_state,
    p.product_id, p.category,
    s.seller_id, s.city AS seller_city, s.state AS seller_state,
    i.price, i.freight_value,
    i.price + i.freight_value                            AS gmv,
    r.review_score,
    pay.payment_type                                     AS primary_payment_type
FROM fact_order_items i
JOIN fact_orders    o ON o.order_id    = i.order_id
JOIN dim_customers  c ON c.customer_id = o.customer_id
JOIN dim_products   p ON p.product_id  = i.product_id
JOIN dim_sellers    s ON s.seller_id   = i.seller_id
LEFT JOIN fact_reviews  r   ON r.order_id   = i.order_id
LEFT JOIN fact_payments pay ON pay.order_id = i.order_id AND pay.payment_sequential = 1;

-- ---------- Order-grain table ----------
DROP VIEW IF EXISTS vw_orders_enriched;
CREATE VIEW vw_orders_enriched AS
SELECT
    o.order_id, o.order_status, o.purchase_date, strftime('%Y-%m', o.purchase_date) AS year_month,
    o.delivery_days, o.estimated_days, o.delay_days, o.is_late,
    c.customer_id, c.customer_unique_id, c.city AS customer_city, c.state AS customer_state,
    COALESCE(it.items, 0)      AS items,
    COALESCE(it.revenue, 0)    AS revenue,
    COALESCE(it.freight, 0)    AS freight,
    COALESCE(it.revenue,0) + COALESCE(it.freight,0) AS gmv,
    pm.payment_total, pm.max_installments, pm.primary_payment_type,
    r.review_score
FROM fact_orders o
JOIN dim_customers c ON c.customer_id = o.customer_id
LEFT JOIN (SELECT order_id, COUNT(*) AS items, SUM(price) AS revenue, SUM(freight_value) AS freight
           FROM fact_order_items GROUP BY order_id) it ON it.order_id = o.order_id
LEFT JOIN (SELECT order_id, SUM(payment_value) AS payment_total, MAX(payment_installments) AS max_installments,
                  MAX(CASE WHEN payment_sequential = 1 THEN payment_type END) AS primary_payment_type
           FROM fact_payments GROUP BY order_id) pm ON pm.order_id = o.order_id
LEFT JOIN fact_reviews r ON r.order_id = o.order_id;

-- ---------- Customer-grain (real people, via customer_unique_id) ----------
DROP VIEW IF EXISTS vw_customer_summary;
CREATE VIEW vw_customer_summary AS
SELECT
    customer_unique_id,
    MAX(customer_state)             AS state,
    COUNT(*)                        AS delivered_orders,
    ROUND(SUM(revenue), 2)          AS total_revenue,
    ROUND(AVG(revenue), 2)          AS avg_order_value,
    MIN(purchase_date)              AS first_order_date,
    MAX(purchase_date)              AS last_order_date,
    ROUND(AVG(review_score), 2)     AS avg_review_score
FROM vw_orders_enriched
WHERE order_status = 'delivered'
GROUP BY customer_unique_id;

-- ---------- RFM scoring (customer_unique_id level, delivered orders only) ----------
-- Reference date = day after the last delivered purchase in the data (reproducible, not CURRENT_DATE).
-- R score: 5 = most recent (quintiles).  M score: 5 = highest spend (quintiles).
-- F score: 97% of customers bought once, so quintiles would be meaningless -> fixed rule:
--          1 order = 1, 2 orders = 3, 3+ orders = 5.
DROP VIEW IF EXISTS vw_rfm;
CREATE VIEW vw_rfm AS
WITH ref AS (
    SELECT DATE(MAX(purchase_date), '+1 day') AS ref_date FROM fact_orders WHERE order_status = 'delivered'
),
base AS (
    SELECT customer_unique_id,
           CAST(julianday((SELECT ref_date FROM ref)) - julianday(MAX(purchase_date)) AS INTEGER) AS recency_days,
           COUNT(*)               AS frequency,
           ROUND(SUM(revenue), 2) AS monetary
    FROM vw_orders_enriched
    WHERE order_status = 'delivered'
    GROUP BY customer_unique_id
),
scored AS (
    SELECT *,
           6 - NTILE(5) OVER (ORDER BY recency_days ASC) AS r_score,
           CASE WHEN frequency = 1 THEN 1 WHEN frequency = 2 THEN 3 ELSE 5 END AS f_score,
           NTILE(5) OVER (ORDER BY monetary ASC)         AS m_score
    FROM base
)
SELECT *,
       CASE
         WHEN f_score >= 3 AND r_score >= 4 THEN 'Loyal Customers'
         WHEN f_score >= 3                  THEN 'At-Risk Repeat Buyers'
         WHEN r_score >= 4 AND m_score >= 4 THEN 'Promising High-Value'
         WHEN r_score >= 4                  THEN 'New / Recent Customers'
         WHEN r_score <= 2 AND m_score >= 4 THEN 'Lapsed High-Value (Win-back)'
         WHEN r_score <= 2                  THEN 'Hibernating'
         ELSE 'Needs Attention'
       END AS segment
FROM scored;
