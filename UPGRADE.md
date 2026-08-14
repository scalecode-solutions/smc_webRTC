# smc_webRTC — next-bump runbook (target: M151)

**Status:** parked deliberately, 2026-08-14. Verification is DONE; only the
build remains. Current build (M147) is fine — this bump is optional freshness,
not a fix.

## Where things stand

| Thing | Value |
|---|---|
| Shipping build | **M147** — `branch-heads/7727` @ `d09f0670e96e`, tag `147.2.0`, Xcode 26.4.1 |
| Next target | **M151** — `branch-heads/7922` (soaked stable; shipped a full stable run) |
| Skipped | M148, M149, M150 (M150 was the July plan target; the train moved) |
| Deferred | **M152** — `branch-heads/7977`, went stable ~2026-08-11; wait for the round after |
| Consumer | Clingy via SPM binary target (`Package.swift` URL + SHA256 pin) |

## API-surface verification — COMPLETE for M147 → M151

Our surface: `RTCAudioSession` (manual-audio mode), `RTCCameraVideoCapturer`,
`RTCMTLVideoView`, `RTCPeerConnection`(+Factory, delegates),
`RTCRtpSender`/parameters, `setCodecPreferences`.

| Window | Method | Verdict |
|---|---|---|
| `7727..7871` (M147→M150) | gitiles commit log, themed (2026-07-31) | clean on our surface |
| `7871..7922` (M150→M151) | **full-tree diff of `sdk/objc`** (2026-08-14) | clean — trivially |

The entire M150→M151 `sdk/objc` diff is **3 files, 34 lines, all internal**:
`RTCRtpHeaderExtension.mm` (`.id` → `.id.value()`, upstream optional-ization),
`RTCRtpHeaderExtensionCapability.mm` (native conversion rewritten to a C++
constructor), `objc_video_track_source.h` (an internal `#include` path moved).
Zero public-header changes; the other 373 files are byte-identical. The
`setCodecPreferences` nullability wart is unchanged — keep the `error: ()`
workaround.

Caveat: this verifies the **ObjC SDK contract only**. The C++ underneath (media
engine, ICE, AEC3, security fixes) is the point of bumping — behavioral
verification is the live-call gate below.

### How to verify the next window (M151→M152) in ~5 minutes

Gitiles `+log` pages are now **sign-in-gated** (403 since ~Aug 2026), but the
archive endpoint is open. Full-tree diff beats commit theming anyway:

```bash
for v in 7922 7977; do
  curl -s "https://webrtc.googlesource.com/src/+archive/refs/branch-heads/$v/sdk/objc.tar.gz" -o objc_$v.tar.gz
  mkdir objc_$v && tar -xzf objc_$v.tar.gz -C objc_$v
done
diff -ru objc_7922 objc_7977        # read every hunk; check the surface list above
```

Current milestone ↔ branch map (verify fresh via
`https://chromiumdash.appspot.com/fetch_milestones?only_branched=true` and
`fetch_releases?channel=Stable&platform=Mac&num=1`):
M147=7727 · M148=7778 · M149=7827 · M150=7871 · M151=7922 · M152=7977.

## The build (when ready)

1. `build/build_webrtc.sh`: set `BRANCH="branch-heads/7922"` and update the
   M147 comment strings. One line of real change.
2. Run it. Plan for the full ~15-20GB fetch (`build/webrtc_build/` is not on
   disk). Five GN/ninja builds → header fix → lipo → xcframework → zip.
3. **Tripwires** (the M147 lesson class): the script echoes
   `iOS sim fat binary archs:` and `macOS fat binary archs:` — both MUST print
   two archs. M147's ninja output silently shipped the mac framework's
   top-level binary as a regular file instead of the `Versions/A` symlink,
   which made `-create-xcframework` drop x86_64 from the mac slice; the script
   now handles that one (`build_webrtc.sh` step 9), but a new milestone can
   drift somewhere new. Read the final slice list.
4. Record the pinned upstream commit in the bump commit message
   (M147 precedent: `d09f0670e96e`).
5. `Package.swift`: new release URL + printed SHA256 →
   `gh release create 151.2.0 output/WebRTC.xcframework.zip --repo scalecode-solutions/smc_webRTC`
   → git tag `151.2.0`.
6. Bump Clingy's pin (Package.resolved; requirement is exact-ish via URL swap —
   commit the resolve).
7. **Acceptance gate: live calls, testical ↔ tmarq27** — audio, video,
   mid-call video toggle, minimize/expand, speaker toggle, a backgrounding
   round-trip. The unit suite exercises `FakeWebRTCClient`, not the binary;
   only live calls test the framework.
8. Ship in its own TestFlight release — never bundled with UI changes, so a
   field regression points at exactly one layer.

## Why M151 over M152 (decided 2026-08-14)

M152 went stable days before this was written — still collecting respins.
M151 finished a full stable run: soaked, boring, ideal for a vendored build
that only gets bumped a couple times a year. M152 (or later) next round, with
its own 5-minute archive diff first.
