package telemetry

import (
	"context"
	"log/slog"

	"go.opentelemetry.io/otel/trace"
)

// The attribute names are the ones log backends look for when they link a line
// to a trace. They are snake_case rather than the dotted OpenTelemetry
// convention because that is what the collectors and the log viewers reading
// plain JSON expect.
const (
	traceIDKey = "trace_id"
	spanIDKey  = "span_id"
)

// logHandler adds the ids of the span a record was logged under, which is what
// joins a log line to the trace it belongs to. Without them a trace says a call
// failed and the log says why, with nothing connecting the two.
type logHandler struct {
	slog.Handler
}

// NewLogHandler wraps h so that records logged with a context carrying a span
// name that span. Records logged without one are passed through untouched, so
// the lines written before the first request look the same as they did.
func NewLogHandler(h slog.Handler) slog.Handler {
	return logHandler{Handler: h}
}

func (h logHandler) Handle(ctx context.Context, record slog.Record) error {
	spanCtx := trace.SpanContextFromContext(ctx)
	if spanCtx.IsValid() {
		record.AddAttrs(
			slog.String(traceIDKey, spanCtx.TraceID().String()),
			slog.String(spanIDKey, spanCtx.SpanID().String()),
		)
	}

	return h.Handler.Handle(ctx, record)
}

// WithAttrs and WithGroup rewrap what the inner handler returns. Left to the
// embedded handler they would hand back a bare one, and a logger built with
// slog.With would quietly stop naming its span.
func (h logHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	return logHandler{Handler: h.Handler.WithAttrs(attrs)}
}

func (h logHandler) WithGroup(name string) slog.Handler {
	return logHandler{Handler: h.Handler.WithGroup(name)}
}
