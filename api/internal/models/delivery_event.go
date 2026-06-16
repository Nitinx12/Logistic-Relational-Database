package models

import "time"

type DeliveryEvent struct {
	EventID           string     `json:"event_id"`
	LoadID            string     `json:"load_id"`
	TripID            string     `json:"trip_id"`
	EventType         string     `json:"event_type"`
	FacilityID        string     `json:"facility_id"`
	ScheduledDatetime *time.Time `json:"scheduled_datetime"`
	ActualDatetime    *time.Time `json:"actual_datetime"`
	DetentionMinutes  int64      `json:"detention_minutes"`
	OnTimeFlag        string     `json:"on_time_flag"`
	LocationCity      string     `json:"location_city"`
	LocationState     string     `json:"location_state"`
	UpdatedAt         *time.Time `json:"updated_at"`
}
