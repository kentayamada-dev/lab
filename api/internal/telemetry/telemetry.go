// Package telemetry installs the OpenTelemetry providers the rest of the
// process records traces and metrics against.
package telemetry

import (
	"context"
	"errors"
	"os"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.30.0"
)

// endpointVars are the standard variables naming where the OTLP exporters send
// to. The exporters read them themselves; they are listed here only to tell
// "nothing is collecting" from "the collector is down", which decides whether
// Setup builds exporters at all.
var endpointVars = []string{
	"OTEL_EXPORTER_OTLP_ENDPOINT",
	"OTEL_EXPORTER_OTLP_TRACES_ENDPOINT",
	"OTEL_EXPORTER_OTLP_METRICS_ENDPOINT",
}

func exportConfigured() bool {
	for _, name := range endpointVars {
		if os.Getenv(name) != "" {
			return true
		}
	}

	return false
}

// Setup installs the propagator and, when an OTLP endpoint is configured, the
// trace and metric providers. The returned function flushes what is still
// buffered and must be called before the process exits.
//
// With no endpoint configured the global no-op providers stay in place, so
// running without a collector costs nothing and needs no separate switch.
// serviceName is what the signals are attributed to unless OTEL_SERVICE_NAME
// or OTEL_RESOURCE_ATTRIBUTES names something else.
func Setup(ctx context.Context, serviceName string) (func(context.Context) error, error) {
	noop := func(context.Context) error { return nil }

	// Installed either way, so an incoming traceparent keeps its trace id
	// through this process even while nothing is exported.
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	if !exportConfigured() {
		return noop, nil
	}

	// WithFromEnv comes last so the environment wins over the fallback name.
	res, err := resource.New(ctx,
		resource.WithTelemetrySDK(),
		resource.WithHost(),
		resource.WithProcessRuntimeDescription(),
		resource.WithAttributes(semconv.ServiceName(serviceName)),
		resource.WithFromEnv(),
	)
	if err != nil {
		return nil, err
	}

	traceExporter, err := otlptracegrpc.New(ctx)
	if err != nil {
		return nil, err
	}
	tracerProvider := sdktrace.NewTracerProvider(
		sdktrace.WithResource(res),
		sdktrace.WithBatcher(traceExporter),
	)

	metricExporter, err := otlpmetricgrpc.New(ctx)
	if err != nil {
		return nil, errors.Join(err, tracerProvider.Shutdown(ctx))
	}
	meterProvider := sdkmetric.NewMeterProvider(
		sdkmetric.WithResource(res),
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExporter)),
	)

	otel.SetTracerProvider(tracerProvider)
	otel.SetMeterProvider(meterProvider)

	return func(ctx context.Context) error {
		return errors.Join(tracerProvider.Shutdown(ctx), meterProvider.Shutdown(ctx))
	}, nil
}
