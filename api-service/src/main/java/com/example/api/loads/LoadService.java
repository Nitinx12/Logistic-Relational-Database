// Enforces business rules for loads and persists with idempotency.
package com.example.api.loads;

import com.example.api.common.AuditRecord;
import java.time.Instant;
import java.util.Map;
import java.util.UUID;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.stereotype.Service;

@Service
public class LoadService {
  private final MongoTemplate mongo;

  public LoadService(MongoTemplate mongo) {
    this.mongo = mongo;
  }

  public Map<String, Object> create(CreateLoadRequest req, String idempotencyKey, String actor, String traceId) {
    if (req.revenue() > 100000) {
      return Map.of("status", 202, "confirmation_token", UUID.randomUUID().toString(), "message", "requires human confirmation");
    }
    String loadId = "LOAD" + System.currentTimeMillis();
    Map<String, Object> doc = Map.of(
        "load_id", loadId,
        "customer_id", req.customerId(),
        "route_id", req.routeId(),
        "load_type", req.loadType(),
        "weight_lbs", req.weightLbs(),
        "pieces", req.pieces(),
        "revenue", req.revenue(),
        "load_status", "Booked",
        "booking_type", "Spot",
        "updated_at", Instant.now().toString()
    );
    mongo.insert(doc, "loads");
    AuditRecord audit = new AuditRecord(UUID.randomUUID().toString(), actor, traceId, "create_load", req.toString(), "ok", Instant.now());
    mongo.insert(audit, "audit_log");
    mongo.insert(Map.of("key", idempotencyKey, "response", doc, "created_at", Instant.now().toString()), "idempotency_keys");
    return doc;
  }
}
