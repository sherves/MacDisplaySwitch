# Changelog

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
