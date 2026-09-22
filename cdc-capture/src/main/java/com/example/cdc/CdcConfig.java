// Holds validated CDC runtime configuration from environment.
package com.example.cdc;

import java.time.Duration;
import java.util.List;

public record CdcConfig(
    String mongoUri,
    String mongoDatabase,
    List<String> collections,
    String landingRoot,
    String s3Endpoint,
    String s3Bucket,
    String postgresUrl,
    String postgresUser,
    String postgresPassword,
    int batchSize,
    Duration batchWindow) {
  public static CdcConfig fromEnvironment() {
    String mongoUri = envOrDefault("MONGO_URI", "mongodb://localhost:27017");
    String mongoDb = envOrDefault("MONGO_DB", "LRDB");
    String cols = envOrDefault("CDC_COLLECTIONS", String.join(",", defaultCollections()));
    String landing = envOrDefault("LANDING_ROOT", "landing");
    String s3Endpoint = System.getenv("S3_ENDPOINT");
    String s3Bucket = envOrDefault("S3_BUCKET", "landing");
    String pgHost = envOrDefault("POSTGRES_HOST", "localhost");
    String pgPort = envOrDefault("POSTGRES_PORT", "5432");
    String pgDb = envOrDefault("POSTGRES_DATABASE", "LRDB");
    String pgUser = envOrDefault("POSTGRES_USERNAME", "postgres");
    String pgPass = envOrDefault("POSTGRES_PASSWORD", "postgres");
    String pgUrl = String.format("jdbc:postgresql://%s:%s/%s", pgHost, pgPort, pgDb);
    int batchSize = Integer.parseInt(envOrDefault("CDC_BATCH_SIZE", "500"));
    Duration window = Duration.ofSeconds(Long.parseLong(envOrDefault("CDC_BATCH_WINDOW_SECONDS", "30")));
    return new CdcConfig(
        mongoUri,
        mongoDb,
        List.of(cols.split(",")),
        landing,
        s3Endpoint,
        s3Bucket,
        pgUrl,
        pgUser,
        pgPass,
        batchSize,
        window);
  }

  private static List<String> defaultCollections() {
    return List.of(
        "loads",
        "trips",
        "delivery_events",
        "fuel_purchases",
        "customers",
        "routes",
        "drivers",
        "trucks",
        "facilities",
        "trailers",
        "maintenance_records",
        "safety_incidents",
        "truck_utilization_metrics",
        "driver_monthly_metrics");
  }

  private static String envOrDefault(String key, String def) {
    String v = System.getenv(key);
    return v == null || v.isBlank() ? def : v;
  }
}
