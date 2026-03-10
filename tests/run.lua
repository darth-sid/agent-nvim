local cwd = vim.fn.getcwd()

package.path = table.concat({
  "/opt/homebrew/share/lua/5.5/?.lua",
  "/opt/homebrew/share/lua/5.5/?/init.lua",
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
