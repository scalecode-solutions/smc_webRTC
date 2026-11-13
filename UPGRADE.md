# smc_webRTC — milestone upgrade runbook

**Current build: M158** — `branch-heads/8127` @ `fb1c41a93d92d4188f068f437d80ef2c4b50c3a9`,
built 2026-11-13 with Xcode 27.2 on Apple Silicon. Tag `158.2.0`.
Next bump: whenever — run the 5-minute surface check below first.

## API-surface verification ledger

Consumer surface (Clingy's WebRTCClient): `RTCAudioSession` (manual-audio mode),
`RTCCameraVideoCapturer`, `RTCMTLVideoView`, `RTCPeerConnection`(+Factory,
delegates), `RTCRtpSender`/parameters, `setCodecPreferences`.

| Window | Method | Verdict |
|---|---|---|
| `7727..7871` (M147→M150) | gitiles commit log, themed (2026-07-31) | clean |
| `7871..7922` (M150→M151) | full-tree `sdk/objc` archive diff (2026-08-14) | clean — 3 files, all internal |
| `7922..7977` (M151→M152) | full-tree `sdk/objc` archive diff (2026-08-14) | clean — `copy`-attr cleanup on readonly props + additive `RTCCertificate.getFingerprints`/`RTCDtlsFingerprint`; our files untouched |
| `7977..8127` (M152→M158) | full-tree `sdk/objc` archive diff (2026-11-12) | clean for Clingy — 6 files. Public: `kRTCFieldTrialH264HighProfileKey` **removed** (Clingy doesn't use field trials). **Behavioral:** `RTCPeerConnectionFactory` no longer creates its own worker thread; the network thread now does that job too (live calls are the gate). Rest internal (absl→std, `std::span`, `constinit`) |

The `setCodecPreferences` nullability wart persists through M158 — keep the
`error: ()` workaround.

### The 5-minute surface check (do this before any bump)

Gitiles `+log` pages are **sign-in-gated** (403 since ~Aug 2026); the archive
endpoint is open and a full-tree diff beats commit theming anyway:

```bash
for v in OLD NEW; do
  curl -s "https://webrtc.googlesource.com/src/+archive/refs/branch-heads/$v/sdk/objc.tar.gz" -o objc_$v.tar.gz
  mkdir objc_$v && tar -xzf objc_$v.tar.gz -C objc_$v
done
diff -ru objc_OLD objc_NEW     # read every hunk; check the surface list above
```

Milestone ↔ branch map (refresh via
`https://chromiumdash.appspot.com/fetch_milestones?only_branched=true`, current
stable via `fetch_releases?channel=Stable&platform=Mac&num=1`):
M147=7727 · M148=7778 · M149=7827 · M150=7871 · M151=7922 · M152=7977 · M153=8010 · M154=8037 · M155=8059 · M156=8078 ·
M157=8103 · M158=8127 · M159=8154 (beta at 2026-11-12).

## The build

1. `build/build_webrtc.sh`: set `BRANCH="branch-heads/NNNN"` + comment strings.
2. Run it. With a warm `build/webrtc_build/` the sync is minutes; cold fetch is
   ~22GB (took ~10 min on fiber). The five ninja builds took ~20 min total on
   an M5 — the whole M152 build was ~35 minutes end to end. M158 from a cold
   checkout took ~1h35 (fetch ~30 min, ninja ~65 min).
3. **Tripwires:** the `iOS sim fat binary archs:` and `macOS fat binary archs:`
   echoes must BOTH print two archs, and `remaining broken: 0` on all five
   header fixes. Verify the mac slice directly:
   `lipo -archs .../macos-arm64_x86_64/WebRTC.framework/Versions/A/WebRTC`
   and that the top-level `WebRTC` is a symlink (the M147 lesson). Every
   `Umbrella check … missing 0` (the M158 lesson; the script exits on a miss).
   Then **import it from Swift** — the only check that proves the mac slice is
   usable (`swiftc x.swift -F .../macos-arm64_x86_64 -framework WebRTC`, make a
   factory + peer connection). 141.2.0–152.2.0 shipped a mac slice that passed every
   other tripwire yet couldn't be imported (headers missing).
   If packaging needs a redo, `PACKAGE_ONLY=1 ./build/build_webrtc.sh` reruns
   steps 9–10 alone.
4. Record the pinned upstream commit
   (`git -C build/webrtc_build/webrtc/src log -1`) in the bump commit.
5. Update `Package.swift` (release URL + printed SHA256), README badge +
   version table, this file's header. Commit, push, then:
   `gh release create NNN.2.0 build/output/WebRTC.xcframework.zip --repo scalecode-solutions/smc_webRTC`
   (tag rides the release).
6. Consumer bump (Clingy) is a SEPARATE decision: update the pin, then the
   acceptance gate is **live calls** (audio, video, mid-call video toggle,
   minimize/expand, speaker, backgrounding round-trip) — the unit suite fakes
   WebRTC; only live calls test the binary. Ship in its own TestFlight release.

## Sync failures seen in the wild (M152 build, 2026-08-14)

- **`FileNotFoundError ... _DeleteOrMove ... third_party/<dep>/src`** during
  `fetch`/`gclient sync`: a dep's DEPS layout migrated (e.g. `pthreadpool` →
  `pthreadpool/src`) and the relocation of the old checkout died partway,
  leaving a `_bad_scm/` quarantine dir. Fix: delete the half-moved dep dir AND
  `_bad_scm/`, then **`git checkout -- .` inside `src/third_party`** to restore
  any tracked files the deletion took with it (gclient refuses to sync over
  tracked deletions: "You have uncommitted changes"). Re-run; gclient
  fresh-clones the dep at its new path.
- Untracked `??` entries under `src/third_party` (boringssl/src, catapult, …)
  are normal — nested dep checkouts, not dirt.
