package main

import (
	"log"
	"net/http"
	"os"
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
		v1.GET("/trucks", handlers.GetTrucks(database))
		v1.GET("/trucks/:id", handlers.GetTruckByID(database))

		v1.GET("/drivers", handlers.GetDrivers(database))
		v1.GET("/drivers/:id", handlers.GetDriverByID(database))

		v1.GET("/loads", handlers.GetLoads(database))
		v1.GET("/loads/:id", handlers.GetLoadByID(database))

		v1.GET("/trips", handlers.GetTrips(database))
		v1.GET("/routes", handlers.GetRoutes(database))
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

	log.Printf("[LRDB] Server running on http://localhost:%s", port)
	log.Printf("[LRDB] Health Check -> http://localhost:%s/health", port)
	log.Printf("[LRDB] API Base URL -> http://localhost:%s/api/v1", port)

	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("[LRDB] Server error: %v", err)
	}
}