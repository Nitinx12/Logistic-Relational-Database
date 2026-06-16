-- Status breakdown
SELECT 
    status, 
    COUNT(*) AS count 
FROM trucks 
GROUP BY status 
ORDER BY count DESC;

-- By make
SELECT 
    make, 
    COUNT(*) AS count 
FROM trucks 
GROUP BY make 
ORDER BY count DESC;

-- By fuel type
SELECT 
    fuel_type, 
    COUNT(*) AS count 
FROM trucks 
GROUP BY fuel_type;

-- Age distribution
SELECT
    model_year,
    COUNT(*) AS count,
    ROUND(AVG(tank_capacity_gallons), 1) AS avg_tank_capacity
FROM trucks
GROUP BY model_year
ORDER BY model_year;

SELECT *
FROM trucks;