local M = {
  tests = {},
}

function M.test(name, fn)
  table.insert(M.tests, { name = name, fn = fn })
end

function M.eq(actual, expected, message)
  assert(vim.deep_equal(actual, expected), message or string.format("expected %s, got %s", vim.inspect(expected), vim.inspect(actual)))
end

function M.truthy(value, message)
  assert(value, message or "expected value to be truthy")
end

function M.falsy(value, message)
  assert(not value, message or "expected value to be falsy")
end

function M.matches(value, pattern, message)
  assert(type(value) == "string" and value:match(pattern), message or string.format("expected %q to match %q", tostring(value), pattern))
end

function M.reload(name)
  package.loaded[name] = nil
  return require(name)
end

function M.reset_plugin_modules()
  for name, _ in pairs(package.loaded) do
    if name == "agent" or name:match("^agent%.") then
      package.loaded[name] = nil
    end
  end
end

function M.cleanup_user_commands()
  for _, name in ipairs({ "AgentSpawn", "AgentList", "AgentKill", "AgentKillAll", "AgentFocus", "AgentRename" }) do
    pcall(vim.api.nvim_del_user_command, name)
  end
end

function M.cleanup_keymaps()
  for _, lhs in ipairs({ "zs", "zl", "zk", "zf" }) do
    pcall(vim.keymap.del, "n", lhs)
  end
end

function M.capture_notify()
  local calls = {}
  local original = vim.notify
  vim.notify = function(message, level, opts)
    table.insert(calls, { message = message, level = level, opts = opts })
  end
  return calls, function()
    vim.notify = original
  end
end

function M.stub(tbl, key, value)
  local original = tbl[key]
  tbl[key] = value
  return function()
    tbl[key] = original
  end
end

function M.feed(keys)
  local encoded = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_feedkeys(encoded, "xt", false)
  vim.wait(50)
end

function M.current_buf_lines()
  return vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
end

function M.new_editor_buffer()
  vim.cmd("enew!")
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_set_option_value("buftype", "", { buf = buf })
  return buf
end

function M.close_extra_windows()
  local wins = vim.api.nvim_list_wins()
  local current = vim.api.nvim_get_current_win()
  for _, win in ipairs(wins) do
    if win ~= current and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end

function M.wait_for_job(job_id, timeout)
  vim.fn.jobwait({ job_id }, timeout or 1000)
  vim.wait(50)
end

function M.run()
  local failures = {}

  for _, test in ipairs(M.tests) do
    local ok, err = xpcall(function()
      M.cleanup_user_commands()
      M.cleanup_keymaps()
      M.close_extra_windows()
      M.new_editor_buffer()
      M.reset_plugin_modules()
      test.fn()
    end, debug.traceback)

    if not ok then
      table.insert(failures, string.format("FAIL %s\n%s", test.name, err))
    end
  end

  for _, failure in ipairs(failures) do
    io.stderr:write(failure .. "\n")
  end

  io.stdout:write(string.format("Ran %d tests, %d failures\n", #M.tests, #failures))

  local runner = package.loaded["luacov.runner"]
  if runner and runner.shutdown then
    runner.shutdown()
  end

  if #failures > 0 then
    vim.cmd("cq")
  else
    vim.cmd("qa")
  end
end

return M
