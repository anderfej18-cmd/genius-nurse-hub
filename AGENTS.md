# Project rules

- Keep app-internal server functions in client-safe `*.functions.ts` modules and load privileged helpers only inside authorized server handlers; this preserves the client/server boundary and avoids exposing credentials.