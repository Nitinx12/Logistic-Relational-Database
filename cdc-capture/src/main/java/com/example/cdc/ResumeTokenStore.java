// Persists CDC resume tokens to ops.cdc_offsets after durable landing write.
package com.example.cdc;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.Optional;

public final class ResumeTokenStore {
  private final String url;
  private final String user;
  private final String password;

  public ResumeTokenStore(String url, String user, String password) {
    this.url = url;
    this.user = user;
    this.password = password;
  }

  public Optional<String> load(String collection) {
    String sql = "SELECT resume_token FROM ops.cdc_offsets WHERE collection = ?";
    try (Connection c = DriverManager.getConnection(url, user, password);
        PreparedStatement ps = c.prepareStatement(sql)) {
      ps.setString(1, collection);
      try (ResultSet rs = ps.executeQuery()) {
        if (rs.next()) {
          return Optional.ofNullable(rs.getString(1));
        }
        return Optional.empty();
      }
    } catch (SQLException e) {
      throw new IllegalStateException("failed to load resume token for " + collection, e);
    }
  }

  public void save(String collection, String token) {
    String sql =
        "INSERT INTO ops.cdc_offsets(collection,resume_token,updated_at) VALUES (?,?,now()) "
            + "ON CONFLICT (collection) DO UPDATE SET resume_token=EXCLUDED.resume_token, updated_at=now()";
    try (Connection c = DriverManager.getConnection(url, user, password);
        PreparedStatement ps = c.prepareStatement(sql)) {
      ps.setString(1, collection);
      ps.setString(2, token);
      ps.executeUpdate();
    } catch (SQLException e) {
      throw new IllegalStateException("failed to save resume token for " + collection, e);
    }
  }
}
