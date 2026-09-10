package server

import (
	"connectrpc.com/connect"
	"connectrpc.com/vanguard"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protoreflect"
)

// jsonCodec is vanguard's JSON codec with one change: a document it cannot
// unmarshal is reported as invalid_argument.
//
// The transcoder unmarshals a request body itself whenever it has to merge
// something else into it, which on these routes means the id from the path of
// "PATCH /v1/todos/{id}". It leaves the code of the error unset, and the REST
// protocol then answers 500 with the unknown code, so a truncated body read as
// a server-side failure. (A body the transcoder passes on untouched, as on
// "POST /v1/todos", is unmarshalled by connect-go, which classifies it itself.)
//
// The codec also reads the responses this server sends, where a failure would
// be a server-side fault rather than a client's. That direction cannot
// realistically fail: the document was marshalled by this same codec a moment
// earlier.
type jsonCodec struct {
	*vanguard.JSONCodec
}

// The transcoder type-asserts its codec for both of these. Losing StableCodec
// would silently stop it from putting Connect GET requests in the URL, and
// losing RESTCodec would fail any route whose body maps to a single field.
var (
	_ vanguard.StableCodec = jsonCodec{}
	_ vanguard.RESTCodec   = jsonCodec{}
)

func newJSONCodec(resolver vanguard.TypeResolver) vanguard.Codec {
	return jsonCodec{vanguard.NewJSONCodec(resolver)}
}

func (c jsonCodec) Unmarshal(data []byte, msg proto.Message) error {
	return asInvalidArgument(c.JSONCodec.Unmarshal(data, msg))
}

func (c jsonCodec) UnmarshalField(
	data []byte,
	msg proto.Message,
	field protoreflect.FieldDescriptor,
) error {
	return asInvalidArgument(c.JSONCodec.UnmarshalField(data, msg, field))
}

func asInvalidArgument(err error) error {
	if err == nil {
		return nil
	}

	return connect.NewError(connect.CodeInvalidArgument, err)
}
