package handlers

import (
	"database/sql"
	"log"
	"net/http"

	"github.com/Nitinx12/lrdb/api/internal/models"
	"github.com/gin-gonic/gin"
)

func GetSafetyIncidents(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		rows, err := db.Query(`
			SELECT
				incident_id,
				driver_id,
				truck_id,
				incident_date,
				incident_type,
				severity,
				location,
				state,
				description,
				reported_to_fmcsa,
				recordable_dot,
				estimated_cost
			FROM safety_incidents
			ORDER BY incident_date DESC
		`)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		incidents := make([]models.SafetyIncident, 0)
		for rows.Next() {
			var si models.SafetyIncident
			err := rows.Scan(
				&si.IncidentID,
				&si.DriverID,
				&si.TruckID,
				&si.IncidentDate,
				&si.IncidentType,
				&si.Severity,
				&si.Location,
				&si.State,
				&si.Description,
				&si.ReportedToFMCSA,
				&si.RecordableDOT,
				&si.EstimatedCost,
			)
			if err != nil {
				log.Printf("[safety_incidents] scan error: %v", err)
				continue
			}
			incidents = append(incidents, si)
		}
		if err := rows.Err(); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: incidents, Count: len(incidents)})
	}
}

func GetSafetyIncidentByID(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")

		var si models.SafetyIncident
		err := db.QueryRow(`
			SELECT
				incident_id,
				driver_id,
				truck_id,
				incident_date,
				incident_type,
				severity,
				location,
				state,
				description,
				reported_to_fmcsa,
				recordable_dot,
				estimated_cost
			FROM safety_incidents
			WHERE incident_id = $1
		`, id).Scan(
			&si.IncidentID,
			&si.DriverID,
			&si.TruckID,
			&si.IncidentDate,
			&si.IncidentType,
			&si.Severity,
			&si.Location,
			&si.State,
			&si.Description,
			&si.ReportedToFMCSA,
			&si.RecordableDOT,
			&si.EstimatedCost,
		)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "safety incident not found"})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: si, Count: 1})
	}
}
