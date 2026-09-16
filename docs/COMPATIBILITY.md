# Compatibility

| Component | Support |
| --- | --- |
| Hosted theme studio | Modern desktop and mobile browsers |
| Local studio and JSON CLI | Python 3.9+, no runtime packages |
| Native adapter | macOS 14+, Apple Silicon; exact Polar build below |
| Intel Macs / Windows / Linux native adapters | Not implemented |
| Sidebar / agent chat / settings theming | Not implemented |

Native target: **Polar 0.1.92, build 20260913071337**.

Original thin arm64 executable SHA-256:

```text
f7e1bcbc432a404cfbe0498f85eb0672375793dda3acfa2632acba9aba823fed
```

The adapter is experimental. It relies on version-specific Swift entry points and ARM64 layout patches, not a supported Polar plugin contract. `doctor` reports the installed version; the builder additionally checks the complete executable hash and each patch preimage.

## Signing

The outer native application is signed locally with an ad-hoc identity and library validation disabled. Developer-identity-bound entitlements and the original provisioning profile cannot accompany that signature. This can affect passkeys and other features requiring Polar’s developer identity. Keychain prompts may occur. The nested Chromium host keeps its original signature.

This project does not disable Gatekeeper, modify SIP, change TCC permissions, or remove browser update checks. The installer has no profile migration or cookie-management code.

## Updating compatibility

A new adapter requires inspecting the new binary, updating its instruction preimages and private API mapping, and testing native behavior. Changing the version number or SHA alone is insufficient. Until that work is complete, use the studio to design/export themes and keep your browser up to date.

## Supported geometry

The v1 adapter adjusts normal-window content insets from 6–20 points and clips continuous corners from 0–24 points. It updates matching content overlays together. Fullscreen, split panes, video overlays, and every sidebar transition need additional regression coverage; do not assume they have been validated simply because normal-window theming works.
