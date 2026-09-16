# Installing the native adapter

The theme studio and JSON tools require no modified browser. These steps are only for changing Polar’s native frame and command palette.

## Requirements

- Apple Silicon Mac, macOS 14 or later.
- Python 3.9+ and Xcode command-line tools (`xcode-select --install`).
- Your own untouched Polar **0.1.92 / 20260913071337** installation.
- Read the [signing and compatibility limitations](COMPATIBILITY.md).

Do not downgrade a newer browser to use this prototype. Unknown versions are deliberately rejected.

## Build

From the repository root:

```sh
./polar-themes doctor
python3 scripts/native_adapter.py build
```

This verifies the original executable SHA-256, compiles the native adapter, and builds a locally signed copy at `build/Polar Themes.app`. Your installed app is unchanged.

If your original app is in another location:

```sh
python3 scripts/native_adapter.py build --original '/path/to/Polar.app'
```

The entire app is copied locally because it must be re-signed. On APFS, the builder uses copy-on-write cloning. Never commit or distribute the resulting app.

## Install

Finish any active browser work and quit Polar normally. Installation refuses a running app.

```sh
python3 scripts/native_adapter.py install
./polar-themes use midnight
open -a Polar
```

The installer backs up the untouched, signed original in `~/Library/Application Support/Polar Themes/backups/`. It stages the replacement beside the installed app and preserves the previous app for rollback. Browser profiles and cookies are not modified by the installer.

macOS may request Keychain access because the outer app’s signing identity changed. Another native rebuild can trigger the request again; editing a theme JSON file does not change the signature. Enter a password only in the macOS dialog. The locally signed app may not support identity-bound features such as passkeys. Use the original browser if those features are required.

## Change your theme

```sh
./polar-themes use ember
./polar-themes studio
```

Subsequent theme changes reload without restarting. ⌘L opens the floating palette, ⌘T opens it for a new tab, Escape dismisses it, ⌘S toggles the existing sidebar, and ⌘⇧D restores or hides the original browser controls. Arrow keys select palette results.

`controls.hidden` determines the initial layout and is reapplied when a theme changes. Frame styling is active in the hidden-controls layout. The original controls retain Polar’s own styling when shown.

## Restore the original browser

Quit Polar normally, then:

```sh
python3 scripts/native_adapter.py restore
open -a Polar
```

Restore verifies the original backup and refuses to overwrite an app with a different build. It restores the original signing identity and keeps the previous customized app. Theme files remain available for later use.

Polar’s updater remains enabled. If an update replaces the adapter, keep the new browser version and wait for a reviewed compatibility update. Do not attempt to force old offsets onto a new executable.
