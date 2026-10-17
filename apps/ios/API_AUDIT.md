# iOS SDK audit

Checked 2026-10-17 against the iOS 27.1 SDK in Xcode 27.1 (27A9275), from the SDK's own
`.swiftinterface` files and the warnings of a clean build. Work through the list top to bottom
and tick items off as they land.

## Already current

No `ObservableObject`, `@Published`, `NavigationView`, `foregroundColor`, `.cornerRadius()`,
`UIScreen.main`, `PreviewProvider`, Combine or callback `URLSession`. State is `@Observable`,
environment values use `@Entry`, and the app already uses `onGeometryChange`,
`onScrollGeometryChange`, `ScrollPosition`, zoom transitions and `ContentUnavailableView`.

## To do, in order

- [x] **`installTap` deprecated in iOS 27** (`State/MicrophoneTester.swift`). Now on
      `installAudioTap(onBus:bufferSize:format:tapProvider:)`, the Swift name of the throwing tap,
      reading an `AVReadOnlyAudioPCMBuffer`.
- [ ] **Drag to reorder with `reorderable()` / `reorderContainer`** (iOS 27). Channels
      (`Views/Admin/ChannelsAdminScreen.swift`) and roles (`Views/Admin/RolesScreen.swift`) use
      `onMove` in edit mode on iPhone and iPad and arrow buttons on the Mac, where edit mode does
      nothing. One drag interaction on all three.
- [ ] **`dismissalConfirmationDialog`** (iOS 27) on Edit Profile, so a swipe down with unsaved
      changes asks first. Then any other sheet that edits something.
- [ ] **`AVSampleBufferDisplayLayer` deprecated in iOS 27** (`Views/PictureInPictureSource.swift:178`).
      `status`, `flush()` and `enqueue` give way to an `AVSampleBufferRenderSynchronizer` with
      `sampleBufferReceiver(adding:)`. Needs a live call with picture in picture to verify.

## Worth considering

- **`swipeActions` on any view** (iOS 27, `swipeActionsContainer`): swipe on channel and direct
  message rows, which are plain stacks, for mute or mark as read. Messages keep long press.
- **`copyable` / `pasteDestination` / `onCopyCommand`** (iOS 27): Cmd C on a message on the Mac
  and an iPad keyboard.
- **`toolbarOverflowMenu`, `visibilityPriority`, `.topBarPinnedTrailing`** (iOS 27): pick which
  top bar buttons fold into a menu in a narrow iPad or Mac window, if the chat bar ever crowds.
- **`UITraitSystemPrefersReducedResourceUsage`** (iOS 27): back off GIF playback and outgoing
  video when the system asks.
- **Liquid Glass** (iOS 26): `glassEffect` is used once, `.buttonStyle(.glass)` never. The themed
  surfaces are deliberate, but floating controls (jump to bottom, the call tile, the voice bar)
  could take the system look.
- **`safeAreaBar` / `scrollEdgeEffectStyle`** (iOS 26) for the composer over the conversation,
  only if that code is reworked anyway.
- **Swift 6 readiness**: about 20 main actor and `Sendable` warnings, mostly AVFoundation objects
  captured in closures and theme constants read from `Sendable` closures.
- **`AsyncImage` without a cache** in link previews, reactions and search cards: a flash when a
  view is rebuilt, no jump, since their heights are fixed.
- **`print` for tRPC and voice errors** (7 places): `os.Logger` would show them in Console on a
  TestFlight build.

## Skipped on purpose

- `UIImpactFeedbackGenerator` to `.sensoryFeedback`: style only, no change in behaviour.
- `@Animatable` for the one hand written `animatableData` in `CardPosition`: cosmetic.
