# Contributing

Small, explainable changes and real hardware reports are welcome. AI-assisted contributions are allowed; describe material assistance honestly and understand the submitted code. Do not claim a test or authorship that did not happen.

- One behavior change per pull request. Explain the trigger, resulting behavior, tests and remaining limitations.
- Run `bash scripts/check.sh` and `bash scripts/build.sh` on macOS with an awake graphical session. Build success is not physical-display validation.
- Preserve the independent recovery handshake, boot/token guards, stable identity selection, bounded retries and refresh-rate preservation.
- Never introduce a first-display/main-display recovery fallback, automatic security lowering or kernel/EFI changes.
- Changes that disable displays need explicit, owner-observed hardware testing with a recovery path. Document failures as well as passes.
- Do not reverse engineer or copy proprietary display utilities. Identify the origin and license of any third-party code added.

For reports, include machine/GPU/OS/app versions, the reproduction sequence, physical behavior and redacted readback. Remove monitor serials/UUIDs, account names, credentials, private paths and unrelated logs. Do not post a full EFI or recovery ticket.
