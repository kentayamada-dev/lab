package server

import (
	"log/slog"
	"net/http"

	"example/app/gen"
)

// registerOpenAPI serves the generated OpenAPI document. The Swagger UI page in
// the docs container loads it from here (docker-compose.yml), so the document
// the page shows is always the one the running binary was built from.
func registerOpenAPI(mux *http.ServeMux) {
	mux.HandleFunc("GET /openapi.yaml", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/yaml")
		if _, err := w.Write(gen.OpenAPIYAML); err != nil {
			slog.ErrorContext(r.Context(), "serving /openapi.yaml", "error", err)
		}
	})
}
