package models

import "time"

type Load struct {
	LoadID          string    `json:"load_id"`
	CustomerID      string    `json:"customer_id"`
	OriginFacility  string    `json:"origin_facility"`
	DestFacility    string    `json:"dest_facility"`
	PickupDate      time.Time `json:"pickup_date"`
	DeliveryDate    time.Time `json:"delivery_date"`
	WeightLbs       float64   `json:"weight_lbs"`
	RatePerMile     float64   `json:"rate_per_mile"`
	TotalMiles      float64   `json:"total_miles"`
	TotalRevenue    float64   `json:"total_revenue"`
	Status          string    `json:"status"`
	CommodityType   string    `json:"commodity_type"`
}
