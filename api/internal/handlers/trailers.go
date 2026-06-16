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
				unit_number,
				trailer_type,
				length_feet,
				capacity_lbs,
				acquisition_date,
				status,
				home_terminal
			FROM trailers
			ORDER BY unit_number
		`)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		trailers := make([]models.Trailer, 0)
		for rows.Next() {
			var t models.Trailer
			err := rows.Scan(
				&t.TrailerID,
				&t.UnitNumber,
				&t.TrailerType,
				&t.LengthFeet,
				&t.CapacityLbs,
				&t.AcquisitionDate,
				&t.Status,
				&t.HomeTerminal,
			)
			if err != nil {
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
				unit_number,
				trailer_type,
				length_feet,
				capacity_lbs,
				acquisition_date,
				status,
				home_terminal
			FROM trailers
			WHERE trailer_id = $1
		`, id).Scan(
			&t.TrailerID,
			&t.UnitNumber,
			&t.TrailerType,
			&t.LengthFeet,
			&t.CapacityLbs,
			&t.AcquisitionDate,
			&t.Status,
			&t.HomeTerminal,
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
