package handlers

import (
	"database/sql"
	"log"
	"net/http"

	"github.com/Nitinx12/lrdb/api/internal/models"
	"github.com/gin-gonic/gin"
)

func GetCustomers(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		rows, err := db.Query(`
			SELECT
				customer_id,
				company_name,
				contact_name,
				phone_number,
				email,
				address,
				city,
				state,
				zip_code,
				credit_limit,
				payment_term_days
			FROM customers
			ORDER BY company_name
		`)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		customers := make([]models.Customer, 0)
		for rows.Next() {
			var cu models.Customer
			err := rows.Scan(
				&cu.CustomerID,
				&cu.CompanyName,
				&cu.ContactName,
				&cu.PhoneNumber,
				&cu.Email,
				&cu.Address,
				&cu.City,
				&cu.State,
				&cu.ZipCode,
				&cu.CreditLimit,
				&cu.PaymentTermDays,
			)
			if err != nil {
				log.Printf("[customers] scan error: %v", err)
				continue
			}
			customers = append(customers, cu)
		}
		if err := rows.Err(); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: customers, Count: len(customers)})
	}
}

func GetCustomerByID(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		id := c.Param("id")

		var cu models.Customer
		err := db.QueryRow(`
			SELECT
				customer_id,
				company_name,
				contact_name,
				phone_number,
				email,
				address,
				city,
				state,
				zip_code,
				credit_limit,
				payment_term_days
			FROM customers
			WHERE customer_id = $1
		`, id).Scan(
			&cu.CustomerID,
			&cu.CompanyName,
			&cu.ContactName,
			&cu.PhoneNumber,
			&cu.Email,
			&cu.Address,
			&cu.City,
			&cu.State,
			&cu.ZipCode,
			&cu.CreditLimit,
			&cu.PaymentTermDays,
		)
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "customer not found"})
			return
		}
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}

		c.JSON(http.StatusOK, models.APIResponse{Data: cu, Count: 1})
	}
}
