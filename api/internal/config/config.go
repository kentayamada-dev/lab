// Package config loads the runtime settings from the environment.
package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
)

// maxPort is the highest TCP port number.
const maxPort = 65535

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
	// Caught here rather than at ListenAndServe, so a typo fails before the
	// database connection is opened.
	if n, err := strconv.Atoi(port); err != nil || n < 1 || n > maxPort {
		return Config{}, fmt.Errorf("PORT must be a number between 1 and %d, got %q", maxPort, port)
	}

	return Config{
		DBURL: dbURL,
		Addr:  ":" + port,
	}, nil
}
