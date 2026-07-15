# macOS distribution

## Identity

- Bundle ID: `dev.gnaroshi.ArxivDiscovery`
- Stable local install: `/Applications/Arxiv Discovery.app`
- Minimum macOS: 14
- Version source: `pyproject.toml`
- Build number: Git commit count

The approved raster identity is copied into `identity/app-icon/` with its source hash. Platform sizes are generated with nearest-neighbor resampling and packaged as `AppIcon.icns`.

## Local delivery

```bash
./ArxivDiscoveryApp/build_app.sh
./ArxivDiscoveryApp/install_app.sh
```

The build script selects a Developer ID Application identity first, signs the bundled integration executable and the app, records commit/build/dirty provenance, and verifies the bundle. The install script refuses to replace a running app, performs a stable-path replacement, refreshes Spotlight metadata, and verifies the installed target.

## Public release boundary

Local Developer ID signing is not a public release. A public ZIP or DMG additionally requires a clean `v<semver>` tag, hardened runtime, timestamp, notarization, stapling, artifact checksums, and verified release metadata. The build does not silently fall back to ad-hoc signing unless an isolated packaging test explicitly opts in.

## Rollback

Keep the prior installed bundle until the replacement has moved into place. If verification fails, restore that bundle. Data remains outside the bundle and is not deleted by install or rollback.
