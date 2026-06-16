package models

import "time"

type FuelPurchase struct {
	FuelPurchaseID string    `json:"fuel_purchase_id"`
	TruckID        string    `json:"truck_id"`
	DriverID       string    `json:"driver_id"`
	PurchaseDate   time.Time `json:"purchase_date"`
	Location       string    `json:"location"`
	State          string    `json:"state"`
	Gallons        float64   `json:"gallons"`
	PricePerGallon float64   `json:"price_per_gallon"`
	TotalCost      float64   `json:"total_cost"`
	FuelType       string    `json:"fuel_type"`
	Odometer       float64   `json:"odometer"`
}
