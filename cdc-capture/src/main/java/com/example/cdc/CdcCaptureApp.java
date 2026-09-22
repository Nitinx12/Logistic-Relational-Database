// Tails MongoDB Change Streams per collection and batches NDJSON to landing.
package com.example.cdc;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.mongodb.client.MongoClient;
import com.mongodb.client.MongoClients;
import com.mongodb.client.MongoCollection;
import com.mongodb.client.MongoDatabase;
import com.mongodb.client.model.changestream.ChangeStreamDocument;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.time.Instant;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import org.bson.BsonDocument;
import org.bson.Document;

public final class CdcCaptureApp {
  private final CdcConfig config;
  private final ResumeTokenStore tokenStore;
  private final LandingWriter writer;
  private final ObjectMapper mapper;

  public CdcCaptureApp(CdcConfig config, ResumeTokenStore tokenStore, LandingWriter writer, ObjectMapper mapper) {
    this.config = config;
    this.tokenStore = tokenStore;
    this.writer = writer;
    this.mapper = mapper;
  }

  public static void main(String[] args) {
    CdcConfig cfg = CdcConfig.fromEnvironment();
    ObjectMapper mapper = new ObjectMapper();
    mapper.findAndRegisterModules();
    ResumeTokenStore store = new ResumeTokenStore(cfg.postgresUrl(), cfg.postgresUser(), cfg.postgresPassword());
    LandingWriter writer = new LandingWriter(Path.of(cfg.landingRoot()), mapper);
    CdcCaptureApp app = new CdcCaptureApp(cfg, store, writer, mapper);
    app.start();
  }

  public void start() {
    try (MongoClient client = MongoClients.create(config.mongoUri())) {
      MongoDatabase db = client.getDatabase(config.mongoDatabase());
      ScheduledExecutorService pool = Executors.newScheduledThreadPool(config.collections().size());
      for (String col : config.collections()) {
        pool.submit(() -> watchCollection(db, col));
      }
      Runtime.getRuntime().addShutdownHook(new Thread(pool::shutdownNow));
      try {
        pool.awaitTermination(Long.MAX_VALUE, TimeUnit.DAYS);
      } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
      }
    }
  }

  private void watchCollection(MongoDatabase db, String collectionName) {
    MongoCollection<Document> col = db.getCollection(collectionName);
    List<CdcEvent> buffer = new ArrayList<>(config.batchSize());
    Instant windowStart = Instant.now();
    String resumeToken = tokenStore.load(collectionName).orElse(null);
    while (!Thread.currentThread().isInterrupted()) {
      try {
        var stream = resumeToken == null
            ? col.watch(List.of()).fullDocument(com.mongodb.client.model.changestream.FullDocument.UPDATE_LOOKUP)
            : col.watch(List.of()).resumeAfter(BsonDocument.parse(resumeToken)).fullDocument(com.mongodb.client.model.changestream.FullDocument.UPDATE_LOOKUP);
        for (ChangeStreamDocument<Document> change : stream) {
          CdcEvent event = toEvent(collectionName, change);
          buffer.add(event);
          resumeToken = change.getResumeToken().toJson();
          boolean timeFlush = Instant.now().isAfter(windowStart.plus(config.batchWindow()));
          if (buffer.size() >= config.batchSize() || timeFlush) {
            Path file = writer.writeBatch(collectionName, List.copyOf(buffer));
            tokenStore.save(collectionName, resumeToken);
            buffer.clear();
            windowStart = Instant.now();
            if (file != null) {
              System.out.println("{\"collection\":\"" + collectionName + "\",\"file\":\"" + file + "\",\"events\":" + event.eventId() + "}");
            }
          }
        }
      } catch (Exception e) {
        System.err.println("watch failed for " + collectionName + ": " + e.getMessage());
        try {
          TimeUnit.SECONDS.sleep(5);
        } catch (InterruptedException ie) {
          Thread.currentThread().interrupt();
          return;
        }
      }
    }
  }

  static CdcEvent toEvent(String collection, ChangeStreamDocument<Document> change) {
    String op = change.getOperationType().getValue().toLowerCase();
    String docId = "";
    if (change.getDocumentKey() != null && change.getDocumentKey().containsKey("_id")) {
      docId = String.valueOf(change.getDocumentKey().get("_id"));
    }
    String fullDoc = change.getFullDocument() != null ? change.getFullDocument().toJson() : null;
    Instant cluster = change.getClusterTime() != null ? Instant.ofEpochSecond(change.getClusterTime().getTime() / 1000) : Instant.now();
    String eventId = hash(collection + "|" + docId + "|" + cluster + "|" + op);
    return new CdcEvent(eventId, collection, docId, op, cluster, fullDoc, null, Instant.now());
  }

  static String hash(String input) {
    try {
      MessageDigest md = MessageDigest.getInstance("SHA-256");
      byte[] dig = md.digest(input.getBytes(StandardCharsets.UTF_8));
      return HexFormat.of().formatHex(dig).substring(0, 32);
    } catch (Exception e) {
      throw new IllegalStateException(e);
    }
  }
}
