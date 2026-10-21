# iOS changes

Record of the changes made in `apps/ios` during the iOS audit on 2026-10-21.

## App Store readiness

### Privacy manifest

- Added `Sharkord/PrivacyInfo.xcprivacy`.
- Declares no tracking, no collected data types, and one required-reason API:
  UserDefaults (`CA92.1`).
- Confirmed the file is copied into the built `.app` bundle.

### Camera usage

- `Info.plist`: the camera usage description now covers both voice video and QR
  sign-in, which the app already supports.

## UI and accessibility

### Chat

`Sharkord/Views/ChatScreen.swift`

- The member column is no longer Mac only. It is available on iPad as well, still
  only when the chat is wide enough and never in a direct message.
- The width gate is unchanged: the chat must be at least
  `520 + 240 * 1.35` points (844pt). That means the column appears on a 13 inch
  iPad in landscape, not in portrait.
- The chat title now occupies a fixed slot, 160pt on phone and 220pt on iPad.
  The old `.fixedSize()` forced the full title into the bar and could push
  search and pin buttons off. Removing it entirely collapsed the title to a
  couple of characters under the toolbar's minimum width. The fixed slot
  truncates long names without moving the trailing buttons.

### Composer

`Sharkord/Views/ComposerView.swift`

- Attach, send, emoji, and mic hit targets are now 44pt. The visible circles
  stay 38pt; the outer frame carries the tap.
- Applied to the Mac plus menu, the phone attach button, the emoji and mic
  buttons, and the send button.

### Inbox

`Sharkord/Views/InboxSheet.swift`

- The Unreads list now uses `.plain` like Mentions instead of
  `.insetGrouped`, so switching tabs no longer changes the list style.
- Unread rows get `listRowBackground(Theme.listBackground)` to keep the row
  color consistent in the plain list.

### Member list

`Sharkord/Views/MembersColumn.swift`

- Offline rows use 0.6 opacity instead of 0.45. The lower value left names
  below the contrast a dark theme needs to stay readable.

### Search

`Sharkord/Views/SearchHome.swift`

- Replaced fixed `.system(size:)` fonts with semantic styles (`.body`,
  `.title2`, `.title3`, `.callout`) on the tab strip, section titles and their
  action buttons, channel rows, user rows, and message authors.
- These now scale with Dynamic Type instead of staying at a fixed size.

### Server settings

`Sharkord/Views/Admin/ServerSettingsScreen.swift`

- Added `.presentationSizing(.page)` so the screen opens at the same page size
  as user settings instead of a narrower card.

### Attachment panel

`Sharkord/Views/AttachmentPanel.swift`

- `AttachPanelModel.restingHeight` now clamps the last keyboard height to 55%
  of the key window's height.
- The stored height is from the previous orientation, and a portrait keyboard
  height covered most of a landscape phone after rotation.

## Performance and correctness

### Network timeouts

`Sharkord/Networking/TRPCClient.swift`

- Every request now has a 30 second timeout. A reply that never arrives can no
  longer leave a screen waiting forever.
- Requests are cancelled with their caller using
  `withTaskCancellationHandler`.
- Added `resolve(_:with:)`, which cancels the request's timeout and resumes the
  continuation exactly once.
- Timeouts are cancelled when the connection finishes.
- A late reply for a request that already timed out is ignored.

### Live message insert

`Sharkord/State/ChannelMessagesStore.swift`

- `insert` now appends when the message is newer than the last loaded message,
  which is the normal case for live events.
- Out of order messages still go through the duplicate check and a sorted
  insert.
- This avoids re-sorting the whole page on every live message.

### Emoji cache

`Sharkord/Helpers/EmojiImageCache.swift`

- Cache key is now `(url, pointSize)` instead of just `url`. A 14pt render
  reused at 44pt in the picker was blurry, and a 44pt render in a message was
  heavier than needed.
- Failed loads are removed from the requested set, so they can retry. They
  previously stayed requested forever and never loaded.

### Attachment images

`Sharkord/Views/AttachmentView.swift`

- Message images decode at `300 * displayScale` instead of full upload
  resolution. A 12 megapixel upload was being decoded for a 300pt thumbnail.
- The load task is keyed by file id and pixel size.

### Animated images

`Sharkord/Views/AnimatedImage.swift`

- The GIF cache keeps its 120 item count limit and gains a 128MB total cost
  limit.
- Cost is the sum of the decoded frame bytes (`bytesPerRow * height`), so a few
  long GIFs can no longer keep hundreds of megabytes alive.

### Unread divider

`Sharkord/Views/MessageListView.swift`

- The first unread message id is read once per list render instead of once per
  row.
