package auth

import (
	"net/http"
	"strings"
)

// bearerPrefix is the authentication scheme the Authorization header has to
// name. RFC 9110 makes the scheme case-insensitive, so it is matched that way.
const bearerPrefix = "bearer "

// bearerToken pulls the token out of an Authorization header value.
func bearerToken(header string) (string, bool) {
	if len(header) < len(bearerPrefix) || !strings.EqualFold(header[:len(bearerPrefix)], bearerPrefix) {
		return "", false
	}

	token := strings.TrimSpace(header[len(bearerPrefix):])

	return token, token != ""
}

// sessionToken pulls the token out of the session cookie (cookie.go).
func sessionToken(header http.Header) (string, bool) {
	for _, line := range header.Values("Cookie") {
		cookies, err := http.ParseCookie(line)
		if err != nil {
			continue
		}

		for _, cookie := range cookies {
			if cookie.Name == SessionCookieName && cookie.Value != "" {
				return cookie.Value, true
			}
		}
	}

	return "", false
}

// RequestToken takes the token a request is authenticated by. The Authorization
// header comes first, so a client that names one explicitly is not overruled by
// a cookie its browser attached on its own; a browser sends no header and is
// authenticated by the cookie alone.
//
// It lives here rather than beside the interceptor that guards the procedures
// (api/internal/server/auth.go) because LogOut needs it too: that procedure
// takes no token to reach, and still has to find out which session it is being
// asked to close (service.go).
func RequestToken(header http.Header) (string, bool) {
	if token, ok := bearerToken(header.Get("Authorization")); ok {
		return token, true
	}

	return sessionToken(header)
}
