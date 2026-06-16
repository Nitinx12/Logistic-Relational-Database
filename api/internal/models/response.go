package models

type APIResponse struct {
	Data  any `json:"data"`
	Count int `json:"count"`
}
