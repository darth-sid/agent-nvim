#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
rm -f luacov.stats.out luacov.report.out

lua_path_from_luarocks() {
  luarocks path --lr-path 2>/dev/null || true
}

LUA_PATH_PREFIX="$(lua_path_from_luarocks)"
if [[ -n "${LUA_PATH_PREFIX}" ]]; then
  export LUA_PATH="${LUA_PATH_PREFIX};${LUA_PATH:-;;}"
fi

nvim --headless -u NONE -c "luafile tests/run.lua"
luacov
