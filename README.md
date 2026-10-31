# Codex Meter

Codex Meter is a native macOS menu-bar app that shows usage limits, AI credits, and banked resets for the Codex CLI account on your Mac. It supports personal plans and Business, Enterprise, and Edu workspace plans. You can also use the app to consume an available banked reset.

## Requirements

- macOS 13 or later
- Codex CLI installed and set up for your account
- Apple Command Line Tools with `swiftc`, `xcrun`, and `codesign`

## Build and run

From the repository directory, run:

```zsh
./build.sh
open "build/Codex Meter.app"
```

The build script compiles for the current Mac architecture and creates a locally signed app at `build/Codex Meter.app`.

## Use

Select the gauge icon in the menu bar to open the limits panel. Codex Meter displays the 5-hour and weekly usage windows, reset times, and banked resets when the Codex CLI provides that data.

The separate **AI credits** section shows the reported balance or credit availability, including unlimited status. If Codex returns an individual spending limit, the app shows credits used, the limit, the remaining percentage, and the reset time. Messages distinguish depleted workspace or member credits from workspace or member spending limits.

The app reads only the data returned by your signed-in Codex CLI. It does not fetch workspace billing data or calculate a shared workspace balance. Missing balances and spending limits remain unknown. AI credits can appear without 5-hour or weekly limits. For workspace plans, the app hides the banked-resets section unless resets are available. Update Codex CLI if your version does not return credit or spending-limit data.

The menu bar shows the remaining percentage for the 5-hour window. In **Settings**, you can switch it to the weekly window. If the selected window is unavailable, only the icon appears.

Codex Meter refreshes at launch and at the interval set in **Settings**. The default is one minute; the stepper accepts intervals from 1 to 60 minutes. It also refreshes when you open the panel if the last successful update is more than one minute old. Select **Refresh** to fetch the latest data immediately. The panel shows the time of the last successful update and marks data as stale after twice the configured interval or after a refresh error. The menu-bar tooltip also marks stale data. Countdown labels update while the panel is open.

In **Settings**, you can enable separate alerts for the 5-hour and weekly windows at 80%, 90%, or 95% used. Alerts are off by default and require macOS notification permission. The app checks usage at each refresh, so it must be running to send alerts. It sends an alert once per window, reset period, and threshold during an app session, and can alert again after a restart. If Codex does not provide a reset time, an alert can fire again after usage falls below its threshold and rises back above it.

To consume a banked reset, select **Use** beside an available credit and confirm. This changes your Codex reset schedule. Codex Meter refreshes the displayed data after the reset request succeeds.

## Codex CLI path

Codex Meter checks these paths in order:

- `~/.local/bin/codex`
- `~/.bun/bin/codex`
- `~/.npm-global/bin/codex`
- `/opt/homebrew/bin/codex`
- `/usr/local/bin/codex`
- `/usr/bin/codex`
- Each directory in `PATH`

To use a different executable, open **Settings** in the panel and enter its full path. Leave the field empty to use automatic detection. The path is saved in macOS user defaults.

Codex Meter starts `codex app-server --listen stdio://` to read usage data and process reset requests.

## Troubleshooting

If the build fails, check that the Command Line Tools are selected and that the macOS SDK is available:

```zsh
xcode-select -p
xcrun --sdk macosx --show-sdk-path
xcrun swiftc --version
```

If Codex Meter cannot find Codex CLI, confirm that the executable exists and is executable, or set its full path in **Settings**.
