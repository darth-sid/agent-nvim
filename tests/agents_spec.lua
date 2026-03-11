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

T.test("agents.spawn creates a git worktree and starts the job there", function()
  local config = T.reload("agent.config")
  config.setup({
    commands = { claude = { "cat" } },
    git_worktree = {
      enabled = false,
      root = ".agent-worktrees",
      branch_prefix = "agent/",
    },
  })
  local agents = T.reload("agent.agents")

  local system_calls = {}
  local created_dirs = {}
  local started = {}

  local restore_git = T.stub(agents, "_run_git", function(cmd, cwd)
    table.insert(system_calls, { cmd = cmd, cwd = cwd })
    if vim.deep_equal(cmd, { "git", "rev-parse", "--show-toplevel" }) then
      return 0, "/tmp/repo\n"
    end
    return 0, ""
  end)
  local restore_mkdir = T.stub(agents, "_mkdir", function(path)
    table.insert(created_dirs, path)
  end)
  local restore_jobstart = T.stub(vim.fn, "jobstart", function(cmd, opts)
    started.cmd = cmd
    started.cwd = opts.cwd
    started.term = opts.term
    started.on_exit = opts.on_exit
    return 17
  end)

  local id = agents.spawn("claude", { label = "Pairing Session", worktree = true, focus = false })

  restore_jobstart()
  restore_mkdir()
  restore_git()

  T.eq(id, 1)
  T.eq(created_dirs[1], "/tmp/repo/.agent-worktrees")
  T.eq(system_calls[1].cmd[1], "git")
  T.eq(system_calls[2].cmd[1], "git")
  T.eq(system_calls[2].cwd, "/tmp/repo")
  T.eq(system_calls[2].cmd[2], "worktree")
  T.eq(system_calls[2].cmd[3], "add")
  T.eq(system_calls[2].cmd[4], "-b")
  T.eq(system_calls[2].cmd[5], "agent/1-pairing-session")
  T.eq(system_calls[2].cmd[6], "/tmp/repo/.agent-worktrees/1-pairing-session")
  T.eq(started.cmd, config.opts.commands.claude)
  T.eq(started.cwd, "/tmp/repo/.agent-worktrees/1-pairing-session")
  T.truthy(started.term)
  T.eq(agents.registry[id].worktree.path, "/tmp/repo/.agent-worktrees/1-pairing-session")
  T.eq(agents.registry[id].worktree.branch, "agent/1-pairing-session")
end)

T.test("agents.spawn can default to git worktrees from config", function()
  local config = T.reload("agent.config")
  config.setup({
    commands = { claude = { "cat" } },
    git_worktree = {
      enabled = true,
      root = ".agent-worktrees",
      branch_prefix = "agent/",
    },
  })
  local agents = T.reload("agent.agents")

  local restore_git = T.stub(agents, "_run_git", function(cmd)
    if vim.deep_equal(cmd, { "git", "rev-parse", "--show-toplevel" }) then
      return 0, "/tmp/repo\n"
    end
    return 0, ""
  end)
  local restore_mkdir = T.stub(agents, "_mkdir", function()
  end)
  local started_cwd
  local restore_jobstart = T.stub(vim.fn, "jobstart", function(_, opts)
    started_cwd = opts.cwd
    return 23
  end)

  local id = agents.spawn("claude", { focus = false })

  restore_jobstart()
  restore_mkdir()
  restore_git()

  T.eq(id, 1)
  T.eq(started_cwd, "/tmp/repo/.agent-worktrees/1-1")
end)

