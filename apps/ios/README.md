# Sharkord for iOS

Native SwiftUI client. Open `Sharkord.xcodeproj` in Xcode and run the `Sharkord` scheme.
Requires Xcode 26+ and iOS 18+.

Source files live in `Sharkord/`, which is a synchronized folder: new files added there
are picked up by the project automatically, no project file edits needed.

## How it talks to the server

- `POST /login` and `GET /info` over HTTP (`Networking/AuthAPI.swift`).
- Everything else over the tRPC v11 websocket (`Networking/TRPCClient.swift`): the url gets
  `?connectionParams=1`, the first frame carries `{ token }`, then `others.handshake` and
  `others.joinServer` before any protected procedure or subscription. The server uses no
  transformer, so payloads are plain JSON and the models in `Models/` mirror the types in
  `packages/shared`.

Procedure paths are strings (`"messages.send"`), so a renamed route on the server
breaks here at runtime, not at compile time.

## Status

Done: several servers at once (Discord style server rail, one socket per server), search
including direct messages, invite links, an inbox with mentions and unreads, sign in, OIDC
sign in, server password, channel list with unread counts, message history with pagination,
sending, live new/edited/deleted messages, auto reconnect, DMs, threads, reactions with emoji
picker, uploads, rich message rendering, push notifications, voice with webcams and watching
screen shares, sharing your own screen, profile editing, settings (account, devices, voice and
video, notifications).

## Screen sharing

`SharkordBroadcast` is a ReplayKit broadcast upload extension. It only forwards frames: each
one is shrunk to 1280px, encoded as a jpeg and sent over loopback tcp to the app, which is
already in the voice channel and publishes them as the `screen` stream. The app writes the
port and a random secret to a keychain group both targets share
(`$(AppIdentifierPrefix)com.sharkord.shared`), and the extension has to send that secret
first. A keychain group needs no setup in the developer portal, unlike an App Group.

## Sessions

Each sign in is a row in the server's `sessions` table, and its id rides in the token. The
Devices screen lists them and can sign one or all others out. The app renews its token on
every connect (`sessions.refreshToken`), so a device in regular use is never signed out by
the token's one week expiry.

## OIDC sign in

The app opens `/login/oidc` in an `ASWebAuthenticationSession` and the server redirects back
to `sharkord://oidc`. The browser's state cookie is not shared with the app, so the login is
bound to a PKCE style challenge the app sends up and proves with its verifier on exchange.

## Push notifications

Off by default. The server talks to APNs directly with the operator's own `.p8` key, there is
no push gateway, so the app has to be built and signed under the same team:

```bash
SHARKORD_PUSH_ENABLED=true
SHARKORD_PUSH_APNS_KEY_ID=...
SHARKORD_PUSH_APNS_TEAM_ID=...
SHARKORD_PUSH_APNS_KEY_PATH=/path/to/AuthKey.p8
SHARKORD_PUSH_APNS_BUNDLE_ID=com.sharkord.ios
```

The app registers its device token with every server after joining. Each push carries the
server's `serverId`, so a tap opens the right server. It is notified for direct messages,
mentions and replies, the same set the web client notifies for.

## Voice

`State/VoiceConnection.swift`, on top of
[mediasoup-client-swift](https://github.com/VLprojects/mediasoup-client-swift). One send
transport for the microphone, one receive transport for everyone else.

## Debug launch

In debug builds, `Helpers/DebugLaunch.swift` reads `SHARKORD_DEV_*` environment variables
so a simulator launch can sign in and open a tab or channel without typing (see the
comment in that file).

`Info.plist` allows plain http, since self-hosted servers often run without TLS.
