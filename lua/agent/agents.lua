local M = {}

M.registry = {}
local next_id = 1

local function sanitize_label(label)
  local trimmed = vim.trim(tostring(label or ""))
  if trimmed == "" then
    return nil
  end
  return trimmed
end

local function default_label_for(id)
  return tostring(id)
end

local function label_in_use(label, exclude_id)
  for _, agent in pairs(M.registry) do
    if agent.status == "running" and agent.id ~= exclude_id and agent.label == label then
      return true
    end
  end
  return false
end

local function lookup_agent(ref)
  if ref == nil then
    return nil, "missing"
  end

  if type(ref) == "number" then
    return M.registry[ref]
  end

  local text = vim.trim(tostring(ref))
  if text == "" then
    return nil, "missing"
  end

  local numeric = tonumber(text)
  if numeric and M.registry[numeric] then
    return M.registry[numeric]
  end

  local matches = {}
  for _, agent in pairs(M.registry) do
    if agent.status == "running" and agent.label == text then
      table.insert(matches, agent)
    end
  end
  table.sort(matches, function(a, b) return a.id < b.id end)

  if #matches == 1 then
    return matches[1]
  end
  if #matches > 1 then
    return nil, "ambiguous"
  end
  return nil, "missing"
end

local function require_agent(ref, action)
  local agent, err = lookup_agent(ref)
  if agent then
    return agent
  end

  local target = vim.trim(tostring(ref or ""))
  if err == "ambiguous" then
    vim.notify("agent.nvim: multiple agents match name " .. target, vim.log.levels.WARN)
  else
    vim.notify("agent.nvim: no agent matching " .. target, vim.log.levels.WARN)
  end
  return nil
end

local function resolve_agent_type(agent_type)
  local config = require("agent.config")
  return agent_type or config.opts.default_agent
end

local function format_agent_label(agent)
  return string.format("[%d] %s", agent.id, agent.label)
end

local function buffer_name_for(agent)
  return string.format("agent://%d-%d/[%d] %s | %s | %s", agent.id, agent.bufnr, agent.id, agent.label, agent.type, agent.status)
end

local function sync_agent_metadata(agent)
  if agent and agent.bufnr and vim.api.nvim_buf_is_valid(agent.bufnr) then
    vim.api.nvim_buf_set_name(agent.bufnr, buffer_name_for(agent))
  end
end

-- Spawn a new agent of the given type. opts is reserved for future use.
function M.spawn(agent_type, opts)
  opts = opts or {}
  local config = require("agent.config")
  local t = resolve_agent_type(agent_type)
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
          sync_agent_metadata(M.registry[id])
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
    label  = sanitize_label(opts.label) or default_label_for(id),
  }
  if label_in_use(agent.label, id) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.fn.jobstop(job_id)
    vim.notify("agent.nvim: agent name must be unique: " .. agent.label, vim.log.levels.ERROR)
    return nil
  end
  M.registry[id] = agent
  sync_agent_metadata(agent)
  if opts.focus ~= false then
    M.focus(id)
  end
  vim.notify("agent.nvim: spawned " .. format_agent_label(agent), vim.log.levels.INFO)
  return id
end

function M.kill(ref)
  local agent = require_agent(ref, "kill")
  if not agent then
    return
  end
  if agent.status == "running" then
    vim.fn.jobstop(agent.job_id)
    agent.status = "exited"
    sync_agent_metadata(agent)
  end
  vim.notify("agent.nvim: killed " .. format_agent_label(agent), vim.log.levels.INFO)
end

function M.kill_all()
  for id, agent in pairs(M.registry) do
    if agent.status == "running" then
      vim.fn.jobstop(agent.job_id)
      agent.status = "exited"
      sync_agent_metadata(agent)
    end
  end
  vim.notify("agent.nvim: killed all agents", vim.log.levels.INFO)
end

function M.rename(ref, label)
  local agent = require_agent(ref, "rename")
  if not agent then
    return false
  end

  local new_label = sanitize_label(label)
  if not new_label then
    vim.notify("agent.nvim: rename requires a non-empty label", vim.log.levels.ERROR)
    return false
  end
  if label_in_use(new_label, agent.id) then
    vim.notify("agent.nvim: agent name must be unique: " .. new_label, vim.log.levels.ERROR)
    return false
  end

  agent.label = new_label
  sync_agent_metadata(agent)
  vim.notify("agent.nvim: renamed " .. format_agent_label(agent), vim.log.levels.INFO)
  return true
end

function M.spawn_prompt(agent_type, callback)
  local t = resolve_agent_type(agent_type)
  local default_label = default_label_for(next_id)
  vim.ui.input({
    prompt = string.format("Name new %s agent: ", t),
    default = default_label,
  }, function(input)
    if input == nil then
      if callback then
        callback(nil)
      end
      return
    end

    local id = M.spawn(t, {
      label = sanitize_label(input) or default_label,
    })
    if callback then
      callback(id)
    end
  end)
end

function M.rename_prompt(ref, callback)
  local agent = require_agent(ref, "rename")
  if not agent then
    return
  end

  vim.ui.input({
    prompt = string.format("Rename agent %d: ", agent.id),
    default = agent.label,
  }, function(input)
    if input == nil then
      if callback then
        callback(false)
      end
      return
    end
    local ok = M.rename(agent.id, input)
    if callback then
      callback(ok)
    end
  end)
end

function M.focus(ref)
  local agent = require_agent(ref, "focus")
  if not agent then
    return
  end

  local config = require("agent.config")
  local split = config.opts.split

  if split ~= "current" then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == agent.bufnr then
        vim.api.nvim_set_current_win(win)
        vim.cmd("startinsert")
        return
      end
    end
  end

  if split == "current" then
  elseif split == "float" then
    local width  = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines   * 0.8)
    local row    = math.floor((vim.o.lines   - height) / 2)
    local col    = math.floor((vim.o.columns - width)  / 2)
    vim.api.nvim_open_win(agent.bufnr, true, {
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
  elseif split == "horizontal" then
    vim.cmd("split")
  else
    vim.notify("agent.nvim: invalid split option: " .. tostring(split), vim.log.levels.ERROR)
    return
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
    table.insert(items, string.format("[%d] %-20s %s", a.id, a.label, a.status))
  end
  vim.ui.select(items, { prompt = prompt or "Select agent:" }, function(choice, idx)
    if choice and idx then
      callback(agents[idx].id)
    end
  end)
end

return M
