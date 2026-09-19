#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/core_spec.lua"
nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/treesitter_spec.lua"
nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/python_spec.lua"
nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/lsp_spec.lua"
nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/typescript_spec.lua"
nvim --headless -u NONE -c "set rtp^=$root" -l "$root/tests/languages_spec.lua"
