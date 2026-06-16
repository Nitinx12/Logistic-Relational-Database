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
				facility_id,
				scheduled_datetime,
				actual_datetime,
				detention_minutes,
				on_time_flag,
				location_city,
				location_state,
				updated_at
			FROM delivery_events
			ORDER BY scheduled_datetime DESC
		`)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		events := make([]models.DeliveryEvent, 0)
		for rows.Next() {
			var de models.DeliveryEvent
			if err := rows.Scan(
				&de.EventID,
				&de.LoadID,
				&de.TripID,
				&de.EventType,
				&de.FacilityID,
				&de.ScheduledDatetime,
				&de.ActualDatetime,
				&de.DetentionMinutes,
				&de.OnTimeFlag,
				&de.LocationCity,
				&de.LocationState,
				&de.UpdatedAt,
			); err != nil {
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
				facility_id,
				scheduled_datetime,
				actual_datetime,
				detention_minutes,
				on_time_flag,
				location_city,
				location_state,
				updated_at
			FROM delivery_events
			WHERE event_id = $1
		`, id).Scan(
			&de.EventID,
			&de.LoadID,
			&de.TripID,
			&de.EventType,
			&de.FacilityID,
			&de.ScheduledDatetime,
			&de.ActualDatetime,
			&de.DetentionMinutes,
			&de.OnTimeFlag,
			&de.LocationCity,
			&de.LocationState,
			&de.UpdatedAt,
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

func GetDeliveryEventsByLoad(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		loadID := c.Param("load_id")

		rows, err := db.Query(`
			SELECT
				event_id, load_id, trip_id, event_type, facility_id,
				scheduled_datetime, actual_datetime, detention_minutes,
				on_time_flag, location_city, location_state, updated_at
			FROM delivery_events
			WHERE load_id = $1
			ORDER BY scheduled_datetime ASC
		`, loadID)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		events := make([]models.DeliveryEvent, 0)
		for rows.Next() {
			var de models.DeliveryEvent
			if err := rows.Scan(
				&de.EventID, &de.LoadID, &de.TripID, &de.EventType, &de.FacilityID,
				&de.ScheduledDatetime, &de.ActualDatetime, &de.DetentionMinutes,
				&de.OnTimeFlag, &de.LocationCity, &de.LocationState, &de.UpdatedAt,
			); err != nil {
				log.Printf("[delivery_events] scan error: %v", err)
				continue
			}
			events = append(events, de)
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: events, Count: len(events)})
	}
}
