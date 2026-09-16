# Validation

Initial verification: September 15, 2026. This is an experimental first release, with a deliberately narrow native compatibility target.

## Automated checks

Run `python3 -m unittest discover -s tests -v` from the repository root. The 11 tests cover all bundled themes, invalid documents, atomic writes and undo, local studio authorization and path restrictions, unknown native executables, and refusal to replace a running app. The process test exercises the actual `pgrep` implementation, including application paths containing spaces.

The Python wheel was built and installed into a clean virtual environment. Its CLI loaded bundled theme resources from outside the repository directory. The native library was compiled with the macOS SDK and the generated app and original nested Chromium host both passed strict signature verification.

GitHub Actions runs the portable checks on Python 3.9 and 3.13, builds the static site, tests an installed package, and compiles the native adapter on macOS. See the [actual workflow results](https://github.com/maxmoneycash/polar-browser-themes/actions); native compilation in CI does not imply an installed-app UI test.

## Studio verification

Tested in an existing Arc browser using its Playwriter extension:

- Presets update the preview and editor.
- Shape controls update the preview inset.
- Arrow keys navigate the inspector tabs.
- Invalid JSON is rejected and valid JSON updates the preview.
- Exported Porcelain JSON downloads and passes the Python validator.
- Importing that exported file restores Porcelain in the editor.
- The authenticated local studio saves Midnight through its Apply button and removes the capability token from the visible URL.
- A 390-pixel viewport has no horizontal document overflow.
- Desktop and mobile previews were visually inspected.

The README image is a screenshot of the illustrative studio. It is not evidence that every browser surface supports theming.

## Native verification

Tested against an existing, logged-in Polar 0.1.92 installation, build 20260913071337, on Apple Silicon. The installer retained an untouched, signed backup, replaced only the application bundle, and Polar reopened with its existing tabs. Theme changes were observed without another restart, including a light Porcelain command palette and the dark Aurora palette. The floating palette accepts text and resizes to the result count.

The latest frame paint-order adjustment is installed but its final visual check is pending a macOS Keychain authorization prompt. Palette verification above predates that adjustment. Do not treat this note as a complete native UI pass.

## Coverage limits

Fullscreen, split panes, video overlays, all sidebar transitions, multiple displays, VoiceOver workflows, updater interactions, and identity-bound features such as passkeys do not yet have complete regression coverage. No other native Polar build is supported. A passing test suite is not a claim of general compatibility.
