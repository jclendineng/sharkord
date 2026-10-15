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
it on does not add previews to older messages.

Uploaded files are stored under their own name and served from `/public/<name>`. With
**Signed File Links** off (the default) anyone who has or guesses that link can open the
file without signing in. Turn it on in Server Settings, Storage, and every link carries a
token that expires. It is also `signedUrls` under `[storage]` in config.ini (see Settings in
config.ini).

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

Three settings live both in the settings screens and in `config.ini`, and either side changes
the other:

```ini
[registration]
allowNewUsers=false

[storage]
signedUrls=true

[gifs]
klipyApiKey=your-key
```

Saving the settings screens writes these into the file. Editing the file is picked up at
startup and also while the server runs, without a restart: the change is applied to the
database and pushed to everyone connected, so the screens show it straight away.

`allowNewUsers=false` makes the server invite only: a new account needs an invite from someone
with Manage Invites, single sign on cannot create accounts, and the apps say registration is
closed. `signedUrls=true` makes every file link carry a token that expires, apart from the
server logo, which shows before anyone signs in.

What was last written is recorded in `config-sync.json` next to `config.ini`, so a value that
differs from it is known to be an edit. The `inviteOnly` and `forceSignedUrls` keys from an
earlier version of this fork are carried over once and then replaced. Code
`apps/server/src/helpers/config-file-sync.ts`.

## Server settings in the app

Overview, roles, members, invites, channels with per channel permissions, emoji, stickers,
storage, plugins (marketplace, settings, who can use them, logs) and updates are all in the
app, each shown only to people with the permission for it. They use the same routes as the
web client.

## Running the fork

The fork's server image is built from the `push` branch on every push and published as
`ghcr.io/jclendineng/sharkord:push` (`.github/workflows/fork-image.yml`).
