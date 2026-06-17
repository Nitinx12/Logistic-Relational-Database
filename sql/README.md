# SQL Analytics Library

This folder contains a collection of PostgreSQL scripts designed for a trucking and fleet management database. The scripts range from basic database utility and validation queries to complex analytical reports and dynamic Pl/pgSQL functions. Together, they provide a comprehensive toolkit for managing database schemas, monitoring fleet operations, and generating business intelligence reports.

## File Contents
### Utility & Validation Scripts

1. `lp_drop_all_tables.sql`:- Contains a PL/pgSQL block that iterates through the public schema and drops all existing tables using CASCADE. 
2. `list_table_columns.sql` :- Queries the information_schema.columns to extract a list of all table names, column names, and data types currently active in the public schema.
3. `database_row_counts.sql` :- Uses a UNION ALL statement to quickly return the total row counts for all major tables in the database, including `trucks`, `trailers`, `drivers`, `customers`, `routes`, `facilities`, `loads`, `trips`, `fuel_purchases`, `maintenance_records`, `safety_incidents`, `delivery_events`, and `metrics tables`.
4. `fuel_analysis.sql` :- Analyzes fuel purchase data by calculating total spend, average cost per fill, and identifying the top 10 states and top 10 drivers by fuel spend
5. `truck_fleet_stats.sql` :-  Provides a status breakdown of the fleet by grouping trucks by their current status, manufacturer make, fuel type, and age/model year distribution.

```SQL
SELECT
    COUNT(fuel_purchase_id)             AS total_purchases,
    ROUND(SUM(total_cost)::numeric, 2)  AS total_fuel_spend,
    ROUND(AVG(total_cost)::numeric, 2)  AS avg_cost_per_purchase,
    ROUND(SUM(gallons)::numeric, 2)     AS total_gallons,
    ROUND(AVG(gallons)::numeric, 2)     AS avg_gallons_per_fill,
    ROUND(AVG(price_per_gallon)::numeric, 3) AS avg_price_per_gallon,
    ROUND(MIN(price_per_gallon)::numeric, 3) AS min_price_per_gallon,
    ROUND(MAX(price_per_gallon)::numeric, 3) AS max_price_per_gallon
FROM fuel_purchases;
```


