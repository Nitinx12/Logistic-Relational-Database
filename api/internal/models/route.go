package models

import "time"

type Route struct {
	RouteID              string     `json:"route_id"`
	OriginCity           string     `json:"origin_city"`
	OriginState          string     `json:"origin_state"`
	DestinationCity      string     `json:"destination_city"`
	DestinationState     string     `json:"destination_state"`
	TypicalDistanceMiles int64      `json:"typical_distance_miles"`
	BaseRatePerMile      float64    `json:"base_rate_per_mile"`
	FuelSurchargeRate    float64    `json:"fuel_surcharge_rate"`
	TypicalTransitDays   int64      `json:"typical_transit_days"`
	UpdatedAt            *time.Time `json:"updated_at"`
}
