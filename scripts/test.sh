#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
rm -f luacov.stats.out luacov.report.out
export LUA_PATH="/opt/homebrew/share/lua/5.5/?.lua;/opt/homebrew/share/lua/5.5/?/init.lua;${LUA_PATH:-;;}"
nvim --headless -u NONE -c "luafile tests/run.lua"
luacov
