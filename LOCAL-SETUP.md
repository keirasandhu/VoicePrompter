# Your local VoicePrompter

Source: https://github.com/kosuvorov/VoicePrompter at 99e08a0. Original GPL-3.0 license and attribution retained. This is the browser app, not the proprietary native Mac application.

Double-click **Start VoicePrompter.command**, keep its Terminal window open, and use http://127.0.0.1:4318/app/. Close the tab and press Control-C in Terminal to stop. The server only listens on this computer. Paste a script and start the prompter. Manual scrolling works without microphone access; voice following needs a compatible browser and its permission prompt.

Build manually with `npm ci` then `npm run build`. Start with `npm run preview -- --host 127.0.0.1 --port 4318 --strictPort`.

The upstream analytics, AI-traffic tracking and session recorder were removed from app/index.html. Local script history is stored by this browser under this local origin; it is not automatically synchronized with Kylon or other browser profiles. Google Docs import retains upstream external proxy behavior; use pasted text for this local workflow. External fonts and promotional links are retained. Browser speech recognition depends on the browser's implementation; this build does not enforce on-device/offline recognition. Recording-hide and native always-on-top features are not provided by this browser app.

This copy has no app subscription or paid server. Development tooling has upstream dependency audit findings; no dependency upgrades were made in this quick local build. It has not been approved for public hosting.

## Verified on 15 October 2026

`npm ci` and `npm run build` completed. Launcher passes `zsh -n`. Browser check loaded a sample script, rendered the reading view, opened settings, and returned to the editor. A microphone/voice-following test and camera recording were not performed. No third-party credentials or paid services were configured. The original project is upstream; this working branch is saved in keirasandhu/VoicePrompter. Secret scanning is enabled with `git config core.hooksPath tools/githooks`.

Review: saved-source requirement passes after push/readback; one active local app; secret scanning and loopback-only serving; client-agent character checks and production deployment checks do not apply. This is a local browser build, not a Mizi HQ or Kylon change.
