// Package config loads the runtime settings from the environment.
package config

import (
	"errors"
	"fmt"
	"net/url"
	"os"
	"strconv"
	"strings"
)

// maxPort is the highest TCP port number.
const maxPort = 65535

type Config struct {
	DBURL       string
	Addr        string
	CORSOrigins []string
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

	// Which browser origins may call the REST routes
	// (api/internal/server/cors.go). Locally this is the docs container, which
	// serves its page from another port; unset means the API answers no
	// cross-origin request.
	corsOrigins, err := parseOrigins(os.Getenv("CORS_ORIGINS"))
	if err != nil {
		return Config{}, err
	}

	return Config{
		DBURL:       dbURL,
		Addr:        ":" + port,
		CORSOrigins: corsOrigins,
	}, nil
}

// parseOrigins splits a comma separated list of browser origins. A malformed
// entry fails here rather than being dropped by the CORS handler, where the
// only symptom would be a browser refusing the answer of a request that looks
// fine on the server. "*" is malformed on purpose: opening the routes to every
// origin should take more than a typo.
func parseOrigins(value string) ([]string, error) {
	var origins []string

	for _, origin := range strings.Split(value, ",") {
		origin = strings.TrimSpace(origin)
		if origin == "" {
			continue
		}

		parsed, err := url.Parse(origin)
		if err != nil || parsed.Scheme == "" || parsed.Host == "" ||
			parsed.Path != "" || parsed.RawQuery != "" || parsed.Fragment != "" {
			return nil, fmt.Errorf(
				"CORS_ORIGINS must be a comma separated list of scheme://host origins, got %q",
				origin,
			)
		}

		origins = append(origins, origin)
	}

	return origins, nil
}
