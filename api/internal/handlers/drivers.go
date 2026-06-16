package handlers

import (
	"database/sql"
	"log"
	"net/http"

	"github.com/Nitinx12/lrdb/api/internal/models"
	"github.com/gin-gonic/gin"
)

func GetDrivers(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		rows, err := db.Query(`
			SELECT
				driver_id,
				first_name,
				last_name,
				license_number,
				license_class,
				license_expiry,
				hire_date,
				home_terminal,
				status,
				phone_number,
				email
			FROM drivers
			ORDER BY last_name, first_name
		`)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		drivers := make([]models.Driver, 0)
		for rows.Next() {
			var d models.Driver
			err := rows.Scan(
				&d.DriverID,
				&d.FirstName,
				&d.LastName,
				&d.LicenseNumber,
				&d.LicenseClass,
				&d.LicenseExpiry,
				&d.HireDate,
				&d.HomeTerminal,
				&d.Status,
				&d.PhoneNumber,
				&d.Email,
			)
			if err != nil {
				log.Printf("[drivers] scan error: %v", err)
				continue
			}
			drivers = append(drivers, d)
		}
		if err := rows.Err(); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: drivers, Count: len(drivers)})
	}
}

func GetDriverByID(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")

		var d models.Driver
		err := db.QueryRow(`
			SELECT
				driver_id,
				first_name,
				last_name,
				license_number,
				license_class,
				license_expiry,
				hire_date,
				home_terminal,
				status,
				phone_number,
				email
			FROM drivers
			WHERE driver_id = $1
		`, id).Scan(
			&d.DriverID,
			&d.FirstName,
			&d.LastName,
			&d.LicenseNumber,
			&d.LicenseClass,
			&d.LicenseExpiry,
			&d.HireDate,
			&d.HomeTerminal,
			&d.Status,
			&d.PhoneNumber,
			&d.Email,
		)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "driver not found"})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: d, Count: 1})
	}
}
