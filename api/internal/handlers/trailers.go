package handlers

import (
	"database/sql"
	"log"
	"net/http"

	"github.com/Nitinx12/lrdb/api/internal/models"
	"github.com/gin-gonic/gin"
)

func GetTrailers(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		rows, err := db.Query(`
			SELECT
				trailer_id,
				trailer_number,
				trailer_type,
				length_feet,
				model_year,
				vin,
				acquisition_date,
				status,
				current_location,
				updated_at
			FROM trailers
			ORDER BY trailer_number
		`)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		trailers := make([]models.Trailer, 0)
		for rows.Next() {
			var t models.Trailer
			if err := rows.Scan(
				&t.TrailerID,
				&t.TrailerNumber,
				&t.TrailerType,
				&t.LengthFeet,
				&t.ModelYear,
				&t.VIN,
				&t.AcquisitionDate,
				&t.Status,
				&t.CurrentLocation,
				&t.UpdatedAt,
			); err != nil {
				log.Printf("[trailers] scan error: %v", err)
				continue
			}
			trailers = append(trailers, t)
		}
		if err := rows.Err(); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: trailers, Count: len(trailers)})
	}
}

func GetTrailerByID(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")

		var t models.Trailer
		err := db.QueryRow(`
			SELECT
				trailer_id,
				trailer_number,
				trailer_type,
				length_feet,
				model_year,
				vin,
				acquisition_date,
				status,
				current_location,
				updated_at
			FROM trailers
			WHERE trailer_id = $1
		`, id).Scan(
			&t.TrailerID,
			&t.TrailerNumber,
			&t.TrailerType,
			&t.LengthFeet,
			&t.ModelYear,
			&t.VIN,
			&t.AcquisitionDate,
			&t.Status,
			&t.CurrentLocation,
			&t.UpdatedAt,
		)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "trailer not found"})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: t, Count: 1})
	}
}
