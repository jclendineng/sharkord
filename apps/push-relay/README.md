# Sharkord push relay

A Cloudflare Worker that holds the app's APNs keys and forwards encrypted notifications for
every Sharkord server, so no server operator needs an Apple developer account. Design and
reasoning: [issue 203](https://github.com/jclendineng/sharkord/issues/203).

## How it works

- `POST /v1/tickets` (called by the app): `{ deviceToken, sandbox, serverKey }` returns
  `{ id, ticket, expiresAt }`. The ticket is the device token, the server's public key and an
  expiry, sealed with `TICKET_SECRET`. Only this relay can open it. `id` is stable for one device
  on one server.
- `POST /v1/push` (called by a server): `{ ticket, encrypted }`, signed with the server's
  ed25519 key in `x-sharkord-signature` over `${x-sharkord-timestamp}\n${body}`. The relay opens
  the ticket, checks the signature against the key sealed inside it, and sends `encrypted` to
  the device. A ticket only works for the server it names.
- The payload is encrypted by the server to a key only the app holds, so the relay and Apple
  see ciphertext. The answer mirrors Apple's status and reason, plus `BadTicket`,
  `ExpiredTicket` and `TicketNotForServer` (all mean the server should forget the device).

Not done yet: App Attest on ticket requests, so only the genuine app can get one.

## Deploy

Needs `CLOUDFLARE_API_TOKEN` in the environment (the "Edit Cloudflare Workers" template).

```bash
bunx wrangler@4.152.0 secret put TICKET_SECRET
```

Use 32 random bytes as base64url, for example from `openssl rand -base64 32 | tr '+/' '-_' | tr -d '='`.
Then the APNs secrets: `APNS_TEAM_ID`, `APNS_KEY_ID` and `APNS_KEY` (a topic-specific
production key for `com.sharkord.ios`, the whole `.p8` file), and `APNS_SANDBOX_KEY_ID` and
`APNS_SANDBOX_KEY` for development builds.

```bash
bun run deploy
```

Changing `TICKET_SECRET` voids every ticket. Servers forget the devices and the app gets new
tickets on its next launch.
