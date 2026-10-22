# Changelog

Notable changes to this fork of [Sharkord](https://github.com/Sharkord/sharkord), grouped the way [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) does.

- The iOS app has its own version numbers, starting at 0.1.0.
- The server and the web client keep upstream's numbering, so a server release names the upstream version it is built on.
- Everything here works with any server it is pointed at. Nothing is tied to one domain.

## [Unreleased]

Everything since the fork from upstream Sharkord 0.0.27 (2026-10-11).

### Upgrade notes

- Database migrations run by themselves at startup.
  - This release adds tables for friends, group direct messages, private notes, the new member lounge, QR sign in and the soundboard.
  - Upstream's plugin storage migrations run as this fork's `0060_plugin_storage`, after the fork's own, so a database that already ran `0059` still gets them.
  - `0073_invite_uses` adds the table of who signed up with which invite, and marks deleted invites instead of removing them. Sign ups from before it have only the count.
  - `0072_role_positions` gives roles an order, starting from the order they were made in.
  - `0071_onboarding_removes_default_role` adds the rules setting that takes the default role away on reacting, off for a lounge already set up.
  - `0070_channel_pins` adds the table of channels each account pinned. The apps hand their own pins over the first time they connect, so nobody loses the ones pinned before.
  - `0069_drop_manage_updates_permission` takes Manage Updates off every role, since the self updater it ran is gone.
  - `0068_user_totp` adds the table that holds two-factor secrets, apart from users.
  - `0067_channel_retention` adds a retention period to channels, off on every channel until set.
  - `0066_password_resets` adds the table of reset links.
  - `0065_webhooks` adds the webhooks table and the name a webhook posted under to messages.
  - `0064_ip_bans` adds the table of banned addresses.
  - `0063_afk_channel` adds the AFK channel and timeout to the settings table. AFK is off until an admin picks a channel.
  - `0062_oidc_invite_code` adds a column to SSO sign ins in flight, for the invite they carry.
  - `0061_grant_pin_dm_messages` gives the new Pin Messages in Direct Messages permission to every role that has Pin Messages.
- Permissions granted on upgrade:
  - Use Soundboard goes to every role that can join voice, Manage Soundboard to every role that manages emoji.
  - An iOS app from before the soundboard can't open the roles screen on an upgraded server, because it doesn't know the two new permissions. Update the app along with the server.
  - This release's app keeps permissions it does not know when saving a role.
- File links:
  - On first start, existing uploads are renamed to random names and every file link becomes signed.
  - Links handed out before the upgrade stop working once they expire.
  - `storage.forceSignedUrls` in `config.ini` is gone, since links are now always signed. The server removes the old key.
- New `config.ini` options:
  - `registration.inviteOnly`, for sign ups by invite only.
  - The Klipy key for GIFs, also settable with `SHARKORD_KLIPY_API_KEY`.
  - `freesoundApiKey` under `[sounds]`, for sound search.
  - `basePath` under `[server]` (env `SHARKORD_BASE_PATH`), for running under a subpath. Set the proxy to forward that path and its WebSocket upgrades; it may strip the prefix or not.
  - `listenIp` under `[webRtc]` (env `SHARKORD_WEBRTC_LISTEN_IP`), the address voice listens on. Set `::` for IPv6 as well as IPv4 ([#522](https://github.com/Sharkord/sharkord/issues/522)).
- Security defaults:
  - `server.trustedProxies` now defaults to loopback only on new installs. An existing `config.ini` keeps its list, so narrow it to your reverse proxy's address to stop other machines on the network passing forwarded addresses.
  - New rate limits in `config.ini`, added by themselves: `loginIdentity` (sign in attempts per account), `messageAction` (pins, ending polls, deleting files) and `pluginManage` (plugin toggle and settings).
  - A database first made by a development build had the access token `dev`. It is replaced once at startup with a new one printed to the console, which signs everyone out on that server.
  - Emoji uploads have to be images of 2 MB or less.
  - The web app enforces its content security policy. Plugins that load scripts, frames or connections from other sites are blocked by it.
- The server image is published to `ghcr.io/jclendineng/sharkord`.
  - `:latest` (or no tag) is built from `main`, the stable channel.
  - `:development` is built from the `development` branch.
  - Every build also gets a `:sha-<commit>` tag that never changes, for pinning or rolling back.
  - The old `:push` tag is gone. A container still on it should move to `:development`.

### Added

#### Server, web and apps

- The server keeps who signed up with each invite.
  - Deleting an invite stops it working but keeps it in the list, marked deleted.
  - In the app, tapping an invite in server settings shows its details and who joined with it.
  - People who manage invites see "Joined with an invite from" on a member's profile.
  - The web invite table shows deleted invites as deleted.
- Roles have an order (`roles.reorder`).
  - Drag them in the web client's Roles list, or use Reorder in the apps (arrows on a Mac).
  - The owner's role stays on top and the default one at the bottom.
  - A member shows as their highest role with a colour, and the member list groups by it.
- The rules message setup can close every other channel to new members and take their starting role away once they react, instead of channel by channel permissions by hand.
- Pinned channels follow the account: pinning on the Mac shows on the phone straight away (`channels.setPinned`, `channels.getPins`, `channels.onPinsUpdate`).
- An About page in user settings: versions, the server's contact (its report email) and links to the source and to report a problem.
- `messages.getThreads`: a channel's threads, the one replied to last first, for the apps' threads list.
- Members without a picture get an avatar drawn in colours from their id, the same on the web and in the app ([#867](https://github.com/Sharkord/sharkord/issues/867)).
- Turn off incoming video, in the voice options on the web and the voice sheet in the app. Cameras and screen shares stop reaching you, to save a weak connection ([#123](https://github.com/Sharkord/sharkord/issues/123), [#657](https://github.com/Sharkord/sharkord/issues/657)).
- In a private channel the member list shows only who can see it, with a switch back to everyone ([#458](https://github.com/Sharkord/sharkord/issues/458)).
- Delete your own account, in user settings on the web and Account settings in the app ([#49](https://github.com/Sharkord/sharkord/issues/49)).
  - An account with a password confirms with it.
  - You choose whether your messages stay as Deleted User or go too.
  - The server owner can't delete theirs.
- An AFK channel: members silent in a call for the server's timeout (1 to 60 minutes) are moved into it.
- A ban can also ban the person's IP addresses ([#371](https://github.com/Sharkord/sharkord/issues/371)).
  - Their public addresses are blocked from signing in, signing up and joining, and unbanning lifts it.
  - Private addresses and the moderator's own are never banned.
- Incoming webhooks: a channel's settings on the web make a URL other services post plain text to, shown under the webhook's name ([#293](https://github.com/Sharkord/sharkord/issues/293)).
- Basic Markdown ([#401](https://github.com/Sharkord/sharkord/issues/401)).
  - Strikethrough, underline, lists and quotes survive sending instead of becoming plain lines.
  - The app turns `**bold**`, `*italic*`, `__underline__`, `~~strike~~`, `` `code` ``, code blocks, `- ` lists and `> ` quotes into formatting, shows all of it, and keeps it when editing.
- Password recovery without email ([#331](https://github.com/Sharkord/sharkord/issues/331)).
  - A moderator makes a one time reset link from a member's page and sends it however they reach them.
  - It works for 24 hours, sets a new password on a page of its own and signs the account out everywhere.
- Message retention per channel, in a channel's settings on the web ([#564](https://github.com/Sharkord/sharkord/issues/564)).
  - Messages older than 1 day to a year are deleted every hour, keeping pinned messages and threads still going.
  - Before saving, the screen shows how many messages it would delete now.
  - Their files go with the orphaned file sweep.
- Two-factor authentication with an authenticator app ([#328](https://github.com/Sharkord/sharkord/issues/328)).
  - Set up in Password settings on the web and Account settings in the app, with eight one time recovery codes.
  - Signing in with a password then asks for a code.
  - SSO accounts leave it to their provider, and QR sign in is not asked.
  - A moderator's password reset link turns it off.
- Sharkord can run under a subpath behind a reverse proxy, like `example.com/sharkord`. At the root nothing changes ([#816](https://github.com/Sharkord/sharkord/issues/816)).

#### Messaging

- Polls.
- Voice messages that play in place.
- Server stickers and Klipy GIFs in the picker.
- A soundboard.
  - Anyone in a call plays a sound for everyone there, and each person sets their own soundboard volume.
  - Managers upload sounds or pick them from a library of free CC0 sounds by Kenney that comes with the server.
  - Each sound has a name, emoji and volume.
  - Two new permissions, Use Soundboard and Manage Soundboard.
  - In the app the sounds are cards with a large emoji, in a sheet as tall as they need, and a card lights up while its sound plays.
- With a Freesound API key, soundboard managers search freesound.org for more sounds. Only sounds free to reuse are shown, and a sound that asks for credit keeps it.
- Link previews for bare domains, previews from the server's own network when the admin allows it, and richer link cards.
- A new member lounge: reacting to the rules message gives the role that opens the server.

#### Direct messages and friends

- Friends, with requests and friend buttons on profiles.
- Group direct messages with up to ten friends.
- Close a direct message, hiding it until a new message arrives.
- The messages list shows each conversation's last message.
- Let people turn off new direct messages from others.
- Private notes on a member's profile, visible only to whoever wrote them.

#### Search

- Search with filters (from, in, has, mentions, dates), and tabs for recent, members, media, pins, links and files.
- Search inside direct messages, with results that open at their message.
- `has:` video, poll and sticker.

#### Presence

- Availability (online, idle, do not disturb, invisible) and a custom status message. Do not disturb silences push notifications.
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
- A new microphone or camera, or changed mic processing, applies to the call as soon as Devices settings are saved ([#530](https://github.com/Sharkord/sharkord/issues/530)).
- Mute Stream Audio in Devices settings: screen shares with sound start muted ([#749](https://github.com/Sharkord/sharkord/issues/749)).
- On a phone the channel list opens whenever no channel is open, after signing in or leaving a call, in place of the welcome screen with its swipe hints and mobile warning.
- On an iPhone or iPad browser, a banner across the top of the app offers to open the current channel in the Sharkord app or get it from TestFlight, until it is hidden in that browser.

#### iOS app

- A native iOS and iPad app, signing in to any server by its address, with push notifications, SSO and server passwords.
- A new layout: server rail, channel list and a floating user bar.
  - On iPad the channel list and the chat sit side by side as two rounded cards in both orientations.
  - A handle slides the chat over the list to full width, and typing slides it over by itself.
- A sign in screen over a night sky. Register only shows where the server takes new members.
- Sign in without typing a password by QR code, both ways.
  - A signed in device shows a code, and the new device scans it.
  - A device with no camera, such as a Mac mini, shows a code from **Log In With a QR Code** on the welcome screen, and a signed in phone scans and approves it.
- Alerts on your other devices when a new device signs in, opening the Devices screen.
- Invite links open the app on any server, through `sharkord://`.
- Message actions: reply, edit, react, forward, pin, mark unread and report.
- An attachment panel, with a recent photos grid that trades places with the keyboard.
- An expression panel with emoji, GIFs and stickers. Animated GIFs and stickers play in messages.
- Voice channels with video, screen sharing from the phone (game audio included), voice reactions and moving members.
- The new messages bar, NEW line and jump to bottom button. Jumping to a message rings it with a soft glow.
- A media viewer, link previews with site icons, and files that open in Quick Look.
- A channel screen with members, media, pins, links and files tabs.
- Server settings: channels, roles, per channel permissions, members, invites, emoji, stickers, storage and plugins.
- Mute a channel or conversation for a while, and per channel notification levels.
- A warning before leaving the app through a link.
- Better calls.
  - The camera sends 1080p.
  - Video keeps playing in picture in picture when you leave the app.
  - A signal badge on the call shows the ping and packet loss.
  - Mic Mode (Voice Isolation, Wide Spectrum) opens from the call sheet.
  - A Video Effects sheet plays reactions on your camera, switches Center Stage and shows whether Portrait and Studio Light are on. Hand gestures play reactions too.
  - In a dim room the camera slows to 24 frames a second to gather light.
  - A gear on the call opens its settings, with quick tiles for Deafen, Output and incoming video.
  - Tapping someone in a call brings their video to the front, with everyone else in a strip under it.
  - Whoever is talking gets a green ring, on the call screen and under the voice channel in the channel list.
- A lowered call is the voice bar above the user bar on the phone, iPad and Mac, with mute, deafen and hang up.
  - The call grows out of the bar when opened, joining from a voice channel's sheet included.
  - It shrinks back into the bar when lowered, by its button or a drag down.
- The voice channel sheet on a phone is a short sheet with the channel and the join box.
  - A swipe up grows it into the voice settings, the box becoming the sheet as it rises.
  - A swipe down goes back to the short sheet, and only a swipe from the short one closes it.
  - Hear Yourself, Deafen, audio output and noise suppression sit under Join Voice.
- Long pressing someone in a voice channel opens their menu, with Move To for anyone who can move members.
- The Voice & Video settings page has a new layout, with a hint to turn on Voice Isolation when it is off.
- Long press menus for channels and categories, a right click on a Mac.
  - Channels: Copy Link (text channels), Hide Names (voice channels, shows only who is in it as faces), and for managers Edit Channel and Duplicate Channel.
  - Categories: Mark As Read, Mute Category, Notification Settings for every channel in it, Edit Category and Create Channel.
- On an iPad showing the channels beside the chat:
  - Search drops down under its box, full screen in landscape without a hardware keyboard.
  - Threads open in a panel beside the chat when it is wide enough.
  - Settings fill the screen, and pins open as a panel from the top bar.
- Messages light up under the finger while pressed.
- A thread's first message has the same menu and double tap reaction as any other, so it can be edited from the thread.

#### From upstream

- Hotkeys in the web client for mute, deafen, push to talk and more, set in a new Hotkeys settings tab. Hotkeys that work while the browser is in the background need upstream's bridge app.
- A wider plugin SDK: plugins can store data, add buttons and other parts under their messages, and take arguments in their commands.

### Changed

- The sign in page's GitHub link, the crash screen's report link and the developer console point to this fork rather than upstream.
- File links are always signed, and uploads are stored under random names rather than their original ones.
- Link previews skip error pages and use only pictures the page itself declares.
- Pinning in direct messages has its own permission, Pin Messages in Direct Messages. Roles that could pin keep it there ([#481](https://github.com/Sharkord/sharkord/issues/481)).
- A name another member already uses, whatever its case, can't be taken on rename ([#828](https://github.com/Sharkord/sharkord/issues/828)).
- An open voice channel chat follows you when you switch voice channels. It still never opens by itself ([#716](https://github.com/Sharkord/sharkord/issues/716)).
- The web invite page on an iPhone, iPad or Mac puts **Open in the Sharkord app** first, with the browser sign in below it.
- The app decodes each live update once, straight from the message, instead of parsing it, writing it back out and decoding it again.
- The iOS app now needs iOS 27 or later.
- The iPhone app stays in portrait. Landscape is for the iPad.
- Screen sharing on the phone uses iOS 27's ScreenCaptureKit picker and captures inside the app, so frames go straight to the call instead of through a broadcast extension.
- The iOS app opens on the server as it was last seen while it reconnects.
  - Channels, avatars and server icons are drawn at once.
  - Pictures are decoded at the size they are shown.
  - The requests after joining a server go out together instead of one after another.
- In the app's server Overview, a new or removed icon shows as a preview and is only applied with Save.
- The app's Channels settings page has a Reorder button in its top bar, where it was hidden in the + menu before.
- In the app, the server's search leaves direct messages to the messages panel's own search.
- In the app, the invite sheet reuses your last link while it works, until you generate a new one or delete it.
  - The sheet says how many times the link has been used and when it expires, and links to the full invite list for people who manage invites.
  - Replace Link asks before the old link stops working, as does changing a setting once the link has been used.
  - With no link to reuse, the sheet shows Create Link instead of making one as it opens.
- Long presses on channels and messages open their menu after the same 0.3 seconds as servers and conversations.
- Joining voice from another device takes the seat over instead of failing with "User already in a voice channel".
  - The device that had it ends its call, and the iOS app shows a bar offering to reconnect there.
  - A phone coming back from the background rejoins instead of being locked out.
  - A device that crashes or loses its connection leaves voice even when the account is still connected elsewhere.
- On a Mac, the app has a desktop layout.
  - The server's menu drops down under its name.
  - Server settings and user settings fill the window, with their pages down the side and a search.
  - A thread opens in a panel beside the chat.
  - The plus by the message box opens a short menu, and the box has GIF, sticker and emoji buttons.
  - The emoji picker keeps to its own width.
  - The member list shows down the right of a server channel, online then offline, grouped by role, grows with the window, and hides from a header button.
  - The user bar has mute, deafen and settings, and sits inside the channel list's card.
  - The inbox and a bell for the channel's notifications sit in the top bar.
  - A channel's threads list opens from the top bar.
  - Back and forward through channels with ⌘[ and ⌘].
  - Voice & Video picks the mic and speakers, using a headset's mic whenever one is plugged in, with push to talk and an input volume where the mic allows it.
  - Escape closes sheets, menus and panels and goes back from a thread.
- On a Mac, whatever can be picked lights up under the pointer.
  - Search results, tabs, cards and filters, direct messages, the emoji, GIF and sticker panel, reactions, poll options, soundboard sounds, the rows of every sheet and list, and the user bar.
  - Buttons bounce a little under the pointer, and server icons square off with a short pill.
- On a Mac, right click menus open beside the pointer with what a long press opens.
  - Message, channel, conversation, member and server actions, as compact rows with an icon.
  - The next right click moves the menu, and a click anywhere else closes it.
  - Rows with more choices (Mute Channel, Notification Settings, Add Reaction) open them beside the menu.
  - Add Reaction and the reactions along the top lead with the emoji you use most.
- On a Mac, hovering a message shows a bar of quick reactions, Reply and More.
- On a Mac, search is a box in the chat's top bar with the filter menu beside it, and the results drop down under it. The server search above the channel list opens the same card.
- On a Mac, sheets open centred in the window, scrolling in one no longer fades it out, and they have no grabber.

### Removed

- The server's self updater, its Updates page in the web client and the app, the Manage Updates permission and the `server.autoupdate` setting.
  - It checked upstream's releases, so a server run outside Docker would have replaced this fork with upstream.
  - Update by pulling the new image instead.
- The voice channel sheet's own invite button, which repeated the server invite at the top of the channel list.

### Fixed

#### Server and web client

- The web invite page says how to make an account: choose an identity and a password, then press Connect.
- Open in the Sharkord app on the invite page keeps a server's subpath, so a server under `example.com/sharkord` opens there in the app instead of at `example.com`.
- The sign in page scrolls on a phone instead of cutting off its top and bottom, and the language picker sits below it there rather than over the Connect button.
- In Safari on an iPhone the sign in page runs under the glass address bar instead of stopping above it on a black band.
- The sign in page stays still in Safari on an iPhone when everything fits on screen, rather than scrolling and jumping by the height of the address bar, and it no longer bounces past its edges or reloads on a pull down.
- A sign in page a little taller than the screen, such as one opened from an invite, scrolls smoothly in Safari on an iPhone instead of stuttering as the address bar shrinks and grows.
- The reset password and single sign-on screens are centred again.
- On a phone the web app works without a mouse:
  - A channel's top bar has buttons for the channel list and the member list, which before opened only with a swipe.
  - Picking a channel or opening settings closes the channel list instead of leaving it over the chat.
  - Tapping a message shows its actions, such as reply, edit and delete, which appeared only on hover.
  - A member's profile card opens below their name and fits on the screen, instead of mostly off its left edge.
  - Threads and a call's chat open full screen, where before they opened out of sight.
  - Editing a message has Cancel and Save buttons, since there is no Esc key to cancel with.
  - The home screen, an empty direct messages screen and a call have a way to the channel list besides a swipe.
  - The pinned messages panel fits on the screen instead of running off its right edge.
  - Leaving a call opens the channel list instead of the welcome screen.
  - Coming back to the page after it was in the background no longer flashes the connection lost dialog; it shows only if the first try to reconnect fails.
  - Notifications drop in from the top instead of covering the message box or a call's controls.
  - Closing the keyboard in Safari on an iPhone puts the page back in place, instead of leaving it shifted up with its top cut off and a gap at the bottom.
- A notification's close button shows its X; it was drawn dark on the dark notification.
- Refreshing the web app keeps you signed in, whether or not Login automatically is on, and shows Loading Sharkord while it resumes rather than Logging in automatically. That setting now only decides whether a new tab or a reopened browser stays signed in.
- Only a message's author can edit it. Manage messages let anyone holding it change other people's messages; it still lets them delete one.
- Dependencies with published security fixes are upgraded, among them the HTML sanitizer, the websocket server, the image size reader, the message editor and the database layer.
- The web client joins its call again after a dropped connection comes back, instead of showing a call the server had already ended ([#849](https://github.com/Sharkord/sharkord/issues/849)).
- Voice works in Firefox when `announcedAddress` is a hostname. The server sends the addresses it resolves the name to beside the hostname ([#756](https://github.com/Sharkord/sharkord/issues/756)).
- An invite works for SSO sign ups on a server closed to new users, as it does for password sign ups. Its role is given and its use counted ([#840](https://github.com/Sharkord/sharkord/issues/840)).
- Turning off Upload Files for a role no longer stops its members from setting an avatar or banner. It now only covers attaching files to messages ([#830](https://github.com/Sharkord/sharkord/issues/830)).
- Taking away Webcam or Share Screen in a channel, or making a channel private, turns off a camera or screen share already running there ([#869](https://github.com/Sharkord/sharkord/issues/869)).
- Sticker images are no longer swept up as orphaned files.
- Search names a direct message after its person or group, not "DM - 2:5".
- Signing out many devices in a row no longer hits a rate limit.

#### Security

- The owner role can no longer be made the default role, which would have made every new account an owner.
- Development builds seed a random access token instead of `dev`, and warn when they listen on the network with rate limiting off.
- Channel permissions can only be read or changed by someone who can see the channel, and only for permissions they hold, deleting a row included.
- Who is in a voice channel, and what they are doing there, only reaches people who can see that channel.
- An upload that is cut off part way no longer leaves its file behind, and stale upload files are swept every 15 minutes.
- Sign in attempts are limited per account as well as per address.
- Plugin capability access can't be opened past the permission its plugin asks for, except by the owner.
- A role manager can't edit the owner role or take away permissions they don't hold.
- A ban signs the account out everywhere, so its old sessions don't come back after an unban.
- A password reset link works once even when two requests use it at the same moment.
- A moderator can't unban the owner, and adding a role to an account that doesn't exist says so.
- Invite codes come from a secure random source.
- Upload, avatar and banner size settings are capped at what the server supports.
- Link preview pictures must be http or https and load without a referrer, external links open with `noopener`, and the web app sends HSTS over https.
- Pinning, ending polls, deleting files and plugin settings are rate limited, and one connection can keep at most 200 subscriptions open.
- Debug output leaves secrets out, the plugin marketplace fetch has a timeout and size cap, an SSO avatar is fetched from the address that was checked, and uploads no longer report where the file sits on the server.

#### iOS app

- An empty channel's chat fills the screen, instead of leaving black strips down both sides.
- The app's invite list says "1 use", not "1 uses".
- An invite link opened while the app shows its welcome screen goes straight to making an account on that server, instead of being dropped.
- Coming back to the app while it was reconnecting no longer signs you out with "Invalid handshake hash".
- A call is heard both ways: whoever joined after the app, or started talking or sharing a camera after it joined, was never heard or seen.
- Cameras and screen shares from a browser show. The app could only take H264 baseline, and browsers send VP8 or VP9.
- The camera reaches the others in the call again. It had been sending layers that never carried a frame, so only you could see your picture.
- The camera's picture is turned the right way up from how the device is held, on an iPhone and on an iPad already held sideways when the camera starts.
- A call joined with AirPods or another headset connected plays through the headset instead of the speaker when Use Speaker by Default is on.
- An error during a call, such as the camera not starting, shows over the call instead of behind it.
- A call's tiles grow to fill the screen in either orientation, and someone alone in a call fills it.
- On an iPad, joining or opening a call opens the full-screen call instead of a phone's sheet.
- Starting a screen share on the phone no longer crashes the app, and the share keeps going after switching to another app.
- A screen share from an older iPhone, like an iPhone SE, keeps going after leaving the app instead of freezing. It blinks once as it moves to a software encoder.
- A screen share no longer stays on its last frame after the person sharing leaves the call.
- The mic test is processed the way a call is.
  - With Echo Cancellation on it uses Apple's voice processing, so noise suppression, gain control and Voice Isolation apply.
  - Mic Mode can be opened while the test runs, and hearing yourself plays at the output volume.
  - Turning voice processing on no longer sends the test into a restart loop that stalled the phone.
  - It no longer crashes the app and keeps working with AirPods.
- The conversation scrolls without jumping: fast scrolls no longer stop dead at the top or bounce twice at the bottom.
- A chat opened again lands on the newest message instead of a few messages short.
- The button down to the newest message works on the first tap, even mid scroll, and lands right at the bottom. On an iPad and a Mac it scrolls there smoothly.
- The messages keep scrolling after a long press opens a message's menu partway through, and the pressed row lets go as soon as the menu shows.
- Jumping to a message from search or pins highlights it again, rather than only scrolling to it.
- A long press on a message's replies link opens only its menu, not the thread under it too.
- The messages load at launch instead of showing "You must be authenticated" until another channel was opened.
- Requests made straight after opening the app wait for its sign in to finish.
- Edit Profile keeps unsaved edits: a swipe down springs back, and Cancel asks before discarding them.
- A long press on a member in a channel's Members tab opens the same menu as a right click on a Mac.
- The button that opens the system's settings says Settings on an iPhone or iPad and System Settings on a Mac, where it opens the matching pane.
- Sheets with no button of their own to close them get an X in the top left.
- On an iPad:
  - The message bar sits level with the user bar beside it.
  - The top bar's pins and search stay in place while the chat slides over the list and back.
  - The back button of the search takes the first tap.
  - A tap on the channel list beside the chat puts away the chat's pins or threads panel.
- On a Mac:
  - Sharing the screen opens the system's picker of a window or a screen, and a picker that cannot open says so.
  - The app shows up as macOS in Devices, login alerts and sign in approvals, and iPads get an iPad icon.
  - No sheet crashes the app on opening, pinned messages and the inbox among them.
  - A sheet's X closes on the first click.
  - The inbox under the bell has an X and closes with Escape.
  - The search box keeps focus while typing, results open when clicked, and a message found by a GIF shows it.
  - A server's menu and the search card no longer hide under each other, and a lit row in the menu sits whole inside it.
  - A menu closes before the sheet it opens, the profile card closes when settings open, and the member profile opens tall enough for the note.
  - A member's profile from the member list opens to its left, full width.
  - The dark rail no longer shows a grey block under the title bar.
