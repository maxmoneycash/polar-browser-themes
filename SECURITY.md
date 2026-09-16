# Security

Report a security issue privately using GitHub’s private vulnerability reporting for this repository. Do not attach browser profiles, authentication tokens, or unredacted network captures to public issues.

Themes are data-only JSON. The validators restrict keys, formats, numeric ranges, and file size. Neither the CLI nor native renderer evaluates theme content as code or fetches its `$schema` URL.

The local studio listens only on loopback and requires a per-process capability token plus an exact origin for writes. Do not share the local studio URL; use the hosted preview or exported JSON to share a theme.

The native adapter intentionally modifies a local copy of a signed macOS app and changes the outer app’s signing identity. This is an experimental integration with material compatibility implications. Read [COMPATIBILITY.md](docs/COMPATIBILITY.md). The original signed Chromium host is not re-signed.

Do not redistribute Polar binaries. Public reproduction reports should use the theme JSON, exact version/build, and screenshots with personal content removed.
