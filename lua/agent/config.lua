local M = {}

local defaults = {
  default_agent = "claude",
  commands = {
    claude = "claude",
    codex  = "codex",
  },
  git_worktree = {
    enabled = false,
    root = ".agent-worktrees",
    branch_prefix = "agent/",
  },
  keymaps = {
    spawn   = "<leader>as",
    list    = "<leader>al",
    kill    = "<leader>ak",
    focus   = "<leader>af",
    refresh = "<leader>ar",
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

function M.prefer(agent_type)
  if not M.opts.commands[agent_type] then
    vim.notify("agent.nvim: unknown agent type '" .. agent_type .. "'", vim.log.levels.ERROR)
    return
  end
  M.opts.default_agent = agent_type
  vim.notify("agent.nvim: default agent set to '" .. agent_type .. "'", vim.log.levels.INFO)
end

return M
