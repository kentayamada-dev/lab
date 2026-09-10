package server

import (
	_ "embed"
	"log"
	"net/http"

	"example/app/gen"
)

//go:embed docs.html
var docsHTML []byte

// RapiDoc is vendored from the rapidoc npm package (MIT, see
// rapidoc-min.js.LICENSE.txt, which also records the version) so /docs works
// offline. It renders the OpenAPI 3.1 document the plugin generates, including
// the int64 path parameters, whose "type: [integer, string]" Swagger UI
// rejected as missing when a request was sent from the page.
//
//go:embed rapidoc-min.js
var rapidocJS []byte

func registerDocs(mux *http.ServeMux) {
	serve := func(pattern, contentType string, body []byte) {
		mux.HandleFunc("GET "+pattern, func(w http.ResponseWriter, _ *http.Request) {
			w.Header().Set("Content-Type", contentType)
			if _, err := w.Write(body); err != nil {
				log.Printf("serving %s: %v", pattern, err)
			}
		})
	}

	serve("/openapi.yaml", "application/yaml", gen.OpenAPIYAML)
	serve("/docs", "text/html; charset=utf-8", docsHTML)
	serve("/docs/rapidoc-min.js", "text/javascript; charset=utf-8", rapidocJS)
}
