-- Fuel Purchases Overview
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

-- Fuel Spend by State (top 10)
SELECT
    location_state,
    COUNT(*)                             AS purchases,
    ROUND(SUM(total_cost)::numeric, 2)   AS total_spend,
    ROUND(AVG(price_per_gallon)::numeric, 3) AS avg_price_per_gallon
FROM fuel_purchases
GROUP BY location_state
ORDER BY total_spend DESC
LIMIT 10;

-- Fuel Spend by Driver (top 10)
SELECT
    fp.driver_id,
    COUNT(*)                            AS purchases,
    ROUND(SUM(fp.total_cost)::numeric, 2) AS total_spend,
    ROUND(SUM(fp.gallons)::numeric, 2)  AS total_gallons
FROM fuel_purchases fp
GROUP BY fp.driver_id
ORDER BY total_spend DESC;