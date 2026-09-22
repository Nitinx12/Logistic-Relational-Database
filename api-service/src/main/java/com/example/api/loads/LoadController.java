// Exposes validated load actions with idempotency and confirmation.
package com.example.api.loads;

import jakarta.validation.Valid;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/v1/loads")
public class LoadController {
  private final LoadService service;

  public LoadController(LoadService service) {
    this.service = service;
  }

  @PostMapping
  public ResponseEntity<Map<String, Object>> create(
      @Valid @RequestBody CreateLoadRequest req,
      @RequestHeader("Idempotency-Key") String key,
      @RequestHeader(value = "X-Actor", defaultValue = "anonymous") String actor,
      @RequestHeader(value = "X-Trace-Id", required = false) String traceId) {
    Map<String, Object> res = service.create(req, key, actor, traceId);
    if (res.containsKey("confirmation_token")) {
      return ResponseEntity.status(202).body(res);
    }
    return ResponseEntity.status(201).body(res);
  }
}
