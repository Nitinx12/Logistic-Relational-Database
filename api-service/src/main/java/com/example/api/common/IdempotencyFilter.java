// Enforces Idempotency-Key header presence for state-changing calls.
package com.example.api.common;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
public class IdempotencyFilter extends OncePerRequestFilter {
  @Override
  protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
      throws ServletException, IOException {
    if (request.getMethod().equals("POST") || request.getMethod().equals("PATCH")) {
      String key = request.getHeader("Idempotency-Key");
      String trace = request.getHeader("X-Trace-Id");
      if (key == null || key.isBlank()) {
        response.sendError(400, "Idempotency-Key required");
        return;
      }
      response.setHeader("X-Trace-Id", trace != null ? trace : java.util.UUID.randomUUID().toString());
    }
    chain.doFilter(request, response);
  }
}
