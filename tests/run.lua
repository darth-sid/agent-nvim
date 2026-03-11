local cwd = vim.fn.getcwd()

local function prepend_package_paths_from_env()
  local path = vim.env.LUA_PATH
  if not path or path == "" then
    return {}
  end

  local paths = {}
  for entry in path:gmatch("[^;]+") do
    if entry ~= "" and entry ~= ";;" then
      table.insert(paths, entry)
    end
  end
  return paths
end

package.path = table.concat({
  unpack(prepend_package_paths_from_env()),
  cwd .. "/lua/?.lua",
  cwd .. "/lua/?/init.lua",
  cwd .. "/tests/?.lua",
  package.path,
}, ";")

require("luacov")

local helpers = require("tests.helpers")

require("tests.config_spec")
require("tests.agents_spec")
require("tests.ui_spec")
require("tests.init_spec")

helpers.run()
