package auth

import (
	"net/http"
	"time"
)

// SessionCookieName is the cookie a browser is authenticated by. The token is
// the same one the response carries; putting it here as well is what keeps it
// out of reach of any script on the page.
const SessionCookieName = "session"

// sessionCookie builds the cookie for a session that ends at expiresAt.
//
// HttpOnly is the point of the whole arrangement: a cross-site scripting hole
// can still act as the user while the page is open, but it cannot read the
// token out and keep it.
//
// SameSite=Strict keeps the cookie off requests started by another site.
// Together with the Connect-Protocol-Version header the handlers require
// (api/internal/server/server.go), which no cross-site form can set and no
// cross-origin script can set without a preflight the CORS handler refuses,
// that is what stops another page from acting through the cookie.
//
// secure withholds the cookie from plain http. It is off locally, where the
// app is served over http and the browser would otherwise drop the cookie
// entirely, and on wherever the API is reached over https.
func sessionCookie(token string, expiresAt time.Time, secure bool) *http.Cookie {
	return &http.Cookie{
		Name:     SessionCookieName,
		Value:    token,
		Path:     "/",
		Expires:  expiresAt,
		MaxAge:   int(time.Until(expiresAt).Seconds()),
		HttpOnly: true,
		Secure:   secure,
		SameSite: http.SameSiteStrictMode,
	}
}

// clearedSessionCookie expires the session cookie. Every attribute that
// identifies the cookie has to match the one being replaced, or the browser
// stores a second cookie instead of overwriting the first.
func clearedSessionCookie(secure bool) *http.Cookie {
	return &http.Cookie{
		Name:     SessionCookieName,
		Value:    "",
		Path:     "/",
		MaxAge:   -1,
		HttpOnly: true,
		Secure:   secure,
		SameSite: http.SameSiteStrictMode,
	}
}
