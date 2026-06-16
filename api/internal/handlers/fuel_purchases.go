package handlers

import (
	"database/sql"
	"log"
	"net/http"

	"github.com/Nitinx12/lrdb/api/internal/models"
	"github.com/gin-gonic/gin"
)

func GetFuelPurchases(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		rows, err := db.Query(`
			SELECT
				fuel_purchase_id,
				trip_id,
				truck_id,
				driver_id,
				purchase_date,
				location_city,
				location_state,
				gallons,
				price_per_gallon,
				total_cost,
				fuel_card_number,
				updated_at
			FROM fuel_purchases
			ORDER BY purchase_date DESC
		`)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		purchases := make([]models.FuelPurchase, 0)
		for rows.Next() {
			var fp models.FuelPurchase
			if err := rows.Scan(
				&fp.FuelPurchaseID,
				&fp.TripID,
				&fp.TruckID,
				&fp.DriverID,
				&fp.PurchaseDate,
				&fp.LocationCity,
				&fp.LocationState,
				&fp.Gallons,
				&fp.PricePerGallon,
				&fp.TotalCost,
				&fp.FuelCardNumber,
				&fp.UpdatedAt,
			); err != nil {
				log.Printf("[fuel_purchases] scan error: %v", err)
				continue
			}
			purchases = append(purchases, fp)
		}
		if err := rows.Err(); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: purchases, Count: len(purchases)})
	}
}

func GetFuelPurchaseByID(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")

		var fp models.FuelPurchase
		err := db.QueryRow(`
			SELECT
				fuel_purchase_id,
				trip_id,
				truck_id,
				driver_id,
				purchase_date,
				location_city,
				location_state,
				gallons,
				price_per_gallon,
				total_cost,
				fuel_card_number,
				updated_at
			FROM fuel_purchases
			WHERE fuel_purchase_id = $1
		`, id).Scan(
			&fp.FuelPurchaseID,
			&fp.TripID,
			&fp.TruckID,
			&fp.DriverID,
			&fp.PurchaseDate,
			&fp.LocationCity,
			&fp.LocationState,
			&fp.Gallons,
			&fp.PricePerGallon,
			&fp.TotalCost,
			&fp.FuelCardNumber,
			&fp.UpdatedAt,
		)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "fuel purchase not found"})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: fp, Count: 1})
	}
}

func GetFuelPurchasesByTrip(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		tripID := c.Param("trip_id")

		rows, err := db.Query(`
			SELECT
				fuel_purchase_id, 
				trip_id, 
				truck_id, 
				driver_id,
				purchase_date, 
				location_city, 
				location_state,
				gallons, 
				price_per_gallon, 
				total_cost, 
				fuel_card_number, 
				updated_at
			FROM fuel_purchases
			WHERE trip_id = $1
			ORDER BY purchase_date ASC
		`, tripID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		purchases := make([]models.FuelPurchase, 0)
		for rows.Next() {
			var fp models.FuelPurchase
			if err := rows.Scan(
				&fp.FuelPurchaseID, &fp.TripID, &fp.TruckID, &fp.DriverID,
				&fp.PurchaseDate, &fp.LocationCity, &fp.LocationState,
				&fp.Gallons, &fp.PricePerGallon, &fp.TotalCost, &fp.FuelCardNumber, &fp.UpdatedAt,
			); err != nil {
				log.Printf("[fuel_purchases] scan error: %v", err)
				continue
			}
			purchases = append(purchases, fp)
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: purchases, Count: len(purchases)})
	}
}
