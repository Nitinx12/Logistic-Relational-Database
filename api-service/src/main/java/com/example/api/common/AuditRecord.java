// Immutable audit entry for every business action.
package com.example.api.common;

import java.time.Instant;

public record AuditRecord(String id, String actor, String traceId, String action, String input, String outcome, Instant createdAt) {}
