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
				hire_date,
				termination_date,
				license_number,
				license_state,
				date_of_birth,
				home_terminal,
				employment_status,
				cdl_class,
				years_experience,
				updated_at
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
			if err := rows.Scan(
				&d.DriverID,
				&d.FirstName,
				&d.LastName,
				&d.HireDate,
				&d.TerminationDate,
				&d.LicenseNumber,
				&d.LicenseState,
				&d.DateOfBirth,
				&d.HomeTerminal,
				&d.EmploymentStatus,
				&d.CDLClass,
				&d.YearsExperience,
				&d.UpdatedAt,
			); err != nil {
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
				hire_date,
				termination_date,
				license_number,
				license_state,
				date_of_birth,
				home_terminal,
				employment_status,
				cdl_class,
				years_experience,
				updated_at
			FROM drivers
			WHERE driver_id = $1
		`, id).Scan(
			&d.DriverID,
			&d.FirstName,
			&d.LastName,
			&d.HireDate,
			&d.TerminationDate,
			&d.LicenseNumber,
			&d.LicenseState,
			&d.DateOfBirth,
			&d.HomeTerminal,
			&d.EmploymentStatus,
			&d.CDLClass,
			&d.YearsExperience,
			&d.UpdatedAt,
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

func GetDriverMonthlyMetrics(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")

		rows, err := db.Query(`
			SELECT
				driver_id,
				month,
				trips_completed,
				total_miles,
				total_revenue,
				average_mpg,
				total_fuel_gallons,
				on_time_delivery_rate,
				average_idle_hours,
				updated_at
			FROM driver_monthly_metrics
			WHERE driver_id = $1
			ORDER BY month DESC
		`, id)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		metrics := make([]models.DriverMonthlyMetrics, 0)
		for rows.Next() {
			var m models.DriverMonthlyMetrics
			if err := rows.Scan(
				&m.DriverID,
				&m.Month,
				&m.TripsCompleted,
				&m.TotalMiles,
				&m.TotalRevenue,
				&m.AverageMPG,
				&m.TotalFuelGallons,
				&m.OnTimeDeliveryRate,
				&m.AverageIdleHours,
				&m.UpdatedAt,
			); err != nil {
				log.Printf("[driver_monthly_metrics] scan error: %v", err)
				continue
			}
			metrics = append(metrics, m)
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: metrics, Count: len(metrics)})
	}
}
