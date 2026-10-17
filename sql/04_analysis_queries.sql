/* =====================================================================
   OLIST E-COMMERCE ANALYTICS  |  04_analysis_queries.sql
   ---------------------------------------------------------------------
   Each query starts with a "-- ## Qxx | name" marker so that
   scripts/02_run_analysis.py can run and export them all.

   Window   : 2017-01-01 .. 2018-08-31 (complete months)
   Revenue  : delivered orders only, product price (freight shown separately)
   Business questions answered:
     1. How big is the business and is it growing?              Q01-Q05
     2. Which categories / products drive revenue?              Q06-Q09
     3. Who are the customers, do they come back?               Q10-Q15
     4. Is logistics hurting customer satisfaction?             Q16-Q18
     5. How concentrated / healthy is the seller base?          Q19-Q21
     6. How do customers pay?                                   Q22-Q23
   ===================================================================== */

-- ## Q01 | headline_kpis
SELECT
    ROUND(SUM(price), 0)                                         AS revenue,
    ROUND(SUM(freight_value), 0)                                 AS freight_revenue,
    ROUND(SUM(price + freight_value), 0)                         AS gmv,
    COUNT(DISTINCT order_id)                                     AS orders,
    COUNT(DISTINCT customer_unique_id)                           AS customers,
    ROUND(SUM(price) / COUNT(DISTINCT order_id), 2)              AS aov,
    ROUND(1.0 * COUNT(*) / COUNT(DISTINCT order_id), 3)          AS items_per_order,
    ROUND(AVG(CASE WHEN is_first_item = 1 THEN review_score END), 2)                AS avg_review_score,
    ROUND(100.0 * (1 - AVG(CASE WHEN is_first_item = 1 THEN is_late END)), 2)       AS on_time_pct,
    ROUND(AVG(CASE WHEN is_first_item = 1 THEN delivery_days END), 2)               AS avg_delivery_days
FROM vw_order_items_flat
WHERE is_revenue = 1 AND purchase_date BETWEEN '2017-01-01' AND '2018-08-31';

