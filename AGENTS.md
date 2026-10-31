# Agent guide

Codex Meter is a native macOS menu-bar app written in Swift and AppKit. See [README.md](README.md) for setup and user-facing behavior.

For code changes and reviews, read [CODING_STANDARDS.md](CODING_STANDARDS.md).

## Verification

The checks are standalone Swift executables, not a Swift Package test suite. Run the relevant checks from the repository root. Use a temporary directory so verification does not replace the existing app bundle:

```sh
CHECK_DIR=$(mktemp -d)
xcrun swiftc -parse-as-library Sources/CodexMeter/*.swift -o "$CHECK_DIR/CodexMeter"
xcrun swiftc -parse-as-library \
  Sources/CodexMeter/Models.swift Sources/CodexMeter/CodexAppServerClient.swift \
  Tests/UsageParsingChecks.swift -o "$CHECK_DIR/parsingchecks"
"$CHECK_DIR/parsingchecks"
xcrun swiftc -parse-as-library \
  Sources/CodexMeter/AppState.swift Sources/CodexMeter/CodexLocator.swift \
  Sources/CodexMeter/CodexAppServerClient.swift Sources/CodexMeter/LimitsViewController.swift \
  Sources/CodexMeter/Models.swift Tests/LimitsViewChecks.swift -o "$CHECK_DIR/viewchecks"
"$CHECK_DIR/viewchecks"
```

The view checks require macOS and AppKit. Report any checks you could not run. `build.sh` removes and recreates `build/Codex Meter.app`; inspect the existing bundle and obtain permission before replacing it.
