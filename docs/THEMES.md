# Create a Polar Browser theme

```sh
./polar-themes new my-theme.json --from midnight
./polar-themes validate my-theme.json
./polar-themes use my-theme.json
```

Themes are complete JSON documents. Start from a preset instead of constructing one field at a time. Unknown fields, unsupported versions, incorrect types, invalid colors, non-finite numbers, and out-of-range geometry are rejected. Theme files are limited to 32 KiB.

The canonical [schema](../polar_themes/assets/schema/theme.schema.json) is included in the repository and embedded into the native adapter when compiled. A theme’s `$schema` field is editor metadata; the runtime never fetches it.

| Field | Meaning | Range / format |
| --- | --- | --- |
| `schemaVersion` | Format version | `1` |
| `id` | Stable theme ID | Lowercase letters, numbers, hyphens; starts with a letter; max 48 |
| `name` | Display name | 1–60 characters |
| `author` | Theme author | Up to 80 characters |
| `description` | Gallery description | Up to 240 characters |
| `appearance` | Native palette appearance | `dark` or `light` |
| `frame.color`, `frame.endColor` | Frame gradient endpoints | `#RRGGBB` |
| `frame.angle` | Gradient direction | −180 to 180 degrees |
| `frame.inset` | Page inset with browser controls hidden | 6–20 points |
| `frame.radius` | Page corner radius | 0–24 points |
| `palette.color`, `palette.endColor` | Palette gradient endpoints | `#RRGGBB` |
| `palette.angle` | Palette gradient direction | −180 to 180 degrees |
| `palette.border` | Palette outline | `#RRGGBB` |
| `palette.text`, `palette.muted` | Primary and secondary text | `#RRGGBB` |
| `palette.accent`, `palette.accentText` | Selected row background and text | `#RRGGBB` |
| `palette.radius` | Palette corners | 0–24 points |
| `palette.rowRadius` | Selected row corners | 0–14 points |
| `palette.width` | Preferred palette width, clamped to the window | 480–860 points |
| `palette.rowHeight` | Row spacing | 36–60 points |
| `palette.fontSize` | Primary row text; native system font | 12–20 points |
| `controls.hidden` | Hide the original top tabs and toolbar | Boolean |

Themes cannot supply JavaScript, HTML, remote images, fonts, file paths, or shell commands. They do not access tab content, credentials, or agent conversations.

## Live editing

Applying a theme validates it and atomically writes `current.json` into the theme configuration directory. The previous valid document becomes `previous.json`. The native adapter checks for changes once a second on the main run loop, validates again, then redraws. Invalid edits preserve the last valid rendering.

You can directly edit `current.json` for live development. For an isolated tooling/test configuration, set `POLAR_THEMES_HOME` before starting the CLI or native app. Changing it for the CLI alone does not change an already-running app’s configuration directory.

## Readability

Check primary and muted text against both ends of the palette gradient. Check selected text against the accent color. Test keyboard focus, narrow windows, and maximum font size. The schema validates structure and ranges; it does not certify visual contrast.

## Share a theme

Add a uniquely named JSON file to `polar_themes/assets/themes/`, add it to `index.json`, run the tests, and include a studio screenshot in your pull request. Use your own author name; do not imply an official Polar endorsement.
