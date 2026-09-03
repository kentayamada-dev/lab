// Package config loads the runtime settings from the environment.
package config

import (
	"errors"
	"os"
)

type Config struct {
	DBURL string
	Addr  string
}

func Load() (Config, error) {
	dbURL := os.Getenv("DB_URL")
	if dbURL == "" {
		return Config{}, errors.New("DB_URL is not set")
	}

	port := os.Getenv("PORT")
	if port == "" {
		return Config{}, errors.New("PORT is not set")
	}

	return Config{
		DBURL: dbURL,
		Addr:  ":" + port,
	}, nil
}
