# MacDisplaySwitch for macOS

**Automatic external-only display utility · macOS 自动仅外屏工具**

Version **0.5.0** closes the built-in display automatically after login when an external display is available. Driver updates no longer require a manual test or confirmation. Unplugging the external attempts to restore the built-in panel; reconnecting resumes external-only operation. Existing resolution and refresh rate are preserved.

The project is named **MacDisplaySwitch**. The application, executables and preference domain retain **DisplayFocus** for compatibility.

## Download 0.5.0

[Download the Intel macOS app](https://github.com/sherves/MacDisplaySwitch/raw/refs/heads/main/Downloads/0.5.0/DisplayFocus-0.5.0-macOS-x86_64.zip) · [SHA256](Downloads/0.5.0/SHA256SUMS.txt)

The source is available in this repository through **Code → Download ZIP**, or the build instructions below.

## What changed in 0.5.0

- Automatic mode defaults on and resumes at every application start, including after login. Obsolete confirmation profiles and permanent pause settings are cleared.
- No OS/driver fingerprint or previous physical confirmation is required for automatic operation.
- Startup waits 8 seconds; connected display configuration must remain stable for 4 seconds.
- Temporary failures are retried after a 60-second cooldown instead of permanently turning automation off.
- The user LaunchAgent uses `RunAtLoad` and `KeepAlive=true`, with a 10-second restart throttle. The menu's former quit action now restarts the app through launchd.
- A new app/menu icon and refreshed light/dark interface are included. The overview shows the current resolution, refresh rate and automation status.
- Live display checks and the independent external-loss recovery process continue in the background. The normal automatic path shows no manual confirmation countdown.

## Build and install

Requirements: macOS 13+ build target, Swift Command Line Tools or Xcode, and an awake graphical session for the fixture checks. No external Swift packages are required. The current binary is **Intel x86_64**, ad-hoc signed, and not notarized.

```bash
git clone https://github.com/sherves/MacDisplaySwitch.git
cd MacDisplaySwitch
bash scripts/check.sh
bash scripts/build.sh
```

Outputs are `build/DisplayFocus.app` and `.build/release/displayfocus`. Keep the complete app bundle: `Contents/MacOS/DisplayFocusRecovery` is required. Preserve any older installation before replacing it. Put the full application at `/Applications/DisplayFocus.app` and open it normally.

**Opening the app enables automatic external-only operation and maintains its login item.** Configure an extended desktop and connect the external first. The app appears in the menu bar. The overview's **立即仅外屏** action requests an immediate switch without an extra confirmation. **临时恢复内屏** restores the panel and pauses automatic closing until the next app start/login.

Automation runs after user login, not during firmware boot, disk unlock or the login screen. The app cannot make a driver recognize an otherwise missing external display.

If SwiftPM is unavailable, use `bash scripts/build-swiftc.sh`. Builds use the host architecture. To regenerate icons:

```bash
swift scripts/make-icons.swift Resources
iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
```

## CLI

```bash
.build/release/displayfocus diagnose       # Read-only display state
.build/release/displayfocus status
.build/release/displayfocus auto on
.build/release/displayfocus auto off       # Pause until next app start/login
.build/release/displayfocus enable-builtin # Pause and restore the panel
.build/release/displayfocus login on
.build/release/displayfocus login off
```

The installed CLI is `/Applications/DisplayFocus.app/Contents/MacOS/DisplayFocusRecovery`. `auto off` alone does not restore a disabled panel. To stop the utility completely, unregister the login agent first, then restore the panel:

```bash
"/Applications/DisplayFocus.app/Contents/MacOS/DisplayFocusRecovery" login off
"/Applications/DisplayFocus.app/Contents/MacOS/DisplayFocusRecovery" enable-builtin
```

Opening the app again resumes automation and recreates its login configuration. Legacy `disable-builtin` / `confirm-disable` / `revert-disable` CLI commands remain available for optional manual diagnostics; they are not prerequisites for automatic operation.

Run the CLI without arguments for resolution, refresh-rate, gamma, HiDPI override and text-size commands. HiDPI overrides require administrator authentication and may replace a file at the selected vendor/product path. Software gamma is not hardware brightness.

## Validation and scope

Version 0.5.0 passed a release build, strict signature verification, 19 automation checks, and independent recovery-process fixtures. In the running login session, a real LaunchAgent start automatically disabled the panel without manual confirmation; the external remained 2560×1440@144Hz beyond the old confirmation deadline. Terminating the GUI caused launchd to restart it, with the panel still disabled and monitoring alive.

The project has been exercised on one Intel/OpenCore RTX 3060 laptop with macOS 26.7.1. **A full reboot, a fresh driver upgrade, repeated physical hot-plug, sleep/wake, Apple Silicon and native Mac compatibility have not been qualified for 0.5.0.** Readback does not prove physical usability. Private SkyLight APIs and driver behavior can change; a hung driver or WindowServer can prevent recovery. Logical disable does not guarantee backlight power-off.

See [DESIGN.md](DESIGN.md), [TESTING.md](TESTING.md), [CHANGELOG.md](CHANGELOG.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

## Data and privacy

No telemetry or built-in upload. Preferences (`com.holmes.displayfocus`), recovery tickets (`~/Library/Application Support/DisplayFocus/Recovery/`) and the user login agent stay on the Mac. Diagnostics may contain display identities: redact them before sharing. This repository and release source package exclude real profiles, recovery tickets, raw logs, EFI, driver files, local backups and private handoff notes.

## 中文说明

**0.5.0 默认持续自动仅外屏**：登录后运行，外屏连接稳定后自动关闭内屏。更新驱动不再要求点测试或确认；拔掉外屏恢复内屏，接回后自动关闭。启动等待 8 秒，连接稳定等待 4 秒；临时失败后等待 60 秒再自动重试。

把完整 `DisplayFocus.app` 放到“应用程序”后打开。程序会开启自动模式并维护登录启动项，退出后由系统自动重新运行。“立即仅外屏”直接切换；“临时恢复内屏”只暂停本次自动关闭，下次启动或登录恢复自动。

应用图标与四页界面已更新。当前下载包是 Intel x86_64 版本。恢复目标按内屏 UUID 重新枚举，外屏模式和刷新率保持；逻辑关闭仍不保证背光断电。本次已验证登录项启动后无需人工确认自动关闭、保持外屏 144Hz，以及主程序退出后自动重新运行；真正重启、升级驱动后的实机流程及长期稳定性仍待验收。

如需完全停用，在终端依次运行上方的 `login off` 与 `enable-builtin`。再次打开应用会恢复自动模式及登录项。

## License

[MIT](LICENSE). Developed with AI assistance and owner-operated testing. This is an independent project, not an official component of Apple, NVIDIA, NullMoth or a commercial display utility. No proprietary app code or graphics-driver binaries are distributed.
