// Defines explicit StructTypes for every Mongo collection per EDA.
package com.example.spark

import org.apache.spark.sql.types._

object Schemas {
  val bronze: StructType = StructType(Seq(
    StructField("event_id", StringType, nullable = false),
    StructField("collection", StringType, nullable = false),
    StructField("doc_id", StringType, nullable = false),
    StructField("op", StringType, nullable = false),
    StructField("cluster_time", TimestampType, nullable = false),
    StructField("full_document", StringType, nullable = true),
    StructField("source_file", StringType, nullable = true),
    StructField("ingested_at", TimestampType, nullable = false)
  ))

  val loads: StructType = StructType(Seq(
    StructField("load_id", StringType, nullable = false),
    StructField("customer_id", StringType, nullable = false),
    StructField("route_id", StringType, nullable = false),
    StructField("load_date", StringType, nullable = true),
    StructField("load_type", StringType, nullable = true),
    StructField("weight_lbs", IntegerType, nullable = true),
    StructField("pieces", IntegerType, nullable = true),
    StructField("revenue", DoubleType, nullable = true),
    StructField("fuel_surcharge", DoubleType, nullable = true),
    StructField("accessorial_charges", DoubleType, nullable = true),
    StructField("load_status", StringType, nullable = true),
    StructField("booking_type", StringType, nullable = true),
    StructField("updated_at", StringType, nullable = true)
  ))

  val trips: StructType = StructType(Seq(
    StructField("trip_id", StringType, nullable = false),
    StructField("load_id", StringType, nullable = false),
    StructField("driver_id", StringType, nullable = true),
    StructField("truck_id", StringType, nullable = true),
    StructField("trailer_id", StringType, nullable = true),
    StructField("dispatch_date", StringType, nullable = true),
    StructField("actual_distance_miles", DoubleType, nullable = true),
    StructField("actual_duration_hours", DoubleType, nullable = true),
    StructField("fuel_gallons_used", DoubleType, nullable = true),
    StructField("average_mpg", DoubleType, nullable = true),
    StructField("idle_time_hours", DoubleType, nullable = true),
    StructField("trip_status", StringType, nullable = true)
  ))

  val deliveryEvents: StructType = StructType(Seq(
    StructField("event_id", StringType, nullable = false),
    StructField("load_id", StringType, nullable = true),
    StructField("trip_id", StringType, nullable = true),
    StructField("event_type", StringType, nullable = true),
    StructField("facility_id", StringType, nullable = true),
    StructField("scheduled_datetime", StringType, nullable = true),
    StructField("actual_datetime", StringType, nullable = true),
    StructField("detention_minutes", IntegerType, nullable = true),
    StructField("on_time_flag", StringType, nullable = true)
  ))

  val customers: StructType = StructType(Seq(
    StructField("customer_id", StringType, nullable = false),
    StructField("customer_name", StringType, nullable = true),
    StructField("customer_type", StringType, nullable = true),
    StructField("account_status", StringType, nullable = true),
    StructField("annual_revenue_potential", DoubleType, nullable = true),
    StructField("credit_terms_days", IntegerType, nullable = true)
  ))

  val collections: Map[String, StructType] = Map(
    "loads" -> loads,
    "trips" -> trips,
    "delivery_events" -> deliveryEvents,
    "customers" -> customers
  )
}
