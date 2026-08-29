# Trucking & Logistics Data Analytics Suite

## Overview

This directory contains a comprehensive suite of advanced PostgreSQL scripts designed for an end-to-end trucking and logistics data warehouse. The files encompass the full SQL lifecycle: from database teardown and schema inspection to exploratory data analysis (EDA), advanced parameterized reporting functions, financial validation triggers, and an automated operational feedback loop.

These scripts demonstrate advanced SQL patterns including dynamic SQL execution, Common Table Expressions (CTEs), autonomous transactions (via `dblink`), PL/pgSQL stored procedures, and complex data aggregations.

## File Contents & Directory Structure

The files are sequentially numbered for logical execution and grouped into functional categories:

### 1. Utility & Schema Inspection
Scripts for resetting environments and understanding table structures and volumes.
* **`01_lp_drop_all_tables.sql`**: A PL/pgSQL block that dynamically drops all tables in the `public` schema. Useful for clean environment resets.
* **`02_list_table_columns.sql`**: Queries the `information_schema` to generate a data dictionary, listing all tables, columns, and their data types.
* **`03_database_row_counts.sql`**: Uses `UNION ALL` to compute and rank record counts across all major tables (trucks, loads, drivers, facilities, etc.) to assess data volume.

### 2. Exploratory Data Analysis (EDA)
Quick analytical queries to understand high-level operational metrics.
* **`04_fuel_analytics_report.sql`**: Aggregates fuel purchase data to report on total spend, average cost per gallon, and ranks fuel spend by state and by driver.
* **`05_truck_fleet_analysis.sql`**: Analyzes fleet composition, including status breakdowns, make/model distributions, fuel types, and average tank capacities based on vehicle age.

### 3. Advanced Parameterized Reporting Functions
A collection of PL/pgSQL functions that act as a reporting API. These functions accept optional parameters (date ranges, statuses, types) to generate dynamic, granular metrics without fanning out joins.
* **`06_fn_customers_report.sql`**: Generates customer-level performance metrics (load volume, revenue, and on-time delivery percentages).
* **`07_fn_drivers_report.sql`**: Aggregates driver statistics, combining trip revenues, fuel efficiency (MPG), idle hours, and safety incident histories.
* **`08_fn_trucks_report.sql`**: Produces a truck-level fleet report that calculates total miles, average MPG, revenue per mile, and cost per mile (combining fuel and maintenance).
* **`09_fn_routes_report.sql`**: Analyzes route and lane performance, calculating revenue per mile, on-time delivery rates, and mileage variance (planned vs. actual).
* **`10_fn_sales_report.sql`**: Utilizes dynamic SQL to aggregate load revenue, fuel surcharges, and accessorial charges into flexible time buckets (daily, weekly, monthly, quarterly).
* **`11_fn_facilities_report.sql`**: Reports on dock and detention performance at the facility level, normalizing event counts and detention minutes by the number of dock doors.

### 4. Data Quality & Financial Validation
Ensures data integrity and surfaces discrepancies between live facts and materialized views.
* **`12_fn_metrics_reconciliation_report.sql`**: Compares dynamically computed monthly metrics (from raw trip/load data) against pre-aggregated tables to catch data drift or bugs, flagging significant variances.
* **`13_trg_financial_validation.sql`**: Implements `BEFORE INSERT/UPDATE` triggers that reject invalid financial records (e.g., negative revenue, mismatched maintenance costs). It uses the `dblink` extension to log rejected attempts via autonomous transactions without rolling back the log entry.

### 5. Automated Operational Feedback
A proactive alerting system for continuous monitoring.
* **`14_lp_operational_feedback.sql`**: A complete operational feedback loop. It defines KPI thresholds and creates a master stored procedure (`run_feedback_loop`) that calls individual checks across domains (Driver, Fleet, Safety, Delivery, Fuel, Maintenance). It logs warnings and critical alerts into an `operational_alerts` table, which is surfaced via a `v_open_alerts` view.

## Key SQL Concepts Demonstrated
* **PL/pgSQL Functions & Procedures**: Encapsulating complex business logic into reusable database functions.
* **Dynamic SQL**: Using `EXECUTE format(...)` to reshape output schemas on the fly based on user input (e.g., date granularities).
* **Data Integrity Enforcement**: Leveraging Trigger Functions for advanced row-level validation.
* **Autonomous Transactions**: Utilizing `dblink` for audit logging within rolled-back transactions.
* **Advanced Aggregation Filters**: Extensive use of `COUNT(...) FILTER (WHERE ...)` for precise conditional aggregations without subqueries.
* **Avoidance of Join Fan-Out**: Pre-aggregating one-to-many relationships within CTEs before joining them to master entity lists.