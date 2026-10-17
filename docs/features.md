# Features added in this fork

Everything here is on top of upstream Sharkord, built for the native iOS app in `apps/ios`
and, where it applies, the web client too. Each section says what it does, how an admin
turns it on, and where it lives in the code.

## iOS app

A native SwiftUI client in `apps/ios`, laid out like Discord's iPhone app: a server rail,
channels and direct messages, threads, replies, reactions, voice with video and screen
sharing, push notifications and the full server settings, so nothing needs the website. See
[apps/ios/README.md](../apps/ios/README.md) for how it talks to the server and how to build it.

The app only connects over HTTPS, apart from addresses on the local network (`10.x`,
`192.168.x`, `172.16` to `172.31`, `localhost`, `.local`, `.lan`, `.home.arpa`,
`.internal`) and Tailscale (`100.64.0.0/10`, `.ts.net`), which is already encrypted.

The same app runs on a Mac as the iPad app, with the desk in mind: a right click opens a
message's, channel's, conversation's or server's menu beside the pointer, header buttons
(pins, the inbox) open popovers, search drops down from its box, and a server channel shows
the member list down the right. Sheets there close with their own buttons or an X rather than
a swipe, which a trackpad scroll would set off by mistake (`Helpers/AppSheet.swift`,
`Helpers/SecondaryClick.swift`, `Views/MembersColumn.swift`).

The app opens on each server as it was last seen, from the last join kept on disk
(`State/JoinSnapshot.swift`), so channels, avatars and icons are there before the server has
answered.

## Push notifications

The server sends to Apple's push service directly with the operator's own key. Off until
configured:

```bash
SHARKORD_PUSH_ENABLED=true
SHARKORD_PUSH_APNS_KEY_ID=...
SHARKORD_PUSH_APNS_TEAM_ID=...
SHARKORD_PUSH_APNS_KEY_PATH=/path/to/AuthKey.p8
SHARKORD_PUSH_APNS_BUNDLE_ID=com.sharkord.ios
```

A push goes out for direct messages, mentions, replies, and every message in a channel set to
notify for all. Do not disturb silences every device.

**Show message text** (Server Settings, Overview, Push Notifications) is on by default. Off,
a notification only says who sent something, never what it says or where, so the text never
passes through Apple. Setting: `pushShowMessageContent`.

Code: `apps/server/src/utils/apns.ts`, `apps/server/src/queues/push-notifications`,
routes `notifications.registerDevice` and `notifications.unregisterDevice`.

## Per channel notifications

Each member picks All messages, Only mentions or Nothing for any channel or direct message.
Routes `notifications.getChannelSettings` and `notifications.setChannelSetting`, table
`channel_notification_settings`.

## Devices

Every sign in is a session. Settings, Devices lists them with where and when they were last
used, and can sign one out or all the others. Routes `sessions.getAll`, `sessions.revoke`,
`sessions.revokeOthers`, `sessions.refreshToken`, table `sessions`.

## Status

Online, idle, do not disturb or invisible, and a custom status message. Routes
`users.getPresence` and `users.setPresence`, columns `users.presence` and
`users.custom_status`.

## Direct message privacy

A member can turn off new direct messages from people they have no conversation with.
Routes `users.getPrivacy` and `users.updatePrivacy`, column `users.allow_direct_messages`.

## Mentions inbox and mark unread

`messages.getMentions` pages through the messages that mention you, and
`channels.markAsUnread` marks a channel unread from a given message, like Discord's long
press option.

## Search

Discord's filters: `from:`, `in:`, `mentions:`, `has:`, `before:`, `after:` and `during:`.
`has:` takes `image`, `video`, `link`, `file`, `poll` or `sticker`. The server searches
direct messages too; the app keeps them to the search in the messages panel, as Discord does,
and its server search shows channels only (dropped in the app, so an older server still
works). A message found by its picture shows the picture. In the app, picking a filter puts its token in the search box with the choices
listed under it. Searching from a channel or a direct message starts with an `in:` filter
for it, which can be removed to search everything; searching from the server's channel
list covers the whole server. Route `messages.search`.

Before anything is typed, the app shows Discord's tabs: Recent (the busiest channels with
when each was last active, and the latest photos and media), Members, Channels, Media,
Links and Files. Opened from a channel they cover just that channel, with Pins in place of
Channels and Members narrowed to the people who can see it. Routes `channels.getActivity`
(when each visible channel last had a message) and `channels.getMembers` (who can see a
channel), plus `messages.search` and `messages.getPinned`.

## Files in the app

