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
				service_date,
				service_type,
				description,
				vendor_name,
				labor_cost,
				parts_cost,
				total_cost,
				odometer,
				next_service_due
			FROM maintenance_records
			ORDER BY service_date DESC
		`)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		records := make([]models.MaintenanceRecord, 0)
		for rows.Next() {
			var m models.MaintenanceRecord
			err := rows.Scan(
				&m.MaintenanceID,
				&m.TruckID,
				&m.ServiceDate,
				&m.ServiceType,
				&m.Description,
				&m.VendorName,
				&m.LaborCost,
				&m.PartsCost,
				&m.TotalCost,
				&m.Odometer,
				&m.NextServiceDue,
			)
			if err != nil {
				log.Printf("[maintenance] scan error: %v", err)
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
				service_date,
				service_type,
				description,
				vendor_name,
				labor_cost,
				parts_cost,
				total_cost,
				odometer,
				next_service_due
			FROM maintenance_records
			WHERE maintenance_id = $1
		`, id).Scan(
			&m.MaintenanceID,
			&m.TruckID,
			&m.ServiceDate,
			&m.ServiceType,
			&m.Description,
			&m.VendorName,
			&m.LaborCost,
			&m.PartsCost,
			&m.TotalCost,
			&m.Odometer,
			&m.NextServiceDue,
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
