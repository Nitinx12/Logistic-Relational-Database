// Writes CDC batches to landing as NDJSON partitioned by collection and date.
package com.example.cdc;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.io.BufferedWriter;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.UUID;

public final class LandingWriter {
  private static final DateTimeFormatter DATE = DateTimeFormatter.ofPattern("yyyy-MM-dd");
  private final Path root;
  private final ObjectMapper mapper;

  public LandingWriter(Path root, ObjectMapper mapper) {
    this.root = root;
    this.mapper = mapper;
  }

  public Path writeBatch(String collection, List<CdcEvent> events) {
    if (events.isEmpty()) {
      return null;
    }
    String date = LocalDate.now().format(DATE);
    Path dir = root.resolve(collection).resolve("dt=" + date);
    try {
      Files.createDirectories(dir);
    } catch (IOException e) {
      throw new IllegalStateException("failed to create landing dir " + dir, e);
    }
    String fileName = String.format("events-%s-%s.ndjson", System.currentTimeMillis(), UUID.randomUUID().toString().substring(0, 8));
    Path file = dir.resolve(fileName);
    try (BufferedWriter w = Files.newBufferedWriter(file, StandardCharsets.UTF_8, StandardOpenOption.CREATE_NEW)) {
      for (CdcEvent e : events) {
        w.write(mapper.writeValueAsString(e));
        w.newLine();
      }
    } catch (IOException e) {
      throw new IllegalStateException("failed to write batch " + file, e);
    }
    return file;
  }

  public Path root() {
    return root;
  }
}
