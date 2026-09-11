import { createClient } from "@connectrpc/connect";
import { createConnectTransport } from "@connectrpc/connect-web";
import { AuthService } from "../gen/auth/v1/auth_pb";
import { TodoService } from "../gen/todo/v1/todo_pb";

// Nothing here handles the token. Logging in sets an HttpOnly session cookie
// (api/internal/auth/cookie.go) that the browser attaches on its own and this
// code cannot read, which is the point: a script that gets onto the page has
// no token to take away. Signing out therefore has to be an RPC, since a
// script cannot delete such a cookie either.
//
// Same-origin through the rewrite in next.config.ts, so the cookie travels
// with the default credentials mode and no CORS header is needed for the app
// (api/internal/server/cors.go).
const transport = createConnectTransport({ baseUrl: "/rpc" });

export const authClient = createClient(AuthService, transport);
export const todoClient = createClient(TodoService, transport);
