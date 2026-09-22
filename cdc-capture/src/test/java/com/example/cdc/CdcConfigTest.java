// Validates CdcConfig defaults and batching.
package com.example.cdc;

import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;

public class CdcConfigTest {
  @Test
  void defaultsIncludeFourteenCollections() {
    CdcConfig cfg = CdcConfig.fromEnvironment();
    assertThat(cfg.collections()).hasSize(14);
    assertThat(cfg.batchSize()).isPositive();
  }

  @Test
  void hashIsDeterministic() {
    String h1 = CdcCaptureApp.hash("a|b|c|op");
    String h2 = CdcCaptureApp.hash("a|b|c|op");
    assertThat(h1).isEqualTo(h2).hasSize(32);
  }
}
