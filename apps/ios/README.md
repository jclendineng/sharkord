# Sharkord for iOS

Native SwiftUI client. Open `Sharkord.xcodeproj` in Xcode and run the `Sharkord` scheme.
Requires Xcode 27+ and iOS 27+.

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
sign in, QR sign in both ways (scan a signed in device's code, or show one for it to scan when
there is no camera), server password, channel list with unread counts, an iPad landscape layout with the list and the chat side by side, a "new messages since" bar and NEW line that jump to the first unread message, a button back to the bottom, the new member lounge (Use as Rules Message), message history with pagination,
sending, live new/edited/deleted messages, auto reconnect, DMs, threads, reactions with emoji
picker, uploads, files opened in Quick Look with a preview of their first page, rich message rendering, push notifications, voice with webcams and watching
screen shares, sharing your own screen, profile editing, settings (account, devices, voice and
video, notifications), the full server settings, polls, voice messages, and Discord's
attachment and expression panels (emoji, GIFs, stickers), typing indicators, pinning messages
and a channel's pinned list, a channel screen from its name (members, media, pins, links, files),
search in the expression panel at full height, a double tap reaction you pick, friends and friend requests, group direct messages, direct message menus (close, pin, mute for a while), profile banners, voice reactions, moving people between voice
channels, a member's activity for moderators, and posting locked where a private channel does
not allow it. Not in the app: plugin slash commands, actions and plugin panels, which are web
only. See
[docs/features.md](../../docs/features.md) for what the server side of each needs.

## The composer's panels

The attachment panel and the expression panel take the keyboard's place under the
composer. They share one model, `AttachPanelModel`, and one frame, `ComposerPanel`: the panel
is exactly the keyboard's last height (`KeyboardMetrics`), so the two trade places with the
composer holding still, the screen ignoring the keyboard while they do. A drag up grows the
panel over the conversation, a drag down slides the composer and panel together as an
offset, so nothing is laid out again under the finger. `AnimatedImage` plays GIFs, APNGs and
animated WebPs, decoding frames off the main thread at the size they are shown.

## Screen sharing

`ScreenCapture` uses ScreenCaptureKit, which iOS 27 brought to the phone. The share button
shows the system picker, and once the screen is picked the app captures it itself with an
`SCStream`, sized to the stream quality setting, and hands each frame straight to the
`screen` producer, its orientation passed along as webrtc's rotation rather than drawn in. With
app audio on, the stream also captures the other apps' sound, converted to 48khz mono for
`MixingAudioDevice`. There is no broadcast extension any more.

## On a Mac

The app runs on the Mac as the iPad app. A Mac hands it a right click only as a context menu
request, never as a touch, so each row with a menu carries a view that answers that request
(`Helpers/SecondaryClick.swift`) and the window has one more for right clicks on nothing. The
menus themselves are the long press sheets drawn compact (`isPointerMenu`) in one layer over the
window (`PointerMenuLayer`), not system popovers: a popover's backdrop swallowed the next right
click and was slow to close. That layer also draws the submenus beside a menu and the hover
tooltips.

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

`Info.plist` allows plain http so a server on the local network or Tailscale can be reached
without TLS, but `ServerAddress.isInsecure` refuses plain http to anything else before
signing in or connecting.

## Tests

`SharkordTests` holds unit tests (Swift Testing) for what the app decodes from the server and
its logic: addresses and the plain http rule, search inputs and links, typing, HTML to text.
`SharkordUITests` signs in through the welcome and login screens and opens the main screens,
against a real server and account taken from the environment, so nothing is committed. It
only reads, it never posts, edits or deletes.

```bash
# unit tests
xcodebuild test -project Sharkord.xcodeproj -scheme Sharkord \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SharkordTests

# ui tests against a server, skipped when the variables are missing
TEST_RUNNER_SHARKORD_TEST_SERVER=chat.example.com \
TEST_RUNNER_SHARKORD_TEST_IDENTITY=someone TEST_RUNNER_SHARKORD_TEST_PASSWORD=... \
xcodebuild test -project Sharkord.xcodeproj -scheme Sharkord \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:SharkordUITests
```

Screenshots of every step are kept in the result bundle.
