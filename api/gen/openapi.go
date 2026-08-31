// Package gen exposes generated artifacts that are embedded into the binary.
// This file is hand-written; only the embedded documents are generated.
package gen

import _ "embed"

//go:embed openapi/todo/v1/todo.openapi.yaml
var OpenAPIYAML []byte