A file attached to a message opens on the phone in Quick Look, not in a web page: PDFs,
Office and iWork documents, text, video and audio, with Quick Look's share and save. It is
downloaded once into the app's cache. A file of 10 MB or less shows its first page as a preview
above its name, drawn by Quick Look from that same cached copy. A pinned GIF shows the GIF in the
pinned list, not its link.

Tapping a channel's name at the top of the chat opens its screen, as in Discord: search,
notification settings and, with Manage Channels, the channel's settings, then tabs for its
members (with an invite row), media, pins, links and files. The emoji a double tap on a
message reacts with is set from the Edit link in the message menu and kept on the phone.
Searching for an emoji, GIF or sticker takes the panel to full height with the keyboard over
its bottom, so the results scroll in between.

A link in a message shows a preview card with the page's picture, title and site, like
iMessage, from the preview the server fetched. A bare domain such as `example.com` counts as a
link and gets `https://`, both when the app sends it and when the server looks for links to
preview. The Links tab and `has:link` search include messages whose only link is a bare
domain, and the Media tab and `has:image` include GIFs and pictures shown from links. Pinned
messages show their attachments, and tapping a member in a channel's Members tab opens their
profile with a Message button. Avatars are kept in memory by file id, so they no longer blank
out while a screen is rebuilt.

A channel's Files and Links tabs are grids of cards, as in Discord: a preview (the picture, a
video's first frame, a document's first page, or a page's preview picture), the name or title,
the size or site, who posted it and the channel. Files lists every file, pictures and videos
included, and `messages.search` returns who posted each file it finds.

Media in a channel's tabs opens a full screen viewer, as in Discord: swipe between pictures and
videos, a strip of the channel's media along the bottom, and a menu to save to Photos, share,
open in the browser or jump to the message. Files, links and pins jump to their message too:
the chat loads the messages around it (`messages.get` with `targetMessageId`), scrolls to it
and lights it up, with a Jump to Present bar while it shows older messages. A link to anywhere
other than the servers you are signed in to asks first ("Leaving Sharkord"), with a box to trust
the domain from then on. Long pressing a message puts the keyboard away and never also opens a
link or file under the finger.

A long press on a conversation in the app's Messages list opens Discord's menu: the person's
profile, Close DM, pin it to the top, mark it read, mute it. Closing (`dms.close`) hides the
conversation from your own list until a message newer than the close arrives or you open it
again, the other person's list and the messages are untouched. Tapping a direct message's name
opens the same screen as a channel's, with the person's avatar, their two members, and the
conversation's media, pins, links and files.

