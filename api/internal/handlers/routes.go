package handlers

import (
	"database/sql"
	"log"
	"net/http"

	"github.com/Nitinx12/lrdb/api/internal/models"
	"github.com/gin-gonic/gin"
)

func GetRoutes(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		rows, err := db.Query(`
			SELECT
				route_id,
				origin_city,
				origin_state,
				destination_city,
				destination_state,
				typical_distance_miles,
				base_rate_per_mile,
				fuel_surcharge_rate,
				typical_transit_days,
				updated_at
			FROM routes
			ORDER BY origin_state, origin_city
		`)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		routes := make([]models.Route, 0)
		for rows.Next() {
			var r models.Route
			if err := rows.Scan(
				&r.RouteID,
				&r.OriginCity,
				&r.OriginState,
				&r.DestinationCity,
				&r.DestinationState,
				&r.TypicalDistanceMiles,
				&r.BaseRatePerMile,
				&r.FuelSurchargeRate,
				&r.TypicalTransitDays,
				&r.UpdatedAt,
			); err != nil {
				log.Printf("[routes] scan error: %v", err)
				continue
			}
			routes = append(routes, r)
		}
		if err := rows.Err(); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: routes, Count: len(routes)})
	}
}

func GetRouteByID(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")

		var r models.Route
		err := db.QueryRow(`
			SELECT
				route_id,
				origin_city,
				origin_state,
				destination_city,
				destination_state,
				typical_distance_miles,
				base_rate_per_mile,
				fuel_surcharge_rate,
				typical_transit_days,
				updated_at
			FROM routes
			WHERE route_id = $1
		`, id).Scan(
			&r.RouteID,
			&r.OriginCity,
			&r.OriginState,
			&r.DestinationCity,
			&r.DestinationState,
			&r.TypicalDistanceMiles,
			&r.BaseRatePerMile,
			&r.FuelSurchargeRate,
			&r.TypicalTransitDays,
			&r.UpdatedAt,
		)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "route not found"})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: r, Count: 1})
	}
}
