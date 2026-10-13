#!/bin/bash
# Архив хранилища Trace для безопасной репликации между обновлениями.
# Использование: scripts/archive-vault.sh <путь к vault> <выходной файл без расширения>
# Формат: rar, если установлен проприетарный `rar` (brew install rar),
# иначе — zip (ditto, сохраняет метаданные).
set -euo pipefail

VAULT="${1:?Usage: archive-vault.sh <vault> <output-without-ext>}"
OUTPUT="${2:?Usage: archive-vault.sh <vault> <output-without-ext>}"

[ -d "$VAULT" ] || { echo "Vault не найден: $VAULT" >&2; exit 1; }

if command -v rar >/dev/null 2>&1; then
  rar a -idq -ep1 "$OUTPUT.rar" "$VAULT"
  echo "Created $OUTPUT.rar"
else
  echo "rar не установлен (brew install rar) — использую zip." >&2
  ditto -c -k --sequesterRsrc --keepParent "$VAULT" "$OUTPUT.zip"
  echo "Created $OUTPUT.zip"
fi
