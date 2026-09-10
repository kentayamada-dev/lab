package server

import (
	"bytes"
	_ "embed"
	"log"
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

// shortenOpenAPIPaths rewrites the path keys of the generated document from the
// canonical Connect procedures to the short paths registerShortPaths also
// serves, keyed by short path. The plugin has no option for this, and Swagger
// UI calls whatever path the document names, so leaving the procedures in place
// would document the long form as the only way in.
//
// Whole lines are matched: every key under "paths:" carries this indentation,
// and a procedure appears nowhere else in the document with a leading slash.
func shortenOpenAPIPaths(doc []byte, shortPaths map[string]string) []byte {
	for short, procedure := range shortPaths {
		doc = bytes.ReplaceAll(doc,
			[]byte("\n  "+procedure+":\n"),
			[]byte("\n  "+short+":\n"),
		)
	}

	return doc
}

func registerDocs(mux *http.ServeMux, shortPaths map[string]string) {
	serve := func(pattern, contentType string, body []byte) {
		mux.HandleFunc("GET "+pattern, func(w http.ResponseWriter, _ *http.Request) {
			w.Header().Set("Content-Type", contentType)
			if _, err := w.Write(body); err != nil {
				log.Printf("serving %s: %v", pattern, err)
			}
		})
	}

	serve("/openapi.yaml", "application/yaml", shortenOpenAPIPaths(gen.OpenAPIYAML, shortPaths))
	serve("/docs", "text/html; charset=utf-8", swaggerHTML)
	serve("/docs/swagger-ui.css", "text/css; charset=utf-8", swaggerCSS)
	serve("/docs/swagger-ui-bundle.js", "text/javascript; charset=utf-8", swaggerJS)
}