-- ## Q02 | monthly_trend_with_mom
WITH m AS (
    SELECT year_month,
           ROUND(SUM(price), 0)                AS revenue,
           COUNT(DISTINCT order_id)            AS orders,
           COUNT(DISTINCT customer_unique_id)  AS customers
    FROM vw_order_items_flat
    WHERE is_revenue = 1 AND purchase_date BETWEEN '2017-01-01' AND '2018-08-31'
    GROUP BY year_month
)
SELECT year_month, revenue, orders, customers,
       ROUND(1.0 * revenue / orders, 2)                                                   AS aov,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY year_month))
                   / LAG(revenue) OVER (ORDER BY year_month), 1)                          AS revenue_mom_pct,
       ROUND(AVG(revenue) OVER (ORDER BY year_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS revenue_3m_avg
FROM m ORDER BY year_month;

-- ## Q03 | yoy_same_month_2018_vs_2017
WITH m AS (
    SELECT order_year, CAST(strftime('%m', purchase_date) AS INTEGER) AS month_num,
           SUM(price) AS revenue, COUNT(DISTINCT order_id) AS orders
    FROM vw_order_items_flat
    WHERE is_revenue = 1 AND purchase_date BETWEEN '2017-01-01' AND '2018-08-31'
    GROUP BY order_year, month_num
)
SELECT a.month_num,
       ROUND(b.revenue, 0) AS revenue_2017, ROUND(a.revenue, 0) AS revenue_2018,
       ROUND(100.0 * (a.revenue - b.revenue) / b.revenue, 1)  AS revenue_yoy_pct,
       b.orders AS orders_2017, a.orders AS orders_2018,
       ROUND(100.0 * (a.orders - b.orders) / b.orders, 1)     AS orders_yoy_pct
FROM m a JOIN m b ON b.month_num = a.month_num AND b.order_year = 2017
WHERE a.order_year = 2018 ORDER BY a.month_num;

-- ## Q04 | orders_by_weekday
SELECT d.day_of_week, d.day_name,
       COUNT(*)                                                       AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)             AS pct_of_orders,
       ROUND(AVG(e.revenue), 2)                                       AS aov
FROM vw_orders_enriched e JOIN dim_date d ON d.date_key = e.purchase_date
WHERE e.order_status = 'delivered' AND e.purchase_date BETWEEN '2017-01-01' AND '2018-08-31'
GROUP BY d.day_of_week, d.day_name ORDER BY d.day_of_week;

-- ## Q05 | orders_by_hour_block
SELECT CASE WHEN h BETWEEN 0 AND 5   THEN '1) Night 00-05'
            WHEN h BETWEEN 6 AND 11  THEN '2) Morning 06-11'
            WHEN h BETWEEN 12 AND 17 THEN '3) Afternoon 12-17'
            ELSE '4) Evening 18-23' END AS time_block,
       COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_orders
FROM (SELECT CAST(strftime('%H', purchase_ts) AS INTEGER) AS h
      FROM fact_orders
      WHERE order_status = 'delivered' AND purchase_date BETWEEN '2017-01-01' AND '2018-08-31')
GROUP BY time_block ORDER BY time_block;

-- ## Q06 | category_performance_pareto
WITH cat AS (
    SELECT category,
           ROUND(SUM(price), 0)                       AS revenue,
           COUNT(DISTINCT order_id)                   AS orders,
           COUNT(*)                                   AS items_sold,
           ROUND(AVG(price), 2)                       AS avg_price,
           ROUND(100.0 * SUM(freight_value) / SUM(price), 1) AS freight_pct_of_price,
           ROUND(AVG(review_score), 2)                AS avg_review
    FROM vw_order_items_flat
    WHERE is_revenue = 1 AND purchase_date BETWEEN '2017-01-01' AND '2018-08-31'
    GROUP BY category
)
SELECT category, revenue, orders, items_sold, avg_price, freight_pct_of_price, avg_review,
       ROUND(100.0 * revenue / SUM(revenue) OVER (), 1)                                   AS revenue_share_pct,
       ROUND(100.0 * SUM(revenue) OVER (ORDER BY revenue DESC) / SUM(revenue) OVER (), 1) AS cumulative_share_pct
FROM cat ORDER BY revenue DESC LIMIT 20;

-- ## Q07 | top_20_products
SELECT product_id, category,
       ROUND(SUM(price), 0) AS revenue, COUNT(*) AS units_sold, ROUND(AVG(price), 2) AS avg_price,
       ROUND(AVG(review_score), 2) AS avg_review
FROM vw_order_items_flat
WHERE is_revenue = 1 AND purchase_date BETWEEN '2017-01-01' AND '2018-08-31'
GROUP BY product_id, category ORDER BY revenue DESC LIMIT 20;

-- ## Q08 | category_growth_jan_aug_2018_vs_2017
WITH c AS (
    SELECT category,
           SUM(CASE WHEN order_year = 2017 THEN price END) AS rev_2017,
           SUM(CASE WHEN order_year = 2018 THEN price END) AS rev_2018
    FROM vw_order_items_flat
    WHERE is_revenue = 1
      AND strftime('%m-%d', purchase_date) BETWEEN '01-01' AND '08-31'
      AND order_year IN (2017, 2018)
    GROUP BY category
)
SELECT category, ROUND(rev_2017, 0) AS rev_2017, ROUND(rev_2018, 0) AS rev_2018,
       ROUND(100.0 * (rev_2018 - rev_2017) / rev_2017, 1) AS growth_pct
FROM c
WHERE rev_2017 >= 50000                 -- ignore tiny bases that distort growth %
ORDER BY rev_2018 DESC LIMIT 15;

-- ## Q09 | price_band_analysis
SELECT CASE WHEN price < 50 THEN '1) < R$50'
            WHEN price < 100 THEN '2) R$50-99'
            WHEN price < 200 THEN '3) R$100-199'
            WHEN price < 500 THEN '4) R$200-499'
            ELSE '5) R$500+' END AS price_band,
       COUNT(*) AS items, ROUND(SUM(price), 0) AS revenue,
       ROUND(100.0 * SUM(price) / SUM(SUM(price)) OVER (), 1) AS revenue_share_pct,
       ROUND(100.0 * SUM(freight_value) / SUM(price), 1)      AS freight_pct_of_price
FROM vw_order_items_flat
WHERE is_revenue = 1 AND purchase_date BETWEEN '2017-01-01' AND '2018-08-31'
GROUP BY price_band ORDER BY price_band;

-- ## Q10 | state_performance
SELECT customer_state,
       COUNT(DISTINCT customer_unique_id)                        AS customers,
       COUNT(DISTINCT order_id)                                  AS orders,
       ROUND(SUM(price), 0)                                      AS revenue,
       ROUND(100.0 * SUM(price) / SUM(SUM(price)) OVER (), 1)    AS revenue_share_pct,
       ROUND(SUM(price) / COUNT(DISTINCT order_id), 2)           AS aov,
       ROUND(100.0 * SUM(freight_value) / SUM(price), 1)         AS freight_pct_of_price,
       ROUND(AVG(CASE WHEN is_first_item = 1 THEN delivery_days END), 1) AS avg_delivery_days,
       ROUND(100.0 * AVG(CASE WHEN is_first_item = 1 THEN is_late END), 1) AS late_pct,
       ROUND(AVG(CASE WHEN is_first_item = 1 THEN review_score END), 2)  AS avg_review
FROM vw_order_items_flat
WHERE is_revenue = 1 AND purchase_date BETWEEN '2017-01-01' AND '2018-08-31'
GROUP BY customer_state ORDER BY revenue DESC;

-- ## Q11 | repeat_purchase_rate
SELECT CASE WHEN delivered_orders >= 3 THEN '3+ orders' ELSE delivered_orders || ' order(s)' END AS order_count_bucket,
       COUNT(*) AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_customers,
       ROUND(SUM(total_revenue), 0) AS revenue,
       ROUND(100.0 * SUM(total_revenue) / SUM(SUM(total_revenue)) OVER (), 2) AS pct_revenue
FROM vw_customer_summary
GROUP BY order_count_bucket ORDER BY order_count_bucket;

-- ## Q12 | rfm_segment_summary
SELECT segment,
       COUNT(*)                                                   AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)         AS pct_customers,
       ROUND(SUM(monetary), 0)                                    AS revenue,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_revenue,
       ROUND(AVG(recency_days), 0)                                AS avg_recency_days,
       ROUND(AVG(frequency), 2)                                   AS avg_orders,
       ROUND(AVG(monetary), 2)                                    AS avg_spend
