package models

import "time"

type Driver struct {
	DriverID        string    `json:"driver_id"`
	FirstName       string    `json:"first_name"`
	LastName        string    `json:"last_name"`
	LicenseNumber   string    `json:"license_number"`
	LicenseClass    string    `json:"license_class"`
	LicenseExpiry   time.Time `json:"license_expiry"`
	HireDate        time.Time `json:"hire_date"`
	HomeTerminal    string    `json:"home_terminal"`
	Status          string    `json:"status"`
	PhoneNumber     string    `json:"phone_number"`
	Email           string    `json:"email"`
}
