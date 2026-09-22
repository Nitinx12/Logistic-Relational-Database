// Builds rebuildable gold aggregates from silver for serving.
package com.example.spark

import org.apache.spark.sql.{DataFrame, SparkSession}
import org.apache.spark.sql.functions._

object GoldJob {
  def buildCustomerSummary(silverLoads: DataFrame): DataFrame = {
    silverLoads
      .filter(col("is_deleted") === false)
      .groupBy("customer_id")
      .agg(
        count("load_id").as("total_loads"),
        sum("revenue").as("total_revenue"),
        max("load_date").as("last_load_date")
      )
  }

  def buildLoadFacts(silverLoads: DataFrame, silverTrips: DataFrame, customers: DataFrame, routes: DataFrame): DataFrame = {
    silverLoads.alias("l")
      .join(silverTrips.alias("t"), col("l.load_id") === col("t.load_id"), "left")
      .join(customers.alias("c"), col("l.customer_id") === col("c.customer_id"), "left")
      .join(routes.alias("r"), col("l.route_id") === col("r.route_id"), "left")
      .select(
        col("l.load_id"),
        col("l.customer_id"),
        col("l.route_id"),
        col("l.load_date"),
        col("l.revenue"),
        col("l.weight_lbs"),
        col("t.trip_id"),
        col("t.driver_id"),
        col("t.truck_id"),
        col("r.origin_city"),
        col("r.destination_city")
      )
  }

  def buildDailyMetrics(silverLoads: DataFrame): DataFrame = {
    silverLoads
      .filter(col("is_deleted") === false)
      .groupBy(col("load_date").as("metric_date"), col("route_id"))
      .agg(
        count("load_id").as("loads_count"),
        sum("revenue").as("total_revenue"),
        avg("weight_lbs").as("avg_weight_lbs")
      )
  }

  def run(spark: SparkSession, silverRoot: String, goldRoot: String): Unit = {
    val loads = spark.read.format("delta").load(s"$silverRoot/loads")
    val trips = spark.read.format("delta").load(s"$silverRoot/trips")
    val customers = spark.read.format("delta").load(s"$silverRoot/customers")
    val routes = spark.read.format("delta").load(s"$silverRoot/routes")
    buildCustomerSummary(loads).write.format("delta").mode("overwrite").save(s"$goldRoot/customer_summary")
    buildLoadFacts(loads, trips, customers, routes).write.format("delta").mode("overwrite").save(s"$goldRoot/load_facts")
    buildDailyMetrics(loads).write.format("delta").mode("overwrite").save(s"$goldRoot/route_metrics_daily")
  }
}
