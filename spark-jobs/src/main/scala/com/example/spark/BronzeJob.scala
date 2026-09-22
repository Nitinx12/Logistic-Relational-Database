// Ingests landing NDJSON into bronze Delta as immutable raw events.
package com.example.spark

import org.apache.spark.sql.{DataFrame, SparkSession}
import org.apache.spark.sql.functions._

object BronzeJob {
  def run(spark: SparkSession, landingRoot: String, bronzeRoot: String): Unit = {
    val collections = Seq("loads","trips","delivery_events","fuel_purchases","customers","routes","drivers","trucks","facilities","trailers","maintenance_records","safety_incidents","truck_utilization_metrics","driver_monthly_metrics")
    collections.foreach { coll =>
      val input = s"$landingRoot/$coll"
      val raw = readLanding(spark, input)
      if (!raw.isEmpty) {
        val bronze = toBronze(raw, coll)
        val deduped = bronze.dropDuplicates("event_id")
        deduped.write.format("delta").mode("append").option("mergeSchema","true").save(s"$bronzeRoot/$coll")
      }
    }
  }

  def readLanding(spark: SparkSession, path: String): DataFrame = {
    try {
      spark.read.json(path)
    } catch {
      case _: Exception => spark.createDataFrame(spark.sparkContext.emptyRDD[org.apache.spark.sql.Row], Schemas.bronze)
    }
  }

  def toBronze(df: DataFrame, collection: String): DataFrame = {
    df.withColumn("collection", lit(collection))
      .withColumn("ingested_at", current_timestamp())
  }
}
