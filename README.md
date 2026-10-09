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

Select **Refresh** to fetch the latest data. The app also refreshes when the displayed data is more than a minute old. Countdown labels update while the panel is open.

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
