package db

import (
	"database/sql"
	"fmt"
	"os"
	"time"

	_ "github.com/lib/pq"
)

func Connect() (*sql.DB, error) {

	host := getEnv("POSTGRES_HOST", "localhost")
	port := getEnv("POSTGRES_PORT", "5432")
	user := getEnv("POSTGRES_USERNAME", "postgres")
	password := getEnv("POSTGRES_PASSWORD", "")
	dbname := getEnv("POSTGRES_DATABASE", "LRDB")

	dsn := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		host,
		port,
		user,
		password,
		dbname,
	)

	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to open postgres connection: %w", err)
	}

	// Connection Pool Settings
	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(10)
	db.SetConnMaxLifetime(5 * time.Minute)
	db.SetConnMaxIdleTime(2 * time.Minute)

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf(
			"unable to connect to PostgreSQL (%s:%s/%s): %w",
			host,
			port,
			dbname,
			err,
		)
	}

	fmt.Printf("✓ Connected to PostgreSQL (%s)\n", dbname)

	return db, nil
}

func Close(db *sql.DB) {
	if db != nil {
		_ = db.Close()
	}
}

func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}