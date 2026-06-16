package models

import "time"

type SafetyIncident struct {
	IncidentID      string    `json:"incident_id"`
	DriverID        string    `json:"driver_id"`
	TruckID         string    `json:"truck_id"`
	IncidentDate    time.Time `json:"incident_date"`
	IncidentType    string    `json:"incident_type"`
	Severity        string    `json:"severity"`
	Location        string    `json:"location"`
	State           string    `json:"state"`
	Description     string    `json:"description"`
	ReportedToFMCSA bool      `json:"reported_to_fmcsa"`
	RecordableDOT   bool      `json:"recordable_dot"`
	EstimatedCost   float64   `json:"estimated_cost"`
}
