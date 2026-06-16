package models

import "time"

type Facility struct {
	FacilityID     string     `json:"facility_id"`
	FacilityName   string     `json:"facility_name"`
	FacilityType   string     `json:"facility_type"`
	City           string     `json:"city"`
	State          string     `json:"state"`
	Latitude       float64    `json:"latitude"`
	Longitude      float64    `json:"longitude"`
	DockDoors      int64      `json:"dock_doors"`
	OperatingHours string     `json:"operating_hours"`
	UpdatedAt      *time.Time `json:"updated_at"`
}
