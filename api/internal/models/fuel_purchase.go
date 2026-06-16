package models

import "time"

type FuelPurchase struct {
	FuelPurchaseID string     `json:"fuel_purchase_id"`
	TripID         string     `json:"trip_id"`
	TruckID        string     `json:"truck_id"`
	DriverID       string     `json:"driver_id"`
	PurchaseDate   *time.Time `json:"purchase_date"`
	LocationCity   string     `json:"location_city"`
	LocationState  string     `json:"location_state"`
	Gallons        float64    `json:"gallons"`
	PricePerGallon float64    `json:"price_per_gallon"`
	TotalCost      float64    `json:"total_cost"`
	FuelCardNumber string     `json:"fuel_card_number"`
	UpdatedAt      *time.Time `json:"updated_at"`
}
