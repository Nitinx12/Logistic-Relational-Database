package handlers

import (
	"database/sql"
	"log"
	"net/http"

	"github.com/Nitinx12/lrdb/api/internal/models"
	"github.com/gin-gonic/gin"
)

func GetTrucks(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		rows, err := db.Query(`
			SELECT
				truck_id,
				unit_number,
				make,
				model_year,
				vin,
				acquisition_date,
				acquisition_mileage,
				fuel_type,
				tank_capacity_gallons,
				status,
				home_terminal,
				updated_at
			FROM trucks
			ORDER BY unit_number
		`)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": err.Error(),
			})
			return
		}
		defer rows.Close()

		trucks := make([]models.Truck, 0)

		for rows.Next() {
			var truck models.Truck

			err := rows.Scan(
				&truck.TruckID,
				&truck.UnitNumber,
				&truck.Make,
				&truck.ModelYear,
				&truck.VIN,
				&truck.AcquisitionDate,
				&truck.AcquisitionMileage,
				&truck.FuelType,
				&truck.TankCapacityGallons,
				&truck.Status,
				&truck.HomeTerminal,
				&truck.UpdatedAt,
			)
			if err != nil {
				log.Printf("[GetTrucks] scan error: %v", err)
				continue
			}

			trucks = append(trucks, truck)
		}

		if err := rows.Err(); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"error": err.Error(),
			})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{
			Data:  trucks,
			Count: len(trucks),
		})
	}
}

func GetTruckByID(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		truckID := c.Param("id")

		var truck models.Truck

		err := db.QueryRow(`
			SELECT
				truck_id,
				unit_number,
				make,
				model_year,
				vin,
				acquisition_date,
				acquisition_mileage,
				fuel_type,
				tank_capacity_gallons,
				status,
				home_terminal,
				updated_at
			FROM trucks
			WHERE truck_id = $1
		`, truckID).Scan(
			&truck.TruckID,
			&truck.UnitNumber,
			&truck.Make,
			&truck.ModelYear,
			&truck.VIN,
			&truck.AcquisitionDate,
			&truck.AcquisitionMileage,
			&truck.FuelType,
			&truck.TankCapacityGallons,
			&truck.Status,
			&truck.HomeTerminal,
			&truck.UpdatedAt,
		)

		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{
				"error": "truck not found",
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
			Data:  truck,
			Count: 1,
		})
	}
}
