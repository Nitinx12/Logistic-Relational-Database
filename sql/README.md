# Fleet Management Database Scripts

## Overview
This folder contains a collection of PostgreSQL scripts designed for a trucking and fleet management database. The scripts range from basic database utility and validation queries to complex analytical reports and dynamic Pl/pgSQL functions. Together, they provide a comprehensive toolkit for managing database schemas, monitoring fleet operations, and generating business intelligence reports.

## File Contents

### Utility & Validation Scripts
* **`01_lp_drop_all_tables.sql`**: Contains a PL/pgSQL block that iterates through the `public` schema and drops all existing tables using `CASCADE`.
* **`02_list_table_columns.sql`**: Queries the `information_schema.columns` to extract a list of all table names, column names, and data types currently active in the `public` schema.
* **`03_database_row_counts.sql`**: Uses a `UNION ALL` statement to quickly return the total row counts for all major tables in the database, including `trucks`, `trailers`, `drivers`, `customers`, `routes`, `facilities`, `loads`, `trips`, `fuel_purchases`, `maintenance_records`, `safety_incidents`, `delivery_events`, and metrics tables.

### Data Analysis Queries
* **`04_fuel_analytics_report.sql`**: Analyzes fuel purchase data by calculating total spend, average cost per fill, and identifying the top 10 states and top 10 drivers by fuel spend.
* **`05_truck_fleet_analysis.sql`**: Provides a status breakdown of the fleet by grouping trucks by their current status, manufacturer make, fuel type, and age/model year distribution.

### Advanced Reporting Functions (PL/pgSQL)
* **`06_fn_customers_report.sql`**: Creates the `fn_customers_report` function, which generates customer-level performance reports combining master data with load volume, revenue, and on-time delivery percentages over an optional date window.
* **`07_fn_drivers_report.sql`**: Creates the `fn_drivers_report` function to evaluate driver performance by aggregating total trips, miles driven, revenue generated, average MPG, and safety incident history.
* **`08_fn_trucks_report.sql`**: Creates the `fn_trucks_report` function to analyze truck-level profitability and utilization by tracking revenue, fuel purchase costs, maintenance events, and calculating the overall cost-per-mile.
* **`09_fn_routes_report.sql`**: Creates the `fn_routes_report` function, providing a route/lane-level analysis that compares planned transit distances against actual driven miles, while also calculating detention minutes and on-time delivery rates.
* **`10_fn_sales_report.sql`**: Creates the `fn_sales_report` function, which utilizes dynamic SQL to generate flexible sales reports that aggregate load revenue, fuel surcharges, and accessorial charges into customizable daily, weekly, monthly, or quarterly time buckets.