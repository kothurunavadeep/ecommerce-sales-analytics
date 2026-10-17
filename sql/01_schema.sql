/* =====================================================================
   OLIST E-COMMERCE SALES & CUSTOMER ANALYTICS  |  01_schema.sql
   ---------------------------------------------------------------------
   Dataset : Brazilian E-Commerce Public Dataset by Olist (Kaggle)
   Dialect : SQLite 3 (tested). See docs/SQL_DIALECT_NOTES.md for
             MySQL / PostgreSQL / SQL Server equivalents.
   Layers  : raw_*  = staging tables, loaded 1:1 from the CSV files
             dim_* / fact_* = cleaned star-schema used by SQL, Excel, Power BI
   ===================================================================== */

-- ============================ RAW (STAGING) ============================
DROP TABLE IF EXISTS raw_customers;     DROP TABLE IF EXISTS raw_geolocation;
DROP TABLE IF EXISTS raw_order_items;   DROP TABLE IF EXISTS raw_order_payments;
DROP TABLE IF EXISTS raw_order_reviews; DROP TABLE IF EXISTS raw_orders;
DROP TABLE IF EXISTS raw_products;      DROP TABLE IF EXISTS raw_sellers;
DROP TABLE IF EXISTS raw_category_translation;

CREATE TABLE raw_customers (
    customer_id TEXT, customer_unique_id TEXT, customer_zip_code_prefix INTEGER,
    customer_city TEXT, customer_state TEXT);

CREATE TABLE raw_geolocation (
    geolocation_zip_code_prefix INTEGER, geolocation_lat REAL, geolocation_lng REAL,
    geolocation_city TEXT, geolocation_state TEXT);

CREATE TABLE raw_order_items (
    order_id TEXT, order_item_id INTEGER, product_id TEXT, seller_id TEXT,
    shipping_limit_date TEXT, price REAL, freight_value REAL);

CREATE TABLE raw_order_payments (
    order_id TEXT, payment_sequential INTEGER, payment_type TEXT,
    payment_installments INTEGER, payment_value REAL);

CREATE TABLE raw_order_reviews (
    review_id TEXT, order_id TEXT, review_score INTEGER, review_comment_title TEXT,
    review_comment_message TEXT, review_creation_date TEXT, review_answer_timestamp TEXT);

CREATE TABLE raw_orders (
    order_id TEXT, customer_id TEXT, order_status TEXT, order_purchase_timestamp TEXT,
    order_approved_at TEXT, order_delivered_carrier_date TEXT,
    order_delivered_customer_date TEXT, order_estimated_delivery_date TEXT);

CREATE TABLE raw_products (
    product_id TEXT, product_category_name TEXT, product_name_lenght REAL,
    product_description_lenght REAL, product_photos_qty REAL, product_weight_g REAL,
    product_length_cm REAL, product_height_cm REAL, product_width_cm REAL);

CREATE TABLE raw_sellers (
    seller_id TEXT, seller_zip_code_prefix INTEGER, seller_city TEXT, seller_state TEXT);

CREATE TABLE raw_category_translation (
    product_category_name TEXT, product_category_name_english TEXT);

-- ============================ CLEAN MODEL ============================
DROP TABLE IF EXISTS fact_order_items; DROP TABLE IF EXISTS fact_payments;
DROP TABLE IF EXISTS fact_reviews;     DROP TABLE IF EXISTS fact_orders;
DROP TABLE IF EXISTS dim_customers;    DROP TABLE IF EXISTS dim_products;
DROP TABLE IF EXISTS dim_sellers;      DROP TABLE IF EXISTS dim_geo;
DROP TABLE IF EXISTS dim_date;

-- customer_id is ORDER-level (Olist issues a new one per order);
-- customer_unique_id identifies the real person -> use it for repeat-purchase analysis.
CREATE TABLE dim_customers (
    customer_id        TEXT PRIMARY KEY,
    customer_unique_id TEXT NOT NULL,
    zip_code_prefix    INTEGER,
    city               TEXT,
    state              TEXT
);

CREATE TABLE dim_products (
    product_id       TEXT PRIMARY KEY,
    category_pt      TEXT,
    category         TEXT,           -- English name, 'unknown' if missing
    name_length      INTEGER,
    description_length INTEGER,
    photos_qty       INTEGER,
    weight_g         REAL,
    length_cm        REAL,
    height_cm        REAL,
    width_cm         REAL
);

CREATE TABLE dim_sellers (
    seller_id       TEXT PRIMARY KEY,
    zip_code_prefix INTEGER,
    city            TEXT,
    state           TEXT
);

CREATE TABLE dim_geo (               -- one row per zip prefix (raw file had ~1M rows)
    zip_code_prefix INTEGER PRIMARY KEY,
    lat             REAL,
    lng             REAL,
    city            TEXT,
    state           TEXT
);

CREATE TABLE dim_date (
    date_key     DATE PRIMARY KEY,
    year         INTEGER,
    quarter      INTEGER,
    month_num    INTEGER,
    month_name   TEXT,
    year_month   TEXT,
    week_of_year INTEGER,
    day_of_week  INTEGER,            -- 0 = Sunday
    day_name     TEXT,
    is_weekend   INTEGER
);

CREATE TABLE fact_orders (
    order_id                 TEXT PRIMARY KEY,
    customer_id              TEXT NOT NULL REFERENCES dim_customers(customer_id),
    order_status             TEXT,
    purchase_ts              TEXT,
    purchase_date            DATE,
    approved_ts              TEXT,
    delivered_carrier_ts     TEXT,
    delivered_customer_ts    TEXT,
    estimated_delivery_date  DATE,
    approval_hours           REAL,     -- purchase -> approval
    delivery_days            REAL,     -- purchase -> customer delivery
    estimated_days           REAL,     -- purchase -> promised date
    delay_days               REAL,     -- actual - estimated (positive = late)
    is_late                  INTEGER   -- 1 late, 0 on time, NULL not delivered
);

CREATE TABLE fact_order_items (
    order_id      TEXT NOT NULL REFERENCES fact_orders(order_id),
    order_item_id INTEGER NOT NULL,
    product_id    TEXT REFERENCES dim_products(product_id),
    seller_id     TEXT REFERENCES dim_sellers(seller_id),
    shipping_limit_date TEXT,
    price         REAL,
    freight_value REAL,
    PRIMARY KEY (order_id, order_item_id)
);

CREATE TABLE fact_payments (
    order_id             TEXT NOT NULL REFERENCES fact_orders(order_id),
    payment_sequential   INTEGER NOT NULL,
    payment_type         TEXT,
    payment_installments INTEGER,
    payment_value        REAL,
    PRIMARY KEY (order_id, payment_sequential)
);

CREATE TABLE fact_reviews (            -- exactly ONE review per order after cleaning
    order_id         TEXT PRIMARY KEY REFERENCES fact_orders(order_id),
    review_id        TEXT,
    review_score     INTEGER CHECK (review_score BETWEEN 1 AND 5),
    has_comment      INTEGER,
    review_creation_date TEXT,
    review_answer_ts TEXT
);

CREATE INDEX idx_orders_cust    ON fact_orders(customer_id);
CREATE INDEX idx_orders_date    ON fact_orders(purchase_date);
CREATE INDEX idx_items_product  ON fact_order_items(product_id);
CREATE INDEX idx_items_seller   ON fact_order_items(seller_id);
CREATE INDEX idx_cust_unique    ON dim_customers(customer_unique_id);
