package models

import "time"

type SafetyIncident struct {
	IncidentID        string     `json:"incident_id"`
	TripID            string     `json:"trip_id"`
	TruckID           string     `json:"truck_id"`
	DriverID          string     `json:"driver_id"`
	IncidentDate      *time.Time `json:"incident_date"`
	IncidentType      string     `json:"incident_type"`
	LocationCity      string     `json:"location_city"`
	LocationState     string     `json:"location_state"`
	AtFaultFlag       string     `json:"at_fault_flag"`
	InjuryFlag        string     `json:"injury_flag"`
	VehicleDamageCost float64    `json:"vehicle_damage_cost"`
	CargoDamageCost   float64    `json:"cargo_damage_cost"`
	ClaimAmount       float64    `json:"claim_amount"`
	PreventableFlag   string     `json:"preventable_flag"`
	Description       string     `json:"description"`
	UpdatedAt         *time.Time `json:"updated_at"`
}
