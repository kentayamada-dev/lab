package server

import (
	_ "embed"
	"net/http"

	"example/app/gen"
)

//go:embed swagger.html
var swaggerHTML []byte

// The Swagger UI assets are vendored from swagger-ui-dist (Apache-2.0,
// see swagger-ui-bundle.js.LICENSE.txt) so /docs works offline.
//
//go:embed swagger-ui.css
var swaggerCSS []byte

//go:embed swagger-ui-bundle.js
var swaggerJS []byte

func registerDocs(mux *http.ServeMux) {
	serve := func(pattern, contentType string, body []byte) {
		mux.HandleFunc("GET "+pattern, func(w http.ResponseWriter, _ *http.Request) {
			w.Header().Set("Content-Type", contentType)
			w.Write(body)
		})
	}

	serve("/openapi.yaml", "application/yaml", gen.OpenAPIYAML)
	serve("/docs", "text/html; charset=utf-8", swaggerHTML)
	serve("/docs/swagger-ui.css", "text/css; charset=utf-8", swaggerCSS)
	serve("/docs/swagger-ui-bundle.js", "text/javascript; charset=utf-8", swaggerJS)
}