In a call the app's camera captures 1080p at 30 frames a second, in a format the system's
Portrait and Studio Light effects support where the camera has one (the app opts in with
`NSCameraPortraitEffectEnabled`, `NSCameraStudioLightEnabled` and `NSCameraReactionEffectsEnabled`,
since it is not a VoIP app). It sends one H.264 stream: three VP8 layers for simulcast were
tried, and the bundled WebRTC (m120) encoded no frames in any of them, so the picture reached
nobody. Each frame is tagged with its rotation from the device orientation, read when the camera
starts rather than taken as upright until the first turn. Apple's rotation coordinator answered
0 degrees on an upright iPhone, so it is not used. Each video
tile reports how many pixels tall it is drawn, and the app asks `voice.setConsumerQuality` for the
lowest layer that fills the tallest tile (up to 270 lines the low one, up to 540 the middle, above
that auto). A screen share always asks for its sharpest. Leaving the app with someone else's video
in the call opens picture in picture (a screen share first, then whoever else is talking, then
anyone's camera), started from the voice bar, drawn through a sample buffer layer since WebRTC's Metal view
stays blank there. The call headers show signal bars from the connection's round trip and the
packets lost in the last two seconds, with the numbers on a tap. The call sheet opens the
system's Mic Mode panel and the app's own Video Effects sheet: the camera's preview, a grid of
reactions played with `performEffect(for:)`, Center Stage switched in the cooperative control
mode, and Portrait and Studio Light shown as on or off (apps can only read those two, so a row
opens the system panel to change them). Hand gestures play reactions too, since the camera picks
the 1080p format supporting the most of reactions, Portrait and Studio Light. In dim light the
camera may lower its frame rate to 24 so each exposure runs longer, with low light boost where
the phone has it. A gear in the call header opens the call's settings: tiles for Deafen, Output
and incoming video, then audio and video cards. Leaving a call lets its sheet slide away before the
call is torn down. A lowered call is the voice bar above the user bar on every device, and the
call zooms out of the bar and back into it, joining from a voice channel's sheet included. Each person under a voice
channel is a row of its own: a tap opens their profile, a long press the member menu, which in a
voice channel adds Move To for anyone with Move Members. The Voice & Video settings page follows
the sections of Discord's, and its noise suppression footer says whether the system's Voice
Isolation is on (`AVCaptureDevice.activeMicrophoneMode`), with a button to the Mic Mode panel in a
call.

In a call, tapping a person's tile or a screen share fills the call with it, the rest in a strip of
thumbnails under it; tapping the big tile or its collapse button goes back to the grid.

An iPad showing the list beside the chat takes the Mac's desktop layout (`usesDesktopLayout`):
search drops down under the box it came from, threads open in a panel beside the conversation
(up to 45% of the chat's width, from 640 points of chat), and settings fill the window. In
landscape without a hardware keyboard (`GCKeyboard`) search stays full screen, since the screen's
keyboard covers half of it. Pins open as the top bar's panel on every device. A message lights up
under the finger as it is held, a rounded card a few points past it on every side. A thread's
first message is read live from its channel and takes the list's menu and double tap reaction
through the environment (`showMessageActions`, `reactToMessage`).

A long press on a channel opens its menu: invite, pin it to the top, copy its link, mark it read,
mute it, its notification settings, and for anyone who can manage channels, edit or duplicate it.
The link is `sharkord://channel?server=…&channel=…`, which the app opens on any server it is
signed in to; only text channels have one. A voice channel's menu can hide the names under it,
leaving only the faces, kept per channel on the device. A long press on a category opens the
same kind of menu for every channel in it: mark them read, mute them for a while, set their
notifications, and for managers rename or delete the category and create a channel in it. Muting
a category mutes each of its channels, so any one can still be changed on its own.

Muting a conversation or a channel in the app asks how long, as Discord does: 15 minutes, 1, 3,
8 or 24 hours, or until it is turned back on. `notifications.setChannelSetting` takes
`muteForMinutes` with the `none` level and stores when the mute ends; past that, push and
`getChannelSettings` treat the channel as back on its default. A muted conversation shows a
crossed out bell in the Messages list.

Friends, as in Discord: ask someone (`friends.request`), they accept (`friends.accept`) or
ignore it, and `friends.remove` unfriends, cancels a request you sent or declines one you got.
Asking someone who already asked you makes you friends straight away. `friends.get` lists your
friends and the requests waiting on either side, and `friends.onUpdate` tells both people when
anything between them changes. In the app, your friends sit in a row at the top of Messages,
each opening your conversation with them, next to search, Add Friends (requests, sent ones,
and everyone on the server to ask) and a new message. A profile shows Add Friend, Accept
Request, Pending or Friends beside its message button. The Messages list shows each
conversation's last message, "You:" when it was yours.

Group direct messages, as Discord's: you and up to nine friends in one conversation
(`dms.createGroup`). Anyone in it can add their friends up to ten people (`dms.addGroupMembers`),
rename it or clear the name back to listing its people (`dms.renameGroup`), and leave
(`dms.leaveGroup`); the last one out removes it. A group is a direct message channel like any
other, so privacy, search in DMs, pushes and read states treat it the same, and only its members
can see it. `dms.get` marks a group conversation with its name and members. In the app, New Group
is in the new message sheet, and a group's screen has Add Friends, Rename Group and Leave Group.

The web client has the same: the direct messages list shows each conversation's last message and
groups by name, with Add Friends (add by username, requests, sent, friends and everyone else on
the server) and New Group beside the new conversation button. Right clicking a conversation offers
Mark As Read, Mute, Close DM, and for a group Add Friends, Rename Group and Leave Group. A user's
popover has a friend button that sends, accepts, cancels or removes, and a conversation's header
shows its name and, for a group, how many people are in it.

Search from the Messages panel covers your direct messages only ("Search in DMs"), as Discord's:
`messages.search` takes `scope: 'directMessages'`, which narrows where it looks but is not a
filter by itself. Its tabs are Recent, People (the people you have conversations with), Media,
Pins (every conversation's pins), Links and Files, and a result opens at its message.

Link previews are not fetched from private addresses, so no member can make the server load
pages only it can reach. A server on a home network can allow it with **Preview Links on the
Server's Network** in Server Settings, General, mirrored in config.ini as
`previewPrivateNetwork` under `[links]`. A preview is fetched when a message is sent, so turning
it on does not add previews to older messages. When it is on, devices on that network may use
self signed certificates and hosts without a domain (`http://nas:8080`). Every redirect is checked
again, so a public page cannot send the server inward.

The app's invite sheet sets how long a link lasts (1 hour, 1 day, 7 days or never) and how many
times it can be used, replacing the link it showed before.

Uploaded files are stored under a random name (a uuid and the file's extension), never the
name they were uploaded with, which is kept for display and downloads, and served from
`/public/<name>`. Files uploaded before this are moved to random names when the server starts
(`helpers/rename-stored-files.ts`), once. Every file link carries a token that expires and is
only handed to someone who can see the file, always: there is no switch to turn it off. The
server logo is the one file served without a token, since it shows before anyone signs in. How
long a link lasts is in Server Settings, Storage.

A signed link only works for its lifetime, but no one has to reload for that. Every time the
server sends a file (with its messages, a user, an emoji) it signs a new link. The web client
and the app also keep the links of files they show fresh while open: a little before a link
runs out they ask `files.sign` for new ones, and swap them in once the old ones have run out,
so nothing already on screen loads again. `files.sign` answers only for files the caller can
see (avatars, banners, emoji, stickers and the logo for anyone signed in, attachments and
reaction files when the caller can see the channel) and leaves everything else out.

## Voice messages

A recording from the app goes up as an audio file and plays in place in the message, in the
app and on the web.

## Polls

A poll is a message of its own: a question of up to 300 characters, up to 10 answers of up
to 55 characters each with an optional emoji, one answer or several, and a length from 1
hour to 2 weeks. Anyone who can see the channel can vote, the author or anyone who can manage
messages can end it early. Not available inside threads, as on Discord.

Routes `polls.create`, `polls.vote`, `polls.end`. Tables `polls`, `poll_answers`,
`poll_votes`. A message comes back with its `poll`, answers and voters included. Bounds in
`packages/shared/src/statics/polls.ts`.

## Stickers

Server stickers like Discord's: PNG, APNG, GIF or WebP, 512 KB at most, a name of 2 to 30
characters and an optional description. Admins with Manage Emoji add, rename and delete them
in Server Settings, Stickers. Every member gets them on join and through live events, and
sends them from the Stickers tab of the expression picker. A deleted sticker leaves its
messages behind showing it is gone.

Routes `stickers.add`, `stickers.update`, `stickers.delete`, `stickers.getAll` and the
`onCreate`, `onUpdate`, `onDelete` subscriptions. Table `stickers`, column
`messages.sticker_id`. Bounds in `packages/shared/src/statics/stickers.ts`.

## Soundboard

Discord's soundboard. Anyone in a call with Use Soundboard plays a sound from the call's
controls, and everyone in that call hears it. Each app plays the sound itself, at the sound's
volume times that person's soundboard volume, so it never goes into anyone's mic and a
deafened member does not hear it.

Members with Manage Soundboard add sounds in Server Settings, Soundboard, two ways:

- **Upload:** MP3, WAV or M4A, 512 KB at most. There is no transcoding, so the size is what
  keeps a sound short.
- **Library:** the server ships with a library of CC0 sounds from
  [Kenney](https://kenney.nl), embedded in the binary. Picking one copies it into storage, and
  from then on it is a sound like any other. Each library sound can be added once.

- **Freesound search:** with a [Freesound](https://freesound.org) API key, managers search
  freesound.org from the same screen. Get a free key at
  [freesound.org/apiv2/apply](https://freesound.org/apiv2/apply) (the client secret is the
  key) and paste it into Server Settings, Overview, Freesound API Key, or into
  `freesoundApiKey` under `[sounds]` in `config.ini`. Only CC0 and CC BY sounds of 10 seconds
  or less are shown. Adding one looks it up again by id, downloads its MP3 preview from
  freesound into storage, and keeps a credit (title, maker, license) on the sound. Searches go
  through the server, so the key never reaches members and stays out of the activity log.

Each sound has a name of 2 to 32 characters, an optional emoji and a volume from 0 to 100.
The migration grants Use Soundboard to every role that can join voice, and Manage Soundboard
to every role that manages emoji.

Routes `soundboard.add`, `soundboard.addFromLibrary`, `soundboard.update`,
`soundboard.delete`, `soundboard.getAll`, `soundboard.getLibrary`, `soundboard.searchFreesound`,
`soundboard.addFromFreesound`, the `onCreate`, `onUpdate`,
`onDelete` subscriptions, `voice.playSound` (rate limited by `rateLimiters.soundboardPlay`)
and `voice.onSound`. HTTP `GET /soundboard-library/<key>.m4a` serves a library sound to
preview without signing in. Table `soundboard_sounds`, column `settings.freesound_api_key`,
config `sounds.freesoundApiKey`, public flag `soundSearchEnabled`. Bounds and the library list in
`packages/shared/src/statics/soundboard.ts`, audio in `apps/server/src/soundboard-library`.

## GIFs

The GIFs tab of the expression picker searches [Klipy](https://klipy.com), the provider
Discord uses. To turn it on, get a free API key at
[klipy.com/developers](https://klipy.com/developers) and paste it into Server Settings,
Overview, Klipy API Key, or into `klipyApiKey` under `[gifs]` in `config.ini` (see Settings
in config.ini).

Searches go through the server, so the key never reaches members and stays out of the
activity log. Klipy sees one hashed id per member and server, not who anyone is. A GIF is
sent as its link, which the apps show as the GIF alone.

Routes `gifs.categories`, `gifs.trending`, `gifs.search`. Column `settings.klipy_api_key`, config `gifs.klipyApiKey`,
public flag `gifsEnabled`. Code `apps/server/src/utils/klipy.ts`,
`apps/server/src/helpers/gifs.ts`.

## Report address

Server Settings, Overview, Report Email. The apps' Report action on a server or a message
opens an email to this address, with the server, channel and message filled in. It is
published in `/info` so a report can be sent without an account. Setting `reportEmail`.

## Role order

Roles are ordered as Discord's: the owner's role on top, the default role at the bottom, and
the ones between in the order an admin with Manage Roles arranges them (`roles.reorder`, a
`position` on each role). The web client's Roles list drags; the apps have Reorder, with arrows
on a Mac. A new role starts at the bottom. A member's roles are listed in that order, the first
with a colour colours their name, and the apps' member list groups people under it in that order.

## Pinned channels

Pin Channel to Top on a channel or a conversation in the apps puts it in a Pinned group above
the rest, in the order pinned. Pins belong to the account (`channel_pins`), so every device shows
the same ones, and the others move as soon as one pins or unpins (`channels.onPinsUpdate`). A
deleted channel takes its pins with it. Against a server from before this, pins stay on the device.

## About

User Settings, About, in the web client and the apps: the version, the server's name, the
server's report address as its contact when one is set, and links to the source and its issues
for problems with the app itself. The apps also show their build and the server's version,
which `joinServer` returns as `serverVersion`; `/info` still leaves the version out for anyone
not signed in.

## AFK channel

Server settings, General, AFK Channel and AFK Timeout (`afkChannelId`, `afkTimeoutSeconds`,
1 to 60 minutes, five by default). Each voice runtime's router has an audio level observer on
every microphone, and speaking above about -55 dB, joining or changing your voice state marks
you active. Every 30 seconds `crons/move-afk-users.ts` moves whoever has been inactive for the
timeout into the AFK channel with the same `moveVoiceUser` a moderator uses, so the apps follow
it as they follow any move. Direct message calls and the AFK channel itself are left alone, and
a deleted or no longer voice channel turns AFK off. Muting counts as silence, as on Discord.

## Incoming webhooks

Channel settings, Webhooks (Manage Channels). A webhook gets a URL,
`/webhooks/<id>/<token>`, shown once, since only a hash of the token is kept. Another service
posts JSON to it:

```json
{ "content": "Build passed", "username": "CI" }
```

`content` is plain text up to 4000 characters, a paragraph a line, with links made clickable;
nothing is read as HTML. `username` (up to 32) replaces the webhook's name on that message. The
message is stored with `webhook_name` and no user, so renaming or deleting the webhook leaves its
old messages as they were, and the apps show it with the APP tag. A wrong id and a wrong token both
answer 404, posts are rate limited per address (`rateLimiters.webhook`), and deleting the channel
deletes its webhooks. Code `apps/server/src/http/webhook.ts`, `helpers/webhooks.ts`
([#293](https://github.com/Sharkord/sharkord/issues/293)).

## Message retention

Channel settings, General, Delete Old Messages (`channels.retentionDays`, 1 to 3650 days, off
by default). Every hour `deleteExpiredMessages` (`helpers/message-retention.ts`) deletes the
channel's messages older than that, in batches of 500 so the server is never held up. Pinned
messages are kept, and so is the first message of a thread with a reply newer than the cutoff,
since deleting it would take the replies with it. The files of deleted messages become orphans
the 15 minute file sweep already removes. The dry run: while picking a period, the screen calls
`channels.getRetentionPreview`, which counts what would go if it ran now. Direct messages have
no retention ([#564](https://github.com/Sharkord/sharkord/issues/564)).

## Two-factor authentication

RFC 6238 codes (SHA1, 30 seconds, 6 digits) from any authenticator app, implemented in
`utils/totp.ts` with no extra dependency. `users.startTwoFactor` makes a secret and an
`otpauth://` link (the app shows it as a QR code, the web as a key to type in and a link that
opens an authenticator), `users.confirmTwoFactor` turns it on with a first code and returns
eight recovery codes once, and `users.disableTwoFactor` needs a current code. Secrets live in
`user_totp`, never on the user row, recovery codes only as hashes.

`/login` checks the password first and only then answers `totp` with "Enter the code from your
authenticator app.", so a wrong password never reveals the account has two-factor. A code is
accepted one step either side of now and never twice; a recovery code is spent when used. SSO
accounts cannot turn it on, since their provider is where they sign in. QR sign in and login
links are approved on a device already signed in and are not asked. A moderator's password
reset link turns it off, the way back for someone who lost their authenticator and its codes.
Not yet: a server setting that makes it required
([#328](https://github.com/Sharkord/sharkord/issues/328)).

## Permissions and settings from upstream issues

- **Pin messages in direct messages** (`PIN_DM_MESSAGES`): pinning in direct messages and
  group conversations has its own permission, so members can pin there without pinning in
  channels. `messages.togglePin` checks it when the message's channel is a direct message.
  On upgrade every role that could pin messages gets it, so nothing changes until an admin
  turns it off ([#481](https://github.com/Sharkord/sharkord/issues/481)).
- **Mute Stream Audio** (web, Settings, Devices): screen shares with sound start muted for
  you, each one unmuted from its own volume control. Kept in the browser's device settings
  ([#749](https://github.com/Sharkord/sharkord/issues/749)).
- **Invites with SSO**: `/oidc/login?invite=<code>` carries the code through the provider
  (stored with the login in `oidc_transactions.invite_code`). A new account made through SSO
  then gets in on a closed server, takes the invite's role and counts a use, as a password
  sign up does. The web client passes the page's `?invite=` along, and the app sends the
  invite link pasted or opened on the sign up screen
  ([#840](https://github.com/Sharkord/sharkord/issues/840)).
- **Generated avatars**: a member with no picture and no profile color of their own gets a
  two tone gradient whose hue comes from their id, `getAvatarGradient` in `packages/shared`,
  mirrored in the app's `AvatarView` ([#867](https://github.com/Sharkord/sharkord/issues/867)).
- **Turn off incoming video**: a viewer's switch (voice options on the web, the voice sheet in
  the app) that skips consuming cameras and screen shares and closes the ones already received
  through `voice.closeConsumer`, so they stop using the connection. Turning it back on consumes
  what is running then ([#123](https://github.com/Sharkord/sharkord/issues/123),
  [#657](https://github.com/Sharkord/sharkord/issues/657)).
- **Member list per channel**: in a private channel the member list shows who can see it,
  from `channels.getMembers`, and a header switch shows everyone again. Public channels are
  open to all, so their list is unchanged ([#458](https://github.com/Sharkord/sharkord/issues/458)).
- **Devices apply mid call** (web): saving a new microphone, camera or mic processing setting
  during a call restarts the mic, or the camera when it is on, through the join path, so the
  new device and processing chain take over with a short gap for the others. Screen share
  settings still apply from the next share ([#530](https://github.com/Sharkord/sharkord/issues/530)).
- **Delete your own account** (`users.deleteOwn`): confirmed with the password when the
  account has one, refused for the server owner. `wipe` removes messages, reactions and
  uploads, otherwise they move to the Deleted User placeholder, the same steps as an admin's
  delete in `helpers/delete-user-account.ts`. The account's connections close just after the
  reply ([#49](https://github.com/Sharkord/sharkord/issues/49)).
- **IP bans** (`users.ban` with `banIps`): a choice on every ban. Every public address the
  account signed in from (the `logins` table) and the one it is connected from go into
  `ip_bans`. Private and loopback addresses are never banned, since behind a proxy that does
  not pass the real address on that address is everyone's, and neither is the moderator's own.
  A banned address is refused at `/login` (so no new account either), at the SSO callback and
  at `others.joinServer`. Unbanning the account removes its addresses; deleting the account
  keeps them banned ([#371](https://github.com/Sharkord/sharkord/issues/371)).
- **Basic Markdown**: the server keeps `s`, `u`, `ul`, `ol`, `li` and `blockquote`, which it
  used to flatten, so what the web editor's Markdown shortcuts make stays formatted. The app
  converts Discord style Markdown to the same HTML when sending (`HTMLText.messageHTML(fromMarkdown:)`),
  back to Markdown when editing, and draws lists and quotes. A single `*` or `_` against a
  word character stays as typed, so `snake_case` and `2*3*4` are not italics
  ([#401](https://github.com/Sharkord/sharkord/issues/401)).
- **Password reset links** (`users.createPasswordReset`, Manage Users, not on the owner unless
  by an owner): there is no email, so a moderator makes a link, `/?reset=<token>`, and passes it
  on. Only a hash of the token is kept, a newer link replaces an older one, and it lasts 24
  hours. The web page it opens posts to `/password-reset`, which sets the password, marks it set
  (an SSO account can then sign in with it too), bumps the token version and deletes the
  account's sessions ([#331](https://github.com/Sharkord/sharkord/issues/331)).
- **Unique names**: renaming to a name another member already uses, ignoring case, is
  refused. Names two people already shared before the upgrade stay, and a name from an SSO
  provider that is taken becomes a generated one
  ([#828](https://github.com/Sharkord/sharkord/issues/828)).

## Web features in the app

The app also has what the web client does with routes that predate this fork: typing
indicators (`messages.signalTyping`, `messages.onTyping`), pinning messages and the pinned
list (`messages.togglePin`, `messages.getPinned`), profile banners (`users.changeBanner`),
voice reactions (`voice.sendReaction`, `voice.onReaction`), moving someone to another voice
channel (`voice.moveUser`), a member's logins, files and messages for moderators
(`users.getInfo`), live server settings (`others.onServerSettingsUpdate`) and channel
permissions (`channels.onPermissionsUpdate`), which lock the message box where a private
channel does not allow posting. Plugin commands, actions and panels stay web only.

## Settings in config.ini

Four settings live both in the settings screens and in `config.ini`, and either side changes
the other:

```ini
[registration]
allowNewUsers=false

[links]
previewPrivateNetwork=false

[gifs]
klipyApiKey=your-key

[sounds]
freesoundApiKey=your-key
```

Saving the settings screens writes these into the file. Editing the file is picked up at
startup and also while the server runs, without a restart: the change is applied to the
database and pushed to everyone connected, so the screens show it straight away.

`allowNewUsers=false` makes the server invite only: a new account needs an invite from someone
with Manage Invites, through a password or single sign on, and the apps say registration is
closed. `previewPrivateNetwork` lets link previews load pages on the server's own network.

What was last written is recorded in `config-sync.json` next to `config.ini`, so a value that
differs from it is known to be an edit. The `inviteOnly` key from an earlier version of this
fork is carried over once and then replaced, and the old `signedUrls` and `forceSignedUrls` keys
are removed, since file links are always signed. Code
`apps/server/src/helpers/config-file-sync.ts`.

## Running under a subpath

```ini
[server]
basePath=/sharkord
```

Env `SHARKORD_BASE_PATH`. The server strips the prefix from every request, so a proxy that
passes `/sharkord/...` through and one that strips it both work, and `/sharkord` redirects to
`/sharkord/`. SSO's callback and its return to the web client carry the prefix. The web client
is built with relative paths and works out its base from the page's own address, so the same
build runs at the root and under any path; custom emoji, stored as `/public/...` paths, are
made absolute when shown. The manifest's icons and start URL are relative. In the app, enter
the full address, `https://example.com/sharkord`. The proxy has to forward WebSocket upgrades
on that path too. Voice still uses its own port, `webRtc.port`
([#816](https://github.com/Sharkord/sharkord/issues/816)).

## Voice networking

```ini
[webRtc]
announcedAddress=voice.example.com
listenIp=::
```

`announcedAddress` may be a hostname. Chromium and the app resolve it themselves, which is
what lets split DNS send people on the local network to the LAN address. Firefox refuses
hostname candidates (RFC 8839), so the server also sends each address it resolves the name
to, after the hostname, and Firefox connects through those. Behind split DNS the server sees
its own side of it, so Firefox outside the network still needs the public address to resolve
for the server ([#756](https://github.com/Sharkord/sharkord/issues/756)). Code
`apps/server/src/utils/resolve-ice-candidates.ts`.

`listenIp` (default `0.0.0.0`, env `SHARKORD_WEBRTC_LISTEN_IP`) is the address voice listens
on. `::` takes IPv6 as well as IPv4 on a host where IPv6 is set up; a container without it
fails to bind `::` and has no voice, which is why it is not the default
([#522](https://github.com/Sharkord/sharkord/issues/522)).

## Server settings in the app

Overview, roles, members, invites, channels with per channel permissions, emoji, stickers,
storage and plugins (marketplace, settings, who can use them, logs) are all in the
app, each shown only to people with the permission for it. They use the same routes as the
web client.

## Running the fork

The fork's server image is built from the `push` branch on every push and published as
`ghcr.io/jclendineng/sharkord:push` (`.github/workflows/fork-image.yml`).

A new member lounge, as Discord's rules screening: an admin picks a message with the rules
(**Use as Rules Message** on a message, needing Manage Settings) and the role reacting to it
gives (`others.setOnboarding`). The server puts a ✅ on the message to tap, and can give the role
to everyone already there so nobody is locked out. Open the server's channels to that role and
hide them from everyone else in each channel's permissions: a new member then lands in the rules
channel, the only one they see, and the rest appears as soon as they react. Taking the reaction
back keeps the role. The rules message says what reacting does, the owner's role and the default
role cannot be the one given, and deleting the message turns the lounge off.

The setup can do the channel work too. **Close other channels to new members** makes every
other public channel private, open to every role except the default one (a channel already
private keeps its permissions), so the default role sees only the rules. **Take away the
default role once they react** swaps it for the given role, for a default role that only means
"not in yet" (`onboardingRemovesDefaultRole`, off unless chosen, since a default role can carry
everyday permissions). A public channel's Permissions page in the app warns that nothing there
applies until it is private, with a Make Private button.

Notes, as Discord's: on someone else's profile, **Note (only visible to you)** keeps whatever you
want to remember about them (`users.setNote`, up to 256 characters, empty clears it), read back
with `users.getNote`. Only its author ever sees a note, and it goes when either person does.

Joining with an invite in the app: the server address field takes an invite link
(`https://chat.example.com/?invite=CODE`) and goes straight to making an account with it, and a
server closed to new members asks for the link when making one. The code is sent with the sign
up, as the web client's invite links do.

Invite links open the app on any server. The app is tied to no domain, so on an iPhone, iPad or Mac
the web invite page leads with **Open in the Sharkord app**, a
`sharkord://join?server=…&invite=…` link, above the invite and the browser sign in. A server already signed in to just opens, and any
other goes straight to making an account with the invite filled in.

New login alerts, as Discord's: whenever an account signs in somewhere (a password or single sign
on), every other device it has the app on with notifications gets **New login detected**, naming
the new device. The device that signed in is left out, and do not disturb does not hold it back.
Tapping it opens that server's Devices, to sign the new one out if it was not you. Code
`apps/server/src/queues/push-notifications/login.ts`.

Signing in another device with a QR code, for any server: on a device already signed in,
**Settings, Sign In Another Device** shows a QR code (`sessions.createLoginLink`) holding the
server's address and a one time code, `sharkord://login?server=…&token=…`. On the new device,
**Scan a QR Code** on the welcome screen, or the Camera app, reads it. The first device to present
the code (`POST /login/link`) claims it and is given a key only it holds, the signed in device
shows which device it is (`sessions.getLoginLink`) and approves or declines it
(`sessions.approveLoginLink`), and only then does the claiming device get its own session. Codes
last two minutes, only their hashes are stored, a new code replaces the old one, and nothing is
typed on the new device. Code `apps/server/src/helpers/login-links.ts`.

The other way round, for a device without a camera such as a Mac mini: after its server address,
**Sign In With Another Device** on the login card asks the server for a request
(`POST /login/request`), which returns a token for a QR code, `sharkord://approve?server=…&request=…`,
and a poll key the device keeps to itself. A phone already signed in to that server scans it with
**Settings, Sign In Another Device, Scan a Code Instead**, or the Camera app, sees which device
is asking (`sessions.getLoginRequest`) and approves or declines it for its own account
(`sessions.approveLoginRequest`). The asking device polls the same route with its key and gets
its session once approved. The key never goes in the QR code, so whoever scans it can approve
it but never collect it. Requests last two minutes, only hashes are stored, and expired ones are
swept away with each new one. The server address is still typed on the new device, since without
it there is nothing to ask. Code `apps/server/src/helpers/login-requests.ts`.


## App banner on iPhone and iPad browsers

The web app opened in a browser on an iPhone or iPad shows a slim banner across the top pointing to
the app. Open jumps to the channel on screen in the app, with the same `sharkord://channel` link
the app copies for a channel, and shows only while a channel is open. Get opens the TestFlight
beta. The X hides the banner in that browser until its site data is cleared. Other phones and
computers never see it. Code `apps/client/src/components/app-banner`.
