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

The frame paint-order fix was verified on all four edges. Aurora and Porcelain updated the same open palette without a restart, Escape dismissed it, and ⌘⇧D restored the original tabs and toolbar. Window resizing at 900×660, 1100×800, and 1712×1068 kept the frame inset stable.

The live viewport check exposed a resize feedback loop in the first host-sizing correction. The revised adapter transforms page and host dimensions during native layout, before Chromium receives them. A native AppKit regression executable checks intermediate viewport notifications, stability across repeated layout passes, host alignment, thin overlays, inactive hosts, paint ordering, and toolbar restoration. Run it on macOS with:

```sh
mkdir -p build
xcrun clang -fobjc-arc -framework AppKit -framework QuartzCore tests/native_frame.m native/ThemeFrame.m -o build/test-native-frame
build/test-native-frame
```

The corrected build is installed; its final browser viewport check is pending macOS Keychain authorization. These checks do not constitute a complete native UI pass.

## Coverage limits

Fullscreen, split panes, video overlays, all sidebar transitions, multiple displays, VoiceOver workflows, updater interactions, and identity-bound features such as passkeys do not yet have complete regression coverage. No other native Polar build is supported. A passing test suite is not a claim of general compatibility.
