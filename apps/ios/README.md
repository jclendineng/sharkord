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
video, notifications, about with the server's contact), the full server settings (with who joined with each invite), polls, voice messages, and Discord's
attachment and expression panels (emoji, GIFs, stickers), typing indicators, pinning messages
and a channel's pinned list, a channel screen from its name (members, media, pins, links, files),
search in the expression panel at full height, a double tap reaction you pick, friends and friend requests, group direct messages, direct message menus (close, pin, mute for a while), profile banners, voice reactions, the soundboard (playing in calls, your own soundboard volume, and managing sounds with uploads and the server's library), moving people between voice
channels, a member's activity for moderators, posting locked where a private channel does
not allow it, Discord style Markdown in the composer (`HTMLText.messageHTML(fromMarkdown:)`,
turned back with `markdown(from:)` when editing) with lists, quotes, strikethrough and
underline drawn in messages, two-factor sign in (a code field after the password, and setup with
a QR code in Account settings), deleting your own account, turning off incoming video in the
voice sheet, a private channel's member column showing only who can see it, generated avatars,
webhook messages under their name, and for moderators an optional IP ban, password reset links
shared from a member's page, and the AFK channel in General settings. Calls send 1080p, with each tile asking for the quality it needs when the server has simulcast on; video continues in picture in picture; a signal badge shows ping and packet loss; the call sheet opens the system's Mic Mode and the app's own Video Effects sheet (reactions, Center Stage, Portrait and Studio Light status); a gear in the call opens its settings; long pressing someone in a voice channel opens their member menu with Move To; and tapping a tile in a call brings it to the front. An iPad beside the list takes the Mac's dropdown search, thread panel and full window settings. Messages light up while pressed, and a thread's first message can be edited and reacted to from the thread. Long pressing a channel or a category opens its menu (copy link, hide names in voice, edit, duplicate, mute or set notifications for a whole category, create a channel in it), a right click on a Mac. Not in the app: plugin slash commands, actions and plugin panels, which are web
only. See
[docs/features.md](../../docs/features.md) for what the server side of each needs.

[API_AUDIT.md](API_AUDIT.md) lists the iOS 26 and 27 SDK changes still to adopt, with the
deprecations the compiler reports.

## The composer's panels

The attachment panel and the expression panel take the keyboard's place under the
composer. They share one model, `AttachPanelModel`, and one frame, `ComposerPanel`: the panel
is exactly the keyboard's last height (`KeyboardMetrics`), so the two trade places with the
composer holding still, the screen ignoring the keyboard while they do. A drag up grows the
panel over the conversation, a drag down slides the composer and panel together as an
offset, so nothing is laid out again under the finger. `AnimatedImage` plays GIFs, APNGs and
animated WebPs, decoding frames off the main thread at the size they are shown.

## Voice and video

The server scopes `voice.onNewProducer` and `voice.onProducerClosed` to the voice channel a
socket is in at the moment it subscribes, so the app subscribes to both after each join and
stops them on leave (`subscribeToProducers`). Subscribed at connect they never sent anything,
and whoever spoke or turned a camera on after the app joined was never heard or seen.

The WebRTC factory always gets the default video encoder and decoder factories: the plain one
knows only H264 baseline, which left the phone unable to take a browser's VP8 or VP9. The phone
sends H264 baseline on purpose (`baselineH264`), the hardware encodes it and every browser
decodes it, where mediasoup's own pick would be the server's first codec, VP9, in software.

On a phone, joining or Open Call grows the voice sheet itself into the call, as Discord's does,
rather than covering it with a second screen. A sheet height picked through SwiftUI is jumped to,
so the call's detent is added first and then selected through the sheet's own
`UISheetPresentationController` in `animateChanges`, found by the name SwiftUI gives it
(`Custom:CallDetent`). The contents only learn the final height, so the call fades in on a timer
over the join box. The rise starts at the tap and the join runs under it; a failed join drops
the sheet back. A Mac and an iPad keep the full screen call.

## Screen sharing

`ScreenCapture` uses ScreenCaptureKit, which iOS 27 brought to the phone. The share button
shows the system picker, and once the screen is picked the app captures it itself with an
`SCStream`, sized to the stream quality setting, and hands each frame straight to the
`screen` producer, its orientation passed along as webrtc's rotation rather than drawn in. With
app audio on, the stream also captures the other apps' sound, converted to 48khz mono for
`MixingAudioDevice`. There is no broadcast extension any more.

The share keeps running with the app in the background only because `Info.plist` lists the
`screen-capture` background mode beside `audio`. Without it iOS stops the stream the moment the
app leaves the screen (`SCStreamErrorMissingBackgroundMode`).

## On a Mac

The app runs on the Mac as the iPad app. A Mac hands it a right click only as a context menu
request, never as a touch, so each row with a menu carries a view that answers that request
(`Helpers/SecondaryClick.swift`) and the window has one more for right clicks on nothing. The
menus themselves are the long press sheets drawn compact (`isPointerMenu`) in one layer over the
window (`PointerMenuLayer`), not system popovers: a popover's backdrop swallowed the next right
click and was slow to close. That layer also draws the submenus beside a menu and the hover
tooltips.

Whatever can be picked lights up under the pointer, so it is clear what a click will do. Rows use
`hoverHighlight()`, tiles and cards with a background of their own `hoverBrighten()`
(`Helpers/HoverHighlight.swift`), and a `List` `listHoverHighlight()`, which tints the cell
under the pointer through the list's collection view. The server rail squares an icon off and
shows a short pill instead, as Discord's does. A server menu and the search card close each
other, since they are drawn in separate layers.

Escape closes whatever is open: every sheet (`appSheet`), the menus, the composer's panels and
the search panel, and goes back from a thread or a channel's info (`escapeGoesBack`). A menu
item that opens a sheet hands it to the view that owns the menu, so the menu is gone before the
sheet shows rather than left open behind it.

Laid out the way Discord's Mac app is: the server's menu drops down under its name, server
settings take the whole window with the pages down the side, a thread opens in a panel beside
the chat in the member list's place, the plus by the message box is a short menu, and the emoji
picker keeps to its own width under its button. The member list grows with a wide window.
The user bar carries mute, deafen and settings, user settings fill the window like server
settings, and the message box has GIF, sticker and emoji buttons. Back and forward step through
the channels shown (`ServerListStore.visits`, ⌘[ and ⌘]). A channel's threads list drops down
from the top bar (`messages.getThreads`). Push to talk reads its key through the GameController
framework (`PushToTalk`), which sees a modifier held on its own even while typing. Voice & Video
picks the input and output device; Automatic uses a headset's or USB mic whenever
one is plugged in, kept to on every route change (`AudioInputPreference`).

## Sessions

Each sign in is a row in the server's `sessions` table, and its id rides in the token. The
Devices screen lists them and can sign one or all others out. The app renews its token on
every connect (`sessions.refreshToken`), so a device in regular use is never signed out by
the token's one week expiry.

## Servers under a subpath

A server behind a proxy at a path, `https://example.com/sharkord`, is entered with that path.
`ServerAddress` keeps it in `baseURL`, so every route, the socket and file links go under it,
and emoji stored as `/public/...` are appended to it rather than resolved against the host.

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

Who is talking comes from webrtc's own stats: four times a second `audioLevels()` reads the
`audioLevel` of each audio consumer's `inbound-rtp` entry and of the microphone producer's
`media-source`, and `SessionStore.speakingUserIds` lights anyone above a speech threshold for a
moment after they stop. The app mixes everyone into one playback device, so it cannot measure
each person's sound the way the web client's analysers do.

A lowered call is `VoiceBar` above the user bar on every device. It alone presents the call,
through `ServerListStore.isCallPresented`, with a zoom transition whose source is the bar, so
the call always grows out of it and shrinks back into it. A voice channel's sheet joins, puts
itself away and then sets the flag, since the bar cannot present while the sheet is up.

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
