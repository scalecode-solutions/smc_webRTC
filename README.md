# smc_webRTC

**From-source Google WebRTC builds for iOS and macOS, shipped as a Swift Package binary target.**

![WebRTC](https://img.shields.io/badge/WebRTC-M152-blue)
![Platforms](https://img.shields.io/badge/platforms-iOS%2018%2B%20%7C%20macOS%2015%2B-lightgrey)
![SPM](https://img.shields.io/badge/SPM-binary%20target-orange)
![License](https://img.shields.io/badge/license-BSD--3--Clause-green)

Google stopped publishing official prebuilt WebRTC binaries years ago, and the
community builds that filled the gap tend to be milestones (or years) stale,
stripped of debug symbols, and iOS-only. This repo is the other path: build
libwebrtc **from Google's source**, at a **current milestone**, with everything
a real app and its test suite need — then pin it by checksum and distribute it
as a normal SPM dependency.

## What you get

One `WebRTC.xcframework`, built by [`build/build_webrtc.sh`](build/build_webrtc.sh):

| Slice | Archs |
|---|---|
| iOS device | arm64 |
| iOS simulator | arm64 + x86_64 (fat) |
| **macOS** | arm64 + x86_64 (fat) |

- **dSYMs for every slice** — symbolicated crash reports instead of hex soup.
- **Symbol export enabled** (`rtc_enable_symbol_export=true`) — the ObjC API
  surface is actually linkable, not just present.
- **macOS slices** — so `RTCPeerConnection` integration tests can run natively
  on a Mac host (or in CI) with *real* peer connections, no simulator required.
  This is the slice most distributions skip and the main reason this repo exists.
- VP9 enabled, release build, stripped, `symbol_level=1`.
- Headers rewritten to framework-style imports
  (`#import <WebRTC/RTCMacros.h>`), so the framework works out of the box.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/scalecode-solutions/smc_webRTC", from: "147.2.0")
]
```

Then depend on the `WebRTC` product. The binary is fetched from this repo's
GitHub Releases and verified against the SHA256 checksum pinned in
`Package.swift`.

Version numbers track WebRTC milestones: `147.x.y` = **M147**.

## Versions

| Tag | WebRTC | Upstream branch | Built with | Notes |
|---|---|---|---|---|
| `152.2.0` | M152 | `branch-heads/7977` @ `6f37672d3584` | Xcode 26.6 | current |
| `147.2.0` | M147 | `branch-heads/7727` @ `d09f0670e96e` | Xcode 26.4.1 | macOS fat-framework layout fix |
| `141.2.0` | M141 | `branch-heads/7390` | Xcode 26.2 | symbol export, x86_64 sim, macOS slices |
| `141.1.0` | M141 | `branch-heads/7390` | Xcode 26.2 | dSYMs added |
| `141.0.0` | M141 | `branch-heads/7390` | Xcode 26.2 | first from-source build |

## Building it yourself

```bash
./build/build_webrtc.sh
```

One script, ten steps, no hidden state: fetches `depot_tools`, syncs the WebRTC
source (~15–20 GB — this is Chromium infrastructure, bring disk and patience),
checks out the pinned `branch-heads` ref, runs five GN/ninja builds (one per
slice), fixes the headers, `lipo`s the fat simulator and macOS binaries
(including fat dSYMs), assembles the xcframework, zips it, and prints the
SHA256 for `Package.swift`.

Two hard-won details the script handles for you:

- **Header imports:** the ninja output ships headers with source-tree-relative
  imports (`#import "sdk/objc/base/RTCMacros.h"`); the script rewrites them to
  framework-style so the xcframework is consumable.
- **macOS `Versions/A` layout:** as of M147, ninja emits the mac framework's
  top-level binary as a regular file instead of the canonical symlink — which
  silently makes `xcodebuild -create-xcframework` pick the arm64-only inner
  binary and **drop x86_64 from the mac slice**. The script lipos into
  `Versions/A/` and restores the symlink. (Check the `fat binary archs:` lines
  in the output — they should always print two archs.)

## Updating to a new milestone

See [`UPGRADE.md`](UPGRADE.md) — the standing runbook: how to verify the
`sdk/objc` API surface between milestones in minutes (full-tree archive diff),
the milestone ↔ `branch-heads` map, the build tripwires, and the release
checklist.

## License

The packaging and build scripts in this repo are BSD-3-Clause
([`LICENSE`](LICENSE)). The distributed binaries are unmodified builds of
[Google's WebRTC](https://webrtc.googlesource.com/src/), which is licensed
under its own BSD-3-Clause terms with an additional
[patent grant](https://webrtc.googlesource.com/src/+/refs/heads/main/PATENTS);
those terms govern the framework itself.
