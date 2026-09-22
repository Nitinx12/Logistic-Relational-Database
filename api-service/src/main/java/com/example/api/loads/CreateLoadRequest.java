// Validated DTO for creating a load.
package com.example.api.loads;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

public record CreateLoadRequest(
    @NotBlank String customerId,
    @NotBlank String routeId,
    @NotBlank String loadType,
    @NotNull @Positive Integer weightLbs,
    @NotNull @Positive Integer pieces,
    @NotNull @Positive Double revenue) {}
