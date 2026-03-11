local M = {}

local function make_lines(agents)
  local lines = { "  Agent Manager  ", string.rep("─", 40), "" }
  if #agents == 0 then
    table.insert(lines, "  (no agents)")
  else
    for _, a in ipairs(agents) do
      table.insert(lines, string.format("  [%d]  %-10s  %s", a.id, a.type, a.status))
    end
  end
  table.insert(lines, "")
  table.insert(lines, "  <CR> focus  x kill  q/<Esc> close")
  return lines
end

-- Returns the agent record for the line under cursor (nil if none).
local function agent_at_cursor(buf, agents)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  -- Agent lines start at line 4 (1-indexed): header(1), sep(2), blank(3), agents...
  local idx = row - 3
  if idx >= 1 and idx <= #agents then
    return agents[idx]
  end
  return nil
end

local function move_cursor_to_first_agent(win, agents)
  if #agents > 0 and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_cursor(win, { 4, 0 })
  end
end

function M.open_manager()
  local agents_mod = require("agent.agents")
  local agents = agents_mod.list()

  local width  = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines   * 0.6)
  local row    = math.floor((vim.o.lines   - height) / 2)
  local col    = math.floor((vim.o.columns - width)  / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  local lines = make_lines(agents)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
  vim.api.nvim_set_option_value("bufhidden",  "wipe", { buf = buf })

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width    = width,
    height   = height,
    row      = row,
    col      = col,
    style    = "minimal",
    border   = "rounded",
  })
  move_cursor_to_first_agent(win, agents)

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local opts = { buffer = buf, nowait = true, noremap = true, silent = true }

  -- <CR>: focus agent under cursor
  vim.keymap.set("n", "<CR>", function()
    local a = agent_at_cursor(buf, agents)
    if a then
      close()
      agents_mod.focus(a.id)
    end
  end, opts)

  -- x: kill agent under cursor and refresh
  vim.keymap.set("n", "x", function()
    local a = agent_at_cursor(buf, agents)
    if a then
      agents_mod.kill(a.id)
      -- Refresh the buffer contents
      agents = agents_mod.list()
      local new_lines = make_lines(agents)
      vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, new_lines)
      vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    end
  end, opts)

  -- q / <Esc>: close
  vim.keymap.set("n", "q",     close, opts)
  vim.keymap.set("n", "<Esc>", close, opts)
end

return M