FROM vw_rfm GROUP BY segment ORDER BY revenue DESC;

-- ## Q13 | cohort_retention_counts
-- Cohort = month of a customer's first delivered order. Columns = months since first order.
WITH first_m AS (
    SELECT customer_unique_id, strftime('%Y-%m', MIN(purchase_date)) AS cohort
    FROM vw_orders_enriched WHERE order_status = 'delivered' GROUP BY customer_unique_id
),
act AS (
    SELECT DISTINCT f.customer_unique_id, f.cohort,
           (CAST(strftime('%Y', e.purchase_date) AS INTEGER) - CAST(substr(f.cohort,1,4) AS INTEGER)) * 12
         + (CAST(strftime('%m', e.purchase_date) AS INTEGER) - CAST(substr(f.cohort,6,2) AS INTEGER)) AS m_idx
    FROM vw_orders_enriched e JOIN first_m f ON f.customer_unique_id = e.customer_unique_id
    WHERE e.order_status = 'delivered'
)
SELECT cohort,
       COUNT(DISTINCT CASE WHEN m_idx = 0 THEN customer_unique_id END) AS m0,
       COUNT(DISTINCT CASE WHEN m_idx = 1 THEN customer_unique_id END) AS m1,
       COUNT(DISTINCT CASE WHEN m_idx = 2 THEN customer_unique_id END) AS m2,
       COUNT(DISTINCT CASE WHEN m_idx = 3 THEN customer_unique_id END) AS m3,
       COUNT(DISTINCT CASE WHEN m_idx = 4 THEN customer_unique_id END) AS m4,
       COUNT(DISTINCT CASE WHEN m_idx = 5 THEN customer_unique_id END) AS m5,
       COUNT(DISTINCT CASE WHEN m_idx = 6 THEN customer_unique_id END) AS m6
