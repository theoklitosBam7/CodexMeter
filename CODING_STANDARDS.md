# Coding standards

## Swift and AppKit

- Follow the surrounding Swift style: four-space indentation, descriptive names, and explicit control flow. Keep types and functions focused on their current responsibilities.
- Keep AppKit view updates on the main thread. Run Codex process work off the main thread and return results to the main thread before changing UI state.
- Keep the app compatible with the minimum macOS version in `Info.plist`. Preserve menu-bar operation and keyboard and accessibility support when changing controls.
- Keep settings in `UserDefaults` consistent with their UI and documented defaults. Validate values read from persistent storage before using them.

## Codex data and actions

- Treat Codex CLI responses as external input. Handle absent, malformed, and unknown fields without inventing balances, reset times, or workspace billing data.
- Preserve the distinction between reported values and unavailable values in models and UI text. Do not present estimates as reported data.
- Keep reset consumption behind explicit user confirmation. Preserve idempotency and report unsuccessful or unknown outcomes without claiming success.
- Keep refresh and reset failures visible without discarding the last successful snapshot. Do not mark a snapshot stale solely because an unrelated action failed.

## Tests and documentation

- Add or update checks for changed parsing, state, and view behavior. Cover missing data and failure paths when relevant. Run the commands in [AGENTS.md](AGENTS.md).
- Update `README.md` when a change affects setup, settings, refresh behavior, permissions, or other user-facing behavior.
