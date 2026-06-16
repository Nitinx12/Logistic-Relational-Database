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
				customer_name,
				customer_type,
				credit_terms_days,
				primary_freight_type,
				account_status,
				contract_start_date,
				annual_revenue_potential,
				updated_at
			FROM customers
			ORDER BY customer_name
		`)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		defer rows.Close()

		customers := make([]models.Customer, 0)
		for rows.Next() {
			var cu models.Customer
			if err := rows.Scan(
				&cu.CustomerID,
				&cu.CustomerName,
				&cu.CustomerType,
				&cu.CreditTermsDays,
				&cu.PrimaryFreightType,
				&cu.AccountStatus,
				&cu.ContractStartDate,
				&cu.AnnualRevenuePotential,
				&cu.UpdatedAt,
			); err != nil {
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
				customer_name,
				customer_type,
				credit_terms_days,
				primary_freight_type,
				account_status,
				contract_start_date,
				annual_revenue_potential,
				updated_at
			FROM customers
			WHERE customer_id = $1
		`, id).Scan(
			&cu.CustomerID,
			&cu.CustomerName,
			&cu.CustomerType,
			&cu.CreditTermsDays,
			&cu.PrimaryFreightType,
			&cu.AccountStatus,
			&cu.ContractStartDate,
			&cu.AnnualRevenuePotential,
			&cu.UpdatedAt,
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
