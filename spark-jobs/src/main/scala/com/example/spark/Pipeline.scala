// Orchestrates bronze → silver → dq → gold → postgres in one Spark submit.
package com.example.spark

import org.apache.spark.sql.SparkSession

object Pipeline {
  def main(args: Array[String]): Unit = {
    val landing = sys.env.getOrElse("LANDING_ROOT", "landing")
    val bronze = sys.env.getOrElse("BRONZE_ROOT", "delta/bronze")
    val silver = sys.env.getOrElse("SILVER_ROOT", "delta/silver")
    val gold = sys.env.getOrElse("GOLD_ROOT", "delta/gold")
    val pgUrl = sys.env.getOrElse("POSTGRES_JDBC_URL", "jdbc:postgresql://postgres:5432/LRDB")
    val pgUser = sys.env.getOrElse("POSTGRES_USERNAME", "postgres")
    val pgPass = sys.env.getOrElse("POSTGRES_PASSWORD", "postgres")

    val spark = SparkSession.builder().appName("lrdb-pipeline").getOrCreate()

    BronzeJob.run(spark, landing, bronze)
    SilverTransforms.applySilver(spark, bronze, silver)
    val passed = DataQuality.gate(spark, silver)
    if (!passed) {
      spark.stop()
      throw new IllegalStateException("dq gate failed, gold skipped")
    }
    GoldJob.run(spark, silver, gold)
    LoadToPostgres.run(spark, gold, pgUrl, pgUser, pgPass)
    spark.stop()
  }
}
