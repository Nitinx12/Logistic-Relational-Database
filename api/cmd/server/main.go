package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/Nitinx12/lrdb/api/internal/db"
	"github.com/Nitinx12/lrdb/api/internal/handlers"
	"github.com/gin-gonic/gin"
)

func main() {
	database, err := db.Connect()
	if err != nil {
		log.Fatalf("[LRDB] PostgreSQL connection failed: %v", err)
	}
	defer database.Close()

	log.Println("[LRDB] PostgreSQL connected")

	router := gin.Default()

	router.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "ok",
			"service": "LRDB API",
		})
	})

	v1 := router.Group("/api/v1")
	{
		// Trucks
		v1.GET("/trucks", handlers.GetTrucks(database))
		v1.GET("/trucks/:id", handlers.GetTruckByID(database))

		// Drivers
		v1.GET("/drivers", handlers.GetDrivers(database))
		v1.GET("/drivers/:id", handlers.GetDriverByID(database))

		// Loads
		v1.GET("/loads", handlers.GetLoads(database))
		v1.GET("/loads/:id", handlers.GetLoadByID(database))

		// Trips
		v1.GET("/trips", handlers.GetTrips(database))
		v1.GET("/trips/:id", handlers.GetTripByID(database))

		// Routes
		v1.GET("/routes", handlers.GetRoutes(database))
		v1.GET("/routes/:id", handlers.GetRouteByID(database))

		// Trailers
		v1.GET("/trailers", handlers.GetTrailers(database))
		v1.GET("/trailers/:id", handlers.GetTrailerByID(database))

		// Facilities
		v1.GET("/facilities", handlers.GetFacilities(database))
		v1.GET("/facilities/:id", handlers.GetFacilityByID(database))

		// Customers
		v1.GET("/customers", handlers.GetCustomers(database))
		v1.GET("/customers/:id", handlers.GetCustomerByID(database))

		// Fuel Purchases
		v1.GET("/fuel-purchases", handlers.GetFuelPurchases(database))
		v1.GET("/fuel-purchases/:id", handlers.GetFuelPurchaseByID(database))

		// Maintenance Records
		v1.GET("/maintenance", handlers.GetMaintenanceRecords(database))
		v1.GET("/maintenance/:id", handlers.GetMaintenanceRecordByID(database))

		// Safety Incidents
		v1.GET("/safety-incidents", handlers.GetSafetyIncidents(database))
		v1.GET("/safety-incidents/:id", handlers.GetSafetyIncidentByID(database))

		// Delivery Events
		v1.GET("/delivery-events", handlers.GetDeliveryEvents(database))
		v1.GET("/delivery-events/:id", handlers.GetDeliveryEventByID(database))
	}

	port := os.Getenv("API_PORT")
	if port == "" {
		port = "8080"
	}

	server := &http.Server{
		Addr:           ":" + port,
		Handler:        router,
		ReadTimeout:    10 * time.Second,
		WriteTimeout:   10 * time.Second,
		IdleTimeout:    60 * time.Second,
		MaxHeaderBytes: 1 << 20,
	}

	// Start server in background
	go func() {
		log.Printf("[LRDB] Server running on http://localhost:%s", port)
		log.Printf("[LRDB] Health Check -> http://localhost:%s/health", port)
		log.Printf("[LRDB] API Base URL -> http://localhost:%s/api/v1", port)

		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("[LRDB] Server error: %v", err)
		}
	}()

	// Graceful shutdown on SIGINT / SIGTERM
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("[LRDB] Shutting down server...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Fatalf("[LRDB] Forced shutdown: %v", err)
	}

	log.Println("[LRDB] Server stopped cleanly")
}