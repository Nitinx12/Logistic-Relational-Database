package models

import "time"

type Trip struct {
	TripID              string     `json:"trip_id"`
	LoadID              string     `json:"load_id"`
	DriverID            string     `json:"driver_id"`
	TruckID             string     `json:"truck_id"`
	TrailerID           string     `json:"trailer_id"`
	DispatchDate        *time.Time `json:"dispatch_date"`
	ActualDistanceMiles int64      `json:"actual_distance_miles"`
	ActualDurationHours float64    `json:"actual_duration_hours"`
	FuelGallonsUsed     float64    `json:"fuel_gallons_used"`
	AverageMPG          float64    `json:"average_mpg"`
	IdleTimeHours       float64    `json:"idle_time_hours"`
	TripStatus          string     `json:"trip_status"`
	UpdatedAt           *time.Time `json:"updated_at"`
}
