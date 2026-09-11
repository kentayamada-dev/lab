package server

import (
	"net/http"

	"github.com/rs/cors"
)

// withCORS answers the cross-origin preflight of the docs page and marks the
// answers as readable by the given origins.
//
// The docs container serves the Swagger UI page from its own port
// (docker-compose.yml), so both the fetch of the OpenAPI document and every
// request the page's "Try it out" sends are cross-origin, and a browser drops
// the answer unless these headers allow the origin.
//
// Without a configured origin the handler is returned untouched, so a
// deployment that runs no docs container sends no CORS header at all.
func withCORS(origins []string, handler http.Handler) http.Handler {
	if len(origins) == 0 {
		return handler
	}

	return cors.New(cors.Options{
		AllowedOrigins: origins,
		// GET for the OpenAPI document, POST for the procedures it describes.
		// Named rather than left to the default, which happens to cover both.
		AllowedMethods: []string{http.MethodGet, http.MethodPost},
		// The JSON body's content type, which is what makes a preflight
		// necessary in the first place, the two headers the Connect protocol
		// puts on a unary request, and the bearer token a client that is not
		// the app authenticates with (auth.go). Missing headers reach the
		// handler as a request the browser then refuses to read the answer of.
		//
		// Credentials are deliberately not allowed: the session cookie is for
		// the app, which reaches the API on its own origin through the rewrite
		// in web/next.config.ts and needs none of this.
		AllowedHeaders: []string{
			"Content-Type",
			"Connect-Protocol-Version",
			"Connect-Timeout-Ms",
			"Authorization",
		},
	}).Handler(handler)
}
