package models

type Customer struct {
	CustomerID      string  `json:"customer_id"`
	CompanyName     string  `json:"company_name"`
	ContactName     string  `json:"contact_name"`
	PhoneNumber     string  `json:"phone_number"`
	Email           string  `json:"email"`
	Address         string  `json:"address"`
	City            string  `json:"city"`
	State           string  `json:"state"`
	ZipCode         string  `json:"zip_code"`
	CreditLimit     float64 `json:"credit_limit"`
	PaymentTermDays int     `json:"payment_term_days"`
}
