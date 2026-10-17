/* =====================================================================
   OLIST E-COMMERCE ANALYTICS  |  02_data_cleaning.sql
   ---------------------------------------------------------------------
   PART A  Data profiling   (read-only checks, review the output)
   PART B  Cleaning + load  (raw_* -> dim_* / fact_*)
   PART C  Post-load validation

   Issues found in the raw data and how they are handled
   ---------------------------------------------------------------------
   1. customer_id is unique per ORDER, not per person
        -> keep both; use customer_unique_id for customer analytics
   2. Reviews: duplicate review_ids and orders with >1 review
        -> keep ONE review per order (latest answer timestamp)
   3. Geolocation: ~1M rows, ~260k exact duplicates, many rows per zip prefix
        -> collapse to one row per zip prefix (avg lat/lng)
   4. 610 products have no category; 2 categories missing in the translation table
        -> add manual translations, label the rest 'unknown'
   5. 775 orders have no items (unavailable / canceled)  -> kept in fact_orders, excluded from revenue
   6. 8 'delivered' orders have no delivery date          -> delivery metrics left NULL
   7. Misspelled column names (product_name_lenght)       -> renamed
   8. Data coverage: only Jan-2017 .. Aug-2018 are full months (2016 sparse; Sep/Oct-2018 stub)
        -> analysis window defined in 04_analysis_queries.sql
   ===================================================================== */

-- ============================ PART A: PROFILING ============================

-- A1. Row counts
SELECT 'raw_orders' t, COUNT(*) n FROM raw_orders UNION ALL
SELECT 'raw_customers', COUNT(*) FROM raw_customers UNION ALL
SELECT 'raw_order_items', COUNT(*) FROM raw_order_items UNION ALL
SELECT 'raw_order_payments', COUNT(*) FROM raw_order_payments UNION ALL
SELECT 'raw_order_reviews', COUNT(*) FROM raw_order_reviews UNION ALL
SELECT 'raw_products', COUNT(*) FROM raw_products UNION ALL
SELECT 'raw_sellers', COUNT(*) FROM raw_sellers UNION ALL
SELECT 'raw_geolocation', COUNT(*) FROM raw_geolocation;

-- A2. Orders vs unique people
SELECT COUNT(DISTINCT customer_id) AS customer_ids, COUNT(DISTINCT customer_unique_id) AS unique_people
FROM raw_customers;

-- A3. Order status distribution
SELECT order_status, COUNT(*) AS orders, ROUND(100.0*COUNT(*)/(SELECT COUNT(*) FROM raw_orders),2) AS pct
FROM raw_orders GROUP BY order_status ORDER BY orders DESC;

-- A4. Orders per month (spot the sparse / partial months)
SELECT strftime('%Y-%m', order_purchase_timestamp) AS ym, COUNT(*) AS orders
FROM raw_orders GROUP BY ym ORDER BY ym;

-- A5. Duplicate reviews
SELECT COUNT(*) - COUNT(DISTINCT review_id) AS duplicate_review_ids,
       (SELECT COUNT(*) FROM (SELECT order_id FROM raw_order_reviews GROUP BY order_id HAVING COUNT(*)>1)) AS orders_with_multi_reviews
FROM raw_order_reviews;

-- A6. Orders without items
SELECT o.order_status, COUNT(*) AS orders_without_items
FROM raw_orders o LEFT JOIN raw_order_items i ON i.order_id = o.order_id
WHERE i.order_id IS NULL GROUP BY o.order_status;

-- A7. Products: missing categories and missing translations
SELECT SUM(CASE WHEN product_category_name IS NULL THEN 1 ELSE 0 END) AS products_no_category FROM raw_products;
SELECT DISTINCT p.product_category_name AS category_missing_translation
FROM raw_products p LEFT JOIN raw_category_translation t ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NOT NULL AND t.product_category_name IS NULL;

-- A8. Logical date checks (expect 0)
SELECT COUNT(*) AS delivered_before_purchase FROM raw_orders
WHERE order_delivered_customer_date < order_purchase_timestamp;
SELECT COUNT(*) AS delivered_status_without_date FROM raw_orders
WHERE order_status='delivered' AND order_delivered_customer_date IS NULL;

-- A9. Referential integrity (expect 0)
SELECT COUNT(*) AS items_without_order   FROM raw_order_items i LEFT JOIN raw_orders o   ON o.order_id=i.order_id     WHERE o.order_id IS NULL;
SELECT COUNT(*) AS items_without_product FROM raw_order_items i LEFT JOIN raw_products p ON p.product_id=i.product_id WHERE p.product_id IS NULL;
SELECT COUNT(*) AS items_without_seller  FROM raw_order_items i LEFT JOIN raw_sellers s  ON s.seller_id=i.seller_id   WHERE s.seller_id IS NULL;
SELECT COUNT(*) AS orders_without_customer FROM raw_orders o LEFT JOIN raw_customers c ON c.customer_id=o.customer_id WHERE c.customer_id IS NULL;

-- A10. Payment oddities
SELECT payment_type, COUNT(*) AS n, SUM(CASE WHEN payment_value=0 THEN 1 ELSE 0 END) AS zero_value_rows
FROM raw_order_payments GROUP BY payment_type;

-- ============================ PART B: CLEAN + LOAD ============================

-- B1. Customers (straight load; cities already lower-case / accent-free)
INSERT INTO dim_customers
SELECT customer_id, customer_unique_id, customer_zip_code_prefix, TRIM(customer_city), UPPER(TRIM(customer_state))
FROM raw_customers;

