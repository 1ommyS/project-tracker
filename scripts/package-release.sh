#!/bin/bash
set -euo pipefail

APP_PATH="${1:?Path to Trace.app is required}"
OUTPUT_DIR="${2:-dist}"

mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/Trace.zip" "$OUTPUT_DIR/Trace.dmg"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$OUTPUT_DIR/Trace.zip"

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
ditto "$APP_PATH" "$STAGE_DIR/Trace.app"
ln -s /Applications "$STAGE_DIR/Applications"
diskutil image create from --volumeName "Trace" --format UDZO "$STAGE_DIR" "$OUTPUT_DIR/Trace.dmg"

echo "Created $OUTPUT_DIR/Trace.zip and $OUTPUT_DIR/Trace.dmg"
