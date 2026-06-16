package handlers

import (
	"database/sql"
	"log"
	"net/http"

	"github.com/Nitinx12/lrdb/api/internal/models"
	"github.com/gin-gonic/gin"
)

func GetTrips(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		rows, err := db.Query(`
			SELECT
				trip_id,
				load_id,
				driver_id,
				truck_id,
				trailer_id,
				route_id,
				start_time,
				end_time,
				start_mileage,
				end_mileage,
				fuel_used_gallons,
				status
			FROM trips
			ORDER BY start_time DESC
		`)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		trips := make([]models.Trip, 0)
		for rows.Next() {
			var t models.Trip
			err := rows.Scan(
				&t.TripID,
				&t.LoadID,
				&t.DriverID,
				&t.TruckID,
				&t.TrailerID,
				&t.RouteID,
				&t.StartTime,
				&t.EndTime,
				&t.StartMileage,
				&t.EndMileage,
				&t.FuelUsedGallons,
				&t.Status,
			)
			if err != nil {
				log.Printf("[trips] scan error: %v", err)
				continue
			}
			trips = append(trips, t)
		}
		if err := rows.Err(); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: trips, Count: len(trips)})
	}
}

func GetTripByID(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")

		var t models.Trip
		err := db.QueryRow(`
			SELECT
				trip_id,
				load_id,
				driver_id,
				truck_id,
				trailer_id,
				route_id,
				start_time,
				end_time,
				start_mileage,
				end_mileage,
				fuel_used_gallons,
				status
			FROM trips
			WHERE trip_id = $1
		`, id).Scan(
			&t.TripID,
			&t.LoadID,
			&t.DriverID,
			&t.TruckID,
			&t.TrailerID,
			&t.RouteID,
			&t.StartTime,
			&t.EndTime,
			&t.StartMileage,
			&t.EndMileage,
			&t.FuelUsedGallons,
			&t.Status,
		)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "trip not found"})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: t, Count: 1})
	}
}
