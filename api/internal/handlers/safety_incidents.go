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
				trip_id,
				truck_id,
				driver_id,
				incident_date,
				incident_type,
				location_city,
				location_state,
				at_fault_flag,
				injury_flag,
				vehicle_damage_cost,
				cargo_damage_cost,
				claim_amount,
				preventable_flag,
				description,
				updated_at
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
			if err := rows.Scan(
				&si.IncidentID,
				&si.TripID,
				&si.TruckID,
				&si.DriverID,
				&si.IncidentDate,
				&si.IncidentType,
				&si.LocationCity,
				&si.LocationState,
				&si.AtFaultFlag,
				&si.InjuryFlag,
				&si.VehicleDamageCost,
				&si.CargoDamageCost,
				&si.ClaimAmount,
				&si.PreventableFlag,
				&si.Description,
				&si.UpdatedAt,
			); err != nil {
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
				trip_id,
				truck_id,
				driver_id,
				incident_date,
				incident_type,
				location_city,
				location_state,
				at_fault_flag,
				injury_flag,
				vehicle_damage_cost,
				cargo_damage_cost,
				claim_amount,
				preventable_flag,
				description,
				updated_at
			FROM safety_incidents
			WHERE incident_id = $1
		`, id).Scan(
			&si.IncidentID,
			&si.TripID,
			&si.TruckID,
			&si.DriverID,
			&si.IncidentDate,
			&si.IncidentType,
			&si.LocationCity,
			&si.LocationState,
			&si.AtFaultFlag,
			&si.InjuryFlag,
			&si.VehicleDamageCost,
			&si.CargoDamageCost,
			&si.ClaimAmount,
			&si.PreventableFlag,
			&si.Description,
			&si.UpdatedAt,
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

func GetSafetyIncidentsByDriver(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		driverID := c.Param("driver_id")

		rows, err := db.Query(`
			SELECT
				incident_id, trip_id, truck_id, driver_id, incident_date,
				incident_type, location_city, location_state, at_fault_flag,
				injury_flag, vehicle_damage_cost, cargo_damage_cost,
				claim_amount, preventable_flag, description, updated_at
			FROM safety_incidents
			WHERE driver_id = $1
			ORDER BY incident_date DESC
		`, driverID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		incidents := make([]models.SafetyIncident, 0)
		for rows.Next() {
			var si models.SafetyIncident
			if err := rows.Scan(
				&si.IncidentID, &si.TripID, &si.TruckID, &si.DriverID, &si.IncidentDate,
				&si.IncidentType, &si.LocationCity, &si.LocationState, &si.AtFaultFlag,
				&si.InjuryFlag, &si.VehicleDamageCost, &si.CargoDamageCost,
				&si.ClaimAmount, &si.PreventableFlag, &si.Description, &si.UpdatedAt,
			); err != nil {
				log.Printf("[safety_incidents] scan error: %v", err)
				continue
			}
			incidents = append(incidents, si)
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: incidents, Count: len(incidents)})
	}
}
