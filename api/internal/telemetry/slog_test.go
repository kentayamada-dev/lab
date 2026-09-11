package telemetry

import (
	"bytes"
	"context"
	"encoding/json"
	"log/slog"
	"testing"

	"go.opentelemetry.io/otel/trace"
)

var (
	testTraceID = trace.TraceID{0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10}
	testSpanID  = trace.SpanID{0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18}
)

// newLogger hands the test a logger writing JSON into the returned buffer,
// which is the shape the server's own logger has (api/cmd/server/main.go).
func newLogger(t *testing.T) (*slog.Logger, *bytes.Buffer) {
	t.Helper()

	var buf bytes.Buffer

	return slog.New(NewLogHandler(slog.NewJSONHandler(&buf, nil))), &buf
}

// spanContext returns a context carrying a span with known ids. A recorded
// span is not needed: the handler reads the ids off the context.
func spanContext(t *testing.T) context.Context {
	t.Helper()

	return trace.ContextWithSpanContext(t.Context(), trace.NewSpanContext(trace.SpanContextConfig{
		TraceID: testTraceID,
		SpanID:  testSpanID,
	}))
}

// decode reads the one record the buffer holds.
func decode(t *testing.T, buf *bytes.Buffer) map[string]any {
	t.Helper()

	var record map[string]any
	if err := json.Unmarshal(buf.Bytes(), &record); err != nil {
		t.Fatalf("unmarshalling the record: %v", err)
	}

	return record
}

func TestLogHandlerNamesTheSpan(t *testing.T) {
	logger, buf := newLogger(t)

	logger.InfoContext(spanContext(t), "listening")

	record := decode(t, buf)
	if got, want := record[traceIDKey], testTraceID.String(); got != want {
		t.Errorf("%s = %v, want %q", traceIDKey, got, want)
	}
	if got, want := record[spanIDKey], testSpanID.String(); got != want {
		t.Errorf("%s = %v, want %q", spanIDKey, got, want)
	}
}

// Lines logged outside a request carry no ids to name, and inventing empty
// ones would leave a log backend looking for a trace that does not exist.
func TestLogHandlerWithoutASpan(t *testing.T) {
	logger, buf := newLogger(t)

	logger.InfoContext(t.Context(), "listening")

	record := decode(t, buf)
	if _, ok := record[traceIDKey]; ok {
		t.Errorf("record has %s, want it absent", traceIDKey)
	}
	if _, ok := record[spanIDKey]; ok {
		t.Errorf("record has %s, want it absent", spanIDKey)
	}
}

// slog.With returns a logger built from WithAttrs, which has to keep naming
// the span.
func TestLogHandlerThroughWithAttrs(t *testing.T) {
	logger, buf := newLogger(t)

	logger.With("procedure", "ListTodos").InfoContext(spanContext(t), "handled")

	record := decode(t, buf)
	if got, want := record[traceIDKey], testTraceID.String(); got != want {
		t.Errorf("%s = %v, want %q", traceIDKey, got, want)
	}
}

// Under an open group the ids land inside it, as any attribute added while
// handling does. What matters is that they are still there.
func TestLogHandlerThroughWithGroup(t *testing.T) {
	logger, buf := newLogger(t)

	logger.WithGroup("rpc").InfoContext(spanContext(t), "handled")

	group, ok := decode(t, buf)["rpc"].(map[string]any)
	if !ok {
		t.Fatal("record has no rpc group")
	}
	if got, want := group[traceIDKey], testTraceID.String(); got != want {
		t.Errorf("rpc.%s = %v, want %q", traceIDKey, got, want)
	}
}
