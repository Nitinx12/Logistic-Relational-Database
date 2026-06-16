package models

import "time"

type Trailer struct {
	TrailerID       string     `json:"trailer_id"`
	TrailerNumber   int64      `json:"trailer_number"`
	TrailerType     string     `json:"trailer_type"`
	LengthFeet      int64      `json:"length_feet"`
	ModelYear       int64      `json:"model_year"`
	VIN             string     `json:"vin"`
	AcquisitionDate *time.Time `json:"acquisition_date"`
	Status          string     `json:"status"`
	CurrentLocation string     `json:"current_location"`
	UpdatedAt       *time.Time `json:"updated_at"`
}
