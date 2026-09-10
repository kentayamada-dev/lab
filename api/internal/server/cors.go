package server

import (
	"net/http"

	"github.com/rs/cors"
)

// withCORS answers the cross-origin preflight for the REST routes and marks
// their answers as readable by the given origins.
//
// The docs container serves its page from its own port (docker-compose.yml), so
// every request that page sends is cross-origin, and a browser drops the answer
// unless these headers allow the origin. Only the REST routes are wrapped: they
// are the whole of the generated OpenAPI document, while the Connect procedures
// are called same-origin, through the web app's proxy (web/next.config.ts).
//
// Without a configured origin the handler is returned untouched, so a
// deployment that runs no docs container sends no CORS header at all.
func withCORS(origins []string, handler http.Handler) http.Handler {
	if len(origins) == 0 {
		return handler
	}

	return cors.New(cors.Options{
		AllowedOrigins: origins,
		// The methods the google.api.http annotations declare. The default
		// covers neither PATCH nor DELETE.
		AllowedMethods: []string{
			http.MethodGet,
			http.MethodPost,
			http.MethodPatch,
			http.MethodDelete,
		},
		// The JSON body's content type, which is what makes a preflight
		// necessary in the first place.
		AllowedHeaders: []string{"Content-Type"},
	}).Handler(handler)
}
