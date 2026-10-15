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
  group direct messages, private notes, the new member lounge and QR sign in.
- On first start, existing uploads are renamed to random names and every file link becomes
  signed. Links handed out before the upgrade stop working once they expire.
- `storage.forceSignedUrls` in `config.ini` is gone, since links are now always signed. The
  server removes the old key.
- New `config.ini` options: `registration.inviteOnly` (sign ups by invite only) and the Klipy
  key for GIFs, which can also be set with `SHARKORD_KLIPY_API_KEY`.
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

### Changed

- File links are always signed. Uploads are stored under random names rather than their
  original ones.
- Link previews skip error pages and use only pictures the page itself declares.
- The iPhone app stays in portrait. Landscape is for the iPad.

### Fixed

- Sticker images are no longer swept up as orphaned files.
- Search names a direct message after its person or group, not "DM - 2:5".
- Signing out many devices in a row no longer hits a rate limit.
- Requests made straight after opening the app wait for its sign in to finish rather than
  failing as unauthenticated.
- On a Mac, opening pinned messages, or a sheet from channel info's toolbar, no longer crashes
  the app.
- On a Mac, the app shows up as macOS in Devices, login alerts and sign in approvals instead of
  as an iPad, and iPads get an iPad icon in Devices rather than a phone.
