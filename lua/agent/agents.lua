local M = {}

M.registry = {}
local next_id = 1

-- Spawn a new agent of the given type. opts is reserved for future use.
function M.spawn(agent_type, opts)
  local config = require("agent.config")
  opts = opts or {}
  local t = agent_type or config.opts.default_agent
  local cmd = config.opts.commands[t]
  if not cmd then
    vim.notify("agent.nvim: unknown agent type: " .. tostring(t), vim.log.levels.ERROR)
    return nil
  end

  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_set_option_value("buflisted",  false,  { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden",  "hide", { buf = bufnr })
  vim.api.nvim_set_option_value("swapfile",   false,  { buf = bufnr })

  local id = next_id
  next_id = next_id + 1

  local job_id
  local ok = pcall(vim.api.nvim_buf_call, bufnr, function()
    job_id = vim.fn.jobstart(cmd, {
      term    = true,
      on_exit = function()
        if M.registry[id] then
          M.registry[id].status = "exited"
        end
      end,
    })
  end)

  if not ok or job_id <= 0 then
    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.notify("agent.nvim: failed to start job for " .. t, vim.log.levels.ERROR)
    return nil
  end

  local agent = {
    id     = id,
    type   = t,
    status = "running",
    bufnr  = bufnr,
    job_id = job_id,
    label  = t .. " #" .. id,
  }
  M.registry[id] = agent
  if opts.focus ~= false then
    M.focus(id)
  end
  vim.notify("agent.nvim: spawned " .. agent.label, vim.log.levels.INFO)
  return id
end

function M.kill(id)
  local agent = M.registry[id]
  if not agent then
    vim.notify("agent.nvim: no agent with id " .. tostring(id), vim.log.levels.WARN)
    return
  end
  if agent.status == "running" then
    vim.fn.jobstop(agent.job_id)
    agent.status = "exited"
  end
  vim.notify("agent.nvim: killed " .. agent.label, vim.log.levels.INFO)
end

function M.kill_all()
  for id, agent in pairs(M.registry) do
    if agent.status == "running" then
      vim.fn.jobstop(agent.job_id)
      agent.status = "exited"
    end
  end
  vim.notify("agent.nvim: killed all agents", vim.log.levels.INFO)
end

function M.focus(id)
  local agent = M.registry[id]
  if not agent then
    vim.notify("agent.nvim: no agent with id " .. tostring(id), vim.log.levels.WARN)
    return
  end

  -- Check if buffer is already visible in a window
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == agent.bufnr then
      vim.api.nvim_set_current_win(win)
      vim.cmd("startinsert")
      return
    end
  end

  local config = require("agent.config")
  local split = config.opts.split
  if split == "float" then
    local width  = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines   * 0.8)
    local row    = math.floor((vim.o.lines   - height) / 2)
    local col    = math.floor((vim.o.columns - width)  / 2)
    local win = vim.api.nvim_open_win(agent.bufnr, true, {
      relative = "editor",
      width    = width,
      height   = height,
      row      = row,
      col      = col,
      style    = "minimal",
      border   = "rounded",
    })
    vim.cmd("startinsert")
    return
  elseif split == "vertical" then
    vim.cmd("vsplit")
  else
    -- horizontal (default)
    vim.cmd("split")
  end
  vim.api.nvim_set_current_buf(agent.bufnr)
  vim.cmd("startinsert")
end

function M.list()
  local result = {}
  for id, agent in pairs(M.registry) do
    if agent.status == "running" then
      table.insert(result, agent)
    else
      M.registry[id] = nil
    end
  end
  table.sort(result, function(a, b) return a.id < b.id end)
  return result
end

function M.pick_id(prompt, callback)
  if type(prompt) == "function" then
    callback = prompt
    prompt = "Select agent:"
  end
  local agents = M.list()
  if #agents == 0 then
    vim.notify("agent.nvim: no agents", vim.log.levels.INFO)
    return
  end
  local items = {}
  for _, a in ipairs(agents) do
    table.insert(items, string.format("[%d] %-10s %s", a.id, a.type, a.status))
  end
  vim.ui.select(items, { prompt = prompt or "Select agent:" }, function(choice, idx)
    if choice and idx then
      callback(agents[idx].id)
    end
  end)
end

return M
