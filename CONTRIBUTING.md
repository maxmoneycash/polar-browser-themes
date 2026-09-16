# Contributing

Good first contributions include readable theme presets, accessibility improvements to the studio, smaller-window layouts, native regression coverage, and compatibility reports with exact Polar build numbers.

## Themes

1. Run `./polar-themes new my-theme.json --from midnight`.
2. Choose a unique ID, descriptive name, and your author name.
3. Validate with `./polar-themes validate my-theme.json`.
4. Preview the normal and selected rows, light/dark appearance, and narrow windows.
5. Add the file under `polar_themes/assets/themes/` and register it in `index.json`.
6. Include a studio screenshot and describe the color/spacing decisions in your PR.

Please distinguish studio previews from screenshots of an installed native adapter.

## Code

```sh
python3 -m unittest discover -s tests -v
python3 scripts/build_site.py
```

For native work, also compile on macOS:

```sh
python3 scripts/native_adapter.py build --library-only
```

Keep the CLI, browser, and native validators aligned when changing the schema. Add focused tests for new behavior or a regression. Do not add required runtime dependencies to the theme CLI without explaining the need.

Native patches must include an exact build/hash, instruction preimages, a rollback path, and verification evidence. Never make an unknown executable pass a compatibility check by weakening the guard.

## Pull requests

Describe the concrete change and how you checked it. If it affects visible UI, include an image. If a limitation remains, state it. Keep generated app bundles, browser profiles, private run traces, tokens, and local paths out of commits.

Using AI coding tools is welcome. Contributors are responsible for understanding, testing, and maintaining the code they submit.
