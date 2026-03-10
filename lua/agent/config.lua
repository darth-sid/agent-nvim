local M = {}

local defaults = {
  default_agent = "claude",
  commands = {
    claude = "claude",
    codex  = "codex",
  },
  keymaps = {
    spawn = "<leader>as",
    list  = "<leader>al",
    kill  = "<leader>ak",
    focus = "<leader>af",
  },
  split = "horizontal",
}

M.opts = {}

local function deep_merge(base, override)
  local result = vim.deepcopy(base)
  for k, v in pairs(override) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = deep_merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

function M.setup(opts)
  if opts == false or opts == nil then
    M.opts = vim.deepcopy(defaults)
  else
    M.opts = deep_merge(defaults, opts)
  end
end

return M
