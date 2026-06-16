package models

import "time"

type Customer struct {
	CustomerID             string     `json:"customer_id"`
	CustomerName           string     `json:"customer_name"`
	CustomerType           string     `json:"customer_type"`
	CreditTermsDays        int64      `json:"credit_terms_days"`
	PrimaryFreightType     string     `json:"primary_freight_type"`
	AccountStatus          string     `json:"account_status"`
	ContractStartDate      *time.Time `json:"contract_start_date"`
	AnnualRevenuePotential int64      `json:"annual_revenue_potential"`
	UpdatedAt              *time.Time `json:"updated_at"`
}