-- B2. Products: attach English category, fix missing translations, rename columns
INSERT INTO dim_products
SELECT p.product_id,
       p.product_category_name,
       CASE
         WHEN p.product_category_name IS NULL THEN 'unknown'
         WHEN p.product_category_name = 'pc_gamer' THEN 'pc_gamer'
         WHEN p.product_category_name = 'portateis_cozinha_e_preparadores_de_alimentos' THEN 'portable_kitchen_food_preparers'
         ELSE COALESCE(t.product_category_name_english, p.product_category_name)
       END,
       CAST(p.product_name_lenght AS INTEGER),
       CAST(p.product_description_lenght AS INTEGER),
       CAST(p.product_photos_qty AS INTEGER),
       p.product_weight_g, p.product_length_cm, p.product_height_cm, p.product_width_cm
FROM raw_products p
LEFT JOIN raw_category_translation t ON t.product_category_name = p.product_category_name;

-- B3. Sellers
INSERT INTO dim_sellers
SELECT seller_id, seller_zip_code_prefix, TRIM(seller_city), UPPER(TRIM(seller_state)) FROM raw_sellers;

-- B4. Geo: one row per zip prefix
INSERT INTO dim_geo
SELECT geolocation_zip_code_prefix, AVG(geolocation_lat), AVG(geolocation_lng),
       MIN(geolocation_city), MIN(geolocation_state)
FROM raw_geolocation GROUP BY geolocation_zip_code_prefix;

-- B5. Date dimension (2016-09-01 .. 2018-12-31) via recursive CTE
INSERT INTO dim_date
WITH RECURSIVE d(dt) AS (
    SELECT DATE('2016-09-01')
    UNION ALL
    SELECT DATE(dt, '+1 day') FROM d WHERE dt < DATE('2018-12-31')
)
SELECT dt,
       CAST(strftime('%Y', dt) AS INTEGER),
       (CAST(strftime('%m', dt) AS INTEGER) + 2) / 3,
       CAST(strftime('%m', dt) AS INTEGER),
       SUBSTR('JanFebMarAprMayJunJulAugSepOctNovDec', (CAST(strftime('%m', dt) AS INTEGER) - 1) * 3 + 1, 3),
       strftime('%Y-%m', dt),
       CAST(strftime('%W', dt) AS INTEGER),
       CAST(strftime('%w', dt) AS INTEGER),
       SUBSTR('SunMonTueWedThuFriSat', CAST(strftime('%w', dt) AS INTEGER) * 3 + 1, 3),
       CASE WHEN strftime('%w', dt) IN ('0','6') THEN 1 ELSE 0 END
FROM d;

-- B6. Orders + derived delivery metrics
INSERT INTO fact_orders
SELECT order_id,
       customer_id,
       order_status,
       order_purchase_timestamp,
       DATE(order_purchase_timestamp),
       order_approved_at,
       order_delivered_carrier_date,
       order_delivered_customer_date,
       DATE(order_estimated_delivery_date),
       ROUND((julianday(order_approved_at) - julianday(order_purchase_timestamp)) * 24, 2),
       ROUND(julianday(order_delivered_customer_date) - julianday(order_purchase_timestamp), 2),
       ROUND(julianday(order_estimated_delivery_date) - julianday(order_purchase_timestamp), 2),
       julianday(DATE(order_delivered_customer_date)) - julianday(DATE(order_estimated_delivery_date)),
       CASE WHEN order_delivered_customer_date IS NULL THEN NULL
            WHEN DATE(order_delivered_customer_date) > DATE(order_estimated_delivery_date) THEN 1
            ELSE 0 END
FROM raw_orders;

-- B7. Order items / payments (straight load)
INSERT INTO fact_order_items
SELECT order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value
FROM raw_order_items;

INSERT INTO fact_payments
SELECT order_id, payment_sequential, payment_type, payment_installments, payment_value
FROM raw_order_payments;

-- B8. Reviews: keep ONE per order (latest answer; ties broken by review_id)
INSERT INTO fact_reviews
SELECT order_id, review_id, review_score,
       CASE WHEN review_comment_message IS NOT NULL AND TRIM(review_comment_message) <> '' THEN 1 ELSE 0 END,
       review_creation_date, review_answer_timestamp
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC, review_id) AS rn
    FROM raw_order_reviews
) WHERE rn = 1;

-- ============================ PART C: VALIDATION ============================
SELECT 'dim_customers' t, COUNT(*) n FROM dim_customers UNION ALL
SELECT 'dim_products',   COUNT(*) FROM dim_products UNION ALL
SELECT 'dim_sellers',    COUNT(*) FROM dim_sellers UNION ALL
SELECT 'dim_geo',        COUNT(*) FROM dim_geo UNION ALL
SELECT 'dim_date',       COUNT(*) FROM dim_date UNION ALL
SELECT 'fact_orders',    COUNT(*) FROM fact_orders UNION ALL
SELECT 'fact_order_items', COUNT(*) FROM fact_order_items UNION ALL
SELECT 'fact_payments',  COUNT(*) FROM fact_payments UNION ALL
SELECT 'fact_reviews',   COUNT(*) FROM fact_reviews;

-- Reconciliation: item revenue must equal raw total (13,591,643.70)
SELECT ROUND(SUM(price),2) AS clean_total_price,
       (SELECT ROUND(SUM(price),2) FROM raw_order_items) AS raw_total_price
FROM fact_order_items;

-- One review per order?
SELECT COUNT(*) AS reviews, COUNT(DISTINCT order_id) AS distinct_orders FROM fact_reviews;
