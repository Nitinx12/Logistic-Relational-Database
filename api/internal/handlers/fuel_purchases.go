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
				truck_id,
				driver_id,
				purchase_date,
				location,
				state,
				gallons,
				price_per_gallon,
				total_cost,
				fuel_type,
				odometer
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
			err := rows.Scan(
				&fp.FuelPurchaseID,
				&fp.TruckID,
				&fp.DriverID,
				&fp.PurchaseDate,
				&fp.Location,
				&fp.State,
				&fp.Gallons,
				&fp.PricePerGallon,
				&fp.TotalCost,
				&fp.FuelType,
				&fp.Odometer,
			)
			if err != nil {
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
				truck_id,
				driver_id,
				purchase_date,
				location,
				state,
				gallons,
				price_per_gallon,
				total_cost,
				fuel_type,
				odometer
			FROM fuel_purchases
			WHERE fuel_purchase_id = $1
		`, id).Scan(
			&fp.FuelPurchaseID,
			&fp.TruckID,
			&fp.DriverID,
			&fp.PurchaseDate,
			&fp.Location,
			&fp.State,
			&fp.Gallons,
			&fp.PricePerGallon,
			&fp.TotalCost,
			&fp.FuelType,
			&fp.Odometer,
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
