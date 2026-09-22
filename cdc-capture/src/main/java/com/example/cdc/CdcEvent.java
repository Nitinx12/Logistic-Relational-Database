// Immutable CDC event persisted to landing and bronze.
package com.example.cdc;

import java.time.Instant;

public record CdcEvent(
    String eventId,
    String collection,
    String docId,
    String op,
    Instant clusterTime,
    String fullDocument,
    String sourceFile,
    Instant ingestedAt) {}
