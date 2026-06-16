package handlers

import (
	"database/sql"
	"log"
	"net/http"

	"github.com/Nitinx12/lrdb/api/internal/models"
	"github.com/gin-gonic/gin"
)

func GetDeliveryEvents(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		rows, err := db.Query(`
			SELECT
				event_id,
				load_id,
				trip_id,
				event_type,
				event_time,
				location,
				state,
				notes,
				recorded_by
			FROM delivery_events
			ORDER BY event_time DESC
		`)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		events := make([]models.DeliveryEvent, 0)
		for rows.Next() {
			var de models.DeliveryEvent
			err := rows.Scan(
				&de.EventID,
				&de.LoadID,
				&de.TripID,
				&de.EventType,
				&de.EventTime,
				&de.Location,
				&de.State,
				&de.Notes,
				&de.RecordedBy,
			)
			if err != nil {
				log.Printf("[delivery_events] scan error: %v", err)
				continue
			}
			events = append(events, de)
		}
		if err := rows.Err(); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: events, Count: len(events)})
	}
}

func GetDeliveryEventByID(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")

		var de models.DeliveryEvent
		err := db.QueryRow(`
			SELECT
				event_id,
				load_id,
				trip_id,
				event_type,
				event_time,
				location,
				state,
				notes,
				recorded_by
			FROM delivery_events
			WHERE event_id = $1
		`, id).Scan(
			&de.EventID,
			&de.LoadID,
			&de.TripID,
			&de.EventType,
			&de.EventTime,
			&de.Location,
			&de.State,
			&de.Notes,
			&de.RecordedBy,
		)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "delivery event not found"})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: de, Count: 1})
	}
}
