# Display automation design

## Components

- `DisplaySafety`: enumerate CGS display records, prefer stable UUIDs, filter invalid/synthetic placeholders, reject ambiguous identities and mirroring.
- `DisplayTrial`: persist a boot-scoped transaction before changing displays, start a separate CLI and require its ready handshake, establish the external as main, disable the panel and validate actual state.
- `AutomaticDisplayPolicy`: store a physically confirmed panel/external/mode/environment profile. It never substitutes display IDs for durable identity.
- `AutoController`: callback plus 2-second polling, an 8-second startup wait, a 4-second stability gate and a maximum of six actions per minute.
- `DisplayFocusRecovery`: bundled CLI that owns the manual deadline and the continuing external-loss monitor independently of the GUI.

## Transaction lifecycle

1. `armed`: before any mutation, save original identities, layout and modes, boot-session UUID, monotonic deadline and a unique transaction token.
2. Wait for the helper's ready file and living process. Refuse disabling if it is missing.
3. Make the external primary without changing its mode, verify it and all original external outputs, then request panel disable. Check actual active state and preserved modes.
4. Manual confirmation before 25 seconds transitions to `monitoring` and saves the verified profile. Automatic confirmation only accepts an already verified profile and does not claim a new human observation.
5. Pending timeout/external loss attempts the original snapshot recovery. After confirmation, external loss restores only the panel, without replaying stale external modes/layout.
6. Recovery finishes as `restored` or `recoveryFailed`. A failed recovery pauses auto mode. Healthy confirmed monitoring is not subject to the original 25-second deadline.

An explicitly delayed confirmation may remember a manual test that already restored successfully within five minutes after its deadline. It must match the same boot, identities and external mode; it does not undo the timeout recovery or re-disable a display. Any later automatic close is a fresh guarded transaction. See the fixture checks for the acceptance conditions.

## Identity during hot-plug

The tested driver temporarily exposed changing display IDs, a false builtin flag on an external identity, and virtual fallback outputs. Recovery therefore targets the saved physical panel UUID and resolves its current ID each time. It refuses a missing/ambiguous target instead of selecting the first or primary display. A synthetic 1x1 output is not accepted as recovery success.

Retries are bounded to 20 seconds, at most one enable request every three seconds. Successful API return values do not alone establish success; active, online, non-sleeping and mode state are read back. Readback still cannot prove real scan-out or physical usability.

## Boot and process lifetime

Use `kern.bootsessionuuid`, not `kern.boottime`: the latter changed by one second during time synchronization in testing and caused a prior monitor to exit despite no reboot. If boot-session lookup fails, a process-local random UUID prevents cross-process transaction matching, so disable handshake fails before mutation. Recovery tokens also keep an old helper from acting on a new ticket.

Ready files contain the helper PID; the GUI checks liveness. If a managed panel disable loses its helper, the GUI pauses automation and attempts panel restoration. PID reuse and a hung WindowServer remain limitations; liveness is not proof of progress.

## Permissions and optional features

The core automatic display path runs in the user session and does not require administrator rights or alter EFI, GPU drivers, network settings or security policy. The optional HiDPI override action asks for administrator authentication to write its exact system override path. Software gamma is not hardware brightness; text-size settings use an undocumented preference.

The disable/enumeration functionality dynamically loads private SkyLight symbols. Future macOS releases or drivers can remove or change them. The OS/driver fingerprint currently includes SystemVersion and specific NullMoth files; it is not a complete inventory of arbitrary graphics drivers or firmware, and is cached for each process lifetime. Restart the app after environmental changes and re-test.
