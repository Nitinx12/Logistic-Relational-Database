// Evaluates silver data quality between silver and gold.
package com.example.spark

import org.apache.spark.sql.{DataFrame, SparkSession}
import org.apache.spark.sql.functions._

object DataQuality {
  case class Result(table: String, passed: Boolean, nullRate: Double, duplicateCount: Long, rejectRatio: Double, rowCount: Long)

  def checkLoads(df: DataFrame, rejects: DataFrame): Result = {
    val total = df.count()
    val nullKeys = df.filter(col("load_id").isNull || col("customer_id").isNull).count()
    val dups = total - df.select("load_id").distinct().count()
    val rejectCount = rejects.count()
    val rejectRatio = if (total == 0) 0.0 else rejectCount.toDouble / (total + rejectCount)
    val nullRate = if (total == 0) 0.0 else nullKeys.toDouble / total
    val passed = nullRate < 0.01 && dups == 0 && rejectRatio < 0.05
    Result("loads", passed, nullRate, dups, rejectRatio, total)
  }

  def gate(spark: SparkSession, silverRoot: String): Boolean = {
    val loads = spark.read.format("delta").load(s"$silverRoot/loads")
    val rejects = spark.read.format("delta").load(s"$silverRoot/_rejects")
    val r = checkLoads(loads, rejects)
    spark.createDataFrame(Seq(r)).write.format("delta").mode("append").save(s"$silverRoot/_dq_results")
    r.passed
  }
}
