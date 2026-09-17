# Homem app icon

The icon adapts Memoh's original eyes and smile into a white brick mobile phone
with two cat ears, a screen opening, and a nine-key keypad. The background adapts
the sunset colors in the supplied Memoh website reference into a vertical gradient:
deep blue (`#194B82`), lavender (`#53649D`), rose (`#B67DA1`), and peach (`#F4A586`).

## Editable source

Open `Homem/Resources/AppIcon.icon` in Apple's Icon Composer (included with Xcode).
The foreground SVG layers are the handset shell and Memoh's original facial paths.
`Assets/Memoh Sunset.svg` supplies the four-stop gradient in a separate background
group, without glass, shadows, or translucency. Both the native icon and the legacy
renderer use this same gradient source.
Keep their 1024 × 1024 canvases aligned. Corner masks and lighting are applied by
Icon Composer, not baked into the SVGs. The foreground stays white in Default and
Dark appearances; Icon Composer generates the native tinted appearance.

The Xcode target includes this document as `AppIcon`. Xcode 26 compiles it into
the app's icon, including images for older supported systems. The existing asset
catalog contains an unmasked, opaque PNG of the same design as a legacy fallback.

## Export a preview

```sh
"$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool" \
  Homem/Resources/AppIcon.icon --export-image \
  --output-file docs/assets/homem-icon-default.png \
  --platform iOS --rendition Default --width 1024 --height 1024 --scale 1
```

Use `Dark` or `TintedDark` for the other preview renditions. These previews contain
the system icon mask; do not put them in the legacy marketing-icon slot.

Regenerate the opaque legacy fallback after editing the SVG artwork:

```sh
swift scripts/render-icon.swift Homem/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

The preview exports are in `docs/assets/homem-icon-*.png`.

## Attribution

Facial paths are adapted from `apps/web/public/logo.svg` in
[felinics/Memoh](https://github.com/felinics/Memoh/blob/1aaef83ff55a9432da4ac7dc631fff36f5e254ab/apps/web/public/logo.svg),
commit `1aaef83ff55a9432da4ac7dc631fff36f5e254ab`, under AGPL-3.0.
Copyright (C) 2026 MemohAI. See `THIRD_PARTY_NOTICES.md` and `LICENSE`.

[Apple's Icon Composer documentation](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
describes the layered icon workflow and Xcode integration.
