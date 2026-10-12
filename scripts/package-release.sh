#!/bin/bash
set -euo pipefail

APP_PATH="${1:?Path to Pulseboard.app is required}"
OUTPUT_DIR="${2:-dist}"

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/Pulseboard.zip" "$OUTPUT_DIR/Pulseboard.dmg"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$OUTPUT_DIR/Pulseboard.zip"

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
ditto "$APP_PATH" "$STAGE_DIR/Pulseboard.app"
ln -s /Applications "$STAGE_DIR/Applications"
diskutil image create from --volumeName Pulseboard --format UDZO "$STAGE_DIR" "$OUTPUT_DIR/Pulseboard.dmg"

echo "Created $OUTPUT_DIR/Pulseboard.zip and $OUTPUT_DIR/Pulseboard.dmg"
