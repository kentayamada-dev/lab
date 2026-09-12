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
	DBURL string
	Addr  string
	// TokenSecret signs the bearer tokens. How short a secret is too short is
	// settled by auth.NewIssuer, which is what uses it.
	TokenSecret string
	// SecureCookies withholds the session cookie from plain http
	// (api/internal/auth/cookie.go).
	SecureCookies bool
	CORSOrigins   []string
}

// LoadDBURL reads the one setting a command that does nothing but reach the
// database needs (api/cmd/purge). Load goes through it too, so the variable is
// named and reported in one place rather than in each command that wants it.
func LoadDBURL() (string, error) {
	dbURL := os.Getenv("DB_URL")
	if dbURL == "" {
		return "", errors.New("DB_URL is not set")
	}

	return dbURL, nil
}

func Load() (Config, error) {
	dbURL, err := LoadDBURL()
	if err != nil {
		return Config{}, err
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

	tokenSecret := os.Getenv("TOKEN_SECRET")
	if tokenSecret == "" {
		return Config{}, errors.New("TOKEN_SECRET is not set")
	}

	// On unless something says otherwise: a session cookie offered over plain
	// http is one a network can read, and forgetting the setting should not be
	// what makes that happen. Local development is the one place that needs it
	// off, and docker-compose.yml says so explicitly.
	secureCookies, err := parseBool("COOKIE_SECURE", os.Getenv("COOKIE_SECURE"), true)
	if err != nil {
		return Config{}, err
	}

	// Which browser origins may call the API from a page they serve
	// (api/internal/server/cors.go). Locally this is the docs container, which
	// serves the Swagger UI page from another port; unset means the API answers
	// no cross-origin request.
	corsOrigins, err := parseOrigins(os.Getenv("CORS_ORIGINS"))
	if err != nil {
		return Config{}, err
	}

	return Config{
		DBURL:         dbURL,
		Addr:          ":" + port,
		TokenSecret:   tokenSecret,
		SecureCookies: secureCookies,
		CORSOrigins:   corsOrigins,
	}, nil
}

// parseBool reads an optional flag. A value it cannot read is an error rather
// than a silent fallback, which would leave a misspelling looking like a
// deliberate setting.
func parseBool(name, value string, fallback bool) (bool, error) {
	if value == "" {
		return fallback, nil
	}

	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return false, fmt.Errorf("%s must be a boolean, got %q", name, value)
	}

	return parsed, nil
}

// parseOrigins splits a comma separated list of browser origins. A malformed
// entry fails here rather than being dropped by the CORS handler, where the
// only symptom would be a browser refusing the answer of a request that looks
// fine on the server. "*" is malformed on purpose: opening the API to every
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
