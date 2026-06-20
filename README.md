
```
LRDB
├─ .python-version
├─ assets
│  ├─ customer_report
│  │  ├─ active_inactive.png
│  │  ├─ delivery_distribution.png
│  │  ├─ revenue_by_type.png
│  │  ├─ revenue_vs_potential (1).png
│  │  ├─ revenue_vs_potential.png
│  │  ├─ top10_revenue.png
│  │  └─ underutilized.png
│  ├─ driver_report
│  └─ trucks_report
│     ├─ cost_per_mile_distribution.png
│     ├─ downtime_vs_maintenance_cost.png
│     ├─ fleet_status_breakdown.png
│     ├─ mpg_by_make.png
│     ├─ top10_maintenance_cost.png
│     └─ top10_truck_revenue.png
├─ dataset
│  ├─ customers.csv
│  ├─ delivery_events.csv
│  ├─ drivers.csv
│  ├─ driver_monthly_metrics.csv
│  ├─ facilities.csv
│  ├─ fuel_purchases.csv
│  ├─ loads.csv
│  ├─ maintenance_records.csv
│  ├─ routes.csv
│  ├─ safety_incidents.csv
│  ├─ trailers.csv
│  ├─ trips.csv
│  ├─ trucks.csv
│  └─ truck_utilization_metrics.csv
├─ desktop.ini
├─ docs
│  ├─ architecture.md
│  └─ datacatlog.md
├─ LICENSE
├─ main.py
├─ pyproject.toml
├─ README.md
├─ reports
│  ├─ customer_report.md
│  ├─ driver_report.md
│  └─ truck_report.md
├─ scripts
│  ├─ mongo_to_postgres.py
│  └─ README.md
├─ sql
│  ├─ 01_lp_drop_all_tables.sql
│  ├─ 02_list_table_columns.sql
│  ├─ 03_database_row_counts.sql
│  ├─ 04_fuel_analytics_report.sql
│  ├─ 05_truck_fleet_analysis.sql
│  ├─ 06_fn_customers_report.sql
│  ├─ 07_fn_drivers_report.sql
│  ├─ 08_fn_trucks_report.sql
│  ├─ 09_fn_routes_report.sql
│  ├─ 10_fn_sales_report.sql
│  ├─ 11_fn_facilities_report.sql
│  ├─ 12_fn_metrics_reconciliation_report.sql
│  ├─ 13_trg_financial_validation.sql
│  ├─ 14_lp_operational_feedback.sql
│  ├─ README.md
│  └─ test.sql
├─ tests
│  ├─ 01_proc_customer_data_quality.sql
│  ├─ 02_proc_driver_data_quality.sql
│  ├─ 03_proc_delivery_events_data_quality.sql
│  ├─ 04_proc_loads_data_quality.sql
│  ├─ 05_proc_routes_data_quality.sql
│  ├─ 06_proc_trucks_data_quality.sql
│  └─ README.md
├─ utils
│  ├─ connection.py
│  ├─ engine.py
│  ├─ logger.py
│  └─ README.md
├─ uv.lock
└─ watermark.json

```