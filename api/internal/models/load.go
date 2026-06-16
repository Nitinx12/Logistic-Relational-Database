package models

import "time"

type Load struct {
	LoadID             string     `json:"load_id"`
	CustomerID         string     `json:"customer_id"`
	RouteID            string     `json:"route_id"`
	LoadDate           *time.Time `json:"load_date"`
	LoadType           string     `json:"load_type"`
	WeightLbs          int64      `json:"weight_lbs"`
	Pieces             int64      `json:"pieces"`
	Revenue            float64    `json:"revenue"`
	FuelSurcharge      float64    `json:"fuel_surcharge"`
	AccessorialCharges int64      `json:"accessorial_charges"`
	LoadStatus         string     `json:"load_status"`
	BookingType        string     `json:"booking_type"`
	UpdatedAt          *time.Time `json:"updated_at"`
}
