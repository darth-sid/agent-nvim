local T = require("tests.helpers")

T.test("agent.setup registers commands and routes each command correctly", function()
  local recorded = {
    spawn_prompt = {},
    kills = {},
    focus = {},
    rename = {},
    rename_prompt = {},
    pick_prompts = {},
  }

  package.loaded["agent.config"] = {
    opts = {
      keymaps = false,
    },
    setup = function(opts)
      package.loaded["agent.config"].setup_opts = opts
      package.loaded["agent.config"].opts = {
        keymaps = false,
      }
    end,
  }

  package.loaded["agent.agents"] = {
    spawn_prompt_with_opts = function(agent_type, opts)
      table.insert(recorded.spawn_prompt, {
        agent_type = agent_type,
        worktree = opts and opts.worktree or false,
      })
    end,
    kill = function(id)
      table.insert(recorded.kills, id)
    end,
    kill_all = function()
      recorded.kill_all = true
    end,
    focus = function(id)
      table.insert(recorded.focus, id)
    end,
    rename = function(id, label)
      table.insert(recorded.rename, { id = id, label = label })
    end,
    rename_prompt = function(id)
      table.insert(recorded.rename_prompt, id)
    end,
    pick_id = function(prompt, callback)
      table.insert(recorded.pick_prompts, prompt)
      callback(42)
    end,
  }

  package.loaded["agent.ui"] = {
    open_manager = function()
      recorded.listed = true
    end,
  }

  local notifications, restore_notify = T.capture_notify()
  local agent = T.reload("agent")
  agent.setup({ keymaps = false })

  vim.cmd("AgentSpawn codex")
  vim.cmd("AgentSpawn! claude")
  vim.cmd("AgentList")
  vim.cmd("AgentKill 9")
  vim.cmd("AgentKillAll")
  vim.cmd("AgentFocus 5")
  vim.cmd("AgentRename 4 named session")
  vim.cmd("AgentKill notes")
  vim.cmd("AgentFocus review")
  vim.cmd("AgentRename pair mob session")
  vim.cmd("AgentRename 8")

  restore_notify()
  T.eq(recorded.spawn_prompt[1].agent_type, "codex")
  T.eq(recorded.spawn_prompt[1].worktree, false)
  T.eq(recorded.spawn_prompt[2].agent_type, "claude")
  T.eq(recorded.spawn_prompt[2].worktree, true)
  T.truthy(recorded.listed)
  T.eq(recorded.kills[1], 9)
  T.eq(recorded.kills[2], "notes")
  T.truthy(recorded.kill_all)
  T.eq(recorded.focus[1], 5)
  T.eq(recorded.focus[2], "review")
  T.eq(recorded.rename[1].id, 4)
  T.eq(recorded.rename[1].label, "named session")
  T.eq(recorded.rename[2].id, "pair")
  T.eq(recorded.rename[2].label, "mob session")
  T.eq(recorded.rename_prompt[1], 8)
  T.eq(#notifications, 0)
end)

T.test("agent.setup installs keymaps and dispatches mapped actions", function()
  local recorded = {
    spawn_prompt = 0,
    list = 0,
    kill = {},
    focus = {},
    prompts = {},
  }

  package.loaded["agent.config"] = {
    opts = {},
    setup = function()
      package.loaded["agent.config"].opts = {
        keymaps = {
          spawn = "zs",
          list = "zl",
          kill = "zk",
          focus = "zf",
        },
      }
    end,
  }

  package.loaded["agent.agents"] = {
    spawn_prompt_with_opts = function(_, opts)
      recorded.spawn_prompt = recorded.spawn_prompt + 1
      recorded.spawn_worktree = opts and opts.worktree or false
    end,
    kill = function(id)
      table.insert(recorded.kill, id)
    end,
    kill_all = function() end,
    focus = function(id)
      table.insert(recorded.focus, id)
    end,
    pick_id = function(prompt, callback)
      table.insert(recorded.prompts, prompt)
      callback(prompt:match("Kill") and 11 or 12)
    end,
  }

  package.loaded["agent.ui"] = {
    open_manager = function()
      recorded.list = recorded.list + 1
    end,
  }

  local agent = T.reload("agent")
  agent.setup({})

  T.feed("zs")
  T.feed("zl")
  T.feed("zk")
  T.feed("zf")

  T.eq(recorded.spawn_prompt, 1)
  T.eq(recorded.spawn_worktree, false)
  T.eq(recorded.list, 1)
  T.eq(recorded.kill[1], 11)
  T.eq(recorded.focus[1], 12)
  T.eq(recorded.prompts[1], "Kill agent:")
  T.eq(recorded.prompts[2], "Focus agent:")
end)

T.test("agent.setup commands validate blank args", function()
  local recorded = {}
  local commands = {}

  package.loaded["agent.config"] = {
    opts = { keymaps = false },
    setup = function()
      package.loaded["agent.config"].opts = { keymaps = false }
    end,
  }

  package.loaded["agent.agents"] = {
    kill = function(id) recorded.kill = id end,
    focus = function(id) recorded.focus = id end,
    rename = function(id, label) recorded.rename = { id = id, label = label } end,
    rename_prompt = function(id) recorded.rename_prompt = id end,
    spawn_prompt_with_opts = function() end,
    kill_all = function() end,
    pick_id = function() end,
  }

  package.loaded["agent.ui"] = {
    open_manager = function() end,
  }

  local restore_create = T.stub(vim.api, "nvim_create_user_command", function(name, fn)
    commands[name] = fn
  end)
  local notifications, restore_notify = T.capture_notify()
  local agent = T.reload("agent")
  agent.setup({ keymaps = false })

  commands.AgentKill({ args = "   " })
  commands.AgentFocus({ args = "   " })
  commands.AgentRename({ fargs = { "" } })

  restore_create()
  restore_notify()

  T.eq(recorded.kill, nil)
  T.eq(recorded.focus, nil)
  T.eq(recorded.rename, nil)
  T.eq(recorded.rename_prompt, nil)
  T.matches(notifications[1].message, "AgentKill requires an agent id or name")
  T.matches(notifications[2].message, "AgentFocus requires an agent id or name")
  T.matches(notifications[3].message, "AgentRename requires an agent id or name")
end)
