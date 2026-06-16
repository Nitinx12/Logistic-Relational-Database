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
				dispatch_date,
				actual_distance_miles,
				actual_duration_hours,
				fuel_gallons_used,
				average_mpg,
				idle_time_hours,
				trip_status,
				updated_at
			FROM trips
			ORDER BY dispatch_date DESC
		`)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": err.Error(),
			})
			return
		}
		defer rows.Close()

		trips := make([]models.Trip, 0)

		for rows.Next() {
			var trip models.Trip

			err := rows.Scan(
				&trip.TripID,
				&trip.LoadID,
				&trip.DriverID,
				&trip.TruckID,
				&trip.TrailerID,
				&trip.DispatchDate,
				&trip.ActualDistanceMiles,
				&trip.ActualDurationHours,
				&trip.FuelGallonsUsed,
				&trip.AverageMPG,
				&trip.IdleTimeHours,
				&trip.TripStatus,
				&trip.UpdatedAt,
			)
			if err != nil {
				log.Printf("[GetTrips] scan error: %v", err)
				continue
			}

			trips = append(trips, trip)
		}

		if err := rows.Err(); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": err.Error(),
			})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{
			Data:  trips,
			Count: len(trips),
		})
	}
}

func GetTripByID(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		tripID := c.Param("id")

		var trip models.Trip

		err := db.QueryRow(`
			SELECT
				trip_id,
				load_id,
				driver_id,
				truck_id,
				trailer_id,
				dispatch_date,
				actual_distance_miles,
				actual_duration_hours,
				fuel_gallons_used,
				average_mpg,
				idle_time_hours,
				trip_status,
				updated_at
			FROM trips
			WHERE trip_id = $1
		`, tripID).Scan(
			&trip.TripID,
			&trip.LoadID,
			&trip.DriverID,
			&trip.TruckID,
			&trip.TrailerID,
			&trip.DispatchDate,
			&trip.ActualDistanceMiles,
			&trip.ActualDurationHours,
			&trip.FuelGallonsUsed,
			&trip.AverageMPG,
			&trip.IdleTimeHours,
			&trip.TripStatus,
			&trip.UpdatedAt,
		)

		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{
				"error": "trip not found",
			})
			return
		}

		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": err.Error(),
			})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{
			Data:  trip,
			Count: 1,
		})
	}
}
