// Transforms bronze raw JSON into typed, deduped silver tables.
package com.example.spark

import org.apache.spark.sql.{DataFrame, SparkSession}
import org.apache.spark.sql.functions._
import org.apache.spark.sql.types._

object SilverTransforms {
  def bronzeToSilverLoads(spark: SparkSession, bronze: DataFrame): (DataFrame, DataFrame) = {
    import spark.implicits._
    val parsed = bronze
      .filter(col("collection") === "loads")
      .withColumn("doc", from_json(col("full_document"), Schemas.loads))
      .select(col("doc.*"), col("cluster_time"), col("op"))
      .withColumn("load_date", to_date(col("load_date"), "yyyy-MM-dd"))
      .withColumn("on_time_flag", when(col("load_status").isNull, lit(null)).otherwise(col("load_status")))
    val window = org.apache.spark.sql.expressions.Window.partitionBy("load_id").orderBy(col("cluster_time").desc)
    val ranked = parsed.withColumn("rn", row_number().over(window)).filter(col("rn") === 1).drop("rn")
    val rejects = ranked.filter(col("load_id").isNull || col("customer_id").isNull || col("route_id").isNull)
      .withColumn("reason_code", lit("null_key"))
    val valid = ranked.filter(col("load_id").isNotNull && col("customer_id").isNotNull)
      .withColumn("is_deleted", when(col("op") === "delete", lit(true)).otherwise(lit(false)))
    (valid, rejects)
  }

  def bronzeToSilverTrips(spark: SparkSession, bronze: DataFrame): (DataFrame, DataFrame) = {
    import spark.implicits._
    val parsed = bronze
      .filter(col("collection") === "trips")
      .withColumn("doc", from_json(col("full_document"), Schemas.trips))
      .select(col("doc.*"), col("cluster_time"), col("op"))
      .withColumn("driver_id", when(col("driver_id") === "", lit(null)).otherwise(col("driver_id")))
      .withColumn("truck_id", when(col("truck_id") === "", lit(null)).otherwise(col("truck_id")))
      .withColumn("dispatch_date", to_date(col("dispatch_date"), "yyyy-MM-dd"))
    val window = org.apache.spark.sql.expressions.Window.partitionBy("trip_id").orderBy(col("cluster_time").desc)
    val ranked = parsed.withColumn("rn", row_number().over(window)).filter(col("rn") === 1).drop("rn")
    val rejects = ranked.filter(col("trip_id").isNull)
      .withColumn("reason_code", lit("null_key"))
    val valid = ranked.filter(col("trip_id").isNotNull)
      .withColumn("is_deleted", when(col("op") === "delete", lit(true)).otherwise(lit(false)))
    (valid, rejects)
  }

  def applySilver(spark: SparkSession, bronzeRoot: String, silverRoot: String): Unit = {
    val bronzeLoads = spark.read.format("delta").load(s"$bronzeRoot/loads")
    val (validLoads, rejectsLoads) = bronzeToSilverLoads(spark, bronzeLoads)
    validLoads.write.format("delta").mode("overwrite").option("overwriteSchema","true").save(s"$silverRoot/loads")
    rejectsLoads.write.format("delta").mode("append").save(s"$silverRoot/_rejects")

    val bronzeTrips = spark.read.format("delta").load(s"$bronzeRoot/trips")
    val (validTrips, rejectsTrips) = bronzeToSilverTrips(spark, bronzeTrips)
    validTrips.write.format("delta").mode("overwrite").save(s"$silverRoot/trips")
    rejectsTrips.write.format("delta").mode("append").save(s"$silverRoot/_rejects")
  }
}
