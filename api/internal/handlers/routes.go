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
				route_name,
				origin_facility,
				dest_facility,
				distance_miles,
				estimated_hours,
				route_type
			FROM routes
			ORDER BY route_name
		`)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		routes := make([]models.Route, 0)
		for rows.Next() {
			var r models.Route
			err := rows.Scan(
				&r.RouteID,
				&r.RouteName,
				&r.OriginFacility,
				&r.DestFacility,
				&r.DistanceMiles,
				&r.EstimatedHours,
				&r.RouteType,
			)
			if err != nil {
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
				route_name,
				origin_facility,
				dest_facility,
				distance_miles,
				estimated_hours,
				route_type
			FROM routes
			WHERE route_id = $1
		`, id).Scan(
			&r.RouteID,
			&r.RouteName,
			&r.OriginFacility,
			&r.DestFacility,
			&r.DistanceMiles,
			&r.EstimatedHours,
			&r.RouteType,
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
