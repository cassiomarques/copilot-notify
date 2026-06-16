#!/bin/bash
set -euo pipefail

# Generate macOS .icns from SVG using sips (built into macOS)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ICON_SVG="$SCRIPT_DIR/Resources/Icons/AppIcon.svg"
ICONSET_DIR="$SCRIPT_DIR/Resources/Icons/AppIcon.iconset"
ICNS_FILE="$SCRIPT_DIR/Resources/Icons/AppIcon.icns"

# Check for rsvg-convert or use python/cairosvg
if command -v rsvg-convert &>/dev/null; then
    CONVERT_CMD="rsvg-convert"
elif command -v python3 &>/dev/null && python3 -c "import cairosvg" 2>/dev/null; then
    CONVERT_CMD="cairosvg"
else
    echo "Need rsvg-convert (brew install librsvg) or python3 with cairosvg (pip install cairosvg)"
    echo "Alternatively, open the SVG in a browser and export as 1024x1024 PNG manually."
    exit 1
fi

mkdir -p "$ICONSET_DIR"

# Generate PNGs at required sizes
SIZES="16 32 64 128 256 512 1024"

for size in $SIZES; do
    if [ "$CONVERT_CMD" = "rsvg-convert" ]; then
        rsvg-convert -w "$size" -h "$size" "$ICON_SVG" -o "$ICONSET_DIR/icon_${size}x${size}.png"
    else
        python3 -c "
import cairosvg
cairosvg.svg2png(url='$ICON_SVG', write_to='$ICONSET_DIR/icon_${size}x${size}.png', output_width=$size, output_height=$size)
"
    fi
done

# Create the iconset with proper naming for macOS
cd "$ICONSET_DIR"
mv icon_16x16.png icon_16x16.png 2>/dev/null || true
cp icon_32x32.png icon_16x16@2x.png
cp icon_64x64.png icon_32x32@2x.png
cp icon_256x256.png icon_128x128@2x.png
cp icon_512x512.png icon_256x256@2x.png
cp icon_1024x1024.png icon_512x512@2x.png

# Remove intermediate sizes not needed
rm -f icon_64x64.png icon_1024x1024.png

# Generate .icns
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"
echo "Created: $ICNS_FILE"

# Clean up iconset directory
rm -rf "$ICONSET_DIR"
