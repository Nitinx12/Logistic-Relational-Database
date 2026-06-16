package models

type Route struct {
	RouteID         string  `json:"route_id"`
	RouteName       string  `json:"route_name"`
	OriginFacility  string  `json:"origin_facility"`
	DestFacility    string  `json:"dest_facility"`
	DistanceMiles   float64 `json:"distance_miles"`
	EstimatedHours  float64 `json:"estimated_hours"`
	RouteType       string  `json:"route_type"`
}
