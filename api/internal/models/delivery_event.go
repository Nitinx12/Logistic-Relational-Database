package models

import "time"

type DeliveryEvent struct {
	EventID      string    `json:"event_id"`
	LoadID       string    `json:"load_id"`
	TripID       string    `json:"trip_id"`
	EventType    string    `json:"event_type"`
	EventTime    time.Time `json:"event_time"`
	Location     string    `json:"location"`
	State        string    `json:"state"`
	Notes        string    `json:"notes"`
	RecordedBy   string    `json:"recorded_by"`
}
