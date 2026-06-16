package models

import "time"

type DriverMonthlyMetrics struct {
	DriverID           string     `json:"driver_id"`
	Month              *time.Time `json:"month"`
	TripsCompleted     int64      `json:"trips_completed"`
	TotalMiles         int64      `json:"total_miles"`
	TotalRevenue       float64    `json:"total_revenue"`
	AverageMPG         float64    `json:"average_mpg"`
	TotalFuelGallons   float64    `json:"total_fuel_gallons"`
	OnTimeDeliveryRate float64    `json:"on_time_delivery_rate"`
	AverageIdleHours   float64    `json:"average_idle_hours"`
	UpdatedAt          *time.Time `json:"updated_at"`
}
