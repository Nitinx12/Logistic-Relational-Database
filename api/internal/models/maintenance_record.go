package models

import "time"

type MaintenanceRecord struct {
	MaintenanceID      string     `json:"maintenance_id"`
	TruckID            string     `json:"truck_id"`
	MaintenanceDate    *time.Time `json:"maintenance_date"`
	MaintenanceType    string     `json:"maintenance_type"`
	OdometerReading    int64      `json:"odometer_reading"`
	LaborHours         float64    `json:"labor_hours"`
	LaborCost          float64    `json:"labor_cost"`
	PartsCost          float64    `json:"parts_cost"`
	TotalCost          float64    `json:"total_cost"`
	FacilityLocation   string     `json:"facility_location"`
	DowntimeHours      float64    `json:"downtime_hours"`
	ServiceDescription string     `json:"service_description"`
	UpdatedAt          *time.Time `json:"updated_at"`
}
