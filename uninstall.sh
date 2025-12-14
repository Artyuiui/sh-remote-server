#!/usr/bin/env bash
set -euo pipefail

BIN_PATH="$HOME/bin/sh"
CONF_SH="$HOME/.ssh/config.d/sh_hosts"
META_DIR="$HOME/.config/sh-shortcut"
FISH_COMPL="$HOME/.config/fish/completions/sh.fish"

rm -f "$BIN_PATH"
rm -f "$CONF_SH"
rm -rf "$META_DIR"
rm -f "$FISH_COMPL"

echo "🗑️ Uninstalled sh-shortcut."
echo "ℹ️ หมายเหตุ: ~/.ssh/config ยังอยู่เหมือนเดิม (ไม่ได้ลบ Include อัตโนมัติ เพื่อความปลอดภัย)"
