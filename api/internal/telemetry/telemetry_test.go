package telemetry

import (
	"context"
	"testing"
	"time"

	"go.opentelemetry.io/otel"
)

// clearEndpoints unsets every variable an exporter would read, so a value in
// the environment running the tests cannot decide what Setup does.
func clearEndpoints(t *testing.T) {
	t.Helper()

	for _, name := range endpointVars {
		t.Setenv(name, "")
	}
}

// Running without a collector has to stay free: the no-op providers the API
// starts with are left in place, and only the propagator is installed.
func TestSetupWithoutAnEndpoint(t *testing.T) {
	clearEndpoints(t)

	tracerProvider := otel.GetTracerProvider()

	flush, err := Setup(t.Context(), "api")
	if err != nil {
		t.Fatalf("Setup() error = %v, want nil", err)
	}

	if otel.GetTracerProvider() != tracerProvider {
		t.Error("Setup() replaced the tracer provider, want it untouched")
	}
	// The no-op propagator the API starts with carries no fields.
	if fields := otel.GetTextMapPropagator().Fields(); len(fields) == 0 {
		t.Error("Setup() installed no propagator")
	}

	if err := flush(t.Context()); err != nil {
		t.Errorf("flush() error = %v, want nil", err)
	}
}

// The OTLP exporters connect lazily, so an endpoint nothing listens on is
// enough to pin that a configured collector gets real providers installed.
func TestSetupWithAnEndpoint(t *testing.T) {
	clearEndpoints(t)
	t.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://127.0.0.1:1")

	tracerProvider := otel.GetTracerProvider()
	meterProvider := otel.GetMeterProvider()

	flush, err := Setup(t.Context(), "api")
	if err != nil {
		t.Fatalf("Setup() error = %v, want nil", err)
	}
	// The flush cannot reach the endpoint, so it is given a deadline of its
	// own and its error is not what this test is about.
	t.Cleanup(func() {
		ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
		defer cancel()

		_ = flush(ctx)
	})

	if otel.GetTracerProvider() == tracerProvider {
		t.Error("Setup() left the no-op tracer provider in place")
	}
	if otel.GetMeterProvider() == meterProvider {
		t.Error("Setup() left the no-op meter provider in place")
	}
}