FROM act
WHERE cohort BETWEEN '2017-01' AND '2018-02'          -- cohorts with >= 6 observable months
GROUP BY cohort ORDER BY cohort;

-- ## Q14 | new_vs_returning_revenue_by_month
WITH o AS (
    SELECT e.*, ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY purchase_date, order_id) AS order_seq
    FROM vw_orders_enriched e WHERE order_status = 'delivered'
)
SELECT year_month,
       ROUND(SUM(CASE WHEN order_seq = 1 THEN revenue END), 0)  AS new_customer_revenue,
       ROUND(SUM(CASE WHEN order_seq > 1 THEN revenue END), 0)  AS returning_customer_revenue,
       ROUND(100.0 * SUM(CASE WHEN order_seq > 1 THEN revenue END) / SUM(revenue), 1) AS returning_pct
FROM o WHERE purchase_date BETWEEN '2017-01-01' AND '2018-08-31'
GROUP BY year_month ORDER BY year_month;

-- ## Q15 | days_to_second_purchase
WITH o AS (
    SELECT customer_unique_id, purchase_date,
           ROW_NUMBER() OVER (PARTITION BY customer_unique_id ORDER BY purchase_date, order_id) AS seq
    FROM vw_orders_enriched WHERE order_status = 'delivered'
),
gap AS (
    SELECT a.customer_unique_id, julianday(b.purchase_date) - julianday(a.purchase_date) AS days_gap
    FROM o a JOIN o b ON a.customer_unique_id = b.customer_unique_id AND a.seq = 1 AND b.seq = 2
)
SELECT CASE WHEN days_gap = 0 THEN '1) Same day'
            WHEN days_gap <= 30 THEN '2) 1-30 days'
            WHEN days_gap <= 90 THEN '3) 31-90 days'
            WHEN days_gap <= 180 THEN '4) 91-180 days'
            ELSE '5) 180+ days' END AS gap_bucket,
       COUNT(*) AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM gap GROUP BY gap_bucket ORDER BY gap_bucket;

-- ## Q16 | review_score_distribution
SELECT r.review_score, COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_orders
FROM fact_reviews r JOIN fact_orders o ON o.order_id = r.order_id
WHERE o.order_status = 'delivered' AND o.purchase_date BETWEEN '2017-01-01' AND '2018-08-31'
GROUP BY r.review_score ORDER BY r.review_score DESC;

-- ## Q17 | delivery_delay_vs_review
SELECT CASE WHEN o.delay_days <= -7 THEN '1) 7+ days early'
            WHEN o.delay_days <= 0  THEN '2) On time / up to 6 days early'
            WHEN o.delay_days <= 3  THEN '3) 1-3 days late'
            WHEN o.delay_days <= 7  THEN '4) 4-7 days late'
            ELSE '5) 8+ days late' END AS delivery_vs_promise,
       COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_orders,
       ROUND(AVG(r.review_score), 2) AS avg_review,
       ROUND(100.0 * AVG(CASE WHEN r.review_score <= 2 THEN 1.0 ELSE 0 END), 1) AS pct_bad_reviews
FROM fact_orders o JOIN fact_reviews r ON r.order_id = o.order_id
WHERE o.order_status = 'delivered' AND o.delay_days IS NOT NULL
  AND o.purchase_date BETWEEN '2017-01-01' AND '2018-08-31'
GROUP BY delivery_vs_promise ORDER BY delivery_vs_promise;

-- ## Q18 | delivery_time_by_month
SELECT strftime('%Y-%m', purchase_date) AS year_month,
       ROUND(AVG(delivery_days), 1)                          AS avg_delivery_days,
       ROUND(AVG(estimated_days), 1)                         AS avg_promised_days,
       ROUND(100.0 * AVG(is_late), 1)                        AS late_pct
FROM fact_orders
WHERE order_status = 'delivered' AND purchase_date BETWEEN '2017-01-01' AND '2018-08-31'
GROUP BY year_month ORDER BY year_month;

