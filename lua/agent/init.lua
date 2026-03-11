local M = {}

function M.setup(opts)
  local config  = require("agent.config")
  local agents  = require("agent.agents")
  local ui      = require("agent.ui")

  config.setup(opts)

  local function parse_agent_ref(text)
    local trimmed = vim.trim(text or "")
    return tonumber(trimmed) or trimmed
  end

  -- Commands
  vim.api.nvim_create_user_command("AgentSpawn", function(args)
    local t = args.args ~= "" and args.args or nil
    agents.spawn_prompt(t)
  end, {
    nargs = "?",
    complete = function() return { "claude", "codex" } end,
    desc = "Spawn an AI agent",
  })

  vim.api.nvim_create_user_command("AgentList", function()
    ui.open_manager()
  end, { desc = "Open agent manager" })

  vim.api.nvim_create_user_command("AgentKill", function(args)
    local target = vim.trim(args.args)
    if target == "" then
      vim.notify("agent.nvim: :AgentKill requires an agent id or name", vim.log.levels.ERROR)
      return
    end
    agents.kill(parse_agent_ref(target))
  end, { nargs = 1, desc = "Kill agent by id or name" })

  vim.api.nvim_create_user_command("AgentKillAll", function()
    agents.kill_all()
  end, { desc = "Kill all agents" })

  vim.api.nvim_create_user_command("AgentFocus", function(args)
    local target = vim.trim(args.args)
    if target == "" then
      vim.notify("agent.nvim: :AgentFocus requires an agent id or name", vim.log.levels.ERROR)
      return
    end
    agents.focus(parse_agent_ref(target))
  end, { nargs = 1, desc = "Focus agent terminal by id or name" })

  vim.api.nvim_create_user_command("AgentRename", function(args)
    local target = vim.trim(args.fargs[1] or "")
    if target == "" then
      vim.notify("agent.nvim: :AgentRename requires an agent id or name", vim.log.levels.ERROR)
      return
    end

    local label = table.concat(vim.list_slice(args.fargs, 2), " ")
    if label == "" then
      agents.rename_prompt(parse_agent_ref(target))
      return
    end

    agents.rename(parse_agent_ref(target), label)
  end, { nargs = "+", desc = "Rename agent by id or name" })

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
