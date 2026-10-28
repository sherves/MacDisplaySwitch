# Validation and remaining work

Snapshot: **0.3.2**, 2026-10-28. Observations below distinguish program readback from the owner's physical reports. No automatic reboot was performed.

## Test machine

- ASUS ROG GU603ZM, Intel Core i7-12700H, x86_64.
- NVIDIA RTX 3060 Laptop, 6 GiB VRAM, NullMoth driver 2.6.3.
- macOS 26.7.1 (25G241).
- Built-in 2560×1600@165Hz and HDMI 27G5 2560×1440@144Hz.

No actual display UUIDs, serials, raw logs, profiles or EFI are published.

## Completed checks

- Release build, complete app packaging and strict ad-hoc code-signature verification succeeded locally.
- `bash scripts/check.sh`: 16 safety/policy checks plus independent deadline and persistent-monitor process fixtures passed. Fixtures read live display state but do not configure displays or modify real preferences; child tickets use `changed=false`.
- Manual protected disable: owner saw builtin become black while external image/mouse remained usable; external mode read back at 144Hz.
- Unconfirmed test: helper initiated restoration at the 25-second deadline; owner confirmed both screens usable afterward. The deadline starts recovery, not a guaranteed completion time.
- Confirmed disable: external-only remained usable with 144Hz preserved.
- Direct LaunchAgent startup was exercised in the running login session; automatic disable and external mode were read back.
- First automatic unplug recovery failed. It was paused and manually restored. A later test after identity/re-enumeration changes was reported by the owner as a complete built-in recovery, followed by HDMI reinsertion.
- Final 0.3.2 fixed boot-session identity and helper-liveness checks; after deployment, the helper was observed alive beyond the old 25-second deadline while the external remained active at 144Hz.

## Limits — not yet established

- The second unplug report confirms the owner's observation; the recorded observation window does not establish the complete timing/cause of every step or a full automated reconnect cycle.
- The final 0.3.2 boot-UUID/liveness change was not followed by another full physical hot-plug cycle or a real reboot/login acceptance test.
- No overnight reliability, repeated rapid hot-plug, sleep/wake, remote-session continuity, multiple-external-monitor, native Mac or Apple Silicon qualification.
- A black physical panel does not prove backlight power-off or reduced energy consumption.
- HiDPI override/scaling support depends on the driver; an override file is not evidence that a requested mode exists.

## Manual test plan for contributors

1. Build and run fixture checks without changing display configuration.
2. Keep auto off and a recovery/control path available; connect the real external display.
3. Verify extended desktop, unique identities, active non-mirrored outputs and the intended mode.
4. Test a protected close without confirmation and verify actual restoration.
5. Test close with physical confirmation, then disconnect and reconnect the external while observing both physical screens.
6. Check that refresh rate is preserved, auto pauses on failure and `enable-builtin` restores the intended panel.
7. Separately test app quit/crash, helper failure, driver update/profile invalidation and true login startup. Do not deliberately crash a kernel/driver to test recovery.
8. Report hardware, versions, exact steps, physical observations and readback separately. Do not label a path verified solely because a command returned success.
