#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/core_spec.lua"
nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/treesitter_spec.lua"
nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/python_spec.lua"
nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/lsp_spec.lua"
nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/typescript_spec.lua"
nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/languages_spec.lua"
nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/menu_spec.lua"
nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/menu_align_spec.lua"
nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/winbar_theme_sync_spec.lua"
if command -v python3 >/dev/null && python3 -c 'import pynvim' 2>/dev/null; then
  python3 "$root/tests/mouse_ui_spec.py"
else
  printf '%s\n' 'mouse_ui_spec: SKIP (python3/pynvim unavailable)'
fi
