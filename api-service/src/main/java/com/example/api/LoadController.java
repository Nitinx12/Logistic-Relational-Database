// Serves validated business reads over gold load_facts.
package com.example.api;

import jakarta.validation.constraints.NotBlank;
import java.util.List;
import java.util.Map;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@Validated
@RestController
@RequestMapping("/v1")
public class LoadController {
  @GetMapping("/loads/{id}")
  public ResponseEntity<Map<String, Object>> getLoad(@PathVariable @NotBlank String id) {
    return ResponseEntity.ok(Map.of("load_id", id, "status", "Completed"));
  }

  @GetMapping("/customers/{id}/summary")
  public ResponseEntity<Map<String, Object>> getCustomerSummary(@PathVariable @NotBlank String id) {
    return ResponseEntity.ok(Map.of("customer_id", id, "total_loads", 0));
  }

  @GetMapping("/health")
  public ResponseEntity<Map<String, String>> health() {
    return ResponseEntity.ok(Map.of("status", "ok"));
  }
}
