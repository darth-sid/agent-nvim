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
  T.eq(agent.label, "1")
  T.matches(vim.api.nvim_buf_get_name(agent.bufnr), "^agent://1%-%d+/%[1%] 1 | claude | running$")

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
  T.matches(vim.api.nvim_buf_get_name(agent.bufnr), "^agent://1%-%d+/%[1%] 1 | claude | exited$")
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
  agents.kill(tostring(id))
  T.wait_for_job(agent.job_id)
  T.eq(agent.status, "exited")
  T.matches(vim.api.nvim_buf_get_name(agent.bufnr), "^agent://1%-%d+/%[1%] 1 | claude | exited$")

  agents.kill(999)
  restore_notify()
  T.matches(notifications[#notifications].message, "no agent matching 999")
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

T.test("agents.focus opens current, horizontal, vertical, and floating targets", function()
  local config = T.reload("agent.config")
  config.setup({ commands = { claude = { "cat" } }, split = "current" })
  local agents = T.reload("agent.agents")
  local original = T.new_editor_buffer()
  local id = agents.spawn("claude")
  local agent = agents.registry[id]
  T.eq(vim.api.nvim_get_current_buf(), agent.bufnr)
  T.eq(#vim.api.nvim_list_wins(), 1)
  T.falsy(vim.api.nvim_get_current_buf() == original, "current mode should replace the current window buffer")

  T.close_extra_windows()
  T.new_editor_buffer()
  config.setup({ commands = { claude = { "cat" } }, split = "horizontal" })
  agents.focus(id)
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

T.test("agents.focus with current mode does not reuse another visible agent window", function()
  local config = T.reload("agent.config")
  config.setup({ commands = { claude = { "cat" } }, split = "current" })
  local agents = T.reload("agent.agents")

  local id = agents.spawn("claude")
  local agent = agents.registry[id]

  vim.cmd("split")
  local reused_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_buf(agent.bufnr)
  vim.cmd("wincmd p")
  local current_win = vim.api.nvim_get_current_win()

  agents.focus(id)

  T.eq(vim.api.nvim_get_current_win(), current_win)
  T.eq(vim.api.nvim_get_current_buf(), agent.bufnr)
  T.falsy(vim.api.nvim_get_current_win() == reused_win, "current mode should not jump to another visible agent window")

  vim.fn.jobstop(agent.job_id)
  T.wait_for_job(agent.job_id)
end)

T.test("agents.focus warns for unknown ids", function()
  running_config()
  local agents = T.reload("agent.agents")
  local notifications, restore_notify = T.capture_notify()

  agents.focus(999)

  restore_notify()
  T.matches(notifications[1].message, "no agent matching 999")
end)

T.test("agents.focus warns for invalid split values", function()
  local config = T.reload("agent.config")
  config.setup({ commands = { claude = { "cat" } }, split = "bogus" })
  local agents = T.reload("agent.agents")
  local notifications, restore_notify = T.capture_notify()

  local id = agents.spawn("claude", { focus = false })
  agents.focus(id)

  restore_notify()
  T.matches(notifications[#notifications].message, "invalid split option")

  local agent = agents.registry[id]
  vim.fn.jobstop(agent.job_id)
  T.wait_for_job(agent.job_id)
end)

T.test("agents.rename updates labels and validates input", function()
  running_config()
  local agents = T.reload("agent.agents")
  local notifications, restore_notify = T.capture_notify()

  local id = agents.spawn("claude")
  local agent = agents.registry[id]

  T.truthy(agents.rename(id, "pairing session"))
  T.eq(agent.label, "pairing session")
  T.matches(vim.api.nvim_buf_get_name(agent.bufnr), "^agent://1%-%d+/%[1%] pairing session | claude | running$")

  T.falsy(agents.rename(id, "   "))
  agents.rename(999, "ghost")

  restore_notify()
  T.matches(notifications[#notifications - 1].message, "non%-empty label")
  T.matches(notifications[#notifications].message, "no agent matching 999")

  vim.fn.jobstop(agent.job_id)
  T.wait_for_job(agent.job_id)
end)

T.test("agents.spawn accepts an explicit label", function()
  running_config()
  local agents = T.reload("agent.agents")

  local id = agents.spawn("claude", { label = "pairing" })
  local agent = agents.registry[id]

  T.eq(agent.label, "pairing")
  T.matches(vim.api.nvim_buf_get_name(agent.bufnr), "^agent://1%-%d+/%[1%] pairing | claude | running$")

  vim.fn.jobstop(agent.job_id)
  T.wait_for_job(agent.job_id)
end)

T.test("agents.spawn_prompt collects a name before creating an agent", function()
  running_config()
  local agents = T.reload("agent.agents")

  local prompted
  local restore_input = T.stub(vim.ui, "input", function(opts, callback)
    prompted = opts
    callback("debug run")
  end)

  local id = agents.spawn_prompt("claude")
  restore_input()

  T.eq(id, nil)
  T.eq(prompted.prompt, "Name new claude agent: ")
  T.eq(prompted.default, "1")

  local agent = agents.registry[1]
  T.truthy(agent)
  T.eq(agent.label, "debug run")
  T.eq(agent.type, "claude")

  vim.fn.jobstop(agent.job_id)
  T.wait_for_job(agent.job_id)
end)

T.test("agents.spawn_prompt falls back to the agent id for blank input", function()
  running_config()
  local agents = T.reload("agent.agents")

  local restore_input = T.stub(vim.ui, "input", function(_, callback)
    callback("   ")
  end)

  agents.spawn_prompt("claude")
  restore_input()

  local agent = agents.registry[1]
  T.truthy(agent)
  T.eq(agent.label, "1")

  vim.fn.jobstop(agent.job_id)
  T.wait_for_job(agent.job_id)
end)

T.test("agents.spawn_prompt returns the created id and reports nil on cancel", function()
  running_config()
  local agents = T.reload("agent.agents")

  local restore_input = T.stub(vim.ui, "input", function(_, callback)
    callback("notes")
  end)

  local created
  agents.spawn_prompt("claude", function(id)
    created = id
  end)
  restore_input()

  T.eq(created, 1)
  vim.fn.jobstop(agents.registry[1].job_id)
  T.wait_for_job(agents.registry[1].job_id)

  local cancelled = false
  restore_input = T.stub(vim.ui, "input", function(_, callback)
    callback(nil)
  end)

  agents.spawn_prompt("claude", function(id)
    cancelled = (id == nil)
  end)
  restore_input()

  T.truthy(cancelled)
  T.eq(agents.registry[2], nil)
end)

T.test("agents.rename_prompt uses vim.ui.input defaults and applies the rename", function()
  running_config()
  local agents = T.reload("agent.agents")

  local id = agents.spawn("claude")
  local prompted
  local renamed
  local restore_input = T.stub(vim.ui, "input", function(opts, callback)
    prompted = opts
    callback("debug run")
  end)

  agents.rename_prompt(id, function(ok)
    renamed = ok
  end)

  restore_input()
  T.eq(prompted.prompt, "Rename agent " .. id .. ": ")
  T.eq(prompted.default, "1")
  T.truthy(renamed)
  T.eq(agents.registry[id].label, "debug run")

  vim.fn.jobstop(agents.registry[id].job_id)
  T.wait_for_job(agents.registry[id].job_id)
end)

T.test("agents operations resolve exact labels in addition to ids", function()
  running_config()
  local agents = T.reload("agent.agents")

  local id = agents.spawn("claude", { label = "notes" })
  local agent = agents.registry[id]

  agents.focus(tostring(id))
  T.eq(vim.api.nvim_get_current_buf(), agent.bufnr)

  agents.focus("notes")
  T.eq(vim.api.nvim_get_current_buf(), agent.bufnr)

  T.truthy(agents.rename("notes", "review"))
  T.eq(agent.label, "review")

  agents.kill("review")
  T.eq(agent.status, "exited")
  T.wait_for_job(agent.job_id)
end)

T.test("agents warn when a lookup is blank or ambiguous", function()
  running_config()
  local agents = T.reload("agent.agents")
  local notifications, restore_notify = T.capture_notify()

  agents.kill(nil)
  agents.focus("   ")

  agents.registry[1] = {
    id = 1,
    label = "shared",
    status = "running",
    bufnr = vim.api.nvim_create_buf(false, true),
    type = "claude",
    job_id = 0,
  }
  agents.registry[2] = {
    id = 2,
    label = "shared",
    status = "running",
    bufnr = vim.api.nvim_create_buf(false, true),
    type = "codex",
    job_id = 0,
  }

  agents.rename("shared", "renamed")

  restore_notify()
  T.matches(notifications[1].message, "^agent.nvim: no agent matching %s*$")
  T.matches(notifications[2].message, "^agent.nvim: no agent matching %s*$")
  T.matches(notifications[3].message, "multiple agents match name shared")
end)

T.test("agents.rename rejects duplicate names", function()
  running_config()
  local agents = T.reload("agent.agents")
  local notifications, restore_notify = T.capture_notify()

  local first = agents.spawn("claude", { label = "pairing" })
  local second = agents.spawn("codex", { label = "review" })
  local duplicate = agents.spawn("codex", { label = "pairing" })

  T.truthy(first)
  T.truthy(second)
  T.eq(duplicate, nil)
  T.truthy(agents.rename(first, "pairing"))
  T.falsy(agents.rename(second, "pairing"))

  restore_notify()
  T.matches(notifications[#notifications].message, "agent name must be unique: pairing")

  vim.fn.jobstop(agents.registry[first].job_id)
  vim.fn.jobstop(agents.registry[second].job_id)
  T.wait_for_job(agents.registry[first].job_id)
  T.wait_for_job(agents.registry[second].job_id)
end)

T.test("agents.list sorts by id and pick_id delegates selection", function()
  running_config()
  local agents = T.reload("agent.agents")

  local first = agents.spawn("claude")
  local second = agents.spawn("codex")
  agents.rename(second, "review")
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
  T.matches(selected_items[2], "review")
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
