local M = {}

function M.setup(opts)
  local config  = require("agent.config")
  local agents  = require("agent.agents")
  local ui      = require("agent.ui")

  config.setup(opts)

  -- Commands
  vim.api.nvim_create_user_command("AgentSpawn", function(args)
    local t = args.args ~= "" and args.args or nil
    agents.spawn(t)
  end, {
    nargs = "?",
    complete = function() return { "claude", "codex" } end,
    desc = "Spawn an AI agent",
  })

  vim.api.nvim_create_user_command("AgentList", function()
    ui.open_manager()
  end, { desc = "Open agent manager" })

  vim.api.nvim_create_user_command("AgentKill", function(args)
    local id = tonumber(args.args)
    if not id then
      vim.notify("agent.nvim: :AgentKill requires a numeric id", vim.log.levels.ERROR)
      return
    end
    agents.kill(id)
  end, { nargs = 1, desc = "Kill agent by id" })

  vim.api.nvim_create_user_command("AgentKillAll", function()
    agents.kill_all()
  end, { desc = "Kill all agents" })

  vim.api.nvim_create_user_command("AgentFocus", function(args)
    local id = tonumber(args.args)
    if not id then
      vim.notify("agent.nvim: :AgentFocus requires a numeric id", vim.log.levels.ERROR)
      return
    end
    agents.focus(id)
  end, { nargs = 1, desc = "Focus agent terminal by id" })

  -- Keymaps
  local km = config.opts.keymaps
  if km ~= false and type(km) == "table" then
    local function map(key, action)
      if key then
        vim.keymap.set("n", key, action, { silent = true, desc = "agent.nvim" })
      end
    end

    map(km.spawn, "<Cmd>AgentSpawn<CR>")
    map(km.list,  "<Cmd>AgentList<CR>")
    map(km.kill,  function()
      agents.pick_id("Kill agent:", function(id)
        agents.kill(id)
      end)
    end)
    map(km.focus, function()
      agents.pick_id("Focus agent:", function(id)
        agents.focus(id)
      end)
    end)
  end
end

return M
