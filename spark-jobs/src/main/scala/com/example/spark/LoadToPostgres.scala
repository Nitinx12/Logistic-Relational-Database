// Stages gold Delta to Postgres serving tables via JDBC.
package com.example.spark

import org.apache.spark.sql.SparkSession
import java.util.Properties

object LoadToPostgres {
  def run(spark: SparkSession, goldRoot: String, jdbcUrl: String, user: String, password: String): Unit = {
    val props = new Properties()
    props.setProperty("user", user)
    props.setProperty("password", password)
    props.setProperty("driver", "org.postgresql.Driver")
    val tables = Seq("customer_summary", "load_facts", "route_metrics_daily")
    tables.foreach { t =>
      val df = spark.read.format("delta").load(s"$goldRoot/$t")
      df.write.mode("overwrite").jdbc(jdbcUrl, s"serving.${t}_stg", props)
    }
  }
}
