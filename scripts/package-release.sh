#!/bin/bash
set -euo pipefail

APP_PATH="${1:?Path to PROJECT Tracking.app is required}"
OUTPUT_DIR="${2:-dist}"

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/PROJECT-Tracking.zip" "$OUTPUT_DIR/PROJECT-Tracking.dmg"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$OUTPUT_DIR/PROJECT-Tracking.zip"

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
ditto "$APP_PATH" "$STAGE_DIR/PROJECT Tracking.app"
ln -s /Applications "$STAGE_DIR/Applications"
diskutil image create from --volumeName "PROJECT Tracking" --format UDZO "$STAGE_DIR" "$OUTPUT_DIR/PROJECT-Tracking.dmg"

echo "Created $OUTPUT_DIR/PROJECT-Tracking.zip and $OUTPUT_DIR/PROJECT-Tracking.dmg"
