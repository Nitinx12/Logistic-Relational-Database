package handlers

import (
	"database/sql"
	"log"
	"net/http"

	"github.com/Nitinx12/lrdb/api/internal/models"
	"github.com/gin-gonic/gin"
)

func GetFacilities(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		rows, err := db.Query(`
			SELECT
				facility_id,
				facility_name,
				facility_type,
				city,
				state,
				latitude,
				longitude,
				dock_doors,
				operating_hours,
				updated_at
			FROM facilities
			ORDER BY facility_name
		`)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		facilities := make([]models.Facility, 0)
		for rows.Next() {
			var f models.Facility
			if err := rows.Scan(
				&f.FacilityID,
				&f.FacilityName,
				&f.FacilityType,
				&f.City,
				&f.State,
				&f.Latitude,
				&f.Longitude,
				&f.DockDoors,
				&f.OperatingHours,
				&f.UpdatedAt,
			); err != nil {
				log.Printf("[facilities] scan error: %v", err)
				continue
			}
			facilities = append(facilities, f)
		}
		if err := rows.Err(); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: facilities, Count: len(facilities)})
	}
}

func GetFacilityByID(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")

		var f models.Facility
		err := db.QueryRow(`
			SELECT
				facility_id,
				facility_name,
				facility_type,
				city,
				state,
				latitude,
				longitude,
				dock_doors,
				operating_hours,
				updated_at
			FROM facilities
			WHERE facility_id = $1
		`, id).Scan(
			&f.FacilityID,
			&f.FacilityName,
			&f.FacilityType,
			&f.City,
			&f.State,
			&f.Latitude,
			&f.Longitude,
			&f.DockDoors,
			&f.OperatingHours,
			&f.UpdatedAt,
		)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "facility not found"})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: f, Count: 1})
	}
}
