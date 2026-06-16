package models

import "time"

type Driver struct {
	DriverID         string     `json:"driver_id"`
	FirstName        string     `json:"first_name"`
	LastName         string     `json:"last_name"`
	HireDate         *time.Time `json:"hire_date"`
	TerminationDate  *time.Time `json:"termination_date"`
	LicenseNumber    string     `json:"license_number"`
	LicenseState     string     `json:"license_state"`
	DateOfBirth      *time.Time `json:"date_of_birth"`
	HomeTerminal     string     `json:"home_terminal"`
	EmploymentStatus string     `json:"employment_status"`
	CDLClass         string     `json:"cdl_class"`
	YearsExperience  int64      `json:"years_experience"`
	UpdatedAt        *time.Time `json:"updated_at"`
}
