# MacFeine

MacFeine is a small macOS menu bar app like Caffeine.
It keeps your Mac awake for a time you choose, or forever.

## What You Can Do

- Keep Mac awake for: `5m`, `15m`, `30m`, `1h`, `2h`
- Choose `Never` to keep it awake until you turn it off
- Use `Turn Off` to let macOS sleep normally again
- See current state directly in the menu bar

## From DMG
1. Install `MacFeine-Installer.zip`
2. Unarchive `MacFeine.zip`
3. Open `MacFeine-Installer.dmg`
4. Drag `MacFeine.app` to `Applications`
5. Open `MacFeine` from Applications

## How To Use

1. Click the cup icon in the menu bar
2. Pick a time (or `Never`)
3. When done, choose `Turn Off`

## Build From Source (App Bundle)

```bash
./scripts/build_app_bundle.sh
```

This creates:

```bash
dist/MacFeine.app
```

Run it directly:

```bash
open dist/MacFeine.app
```

## Dev Build (Optional)

```bash
swift build
.build/debug/MacFeine
```

## Notes

- App icon is generated from `logo/macfeine-logo.png`
