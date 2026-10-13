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
`has:` takes `image`, `video`, `link`, `file`, `poll` or `sticker`. Direct messages are
searched too. In the app, picking a filter puts its token in the search box with the choices
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
downloaded once into the app's cache.

Uploaded files are stored under their own name and served from `/public/<name>`. With
**Signed File Links** off (the default) anyone who has or guesses that link can open the
file without signing in. Turn it on in Server Settings, Storage, and every link carries a
token that expires.

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

## GIFs

The GIFs tab of the expression picker searches [Klipy](https://klipy.com), the provider
Discord uses. To turn it on, get a free API key at
[klipy.com/developers](https://klipy.com/developers) and either paste it into Server
Settings, Overview, Klipy API Key, or put it in `config.ini`:

```ini
[gifs]
klipyApiKey=your-key
```

or set `SHARKORD_KLIPY_API_KEY`. The `[gifs]` section is added to `config.ini` on the first
start of a server that has it. A key saved in the settings screen wins over the one in the
file.

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

## Invite only

`config.ini` can lock sign ups to invites, whatever the Allow New Users switch in the
settings screen says:

```ini
[registration]
inviteOnly=true
```

or `SHARKORD_INVITE_ONLY=true`. A new account then needs an invite made by someone with
Manage Invites (the owner, and any role given it), single sign on cannot create accounts,
and `/info` tells the apps registration is closed. Existing members log in as before. The
stored Allow New Users value is left alone, the settings screens show the switch locked off
while config.ini holds it. Code
`apps/server/src/helpers/registration.ts`.

## Server settings in the app

Overview, roles, members, invites, channels with per channel permissions, emoji, stickers,
storage, plugins (marketplace, settings, who can use them, logs) and updates are all in the
app, each shown only to people with the permission for it. They use the same routes as the
web client.

## Running the fork

The fork's server image is built from the `push` branch on every push and published as
`ghcr.io/jclendineng/sharkord:push` (`.github/workflows/fork-image.yml`).