T.test("agents.spawn reports git worktree failures", function()
  local config = T.reload("agent.config")
  config.setup({
    commands = { claude = { "cat" } },
    git_worktree = {
      enabled = false,
      root = ".agent-worktrees",
      branch_prefix = "agent/",
    },
  })
  local agents = T.reload("agent.agents")
  local notifications, restore_notify = T.capture_notify()

  local restore_git = T.stub(agents, "_run_git", function(cmd)
    if vim.deep_equal(cmd, { "git", "rev-parse", "--show-toplevel" }) then
      return 1, "fatal: not a git repository"
    end
    return 1, "fatal: unexpected"
  end)

  local id = agents.spawn("claude", { worktree = true, focus = false })

  restore_git()
  restore_notify()

  T.eq(id, nil)
  T.matches(notifications[#notifications].message, "git worktree spawn requires a git repository")
end)

T.test("agents.spawn reports git worktree add errors", function()
  local config = T.reload("agent.config")
  config.setup({
    commands = { claude = { "cat" } },
    git_worktree = {
      enabled = false,
      root = ".agent-worktrees",
      branch_prefix = "agent/",
    },
  })
  local agents = T.reload("agent.agents")
  local notifications, restore_notify = T.capture_notify()

  local restore_git = T.stub(agents, "_run_git", function(cmd)
    if vim.deep_equal(cmd, { "git", "rev-parse", "--show-toplevel" }) then
      return 0, "/tmp/repo\n"
    end
    return 1, ""
  end)
  local restore_mkdir = T.stub(agents, "_mkdir", function() end)

  local id = agents.spawn("claude", { worktree = true, focus = false })

  restore_mkdir()
  restore_git()
  restore_notify()

  T.eq(id, nil)
  T.matches(notifications[#notifications].message, "git worktree add failed")
end)

T.test("agents._run_git executes git commands with optional cwd", function()
  local agents = T.reload("agent.agents")

  local code, result = agents._run_git({ "git", "rev-parse", "--is-inside-work-tree" })
  T.eq(code, 0)
  T.matches(vim.trim(result), "true")

  code, result = agents._run_git({ "git", "rev-parse", "--show-toplevel" }, vim.fn.getcwd())
  T.eq(code, 0)
  T.truthy(vim.trim(result) ~= "")
end)

T.test("agents._mkdir creates directories", function()
  local agents = T.reload("agent.agents")
  local target = vim.fn.getcwd() .. "/.tmp-agent-test-dir"

  pcall(vim.fn.delete, target, "rf")
  agents._mkdir(target)

  T.eq(vim.fn.isdirectory(target), 1)
  vim.fn.delete(target, "rf")
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

T.test("agents.spawn_prompt_with_opts forwards the worktree flag", function()
  running_config()
  local agents = T.reload("agent.agents")
  local recorded

  local restore_input = T.stub(vim.ui, "input", function(_, callback)
    callback("debug run")
  end)
  local restore_spawn = T.stub(agents, "spawn", function(agent_type, opts)
    recorded = { agent_type = agent_type, opts = opts }
    return 9
  end)

  local created_id = agents.spawn_prompt_with_opts("claude", { worktree = true }, function() end)
  restore_spawn()
  restore_input()

  T.eq(created_id, nil)
  T.eq(recorded.agent_type, "claude")
  T.eq(recorded.opts.label, "debug run")
  T.eq(recorded.opts.worktree, true)
end)

T.test("agents.spawn_prompt_with_opts accepts callback as second argument", function()
  running_config()
  local agents = T.reload("agent.agents")
  local observed

  local restore_input = T.stub(vim.ui, "input", function(_, callback)
    callback(nil)
  end)

  agents.spawn_prompt_with_opts("claude", function(id)
    observed = id
  end)

  restore_input()
  T.eq(observed, nil)
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

T.test("agents.rename_prompt handles missing agents and cancelled input", function()
  running_config()
  local agents = T.reload("agent.agents")
  local notifications, restore_notify = T.capture_notify()

  agents.rename_prompt(999, function() error("should not be called") end)

  local id = agents.spawn("claude", { focus = false })
  local cancelled
  local restore_input = T.stub(vim.ui, "input", function(_, callback)
    callback(nil)
  end)

  agents.rename_prompt(id, function(ok)
    cancelled = ok
  end)

  restore_input()
  restore_notify()

  T.eq(cancelled, false)
  T.matches(notifications[1].message, "no agent matching 999")
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

T.test("agents.list prunes exited agents and pick_id accepts function-only form", function()
  running_config()
  local agents = T.reload("agent.agents")

  agents.registry[10] = {
    id = 10,
    label = "old",
    status = "exited",
    bufnr = vim.api.nvim_create_buf(false, true),
    type = "claude",
    job_id = 0,
  }

  local id = agents.spawn("claude", { label = "live", focus = false })
  local selected_prompt
  local restore_select = T.stub(vim.ui, "select", function(items, opts, callback)
    selected_prompt = opts.prompt
    callback(items[1], 1)
  end)

  local listed = agents.list()
  local picked
  agents.pick_id(function(agent_id)
    picked = agent_id
  end)

  restore_select()

  T.eq(#listed, 1)
  T.eq(listed[1].id, id)
  T.eq(agents.registry[10], nil)
  T.eq(selected_prompt, "Select agent:")
  T.eq(picked, id)

  vim.fn.jobstop(agents.registry[id].job_id)
  T.wait_for_job(agents.registry[id].job_id)
end)

T.test("agents.pick_id notifies when there are no agents", function()
  running_config()
  local agents = T.reload("agent.agents")
  local notifications, restore_notify = T.capture_notify()

  agents.pick_id("Pick agent:", function() end)

  restore_notify()
  T.matches(notifications[1].message, "no agents")
end)
