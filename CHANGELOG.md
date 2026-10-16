# Changelog

Notable changes to this fork of [Sharkord](https://github.com/Sharkord/sharkord). The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

The iOS app has its own version numbers, starting at 0.1.0. The server and the web client keep
upstream's numbering, so a server release names the upstream version it is built on.

Everything here works with any server it is pointed at. Nothing is tied to one domain.

## [Unreleased]

Everything since the fork from upstream Sharkord 0.0.27 (2026-10-11).

### Upgrade notes

- Database migrations run by themselves at startup. This release adds tables for friends,
  group direct messages, private notes, the new member lounge, QR sign in and the soundboard.
  Upstream's plugin storage migrations run as this fork's `0060_plugin_storage`, after the
  fork's own, so a database that already ran `0059` still gets them.
- `0068_user_totp` adds the table that holds two-factor secrets, apart from users.
- `0067_channel_retention` adds a retention period to channels, off on every channel until
  set.
- `0066_password_resets` adds the table of reset links.
- `0065_webhooks` adds the webhooks table and the name a webhook posted under to messages.
- `0064_ip_bans` adds the table of banned addresses.
- `0063_afk_channel` adds the AFK channel and timeout to the settings table. AFK is off until
  an admin picks a channel.
- `0062_oidc_invite_code` adds a column to SSO sign ins in flight, for the invite they carry.
- `0061_grant_pin_dm_messages` gives the new Pin Messages in Direct Messages permission to
  every role that has Pin Messages. An iOS app from before it shows the roles screen without
  that permission; this release's app keeps permissions it does not know when saving a role.
- The soundboard's permissions are granted on upgrade: Use Soundboard to every role that can
  join voice, Manage Soundboard to every role that manages emoji.
- An iOS app from before the soundboard can't open the roles screen on an upgraded server,
  because it doesn't know the two new permissions. Update the app along with the server.
- On first start, existing uploads are renamed to random names and every file link becomes
  signed. Links handed out before the upgrade stop working once they expire.
- `storage.forceSignedUrls` in `config.ini` is gone, since links are now always signed. The
  server removes the old key.
- New `config.ini` options: `registration.inviteOnly` (sign ups by invite only), the Klipy
  key for GIFs, which can also be set with `SHARKORD_KLIPY_API_KEY`, and the Freesound key
  for sound search, `freesoundApiKey` under `[sounds]`.
- New `basePath` under `[server]` for running under a subpath. Set the proxy to forward that
  path and its WebSocket upgrades; it may strip the prefix or not.
- New `listenIp` under `[webRtc]` in `config.ini` (env `SHARKORD_WEBRTC_LISTEN_IP`), the
  address voice listens on. Set `::` for IPv6 as well as IPv4
  ([#522](https://github.com/Sharkord/sharkord/issues/522)).
- The server image is published to `ghcr.io/jclendineng/sharkord`.

### Added

#### iOS app

- A native iOS and iPad app, signing in to any server by its address, with push
  notifications, SSO and server passwords.
- Discord's layout: server rail, channel list and a floating user bar. On iPad the channel
  list and the chat sit side by side as two rounded cards in both orientations, and a handle
  slides the chat over the list to full width. Typing slides it over by itself.
- Discord's sign in screen over a night sky. Register only shows where the server takes new
  members.
- Sign in without typing a password by QR code, both ways:
  - A signed in device shows a code, and the new device scans it.
  - A device with no camera, such as a Mac mini, shows a code from **Log In With a QR Code**
    on the welcome screen, and a signed in phone scans and approves it.
- Alerts on your other devices when a new device signs in, opening the Devices screen.
- Invite links open the app on any server, through `sharkord://`.
- Message actions and composer like Discord's: reply, edit, react, forward, pin, mark unread
  and report.
- Discord's attachment panel, with a recent photos grid that trades places with the keyboard.
- An expression panel with emoji, GIFs and stickers. Animated GIFs and stickers play in
  messages.
- Voice channels with video, screen sharing from the phone (game audio included), voice
  reactions and moving members.
- The new messages bar, NEW line and jump to bottom button. Jumping to a message rings it
  with a soft glow.
- A media viewer, link previews with site icons, and files that open in Quick Look.
- A channel screen with members, media, pins, links and files tabs.
- Server settings in the app: channels, roles, per channel permissions, members, invites,
  emoji, stickers, storage, plugins and updates.
- Mute a channel or conversation for a while, and per channel notification levels.
- A warning before leaving the app through a link.

#### Messaging

- Polls.
- Voice messages that play in place, in the app and on the web.
- Server stickers and Klipy GIFs, in the app and the web client's picker.
- A soundboard like Discord's, in the app and the web client. Anyone in a call plays a sound
  for everyone there, and each person sets their own soundboard volume. Managers upload sounds
  or pick them from a library of free CC0 sounds by Kenney that comes with the server, and set
  each one's name, emoji and volume. Two new permissions, Use Soundboard and Manage
  Soundboard.
- With a Freesound API key, soundboard managers search freesound.org for more sounds, in the
  app and the web client. Only sounds free to reuse are shown, and a sound that asks for
  credit keeps it.
- Link previews for bare domains, previews from the server's own network when the admin
  allows it, and Discord style link cards.
- A new member lounge: reacting to the rules message gives the role that opens the server.

#### Direct messages and friends

- Friends, with requests and friend buttons on profiles.
- Group direct messages with up to ten friends.
- Close a direct message, hiding it until a new message arrives.
- The messages list shows each conversation's last message.
- Let people turn off new direct messages from others.
- Private notes on a member's profile, visible only to whoever wrote them.

#### Search

- Discord's search: filters (from, in, has, mentions, dates), and tabs for recent, members,
  media, pins, links and files.
- Search inside direct messages, with results that open at their message.
- `has:` video, poll and sticker.

#### Presence

- Availability (online, idle, do not disturb, invisible) and a custom status message. Do not
  disturb silences push notifications.
- A mentions inbox.

#### Accounts and security

- Device sessions: see where you are signed in and sign devices out.
- Push previews can leave out message text.
- A report address in server settings, used by Report in the apps.
- The app refuses plain `http` servers off the local network.

#### Web client

- Group direct messages and friends.
- GIF and sticker tabs in the picker, sticker settings and a Klipy key field.
- Signed file links refresh while the page is open.

- Members without a picture get an avatar drawn in colors from their id, the same on the
  web and in the app, instead of a gray circle
  ([#867](https://github.com/Sharkord/sharkord/issues/867)).
- Turn off incoming video, in the voice options on the web and the voice sheet in the app:
  cameras and screen shares stop reaching you at all, to save a weak connection
  ([#123](https://github.com/Sharkord/sharkord/issues/123),
  [#657](https://github.com/Sharkord/sharkord/issues/657)).
- In a private channel the member list shows only who can see it, with a switch back to
  everyone, on the web and in the Mac app's member column
  ([#458](https://github.com/Sharkord/sharkord/issues/458)).
- On the web, a new microphone or camera, or changed mic processing, applies to the call as
  soon as Devices settings are saved, without leaving and joining again
  ([#530](https://github.com/Sharkord/sharkord/issues/530)).
- Delete your own account, in user settings on the web and Account settings in the app. An
  account with a password confirms with it, and you choose whether your messages stay as
  Deleted User or go too. The server owner can't delete theirs
  ([#49](https://github.com/Sharkord/sharkord/issues/49)).
- An AFK channel, like Discord's: members silent in a call for the server's timeout (1 to
  60 minutes) are moved into it. Set in server settings on the web and in the app.
- A ban can also ban the person's IP addresses, chosen each time on the web and in the app.
  Their public sign in addresses are blocked from signing in, signing up and joining, and
  unbanning lifts it. Private addresses and the moderator's own are never banned
  ([#371](https://github.com/Sharkord/sharkord/issues/371)).
- Incoming webhooks: a channel's settings on the web make a URL other services post plain
  text to, shown under the webhook's name on the web and in the app
  ([#293](https://github.com/Sharkord/sharkord/issues/293)).
- Basic Markdown: strikethrough, underline, lists and quotes now survive sending instead of
  becoming plain lines. The app turns Discord style Markdown (`**bold**`, `*italic*`,
  `__underline__`, `~~strike~~`, `` `code` ``, code blocks, `- ` lists, `> ` quotes) into
  formatting when sending, shows all of it, and keeps it when editing
  ([#401](https://github.com/Sharkord/sharkord/issues/401)).
- Password recovery without email: a moderator makes a one time reset link from a member's
  page on the web or in the app and sends it however they reach them. It works for 24 hours,
  sets a new password on a page of its own and signs the account out everywhere
  ([#331](https://github.com/Sharkord/sharkord/issues/331)).
- Message retention per channel, in a channel's settings on the web: messages older than 1 day
  to a year are deleted every hour, pinned messages and threads still going kept. Before
  saving, the screen shows how many messages it would delete now. Their files go with the
  orphaned file sweep ([#564](https://github.com/Sharkord/sharkord/issues/564)).
- Two-factor authentication with an authenticator app, set up in Password settings on the web
  and Account settings in the app, with eight one time recovery codes. Signing in with a
  password then asks for a code on the web and in the app. Accounts that sign in through SSO
  leave it to their provider, and QR sign in, approved on a signed in device, is not asked. A
  moderator's password reset link turns it off
  ([#328](https://github.com/Sharkord/sharkord/issues/328)).
- Sharkord can run under a subpath behind a reverse proxy, like `example.com/sharkord`, with
  `basePath` under `[server]` in `config.ini` (env `SHARKORD_BASE_PATH`). At the root nothing
  changes ([#816](https://github.com/Sharkord/sharkord/issues/816)).
- Mute Stream Audio in Devices settings: screen shares with sound start muted
  ([#749](https://github.com/Sharkord/sharkord/issues/749)).

#### From upstream

- Hotkeys in the web client for mute, deafen, push to talk and more, set in a new Hotkeys
  settings tab. Hotkeys that work while the browser is in the background need upstream's
  bridge app.
- A wider plugin SDK: plugins can store data, add buttons and other parts under their
  messages, and take arguments in their commands.

### Changed

- Pinning in direct messages has its own permission, Pin Messages in Direct Messages. Roles
  that could pin keep it in direct messages
  ([#481](https://github.com/Sharkord/sharkord/issues/481)).
- A name another member already uses, whatever its case, can't be taken on rename
  ([#828](https://github.com/Sharkord/sharkord/issues/828)).
- An open voice channel chat follows you when you switch voice channels. It still never
  opens by itself ([#716](https://github.com/Sharkord/sharkord/issues/716)).

- File links are always signed. Uploads are stored under random names rather than their
  original ones.
- Link previews skip error pages and use only pictures the page itself declares.
- The iPhone app stays in portrait. Landscape is for the iPad.

### Fixed

- On a Mac, the chat's search is a box in its top bar, with the filter menu beside it, and
  the results drop down under it. The server search above the channel list opens the same
  card, as wide, so its tabs no longer scroll.
- On a Mac, settings rows light up under the pointer, as channels and messages do.
- The button that opens the system's settings says Settings on an iPhone or iPad and System
  Settings on a Mac, where it now opens the matching pane (Notifications, Camera, Photos)
  instead of the app's Touch Alternatives.
- On a Mac, the inbox under the bell has an X in its top left and closes with Escape. It
  opens as a sheet there, which a click outside never closed.
- The web client joins its call again after a dropped connection comes back, instead of
  showing a call the server had already ended, as the app already did
  ([#849](https://github.com/Sharkord/sharkord/issues/849)).
- Voice works in Firefox when `announcedAddress` is a hostname. The server sends the
  addresses it resolves the name to beside the hostname, which Firefox ignores
  ([#756](https://github.com/Sharkord/sharkord/issues/756)).
- An invite now works for SSO sign ups on a server closed to new users, as it does for
  password sign ups, on the web and in the app. Its role is given and its use counted
  ([#840](https://github.com/Sharkord/sharkord/issues/840)).
- Turning off Upload Files for a role no longer stops its members from setting an avatar or
  banner. Upload Files now only covers attaching files to messages
  ([#830](https://github.com/Sharkord/sharkord/issues/830)).
- Taking away Webcam or Share Screen in a channel, or making a channel private, turns off a
  camera or screen share already running there, on the web and in the app
  ([#869](https://github.com/Sharkord/sharkord/issues/869)).
- Sticker images are no longer swept up as orphaned files.
- Search names a direct message after its person or group, not "DM - 2:5".
- Signing out many devices in a row no longer hits a rate limit.
- Requests made straight after opening the app wait for its sign in to finish rather than
  failing as unauthenticated.
- On a Mac, opening pinned messages, or a sheet from channel info's toolbar, no longer crashes
  the app.
- On a Mac, the app shows up as macOS in Devices, login alerts and sign in approvals instead of
  as an iPad, and iPads get an iPad icon in Devices rather than a phone.
- On a Mac, no sheet crashes the app on opening anymore, the inbox under the bell among them.
- The mic test in Voice & Video settings no longer crashes the app, plays your voice back when
  Hear yourself is on, and keeps working with AirPods.
- The voice channel sheet no longer has its own invite button, which repeated the server invite
  already at the top of the channel list.
- On a Mac, the user bar sits inside the channel list's card instead of on the window's bottom
  edge.
- On a Mac, scrolling in a sheet no longer fades it out as if closing it.
- Sheets with no button of their own to close them get an X in the top left, as the profile has.
- On a Mac, sheets open centred in the window instead of pinned to its bottom edge.
- On a Mac, a right click opens a menu beside the pointer with what a long press opens:
  message, channel, conversation and server actions. Right clicking elsewhere moves the menu.
- The iOS app now needs iOS 27 or later.
- Screen sharing on the phone uses iOS 27's ScreenCaptureKit picker and captures inside the app,
  so frames go straight to the call instead of through a broadcast extension.
- The iOS app opens on the server as it was last seen, channels, avatars and server icons drawn
  at once, while it reconnects. Pictures are decoded at the size they are shown, and the
  requests after joining a server go out together instead of one after another.
- In the iOS app's server Overview, a new or removed icon shows as a preview and is only applied
  with Save, along with the other fields.
- On a Mac, the header's search opens Discord's dropdown under it, filters and results inside,
  and a result opens in the window as the dropdown closes.
- On a Mac, a server channel shows the member list down the right, online then offline, with a
  header button to hide it. A member opens their profile beside the list.
- Starting a screen share on the phone no longer crashes the app once something is picked to
  share, and the share keeps going after switching to another app instead of stopping.
- Joining voice from another device takes the seat over, as in Discord, instead of failing with
  "User already in a voice channel". The device that had it ends its call, and the iOS app
  shows a bar offering to reconnect there. A phone coming back from the background rejoins
  instead of being locked out, and a device that crashes or loses its connection leaves voice
  even when the account is still connected elsewhere.
- Long presses on channels and messages open their menu after the same 0.3 seconds as servers
  and conversations.
- Hear Yourself in calls plays your mic back to you, in the voice channel sheet's new Voice &
  Video settings (pulled up under Join Voice, with Deafen, audio output and noise suppression)
  and in Voice & Video settings.
- On the phone the voice channel sheet is Discord's: a short sheet with the channel and the
  join box, which a swipe up grows into the voice settings, the box becoming the sheet as it
  rises. A swipe down from there goes back to the short sheet, and only a swipe from the short
  one closes it.
- A call joined with AirPods or another headset connected plays through the headset instead of
  staying on the speaker when Use Speaker by Default is on, with Hear Yourself or app audio.
- On the phone and iPad a lowered call is Discord's floating tile, dragged anywhere and let go
  into the nearest corner, and tapped to open the call again. It replaces the voice bar above
  the user bar, which stays on the Mac.
- Whoever is talking gets Discord's green ring, on the call screen and under the voice channel
  in the channel list. The floating tile shows them without a ring.
- Lowering the call screen goes straight back to the channel list in one slide, instead of the
  voice channel sheet showing again on the way down.
- Jumping to a message from search or pins highlights it again, rather than only scrolling to
  it.
- A long press on a message's replies link opens only its menu, not the thread under it too,
  and Open Thread waits for the menu to close.
- The iOS app's messages load at launch instead of showing "You must be authenticated" until
  another channel was opened.
- On an iPad, the message bar sits level with the user bar beside it, and the top bar's pins
  and search stay in place while the chat slides over the list and back.
- On a Mac, the right click menus are Discord's: compact rows with an icon, opened at the pointer
  and moved there by the next right click, closed by a click anywhere else. Rows with more
  choices (Mute Channel, Notification Settings, Add Reaction) open them beside the menu as the
  pointer reaches them. Add Reaction and the reactions along the top lead with the emoji you
  use most, named as the pointer passes over them.
- On a Mac, hovering a message shows Discord's bar of quick reactions, Reply and More, and a
  channel lights up under the pointer.
- On a Mac, a server channel's top bar has a bell to mute the channel or pick which messages
  notify. Pins and search slide down from under the top bar instead of rising from the bottom,
  your profile opens above the user bar, and the member list shares the chat's background.
- On a Mac, the dark rail no longer shows a grey block under the title bar.
