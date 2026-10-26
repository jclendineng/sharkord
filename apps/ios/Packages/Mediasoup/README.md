# Mediasoup

The voice libraries for the iOS and Mac app, as a local package.

- The iOS slices are mediasoup-client-swift 0.13.2's own prebuilt binaries, unchanged.
- The macOS slices are built from the same sources: WebRTC M140 (branch-heads/7339) with the library's patches, libmediasoupclient `vl-3.5.0.1`, and the library's wrapper.
- The build lives outside the repo. `build-mac.sh` and `patch-mac-framework.py` there say exactly what was changed for macOS.

Link or copy `Mediasoup.xcframework` and `WebRTC.xcframework` into this folder before building.
The same two, zipped, are on the fork's `mediasoup-0.13.2-mac1` release, which the Mac
TestFlight workflow downloads and checks against the checksums it lists. A new build of them
goes on a new release, with the workflow's release name and checksums updated to match.
