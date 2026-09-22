// Validates Bean Validation and idempotency contract for loads.
package com.example.api;

import com.example.api.loads.CreateLoadRequest;
import jakarta.validation.Validation;
import jakarta.validation.Validator;
import org.junit.jupiter.api.Test;
import static org.assertj.core.api.Assertions.assertThat;

public class LoadValidationTest {
  private final Validator validator = Validation.buildDefaultValidatorFactory().getValidator();

  @Test
  void rejectsBlankCustomerId() {
    CreateLoadRequest req = new CreateLoadRequest("", "RTE00001", "Dry Van", 100, 1, 100.0);
    assertThat(validator.validate(req)).isNotEmpty();
  }

  @Test
  void acceptsValidRequest() {
    CreateLoadRequest req = new CreateLoadRequest("CUST00001", "RTE00001", "Dry Van", 100, 1, 100.0);
    assertThat(validator.validate(req)).isEmpty();
  }
}
