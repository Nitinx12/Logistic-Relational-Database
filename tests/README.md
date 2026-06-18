# Data Quality Stored Procedures

Six PL/pgSQL procedures, one per table, each checking the relevant table for nulls, duplicates, invalid formats, out-of-range values, and cross-field inconsistencies. Each raises a `NOTICE` and passes silently if everything's clean, or raises an `EXCEPTION` listing every failed check (with record counts) if something's wrong. Some checks are `RAISE NOTICE` warnings instead of hard failures — those rest on a business-rule assumption that hasn't been confirmed against your data yet, and won't block validation on their own.

| File | Table | Call |
|---|---|---|
| `proc_customer_data_quality.sql` | `customers` | `CALL proc_customer_data_quality();` |
| `proc_driver_data_quality.sql` | `drivers` | `CALL proc_driver_data_quality();` |
| `proc_delivery_events_data_quality.sql` | `delivery_events` | `CALL proc_delivery_events_data_quality();` |
| `proc_loads_data_quality.sql` | `loads` | `CALL proc_loads_data_quality();` |
| `proc_routes_data_quality.sql` | `routes` | `CALL proc_routes_data_quality();` |
| `proc_trucks_data_quality.sql` | `trucks` | `CALL proc_trucks_data_quality();` |

## customers
Checks for missing/duplicate customer_id, missing customer_name, customer_type, account_status, primary_freight_type, negative credit_terms_days, negative annual_revenue_potential, and future contract_start_date.

## drivers
Checks for missing/duplicate driver_id, missing name fields, hire_date and date_of_birth validity (no future dates, no DOB over 100 years ago, no hire before age 18), termination_date consistency with hire_date and employment_status, missing/duplicate license_number+license_state, license_state format (2-letter code), missing home_terminal, employment_status and cdl_class against allowed-value lists, and years_experience bounds. The years-of-experience-vs-age check is a warning only, since this dataset's experience values don't reliably correlate with date_of_birth.

## delivery_events
Checks for missing/duplicate event_id, missing load_id/trip_id/event_type/facility_id, event_type against an allowed-value list, scheduled_datetime/actual_datetime validity (no future actual time, no past-due event missing an actual time), detention_minutes bounds, on_time_flag against an allowed-value list (`TRUE`/`FALSE` text) and cross-checked against the actual scheduled-vs-actual gap (±120 minutes is the confirmed on-time window), location_city/location_state validity, and duplicate event signatures (same load + type + scheduled time).

## loads
Checks for missing/duplicate load_id, missing customer_id/route_id/load_date, load_type against an allowed-value list (`Dry Van`, `Refrigerated`), load_status locked to `Completed` (this table holds historical/completed loads only), booking_type against an allowed-value list (`Contract`, `Dedicated`, `Spot`), no negative weight/pieces/revenue/fuel_surcharge/accessorial_charges, and missing/future updated_at. Zero weight, zero pieces, zero revenue on a completed load, future load_date, and excessive weight (over 80,000 lbs) are warnings only.

## routes
Checks for missing/duplicate route_id, missing origin/destination city and state, origin_state/destination_state format (2-letter code), no negative distance/rate/surcharge/transit days, and missing/future updated_at. Origin identical to destination, the same lane appearing under multiple route_ids, zero distance, distance over 3,500 miles, zero base rate, zero transit days, and transit days over 14 are warnings only.

## trucks
Checks for missing/duplicate truck_id, missing/negative/duplicate unit_number, missing make, model_year bounds (1980 through next year), missing/duplicate vin and VIN format (18 alphanumeric characters, no I/O/Q — this dataset's VIN convention, not the real-world 17-character standard), acquisition_date validity (no future date), no negative acquisition_mileage, fuel_type locked to `Diesel`, status against an allowed-value list (`Active`, `Inactive`, `Maintenance`), missing home_terminal, and missing/future updated_at. Tank capacity of zero or over 300 gallons, and an acquisition_date more than a year before model_year, are warnings only.

## Notes
- All enum/allowed-value lists were confirmed against actual data rather than assumed, except where noted as warnings above.
- If a warning check turns out to never legitimately fire on real data, it can be promoted to a hard failure by moving its `RAISE NOTICE` into the `v_errors` accumulator (see any of the locked-enum checks above for the pattern).