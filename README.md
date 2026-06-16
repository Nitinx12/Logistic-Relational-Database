
```
LRDB
├─ .python-version
├─ api
│  ├─ cmd
│  │  ├─ bronze
│  │  └─ server
│  │     └─ main.go
│  ├─ go.mod
│  ├─ go.sum
│  ├─ internal
│  │  ├─ db
│  │  │  └─ postgres.go
│  │  ├─ handlers
│  │  │  ├─ customers.go
│  │  │  ├─ delivery_events.go
│  │  │  ├─ drivers.go
│  │  │  ├─ facilities.go
│  │  │  ├─ fuel_purchases.go
│  │  │  ├─ loads.go
│  │  │  ├─ maintenance.go
│  │  │  ├─ routes.go
│  │  │  ├─ safety_incidents.go
│  │  │  ├─ trailers.go
│  │  │  ├─ trips.go
│  │  │  └─ trucks.go
│  │  ├─ models
│  │  │  ├─ customer.go
│  │  │  ├─ delivery_event.go
│  │  │  ├─ driver.go
│  │  │  ├─ facility.go
│  │  │  ├─ fuel_purchase.go
│  │  │  ├─ load.go
│  │  │  ├─ maintenance_record.go
│  │  │  ├─ response.go
│  │  │  ├─ route.go
│  │  │  ├─ safety_incident.go
│  │  │  ├─ trailer.go
│  │  │  ├─ trip.go
│  │  │  └─ truck.go
│  │  └─ routes
│  └─ README.md
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
├─ driver
│  └─ postgresql.jar
├─ LICENSE
├─ main.py
├─ pyproject.toml
├─ README.md
├─ scripts
│  └─ mongo_to_postgres.py
├─ sql
│  └─ 01_lp_delete_tables.sql
├─ tests
├─ utils
│  ├─ connection.py
│  ├─ engine.py
│  ├─ logger.py
│  └─ README.md
├─ uv.lock
└─ watermark.json

```