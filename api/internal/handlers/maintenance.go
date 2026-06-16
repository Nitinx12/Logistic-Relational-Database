package handlers

import (
	"database/sql"
	"log"
	"net/http"

	"github.com/Nitinx12/lrdb/api/internal/models"
	"github.com/gin-gonic/gin"
)

func GetMaintenanceRecords(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		rows, err := db.Query(`
			SELECT
				maintenance_id,
				truck_id,
				maintenance_date,
				maintenance_type,
				odometer_reading,
				labor_hours,
				labor_cost,
				parts_cost,
				total_cost,
				facility_location,
				downtime_hours,
				service_description,
				updated_at
			FROM maintenance_records
			ORDER BY maintenance_date DESC
		`)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		records := make([]models.MaintenanceRecord, 0)
		for rows.Next() {
			var m models.MaintenanceRecord
			if err := rows.Scan(
				&m.MaintenanceID,
				&m.TruckID,
				&m.MaintenanceDate,
				&m.MaintenanceType,
				&m.OdometerReading,
				&m.LaborHours,
				&m.LaborCost,
				&m.PartsCost,
				&m.TotalCost,
				&m.FacilityLocation,
				&m.DowntimeHours,
				&m.ServiceDescription,
				&m.UpdatedAt,
			); err != nil {
				log.Printf("[maintenance_records] scan error: %v", err)
				continue
			}
			records = append(records, m)
		}
		if err := rows.Err(); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: records, Count: len(records)})
	}
}

func GetMaintenanceRecordByID(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")

		var m models.MaintenanceRecord
		err := db.QueryRow(`
			SELECT
				maintenance_id,
				truck_id,
				maintenance_date,
				maintenance_type,
				odometer_reading,
				labor_hours,
				labor_cost,
				parts_cost,
				total_cost,
				facility_location,
				downtime_hours,
				service_description,
				updated_at
			FROM maintenance_records
			WHERE maintenance_id = $1
		`, id).Scan(
			&m.MaintenanceID,
			&m.TruckID,
			&m.MaintenanceDate,
			&m.MaintenanceType,
			&m.OdometerReading,
			&m.LaborHours,
			&m.LaborCost,
			&m.PartsCost,
			&m.TotalCost,
			&m.FacilityLocation,
			&m.DowntimeHours,
			&m.ServiceDescription,
			&m.UpdatedAt,
		)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "maintenance record not found"})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: m, Count: 1})
	}
}

func GetMaintenanceRecordsByTruck(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		truckID := c.Param("truck_id")

		rows, err := db.Query(`
			SELECT
				maintenance_id, truck_id, maintenance_date, maintenance_type,
				odometer_reading, labor_hours, labor_cost, parts_cost, total_cost,
				facility_location, downtime_hours, service_description, updated_at
			FROM maintenance_records
			WHERE truck_id = $1
			ORDER BY maintenance_date DESC
		`, truckID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		records := make([]models.MaintenanceRecord, 0)
		for rows.Next() {
			var m models.MaintenanceRecord
			if err := rows.Scan(
				&m.MaintenanceID, &m.TruckID, &m.MaintenanceDate, &m.MaintenanceType,
				&m.OdometerReading, &m.LaborHours, &m.LaborCost, &m.PartsCost, &m.TotalCost,
				&m.FacilityLocation, &m.DowntimeHours, &m.ServiceDescription, &m.UpdatedAt,
			); err != nil {
				log.Printf("[maintenance_records] scan error: %v", err)
				continue
			}
			records = append(records, m)
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: records, Count: len(records)})
	}
}
