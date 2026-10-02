#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Render each existing vector layer at 2x for visionOS's 512-point stack.
# App Store Connect requires the background layer to include a 2x rendition.
# Requires librsvg (rsvg-convert); no artwork is duplicated or redrawn.
source_dir='Homem/Resources/AppIcon.icon/Assets'
output_dir='Homem/Resources/Assets.xcassets/AppIconVision.solidimagestack'
for layer in Front Middle Back; do
    case "$layer" in
        Front) source_file='Memoh Face.svg' ;;
        Middle) source_file='Handset.svg' ;;
        Back) source_file='Memoh Sunset.svg' ;;
    esac
    rsvg-convert -w 1024 -h 1024 "$source_dir/$source_file" -o "$output_dir/$layer.solidimagestacklayer/Content.imageset/Layer.png"
done
