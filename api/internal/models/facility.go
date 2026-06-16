package models

type Facility struct {
	FacilityID   string  `json:"facility_id"`
	FacilityName string  `json:"facility_name"`
	FacilityType string  `json:"facility_type"`
	Address      string  `json:"address"`
	City         string  `json:"city"`
	State        string  `json:"state"`
	ZipCode      string  `json:"zip_code"`
	Latitude     float64 `json:"latitude"`
	Longitude    float64 `json:"longitude"`
	PhoneNumber  string  `json:"phone_number"`
}
