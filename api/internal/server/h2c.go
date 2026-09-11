package server

import "net/http"

// protocols lists what the server speaks. It serves plain http and leaves TLS
// to whatever terminates it in front, so there is no handshake to settle on
// HTTP/2 and a plaintext HTTP/2 client has to be admitted explicitly. Connect
// and gRPC-Web are happy with HTTP/1.1, but a plain gRPC client speaks HTTP/2
// only.
func protocols() *http.Protocols {
	p := new(http.Protocols)
	p.SetHTTP1(true)
	p.SetUnencryptedHTTP2(true)

	return p
}
