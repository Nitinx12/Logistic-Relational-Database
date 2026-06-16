package models

import "time"

type Trip struct {
	TripID          string    `json:"trip_id"`
	LoadID          string    `json:"load_id"`
	DriverID        string    `json:"driver_id"`
	TruckID         string    `json:"truck_id"`
	TrailerID       string    `json:"trailer_id"`
	RouteID         string    `json:"route_id"`
	StartTime       time.Time `json:"start_time"`
	EndTime         time.Time `json:"end_time"`
	StartMileage    float64   `json:"start_mileage"`
	EndMileage      float64   `json:"end_mileage"`
	FuelUsedGallons float64   `json:"fuel_used_gallons"`
	Status          string    `json:"status"`
}
