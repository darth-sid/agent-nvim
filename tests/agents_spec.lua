local T = require("tests.helpers")

local function running_config()
  local config = T.reload("agent.config")
  config.setup({
    default_agent = "claude",
    commands = {
      claude = { "cat" },
      codex = { "cat" },
      done = { "sh", "-c", "exit 0" },
      missing = { "__agent_missing_command__" },
    },
  })
  return config
end

T.test("agents.spawn rejects unknown types", function()
  running_config()
  local agents = T.reload("agent.agents")
  local notifications, restore_notify = T.capture_notify()

  local id = agents.spawn("unknown")

  restore_notify()
  T.eq(id, nil)
  T.matches(notifications[1].message, "unknown agent type")
end)

T.test("agents.spawn attaches terminal to tracked buffer instead of current buffer", function()
  running_config()
  local agents = T.reload("agent.agents")
  local current = T.new_editor_buffer()

  local id = agents.spawn("claude")
  local agent = agents.registry[id]

  T.truthy(agent)
  T.eq(vim.api.nvim_get_option_value("buftype", { buf = current }), "")
  T.eq(vim.api.nvim_get_option_value("buftype", { buf = agent.bufnr }), "terminal")
  T.falsy(agent.bufnr == current, "spawn should use a dedicated terminal buffer")

  vim.fn.jobstop(agent.job_id)
  T.wait_for_job(agent.job_id)
end)

T.test("agents.spawn focuses the new agent buffer", function()
  running_config()
  local agents = T.reload("agent.agents")
  local start_win = vim.api.nvim_get_current_win()

  local id = agents.spawn("claude")
  local agent = agents.registry[id]

  T.truthy(agent)
  T.eq(vim.api.nvim_get_current_buf(), agent.bufnr)
  T.falsy(vim.api.nvim_get_current_win() == start_win, "spawn should move focus to the agent window")

  vim.fn.jobstop(agent.job_id)
  T.wait_for_job(agent.job_id)
end)

T.test("agents.spawn marks exited when the job finishes", function()
  local config = T.reload("agent.config")
  config.setup({
    commands = { claude = { "sh", "-c", "exit 0" } },
  })
  local agents = T.reload("agent.agents")

  local id = agents.spawn("claude")
  local agent = agents.registry[id]

  T.wait_for_job(agent.job_id)
  T.eq(agent.status, "exited")
end)

T.test("agents.spawn cleans up failed job starts", function()
  running_config()
  local agents = T.reload("agent.agents")
  local notifications, restore_notify = T.capture_notify()

  local id = agents.spawn("missing")

  restore_notify()
  T.eq(id, nil)
  T.matches(notifications[#notifications].message, "failed to start job")
end)

T.test("agents.kill updates running jobs and warns on missing ids", function()
  running_config()
  local agents = T.reload("agent.agents")
  local notifications, restore_notify = T.capture_notify()

  local id = agents.spawn("claude")
  local agent = agents.registry[id]
  agents.kill(id)
  T.wait_for_job(agent.job_id)
  T.eq(agent.status, "exited")

  agents.kill(999)
  restore_notify()
  T.matches(notifications[#notifications].message, "no agent with id 999")
end)

T.test("agents.kill_all stops each running job", function()
  running_config()
  local agents = T.reload("agent.agents")

  local id1 = agents.spawn("claude")
  local id2 = agents.spawn("codex")

  agents.kill_all()

  T.eq(agents.registry[id1].status, "exited")
  T.eq(agents.registry[id2].status, "exited")
  T.wait_for_job(agents.registry[id1].job_id)
  T.wait_for_job(agents.registry[id2].job_id)
end)

T.test("agents.focus reuses an existing visible window", function()
  running_config()
  local agents = T.reload("agent.agents")
  local id = agents.spawn("claude")
  local agent = agents.registry[id]

  vim.cmd("split")
  local agent_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_buf(agent.bufnr)
  vim.cmd("wincmd p")
  local other_win = vim.api.nvim_get_current_win()

  agents.focus(id)

  T.eq(vim.api.nvim_get_current_win(), agent_win)
  T.falsy(vim.api.nvim_get_current_win() == other_win, "focus should jump to the agent window")

  vim.fn.jobstop(agent.job_id)
  T.wait_for_job(agent.job_id)
end)

T.test("agents.focus opens horizontal, vertical, and floating targets", function()
  local config = T.reload("agent.config")
  config.setup({ commands = { claude = { "cat" } }, split = "horizontal" })
  local agents = T.reload("agent.agents")
  T.new_editor_buffer()
  local id = agents.spawn("claude")
  local agent = agents.registry[id]
  T.eq(vim.api.nvim_get_current_buf(), agent.bufnr)
  T.eq(#vim.api.nvim_list_wins(), 2)

  T.close_extra_windows()
  T.new_editor_buffer()
  config.setup({ commands = { claude = { "cat" } }, split = "vertical" })
  agents.focus(id)
  T.eq(vim.api.nvim_get_current_buf(), agent.bufnr)

  T.close_extra_windows()
  T.new_editor_buffer()
  config.setup({ commands = { claude = { "cat" } }, split = "float" })
  agents.focus(id)
  local win_config = vim.api.nvim_win_get_config(vim.api.nvim_get_current_win())
  T.eq(win_config.relative, "editor")

  vim.fn.jobstop(agent.job_id)
  T.wait_for_job(agent.job_id)
end)

T.test("agents.focus warns for unknown ids", function()
  running_config()
  local agents = T.reload("agent.agents")
  local notifications, restore_notify = T.capture_notify()

  agents.focus(999)

  restore_notify()
  T.matches(notifications[1].message, "no agent with id 999")
end)

T.test("agents.list sorts by id and pick_id delegates selection", function()
  running_config()
  local agents = T.reload("agent.agents")

  local first = agents.spawn("claude")
  local second = agents.spawn("codex")
  local listed = agents.list()
  T.eq(listed[1].id, first)
  T.eq(listed[2].id, second)

  local selected_prompt
  local selected_items
  local restore_select = T.stub(vim.ui, "select", function(items, opts, callback)
    selected_items = items
    selected_prompt = opts.prompt
    callback(items[2], 2)
  end)

  local picked
  agents.pick_id("Pick agent:", function(id)
    picked = id
  end)

  restore_select()
  T.eq(selected_prompt, "Pick agent:")
  T.matches(selected_items[1], "%[1%]")
  T.eq(picked, second)

  vim.fn.jobstop(agents.registry[first].job_id)
  vim.fn.jobstop(agents.registry[second].job_id)
  T.wait_for_job(agents.registry[first].job_id)
  T.wait_for_job(agents.registry[second].job_id)
end)

T.test("agents.pick_id notifies when there are no agents", function()
  running_config()
  local agents = T.reload("agent.agents")
  local notifications, restore_notify = T.capture_notify()

  agents.pick_id("Pick agent:", function() end)

  restore_notify()
  T.matches(notifications[1].message, "no agents")
end)
