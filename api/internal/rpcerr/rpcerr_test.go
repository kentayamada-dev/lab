package rpcerr

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"connectrpc.com/connect"
	"github.com/google/go-cmp/cmp"
)

func TestInternal(t *testing.T) {
	t.Parallel()

	// Wrapped, because that is how a driver hands a context error back.
	tests := map[string]struct {
		err      error
		wantCode connect.Code
		wantMsg  string
	}{
		"a query failure": {
			err:      errors.New("pq: relation \"todos\" does not exist"),
			wantCode: connect.CodeInternal,
			wantMsg:  "internal error",
		},
		"a cancelled request": {
			err:      fmt.Errorf("querying: %w", context.Canceled),
			wantCode: connect.CodeCanceled,
			wantMsg:  "request cancelled",
		},
		"an expired deadline": {
			err:      fmt.Errorf("querying: %w", context.DeadlineExceeded),
			wantCode: connect.CodeDeadlineExceeded,
			wantMsg:  "request timed out",
		},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			t.Parallel()

			err := Internal(t.Context(), "listing todos", tt.err)

			if got := connect.CodeOf(err); got != tt.wantCode {
				t.Errorf("Internal() code = %v, want %v", got, tt.wantCode)
			}
			// Whatever went wrong, the client is told none of it.
			if diff := cmp.Diff(tt.wantMsg, err.Message()); diff != "" {
				t.Errorf("client-facing message (-want +got):\n%s", diff)
			}
		})
	}
}

// Both layers that can turn a request away give this, so the client cannot
// tell which of them did.
func TestUnauthenticated(t *testing.T) {
	t.Parallel()

	err := Unauthenticated()

	if got := connect.CodeOf(err); got != connect.CodeUnauthenticated {
		t.Errorf("Unauthenticated() code = %v, want %v", got, connect.CodeUnauthenticated)
	}
	if err.Message() == "" {
		t.Error("Unauthenticated() carries no message")
	}
}
