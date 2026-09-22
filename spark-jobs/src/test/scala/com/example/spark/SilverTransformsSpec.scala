// Tests silver transforms for idempotency and explicit schemas.
package com.example.spark

import org.apache.spark.sql.SparkSession
import org.scalatest.funsuite.AnyFunSuite

class SilverTransformsSpec extends AnyFunSuite {
  test("bronzeToSilverLoads dedupes by load_id and keeps latest cluster_time") {
    val spark = SparkSession.builder().master("local[2]").appName("test").getOrCreate()
    import spark.implicits._
    val bronze = spark.createDataFrame(Seq(
      ("e1", "loads", "L1", "insert", java.sql.Timestamp.valueOf("2024-01-01 00:00:00"), """{"load_id":"L1","customer_id":"C1","route_id":"R1","load_type":"Dry Van","weight_lbs":100,"pieces":1,"revenue":10.0}""", "f", java.sql.Timestamp.valueOf("2024-01-01 00:00:00")),
      ("e2", "loads", "L1", "insert", java.sql.Timestamp.valueOf("2024-01-02 00:00:00"), """{"load_id":"L1","customer_id":"C1","route_id":"R1","load_type":"Dry Van","weight_lbs":200,"pieces":1,"revenue":20.0}""", "f", java.sql.Timestamp.valueOf("2024-01-02 00:00:00"))
    )).toDF("event_id","collection","doc_id","op","cluster_time","full_document","source_file","ingested_at")
    val (valid, rejects) = SilverTransforms.bronzeToSilverLoads(spark, bronze)
    assert(valid.count() == 1)
    assert(rejects.count() == 0)
    val row = valid.collect().head
    assert(row.getAs[Int]("weight_lbs") == 200)
    spark.stop()
  }

  test("silver is idempotent when run twice") {
    val spark = SparkSession.builder().master("local[2]").appName("test2").getOrCreate()
    import spark.implicits._
    val bronze = spark.createDataFrame(Seq(
      ("e1", "loads", "L2", "insert", java.sql.Timestamp.valueOf("2024-01-01 00:00:00"), """{"load_id":"L2","customer_id":"C2","route_id":"R2","load_type":"Dry Van","weight_lbs":100,"pieces":1,"revenue":10.0}""", "f", java.sql.Timestamp.valueOf("2024-01-01 00:00:00"))
    )).toDF("event_id","collection","doc_id","op","cluster_time","full_document","source_file","ingested_at")
    val (v1, _) = SilverTransforms.bronzeToSilverLoads(spark, bronze)
    val (v2, _) = SilverTransforms.bronzeToSilverLoads(spark, bronze)
    assert(v1.count() == v2.count())
    spark.stop()
  }
}
