package handlers

import (
	"database/sql"
	"log"
	"net/http"

	"github.com/Nitinx12/lrdb/api/internal/models"
	"github.com/gin-gonic/gin"
)

func GetLoads(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		rows, err := db.Query(`
			SELECT
				load_id,
				customer_id,
				route_id,
				load_date,
				load_type,
				weight_lbs,
				pieces,
				revenue,
				fuel_surcharge,
				accessorial_charges,
				load_status,
				booking_type,
				updated_at
			FROM loads
			ORDER BY load_date DESC
		`)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		loads := make([]models.Load, 0)
		for rows.Next() {
			var l models.Load
			if err := rows.Scan(
				&l.LoadID,
				&l.CustomerID,
				&l.RouteID,
				&l.LoadDate,
				&l.LoadType,
				&l.WeightLbs,
				&l.Pieces,
				&l.Revenue,
				&l.FuelSurcharge,
				&l.AccessorialCharges,
				&l.LoadStatus,
				&l.BookingType,
				&l.UpdatedAt,
			); err != nil {
				log.Printf("[loads] scan error: %v", err)
				continue
			}
			loads = append(loads, l)
		}
		if err := rows.Err(); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: loads, Count: len(loads)})
	}
}

func GetLoadByID(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")

		var l models.Load
		err := db.QueryRow(`
			SELECT
				load_id,
				customer_id,
				route_id,
				load_date,
				load_type,
				weight_lbs,
				pieces,
				revenue,
				fuel_surcharge,
				accessorial_charges,
				load_status,
				booking_type,
				updated_at
			FROM loads
			WHERE load_id = $1
		`, id).Scan(
			&l.LoadID,
			&l.CustomerID,
			&l.RouteID,
			&l.LoadDate,
			&l.LoadType,
			&l.WeightLbs,
			&l.Pieces,
			&l.Revenue,
			&l.FuelSurcharge,
			&l.AccessorialCharges,
			&l.LoadStatus,
			&l.BookingType,
			&l.UpdatedAt,
		)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "load not found"})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: l, Count: 1})
	}
}

func GetLoadsByCustomer(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		customerID := c.Param("customer_id")

		rows, err := db.Query(`
			SELECT
				load_id, customer_id, route_id, load_date, load_type,
				weight_lbs, pieces, revenue, fuel_surcharge,
				accessorial_charges, load_status, booking_type, updated_at
			FROM loads
			WHERE customer_id = $1
			ORDER BY load_date DESC
		`, customerID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		loads := make([]models.Load, 0)
		for rows.Next() {
			var l models.Load
			if err := rows.Scan(
				&l.LoadID, &l.CustomerID, &l.RouteID, &l.LoadDate, &l.LoadType,
				&l.WeightLbs, &l.Pieces, &l.Revenue, &l.FuelSurcharge,
				&l.AccessorialCharges, &l.LoadStatus, &l.BookingType, &l.UpdatedAt,
			); err != nil {
				log.Printf("[loads] scan error: %v", err)
				continue
			}
			loads = append(loads, l)
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: loads, Count: len(loads)})
	}
}
