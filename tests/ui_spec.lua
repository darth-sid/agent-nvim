local T = require("tests.helpers")

T.test("ui.open_manager renders the empty state and closes on q", function()
  package.loaded["agent.agents"] = {
    list = function()
      return {}
    end,
    focus = function() end,
    kill = function() end,
  }

  local ui = T.reload("agent.ui")
  ui.open_manager()

  local lines = T.current_buf_lines()
  T.matches(lines[1], "Agent Manager")
  T.eq(lines[4], "  (no agents)")

  local win = vim.api.nvim_get_current_win()
  T.feed("q")
  T.falsy(vim.api.nvim_win_is_valid(win), "q should close the manager window")
end)

T.test("ui.open_manager focuses the selected agent on <CR>", function()
  local focused
  package.loaded["agent.agents"] = {
    list = function()
      return {
        { id = 7, label = "claude", status = "running" },
      }
    end,
    focus = function(id)
      focused = id
    end,
    kill = function() end,
    rename_prompt = function() end,
  }

  local ui = T.reload("agent.ui")
  ui.open_manager()
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  T.feed("<CR>")

  T.eq(focused, 7)
end)

T.test("ui.open_manager kills and refreshes the list on x", function()
  local list_calls = 0
  local killed

  package.loaded["agent.agents"] = {
    list = function()
      list_calls = list_calls + 1
      if list_calls == 1 then
        return {
          { id = 3, label = "codex", status = "running" },
        }
      end
      return {}
    end,
    focus = function() end,
    kill = function(id)
      killed = id
    end,
    rename_prompt = function() end,
  }

  local ui = T.reload("agent.ui")
  ui.open_manager()
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  T.feed("x")

  T.eq(killed, 3)
  T.eq(T.current_buf_lines()[4], "  (no agents)")
end)

T.test("ui.open_manager ignores actions when the cursor is not on an agent row", function()
  local killed = false
  local focused = false
  local renamed = false

  package.loaded["agent.agents"] = {
    list = function()
      return {
        { id = 1, label = "claude", status = "running" },
      }
    end,
    focus = function()
      focused = true
    end,
    kill = function()
      killed = true
    end,
    rename_prompt = function()
      renamed = true
    end,
  }

  local ui = T.reload("agent.ui")
  ui.open_manager()
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local win = vim.api.nvim_get_current_win()

  T.feed("<CR>")
  T.feed("r")
  T.feed("x")
  T.feed("<Esc>")

  T.falsy(killed, "x on a header line should do nothing")
  T.falsy(focused, "<CR> on a header line should do nothing")
  T.falsy(renamed, "r on a header line should do nothing")
  T.falsy(vim.api.nvim_win_is_valid(win), "<Esc> should close the manager window")
end)

T.test("ui.open_manager renames and refreshes the selected agent on r", function()
  local list_calls = 0
  local renamed

  package.loaded["agent.agents"] = {
    list = function()
      list_calls = list_calls + 1
      if list_calls == 1 then
        return {
          { id = 5, label = "claude", status = "running" },
        }
      end
      return {
        { id = 5, label = "notes", status = "running" },
      }
    end,
    focus = function() end,
    kill = function() end,
    rename_prompt = function(id, callback)
      renamed = id
      callback(true)
    end,
  }

  local ui = T.reload("agent.ui")
  ui.open_manager()
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  T.feed("r")

  T.eq(renamed, 5)
  T.matches(T.current_buf_lines()[4], "notes")
end)

T.test("ui.open_manager ignores async rename refresh after the manager closes", function()
  local rename_callback

  package.loaded["agent.agents"] = {
    list = function()
      return {
        { id = 5, label = "claude", status = "running" },
      }
    end,
    focus = function() end,
    kill = function() end,
    rename_prompt = function(_, callback)
      rename_callback = callback
    end,
  }

  local ui = T.reload("agent.ui")
  ui.open_manager()
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_cursor(0, { 4, 0 })
  T.feed("r")
  T.feed("q")

  T.falsy(vim.api.nvim_win_is_valid(win), "q should close the manager window")
  local ok, err = pcall(function()
    rename_callback(true)
  end)

  T.truthy(ok, err)
end)
