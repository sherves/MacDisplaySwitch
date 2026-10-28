# DisplayFocus

**Experimental macOS menu bar display utility · 实验性 macOS 外屏切换工具**

Connect a previously verified external monitor to use it as the only active display. Disconnect it to attempt to restore the built-in panel. Keep the monitor's existing resolution and refresh rate. A separate recovery process watches the transition and subsequent external-display loss.

Version **0.3.2** is a source release, developed and tested on one Intel/OpenCore laptop. It uses private SkyLight APIs, is not notarized, and is **not a general guarantee of compatibility or recovery**. A hung driver or WindowServer can prevent recovery. Logical disable does not guarantee that the panel backlight powers off.

[中文说明](#中文说明) · [Design](DESIGN.md) · [Test evidence and limits](TESTING.md) · [Changes](CHANGELOG.md) · [Contributing](CONTRIBUTING.md)

## Features

- One-time physical confirmation for a particular panel, external display, mode and OS/driver fingerprint.
- A 25-second confirmation deadline handled by a separate bundled CLI; recovery is attempted if not confirmed.
- External-loss monitoring continues after confirmation, even when the menu app exits.
- Automatic mode waits 8 seconds at app startup and requires 4 seconds of stable display configuration.
- Recovery resolves the panel's saved UUID to its current display ID, rejecting ambiguous targets and virtual placeholders.
- Automatic display switching does not replay stored modes or use a mirroring fallback.
- Optional user LaunchAgent starts the menu app after login; normal quit stays quit, crashes are throttled.
- Display/mode diagnostics, explicit resolution and refresh-rate selection, software gamma dimming/color temperature, and experimental HiDPI override/text-size controls.

## Requirements and scope

- macOS 13 or later is the build target; **only macOS 26.7.1 on Intel has been tested**.
- Swift Command Line Tools or Xcode. The current snapshot was built with Swift 6.3 in Swift 5 language mode.
- A working built-in display and a real, active external display are required for disable testing.
- No external Swift package dependencies, kernel extensions or NVIDIA driver files are bundled.
- The UI and CLI messages are currently primarily Chinese. Apple Silicon, native Macs, docks, multiple external displays, sleep/wake and other GPUs are unverified.
- This is an independent project, not an official component of BetterDisplay, Apple, NVIDIA or NullMoth.

## Build

```bash
git clone https://github.com/sherves/DisplayFocus.git
cd DisplayFocus
bash scripts/check.sh
bash scripts/build.sh
```

Outputs: `build/DisplayFocus.app` and `.build/release/displayfocus`. Keep the full app bundle: `Contents/MacOS/DisplayFocusRecovery` is required for protected disabling. The build script ad-hoc signs the app; it is not Developer ID signed or notarized. Do not disable macOS security protections to run it.

If SwiftPM is unavailable, `bash scripts/build-swiftc.sh` builds with `swiftc` and packages the app. Builds use the host architecture, not a universal binary. The fixture checks need an awake graphical session and are not `swift test`/XCTest tests.

For login startup, put the complete app in `/Applications/DisplayFocus.app` first. If an older installation exists, quit the app and preserve that installation before replacing it. Launch the app normally; it appears only in the menu bar, not the Dock.

## First use

1. Keep an independent recovery/control path available and observe the physical displays locally.
2. Connect the external screen and configure extended desktop using the system's normal display controls. Run `.build/release/displayfocus diagnose` to inspect the current state.
3. In the menu app choose **测试关闭内屏**. Verify that the external image keeps updating and input works. If it does not, do not confirm; the helper starts recovery at the deadline. Recovery completion is not guaranteed within 25 seconds.
4. Choose **外屏正常，保留** before the deadline. Only after this physical check enable **自动仅外屏**. Enable **登录时启动** separately if wanted.
5. Test unplug/reconnect with the actual hardware before unattended use. A different display/mode or changed OS/driver fingerprint needs fresh confirmation.

Auto mode applies **after user login**, not in OpenCore, FileVault unlock or the pre-login screen. It cannot make an unrecognized HDMI connection appear in the driver.

## CLI and recovery

```bash
.build/release/displayfocus diagnose       # Read-only actual display state
.build/release/displayfocus status
.build/release/displayfocus disable-builtin
.build/release/displayfocus confirm-disable
.build/release/displayfocus revert-disable
.build/release/displayfocus auto on
.build/release/displayfocus auto off
.build/release/displayfocus enable-builtin # Also turns auto off
.build/release/displayfocus login on
.build/release/displayfocus login off
```

For an installed app, the same CLI is available at:

```bash
"/Applications/DisplayFocus.app/Contents/MacOS/DisplayFocusRecovery" auto off
"/Applications/DisplayFocus.app/Contents/MacOS/DisplayFocusRecovery" enable-builtin
```

`auto off` alone does not restore a currently disabled panel. `enable-builtin` disables auto mode and attempts panel restoration. A normal quit leaves the independent recovery monitor running while a confirmed panel disable is managed. See [DESIGN.md](DESIGN.md) for failure handling and [TESTING.md](TESTING.md) for recovery limitations.

Run the CLI without arguments to see mode, scaling, gamma and HiDPI commands. Optional HiDPI override writes/removes a vendor/product file under `/Library/Displays/Contents/Resources/Overrides` and asks for administrator authentication; it may replace an existing file at that exact location, so preserve any existing override first. Text-size controls write user accessibility preferences. These are separate from hot-plug automation and have limited hardware validation.

## Data and privacy

No telemetry or built-in log upload. Display profiles, vendor/model/serial-derived keys, recovery tickets and optional login settings stay on the local Mac:

- Preferences: `com.holmes.displayfocus`
- Recovery: `~/Library/Application Support/DisplayFocus/Recovery/`
- Login agent: `~/Library/LaunchAgents/com.holmes.displayfocus.plist`

Diagnostic output can contain display identities. Review it before sharing. This public repository excludes the development machine's real profiles, raw logs, EFI, backups, account data and handoff records.

## 中文说明

DisplayFocus 是独立开发的菜单栏工具。核心用途是：**接上已确认的外屏后自动逻辑停用内屏，拔掉外屏时尝试恢复内屏**，不自动降低刷新率，不用镜像替代关闭。

首次必须看着实体外屏做一次 25 秒保护测试并确认，之后才开启自动模式；登录时启动需要单独开启。登录后先等待 8 秒，显示配置连续稳定 4 秒后才执行。不同屏幕、模式或系统/驱动环境需要重新确认。内屏恢复按保存的 UUID 重新枚举当前 ID，最多等待 20 秒；失败暂停自动操作，不循环强行重试。

目前仅在一台 RTX 3060 Laptop / macOS 26.7.1 / NVIDIA 2.6.3 机器上验证部分路径，外屏 2560×1440@144Hz 保持。曾出现第一次拔线恢复失败，修正后用户确认内屏恢复；最终版本的跨重启、反复插拔和长期稳定性仍待完整验证。**它不是驱动补丁，也不保证其他机器能用或背光彻底断电。**

构建使用上面的 `bash scripts/check.sh` 和 `bash scripts/build.sh`。恢复时使用 `enable-builtin`，它会同时关闭自动模式。不要依赖本工具恢复内核或 WindowServer 卡死；详细边界见 [TESTING.md](TESTING.md)。

## License and development

[MIT](LICENSE). Developed with AI assistance and owner-operated physical testing; this repository does not claim independent human authorship for generated code. No commercial-app binaries or source are distributed here. See [CONTRIBUTING.md](CONTRIBUTING.md) for reporting and validation expectations.
