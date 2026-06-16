package models

import "time"

type Truck struct {
	TruckID             string     `json:"truck_id"`
	UnitNumber          int64      `json:"unit_number"`
	Make                string     `json:"make"`
	ModelYear           int64      `json:"model_year"`
	VIN                 string     `json:"vin"`
	AcquisitionDate     *time.Time `json:"acquisition_date"`
	AcquisitionMileage  int64      `json:"acquisition_mileage"`
	FuelType            string     `json:"fuel_type"`
	TankCapacityGallons int64      `json:"tank_capacity_gallons"`
	Status              string     `json:"status"`
	HomeTerminal        string     `json:"home_terminal"`
	UpdatedAt           *time.Time `json:"updated_at"`
}

type TruckUtilizationMetrics struct {
	TruckID           string     `json:"truck_id"`
	Month             *time.Time `json:"month"`
	TripsCompleted    int64      `json:"trips_completed"`
	TotalMiles        int64      `json:"total_miles"`
	TotalRevenue      float64    `json:"total_revenue"`
	AverageMPG        float64    `json:"average_mpg"`
	MaintenanceEvents int64      `json:"maintenance_events"`
	MaintenanceCost   float64    `json:"maintenance_cost"`
	DowntimeHours     float64    `json:"downtime_hours"`
	UtilizationRate   float64    `json:"utilization_rate"`
	UpdatedAt         *time.Time `json:"updated_at"`
}
