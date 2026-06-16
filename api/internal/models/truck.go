package models

import "time"

type Truck struct {
	TruckID             string    `json:"truck_id"`
	UnitNumber          string    `json:"unit_number"`
	Make                string    `json:"make"`
	ModelYear           int       `json:"model_year"`
	VIN                 string    `json:"vin"`
	AcquisitionDate     time.Time `json:"acquisition_date"`
	AcquisitionMileage  int       `json:"acquisition_mileage"`
	FuelType            string    `json:"fuel_type"`
	TankCapacityGallons float64   `json:"tank_capacity_gallons"`
	Status              string    `json:"status"`
	HomeTerminal        string    `json:"home_terminal"`
}
