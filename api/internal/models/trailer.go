package models

import "time"

type Trailer struct {
	TrailerID          string    `json:"trailer_id"`
	UnitNumber         string    `json:"unit_number"`
	TrailerType        string    `json:"trailer_type"`
	LengthFeet         float64   `json:"length_feet"`
	CapacityLbs        float64   `json:"capacity_lbs"`
	AcquisitionDate    time.Time `json:"acquisition_date"`
	Status             string    `json:"status"`
	HomeTerminal       string    `json:"home_terminal"`
}
