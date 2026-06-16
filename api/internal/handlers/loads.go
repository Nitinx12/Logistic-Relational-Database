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
				origin_facility,
				dest_facility,
				pickup_date,
				delivery_date,
				weight_lbs,
				rate_per_mile,
				total_miles,
				total_revenue,
				status,
				commodity_type
			FROM loads
			ORDER BY pickup_date DESC
		`)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		loads := make([]models.Load, 0)
		for rows.Next() {
			var l models.Load
			err := rows.Scan(
				&l.LoadID,
				&l.CustomerID,
				&l.OriginFacility,
				&l.DestFacility,
				&l.PickupDate,
				&l.DeliveryDate,
				&l.WeightLbs,
				&l.RatePerMile,
				&l.TotalMiles,
				&l.TotalRevenue,
				&l.Status,
				&l.CommodityType,
			)
			if err != nil {
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
				origin_facility,
				dest_facility,
				pickup_date,
				delivery_date,
				weight_lbs,
				rate_per_mile,
				total_miles,
				total_revenue,
				status,
				commodity_type
			FROM loads
			WHERE load_id = $1
		`, id).Scan(
			&l.LoadID,
			&l.CustomerID,
			&l.OriginFacility,
			&l.DestFacility,
			&l.PickupDate,
			&l.DeliveryDate,
			&l.WeightLbs,
			&l.RatePerMile,
			&l.TotalMiles,
			&l.TotalRevenue,
			&l.Status,
			&l.CommodityType,
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
