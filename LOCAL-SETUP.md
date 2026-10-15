# Keira Prompter — native Mac application

The installed app is `~/Applications/Keira Prompter.app`. Open it from Finder, Spotlight or the Dock. It is a native Swift/AppKit/SwiftUI application, not a browser window or a website wrapper. The earlier browser-only launcher was removed and its test server stopped. Upstream web source remains in Git history and this repository as reference; it is not required to run the native app.

## Use

Paste a script in the editor, name it and click Open reading window. Scripts auto-save locally under `~/Library/Application Support/Keira Prompter/scripts.json`. The reading window floats over other apps. Follow voice requests macOS speech and microphone permission and requires on-device English (UK) recognition. The app never falls back to sending audio to a cloud recognizer. Auto-scroll works without microphone access. Use Restart to return to the beginning, A−/A+ for text size, and the editor's speed/opacity sliders to adjust appearance. Bracketed cues remain visible but are skipped by speech matching. The menu-bar icon can reopen the editor or overlay.

## CleanShot exclusion — FAILED on this Mac

The controlled full-display CleanShot test on macOS 26.2 FAILED: the purple test window, with `sharingType = .none`, appears over the green test background in the saved recording. This supersedes the earlier inconclusive blank-region frames. Do not use this build as an invisible CleanShot teleprompter. Apple describes this flag as legacy and no longer used: https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum .

The app menu's “Verify recording privacy…” opens a plain green background and a protected purple test window without microphone access or changing scripts. Record the display, then inspect the saved video: purple visible means failure. “Finish recording test” closes both test windows. The editor now states the failed result explicitly.

Evidence remains local in CleanShot history: `media_w9Vkm5Tvoy/CleanShot 2026-10-15 at 14.05.44.mp4`, 23.0617 seconds, 3436×1436, video only. The frame at 16 seconds clearly includes the protected window. No screenshots or recordings containing desktop context are pushed to GitHub.

## Build and install

Run `./native/build.sh` with Swift Command Line Tools installed (no Xcode project required). It builds for this Mac's architecture with macOS 14 minimum, generates the app icon and ad-hoc signs the bundle under `~/Library/Caches/KeiraPrompter/build/Keira Prompter.app`. Quit the installed app, copy the bundle into `~/Applications/` using `ditto`, and verify with `codesign --verify --deep --strict`. The cache build location avoids cloud-file-provider metadata interfering with signing in Documents.

No subscription, hosting, API key or paid speech service is used. This is a local, ad-hoc-signed build for Keira, not a notarized distribution or an App Store release. The native code was written in this task; the original browser project's GPL-3.0 license and attribution remain intact.

## Verified 15 October 2026

- Native compilation, icon generation, plist lint and ad-hoc signature verification passed.
- Actual UI opened the editor and floating reading window. Auto-scroll moved the scroll position; pause/restart returned it to the top.
- `KeiraPrompter --self-test` passed cue skipping, partial-result progress, restart, repeated phrases, contraction normalization, and script save/reload against an isolated temporary store.
- Microphone permission and a real spoken test are not completed.
- A visual-only CleanShot capture finished (260.018 seconds, 1700×1200, video stream only). Frames at 2s and 120s contain no script text; the native overlay remained open with accessible controls and its direct capture returned blank. The initial overlay frame (x160,y180,width650,height420 points) lies inside the selected recording area (x100,y82,width850,height600 points), assuming the same display origin. This is evidence for this region capture, not a guarantee across full-screen mode, other recorders or a changed display setup. Automation could not reliably access the stop control and a user stop request was sent before the finalized file was read. No further stop action is needed. The real speech-permission/live-voice check remains open.
- Notchie was quit and moved from `/Applications/Setapp/Notchie.app` to the user's Bin at her request. Its user data was not erased.

Review: no client agent behavior or live server changed. The native app's speech request explicitly requires on-device support; errors stop after bounded retries. Scripts save atomically. Secret hooks remain enabled; source must be committed/pushed before handoff. Capture/privacy limitations remain explicit rather than being bypassed with private APIs or unverified claims.

Checklist self-review (the standing rule overrides the older checklist's mandatory claudex-loop wording):

1. **Pass:** native source, icon generator and reproducible build script are saved together and pushed to Keira's VoicePrompter fork; no VPS deployment.
2. **Pass:** one installed native app; browser launcher removed and server retired. Upstream web source is reference, not a second running implementation.
3. **Pass:** no embedded credentials or cloud speech fallback; normal secret hooks retained. Hiding the overlay and opening the editor pause capture/scrolling. No security warnings or OS permissions bypassed.
4. **Not applicable:** no client-facing agent behavior changed.
5. **Pass for installed build; acceptance limited:** installed bundle signature and plist verified and native UI read back. Auto-scroll and matching/persistence tests pass. Actual spoken recognition and full-screen CleanShot exclusion remain unverified. Notchie can be restored from Bin; the native app can be removed without deleting scripts.

15 October follow-up: captured full-display test failure and corrected the UI and docs. Added CleanShot Record Screen / Stop Recording shortcut Control–Option–Command–R for a reliable test stop. No paid product purchased. The official VoicePrompter native free tier advertises 3 scripts and capture hiding, but that product is not yet verified with this setup.
