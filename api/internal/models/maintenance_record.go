package models

import "time"

type MaintenanceRecord struct {
	MaintenanceID   string    `json:"maintenance_id"`
	TruckID         string    `json:"truck_id"`
	ServiceDate     time.Time `json:"service_date"`
	ServiceType     string    `json:"service_type"`
	Description     string    `json:"description"`
	VendorName      string    `json:"vendor_name"`
	LaborCost       float64   `json:"labor_cost"`
	PartsCost       float64   `json:"parts_cost"`
	TotalCost       float64   `json:"total_cost"`
	Odometer        float64   `json:"odometer"`
	NextServiceDue  time.Time `json:"next_service_due"`
}
