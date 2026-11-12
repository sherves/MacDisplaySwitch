# Display automation design

## Policy

0.5.0 evaluates live display records. It requires a usable built-in panel and a real, active, non-mirrored external display with unique identities. It does not read an OS/driver fingerprint or demand a saved confirmation profile. Every application start enables automation and removes legacy confirmation/permanent-pause records.

The controller waits 8 seconds at startup and 4 seconds of stable configuration. Callback notifications and a 2-second poll detect changes. Temporary errors preserve the enabled preference and set a boot-scoped 60-second retry cooldown. A new boot or app start clears obsolete retry state. The controller limits actions to six per minute.

## Transaction and recovery

`DisplayTrial` writes a boot-scoped, tokenized ticket before touching displays. A separate bundled CLI must complete its ready handshake. The app establishes the external as main without changing its mode, requests built-in disable and verifies the active state, external outputs, resolution and refresh rate.

Automatic transactions transition to `monitoring` after readback without user input. Their internal transition deadline is not shown as a manual confirmation countdown. Monitoring continues past that deadline; external loss restores only the panel rather than replaying stale external modes/layout. A pending failed transaction attempts snapshot recovery. An absent helper causes panel restoration and a later automatic retry. API success or PID liveness alone cannot establish physical usability or kernel progress.

The legacy manual CLI trial retains its 25-second confirmation flow for optional diagnostics. It is not part of the automatic startup path, and its confirmation no longer stores an automation profile.

Recovery resolves the recorded physical panel UUID to its current display ID. It rejects missing/ambiguous targets, synthetic outputs and virtual placeholders. The tested driver sometimes changed display IDs and mislabeled the external as built-in during hot-plug. Each panel-enable attempt is bounded to 20 seconds, with requests spaced by three seconds; failed controller operations may be retried in later cooldown periods.

## Process lifetime

Transactions use `kern.bootsessionuuid` and unique tokens so an old helper cannot act on a new boot or ticket. Ready files contain helper PIDs for liveness checks. The GUI and CLI share the preference domain.

The user LaunchAgent runs the installed GUI directly with RunAtLoad and KeepAlive=true, throttled to 10 seconds. The GUI maintains next-login configuration without unloading itself or spawning another copy. Each startup restores automatic mode; explicit manual panel restore/CLI `auto off` pauses only until the next app start/login. To stop entirely, unregister the login agent before restoring the panel. Opening the app again maintains the login item.

## Optional features and permissions

Core display switching runs in the user session. It does not modify EFI, kernel extensions, graphics drivers, networking or security settings. It dynamically loads private SkyLight symbols whose behavior may change. HiDPI override editing separately requests administrator authentication; gamma adjustment is software-only, and text size uses an undocumented preference.
