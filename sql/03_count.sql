SELECT 'trucks'                  AS table_name, COUNT(*) AS records FROM trucks
UNION ALL
SELECT 'trailers',                              COUNT(*) FROM trailers
UNION ALL
SELECT 'drivers',                               COUNT(*) FROM drivers
UNION ALL
SELECT 'customers',                             COUNT(*) FROM customers
UNION ALL
SELECT 'routes',                                COUNT(*) FROM routes
UNION ALL
SELECT 'facilities',                            COUNT(*) FROM facilities
UNION ALL
SELECT 'loads',                                 COUNT(*) FROM loads
UNION ALL
SELECT 'trips',                                 COUNT(*) FROM trips
UNION ALL
SELECT 'fuel_purchases',                        COUNT(*) FROM fuel_purchases
UNION ALL
SELECT 'maintenance_records',                   COUNT(*) FROM maintenance_records
UNION ALL
SELECT 'safety_incidents',                      COUNT(*) FROM safety_incidents
UNION ALL
SELECT 'delivery_events',                       COUNT(*) FROM delivery_events
UNION ALL
SELECT 'driver_monthly_metrics',                COUNT(*) FROM driver_monthly_metrics
UNION ALL
SELECT 'truck_utilization_metrics',             COUNT(*) FROM truck_utilization_metrics
ORDER BY records DESC;