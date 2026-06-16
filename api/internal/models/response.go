package models

type APIResponse struct {
	Data  interface{} `json:"data"`
	Count int         `json:"count"`
}