- Used for both the new messages divider and the header decision.

## Swift optimization review

Checked against
[`OptimizationTips.rst`](https://github.com/swiftlang/swift/blob/main/docs/OptimizationTips.rst)
from the Swift repository.

### Build settings

`Sharkord.xcodeproj/project.pbxproj`

- Release now sets `SWIFT_OPTIMIZATION_LEVEL = "-O"` explicitly. It relied on
  Xcode's default before, and the resolved value is now visible in
  `xcodebuild -showBuildSettings`.
- Release already used `SWIFT_COMPILATION_MODE = wholemodule`, so whole module
  optimization was on. Debug stays at `-Onone`, which is intended.
- WMO lets the compiler devirtualize internal declarations without making
  everything `final`.

### Dynamic dispatch

- Every class in the app is already `final`. There are no `open` classes,
  `dynamic` members, or custom protocols, so there was nothing to change here.
- `@objc` is limited to UIKit delegate methods and the hover recogniser
  callback, none of which are on a hot path.

### Containers and copies

`Sharkord/State/SessionStore.swift`

- `displayRole(for:)` used to build an array, sort it, and take the first
  coloured role. It runs for every message row and every member row. It now
  scans the user's roles once and keeps the highest ranked coloured one, with
  no array allocation and no sort. The result is the same.
- A direct message arriving updated the conversation list with `map` plus
  `sorted`, which rebuilt the whole list. It now updates the matching entry in
  place and sorts the existing array.

`Sharkord/Views/AnimatedImage.swift`

- The animated image frame loop now reserves its frame capacity and wraps each
  frame in `autoreleasepool`, so ImageIO's per frame temporaries are released
  during a long decode instead of at the end.

`Sharkord/Helpers/MessageHTML.swift`

- The parsed message cache now has a 500 entry limit. It was unbounded, so it
  kept the parsed blocks of every message in every channel visited until the
  system reported memory pressure.

`Sharkord/State/ChannelMessagesStore.swift`

- The custom emoji `NSRegularExpression` is built once as a static instead of
  for every message sent.

### Escaping closure captures

- `TRPCClient.requestData` copied its request parameters to a `let` before the
  escaping send task.
- `ComposerView.toggleAsset` builds its attachment as a `let` instead of
  mutating a `var` that the upload task captures.
- `RolesScreen.move` computes the role ids before its reorder task.
- A `var` captured by an escaping closure needs a heap box. These three read
  only, so the copies remove the box with no behaviour change.

### Checked and left as they are

- No `ContiguousArray` migration. The hot arrays hold structs, and the image
  frame array is passed to `UIImage.animatedImage(with:)`, which needs
  `[UIImage]`.
- `AnyView` only appears in the pointer menu presentation, not in the message
  list.
- `[String: Any]` appears at the JSON and Mediasoup boundaries, where the app
  relays untyped payloads.
- `MessageListView` still builds `Array(store.messages.enumerated())` for its
  day and header decisions. It is a page of 50 rows, and the index is needed
  for both.
- `TRPCClient` still parses the websocket envelope with `JSONSerialization`
  and then decodes the payload again. Removing the second pass needs typed
  subscription envelopes and a larger change than this review.

## Verification

- Debug build for the iOS Simulator succeeded with Xcode 27.2.
- Release build for the iOS Simulator succeeded. The resolved Release settings
  are `SWIFT_OPTIMIZATION_LEVEL = -O` and
  `SWIFT_COMPILATION_MODE = wholemodule`.
- The privacy manifest is present in the built app bundle.
- Screenshot walkthroughs were run on:
  - iPhone SE (3rd generation), iOS 27.2.
  - iPhone 17 Pro Max, iOS 27.2.
  - iPad 13 inch, iOS 27.2, portrait.
- Checked chat, channel list, channel info tabs, server sheet, server settings,
  profile, settings, inbox, and search.

## Not verified

- Mac. The Mediasoup and WebRTC xcframeworks have no macOS slice, so the My Mac
  destination fails to build and the iOS build cannot launch with the Mac app
  runtime.
- iPad landscape. `simctl` cannot rotate and `Simulator.app` is not available.
  XCUITest rotation rotated the content inside a portrait framebuffer without
  widening the window, so the member column could not be checked in pixels.
- Voice and video media, push delivery, and offline behavior.

## Temporary and reversed changes

- `SharkordUITests/TourUITests.swift` was added for the screenshot tour and
  deleted afterwards. No test target changes remain.
- `Sharkord.xcodeproj` was temporarily changed to add `macosx` to
  `SUPPORTED_PLATFORMS` while investigating Mac support. The change was
  reverted and the project file is unchanged.