-- ## Q19 | top_20_sellers
SELECT seller_id, seller_state,
       ROUND(SUM(price), 0)                                           AS revenue,
       COUNT(DISTINCT order_id)                                       AS orders,
       ROUND(AVG(review_score), 2)                                    AS avg_review,
       ROUND(100.0 * AVG(is_late), 1)                                 AS late_pct,
       ROUND(100.0 * SUM(price) / SUM(SUM(price)) OVER (), 2)         AS revenue_share_pct
FROM vw_order_items_flat
WHERE is_revenue = 1 AND purchase_date BETWEEN '2017-01-01' AND '2018-08-31'
GROUP BY seller_id, seller_state ORDER BY revenue DESC LIMIT 20;

-- ## Q20 | seller_concentration_by_decile
WITH s AS (
    SELECT seller_id, SUM(price) AS revenue
    FROM vw_order_items_flat
    WHERE is_revenue = 1 AND purchase_date BETWEEN '2017-01-01' AND '2018-08-31'
    GROUP BY seller_id
),
d AS (SELECT *, NTILE(10) OVER (ORDER BY revenue DESC) AS decile FROM s)
SELECT decile, COUNT(*) AS sellers, ROUND(SUM(revenue), 0) AS revenue,
       ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1) AS revenue_share_pct,
       ROUND(100.0 * SUM(SUM(revenue)) OVER (ORDER BY decile) / SUM(SUM(revenue)) OVER (), 1) AS cumulative_share_pct
FROM d GROUP BY decile ORDER BY decile;

-- ## Q21 | same_state_vs_cross_state_shipping
SELECT CASE WHEN seller_state = customer_state THEN 'Same state' ELSE 'Cross-state' END AS shipping_type,
       COUNT(DISTINCT order_id)                                     AS orders,
       ROUND(100.0 * COUNT(DISTINCT order_id) / SUM(COUNT(DISTINCT order_id)) OVER (), 1) AS pct_orders,
       ROUND(100.0 * SUM(freight_value) / SUM(price), 1)            AS freight_pct_of_price,
       ROUND(AVG(CASE WHEN is_first_item = 1 THEN delivery_days END), 1) AS avg_delivery_days,
       ROUND(AVG(CASE WHEN is_first_item = 1 THEN review_score END), 2)  AS avg_review
FROM vw_order_items_flat
WHERE is_revenue = 1 AND purchase_date BETWEEN '2017-01-01' AND '2018-08-31'
GROUP BY shipping_type;

-- ## Q22 | payment_type_mix
SELECT p.payment_type,
       COUNT(DISTINCT p.order_id)                                     AS orders,
       ROUND(100.0 * COUNT(DISTINCT p.order_id) / SUM(COUNT(DISTINCT p.order_id)) OVER (), 1) AS pct_orders,
       ROUND(SUM(p.payment_value), 0)                                 AS payment_value,
       ROUND(100.0 * SUM(p.payment_value) / SUM(SUM(p.payment_value)) OVER (), 1) AS pct_value,
       ROUND(AVG(p.payment_value), 2)                                 AS avg_payment,
       ROUND(AVG(p.payment_installments), 1)                          AS avg_installments
FROM fact_payments p JOIN fact_orders o ON o.order_id = p.order_id
WHERE o.order_status = 'delivered' AND o.purchase_date BETWEEN '2017-01-01' AND '2018-08-31'
GROUP BY p.payment_type ORDER BY payment_value DESC;

-- ## Q23 | installments_vs_order_value
SELECT CASE WHEN max_installments = 1 THEN '1 (pay in full)'
            WHEN max_installments <= 3 THEN '2-3'
            WHEN max_installments <= 6 THEN '4-6'
            WHEN max_installments <= 10 THEN '7-10'
            ELSE '11+' END AS installment_bucket,
       COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_orders,
       ROUND(AVG(revenue), 2) AS avg_order_value
FROM vw_orders_enriched
WHERE order_status = 'delivered' AND purchase_date BETWEEN '2017-01-01' AND '2018-08-31'
  AND max_installments IS NOT NULL AND primary_payment_type = 'credit_card'
GROUP BY installment_bucket ORDER BY MIN(max_installments);
