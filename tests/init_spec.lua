local T = require("tests.helpers")

T.test("agent.setup registers commands and routes each command correctly", function()
  local recorded = {
    spawn = {},
    kills = {},
    focus = {},
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
    spawn = function(agent_type)
      table.insert(recorded.spawn, agent_type)
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
  vim.cmd("AgentList")
  vim.cmd("AgentKill 9")
  vim.cmd("AgentKillAll")
  vim.cmd("AgentFocus 5")
  vim.cmd("AgentKill nope")
  vim.cmd("AgentFocus nope")

  restore_notify()
  T.eq(recorded.spawn[1], "codex")
  T.truthy(recorded.listed)
  T.eq(recorded.kills[1], 9)
  T.truthy(recorded.kill_all)
  T.eq(recorded.focus[1], 5)
  T.matches(notifications[1].message, "requires a numeric id")
  T.matches(notifications[2].message, "requires a numeric id")
end)

T.test("agent.setup installs keymaps and dispatches mapped actions", function()
  local recorded = {
    spawn = 0,
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
    spawn = function()
      recorded.spawn = recorded.spawn + 1
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

  T.eq(recorded.spawn, 1)
  T.eq(recorded.list, 1)
  T.eq(recorded.kill[1], 11)
  T.eq(recorded.focus[1], 12)
  T.eq(recorded.prompts[1], "Kill agent:")
  T.eq(recorded.prompts[2], "Focus agent:")
end)
