# Changelog

## 0.5.0 — 2026-11-08 (published 2026-11-13)

- Default to persistent automatic external-only operation after login/app start.
- Remove OS/driver fingerprint and stored-confirmation prerequisites; driver changes no longer ask for a manual test.
- Replace permanent failure pauses with boot-scoped 60-second retry cooldowns.
- Keep the user login agent running with RunAtLoad and KeepAlive, with a 10-second restart throttle.
- Show direct external-only and temporary panel-restore actions; automatic switching requires no confirmation countdown.
- Retain stable-identity recovery, actual mode readback, external-loss monitoring and refresh-rate preservation.
- Pass 19 automation checks and real login-agent/relaunch readback checks; true reboot/driver-upgrade acceptance remains unverified.

## 0.4.0 — 2026-10-31

- Add app/menu icons and a shared blue-violet/teal visual identity.
- Refresh all four pages for light/dark appearances and expose automation state in the overview.

## 0.3.2 — 2026-10-28

Initial public source snapshot, published as **MacDisplaySwitch for macOS**. The app bundle, executables and preference domain retain the original DisplayFocus name for compatibility.

- Persist physically verified external/display-mode/OS-driver profiles across logins.
- Add startup delay, stable-configuration gate and bounded automatic actions.
- Keep an independent recovery process after manual or automatic confirmation.
- Resolve builtin recovery by saved UUID across hot-plug display-ID changes; reject ambiguous/synthetic targets.
- Use a stable boot-session UUID and monitor actual helper liveness.
- Start the real GUI executable from a user LaunchAgent with throttled crash restarts.
- Preserve external modes and remove mirroring as a panel-disable fallback.

Earlier private prototypes led to the current guarded design. See TESTING.md for the failed recovery and the limits of final-version hardware validation. The public export does not include private handoff material or device-specific settings.
