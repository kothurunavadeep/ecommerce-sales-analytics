# Olist E-Commerce Sales & Customer Analytics
**SQL + Excel + Power BI | Retail / E-Commerce | Brazil (2017-2018)**

An end-to-end data analyst project on the public [Olist Brazilian E-Commerce dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
(~100K orders, 9 tables). Raw CSVs are cleaned and modelled in **SQL**, analysed and summarised in **Excel** (formula-driven),
and visualised in **Power BI**.

## Business questions
1. How big is the business and how fast is it growing? Which months/days matter most?
2. Which product categories and price bands drive revenue and satisfaction?
3. Who are the customers, how do they behave, and do they come back? (RFM, cohorts, repeat rate)
4. Is delivery performance hurting customer reviews? Which regions suffer?
5. How concentrated is the seller base?
6. How do customers pay (credit card, boleto, installments)?

## Headline results (Jan-2017 to Aug-2018, delivered orders)
| | |
|---|---|
| Revenue | R$ 13.2 M (96,211 orders, AOV R$ 137) |
| Growth | +141% revenue YoY (Jan-Aug 2018 vs 2017); Black Friday 2017 = peak month |
| Retention | **97% of customers buy only once**; month-1 retention ~0.5% |
| Delivery | 93% on time - but late orders average **1.7 stars** vs 4.3 for on-time |
| Concentration | SP+RJ+MG = 63% of sales; top 10% of sellers = 67% of revenue |
| Top categories | health_beauty, watches_gifts, bed_bath_table, sports_leisure, computers_accessories (40%) |

Full findings and recommendations: [`docs/INSIGHTS.md`](docs/INSIGHTS.md)

## Project structure
```
olist_project/
├── README.md
├── requirements.txt
├── sql/
│   ├── 01_schema.sql            raw staging tables + clean star schema (PK/FK/checks/indexes)
│   ├── 02_data_cleaning.sql     profiling (A), cleaning + load (B), validation (C)
│   ├── 03_views.sql             flat views, KPI definitions, customer summary, RFM
│   └── 04_analysis_queries.sql  23 analysis queries (CTEs, window functions, cohorts)
├── scripts/
│   ├── 01_build_database.py     CSV -> SQLite -> clean tables -> data/clean/*.csv
│   ├── 02_run_analysis.py       runs all queries -> docs/query_results/*.csv
│   └── 03_build_excel.py        builds the Excel workbook
├── data/clean/                  cleaned tables (CSV) ready for Power BI
├── excel/Olist_Sales_Customer_Analytics.xlsx
├── powerbi/
│   ├── POWER_BI_GUIDE.md        model, relationships, page-by-page build spec
│   ├── DAX_Measures.dax         calculated columns + 45+ measures
│   └── Olist_Theme.json         report theme
└── docs/
    ├── INSIGHTS.md  DATA_DICTIONARY.md  SQL_DIALECT_NOTES.md
    └── query_results/           CSV output of every analysis query
```

## How to reproduce
1. Download the dataset from Kaggle and unzip the 9 CSVs into any folder.
2. `pip install -r requirements.txt`
3. `python scripts/01_build_database.py --raw <folder_with_csvs>`  (creates `data/olist.db` + `data/clean/*.csv`)
4. `python scripts/02_run_analysis.py`
5. `python scripts/03_build_excel.py`  (optional - rebuilds the workbook; then open it and let Excel recalculate)
6. Power BI: follow `powerbi/POWER_BI_GUIDE.md` (import `data/clean/*.csv`).

## Data model (star schema)
```
dim_date ─┐
dim_customers ─┤
               fact_orders ──< fact_order_items >── dim_products
                    │  └──< fact_payments        └── dim_sellers
                    └── fact_reviews (1:1)
```

## SQL techniques demonstrated
CTEs & recursive CTE (date dimension) | window functions (`ROW_NUMBER`, `LAG`, `NTILE`, running totals) |
cohort retention | RFM segmentation | Pareto / cumulative share | data profiling & validation checks |
de-duplication | referential-integrity and reconciliation checks (clean revenue = raw revenue to the cent)

## Data cleaning highlights
- `customer_id` is order-level -> used `customer_unique_id` for people-level analysis (99,441 ids -> 96,096 people)
- 814 duplicate review IDs / 547 orders with multiple reviews -> one review per order kept
- 1,000,163 geolocation rows (261,831 duplicates) -> 19,015 zip prefixes
- 610 products with no category, 2 missing translations -> fixed / labelled `unknown`
- Partial months (2016, Sep/Oct-2018) excluded from analysis window
- 775 orders without items and 8 "delivered" orders with no delivery date flagged and handled

## Excel workbook
10 sheets: Dashboard (KPIs + 4 charts), Monthly_Trend, Categories, States, Delivery_Reviews, Payments, Customers_RFM,
Cohort_Retention, Notes, Data_Items (109,880 rows). 653 live formulas (`SUMIFS`, `COUNTIFS`, `AVERAGEIFS`), zero errors;
values pasted from SQL are in blue font.

## Resume-ready bullets
- Cleaned and modelled 9 raw tables (~1.5 M rows) into a star schema in SQL; resolved duplicate reviews, order-vs-customer ID mismatch and 1 M-row geolocation table; reconciled revenue to the raw data to the cent.
- Wrote 23 analytical SQL queries (CTEs, window functions, cohort and RFM analysis) answering growth, product, customer, delivery and seller questions on R$13.2 M of sales across 96 K orders.
- Found that 97% of customers never reorder and that late deliveries cut review scores from 4.3 to 1.7 stars; recommended a post-purchase retention programme and delivery-promise alerts.
- Built a formula-driven Excel dashboard and a 5-page Power BI report (DAX measures, time intelligence, RFM segmentation) for executive decision-making.

## Tools
SQL (SQLite-tested; MySQL / PostgreSQL / SQL Server notes included) | Python (pandas, openpyxl) for the pipeline | Excel | Power BI (DAX, Power Query)

*Data: Olist (CC BY-NC-SA 4.0). Not affiliated with Olist.*
