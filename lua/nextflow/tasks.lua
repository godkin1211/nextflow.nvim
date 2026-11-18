---@mod nextflow.tasks Task explorer for a run (debug failed tasks)
local config = require("nextflow.config")
local history = require("nextflow.history")
local util = require("nextflow.util")

local M = {}

M.FIELDS = "status,exit,name,hash,duration,workdir"

---@class NextflowTask
---@field status string
---@field exit string
---@field name string
---@field hash string
---@field duration string
---@field workdir string

---@param stdout string output of `nextflow log <run> -f <FIELDS>`
---@return NextflowTask[]
function M.parse(stdout)
  local list = {}
  for _, line in ipairs(vim.split(stdout, "\n", { trimempty = true })) do
    local f = vim.split(line, "\t", { plain = true })
    if #f >= 6 then
      list[#list + 1] = {
        status = vim.trim(f[1]),
        exit = vim.trim(f[2]),
        name = vim.trim(f[3]),
        hash = vim.trim(f[4]),
        duration = vim.trim(f[5]),
        workdir = vim.trim(f[6]),
      }
    end
  end
  return list
end

local rank = { FAILED = 1, ABORTED = 2 }

---Stable sort: FAILED, then ABORTED, then the rest in log order.
---@param list NextflowTask[]
---@return NextflowTask[]
function M.sort(list)
  local indexed = {}
  for i, t in ipairs(list) do
    indexed[i] = { t = t, i = i }
  end
  table.sort(indexed, function(a, b)
    local ra, rb = rank[a.t.status] or 3, rank[b.t.status] or 3
    if ra ~= rb then
      return ra < rb
    end
    return a.i < b.i
  end)
  return vim.tbl_map(function(x)
    return x.t
  end, indexed)
end

local markers = { FAILED = "✗", ABORTED = "!", COMPLETED = "✓", CACHED = "↺" }

---@param t NextflowTask
---@return string
function M.label(t)
  return ("%s [%s] %s  %s  %s"):format(markers[t.status] or "?", t.exit, t.name, t.duration, t.hash)
end

local FILES = { ".command.err", ".command.out", ".command.log", ".command.sh", ".command.run", ".exitcode" }

---@param workdir string
---@return {label: string, path: string}[]
function M.files(workdir)
  local stat = vim.uv.fs_stat(workdir)
  if not (stat and stat.type == "directory") then
    return {}
  end
  local out = {}
  for _, name in ipairs(FILES) do
    local p = workdir .. "/" .. name
    if vim.uv.fs_stat(p) then
      out[#out + 1] = { label = name, path = p }
    end
  end
  out[#out + 1] = { label = "open work directory", path = workdir }
  return out
end

---The file to show for a failed task: non-empty .command.err, else .command.log.
---@param workdir string
---@return string|nil
function M.failed_file(workdir)
  for _, name in ipairs({ ".command.err", ".command.log" }) do
    local p = workdir .. "/" .. name
    local stat = vim.uv.fs_stat(p)
    if stat and stat.size > 0 then
      return p
    end
  end
  return nil
end

---The failed task to show: the last FAILED task whose name never succeeded later
---(retried attempts that then COMPLETED/CACHED are skipped), else the last FAILED one.
---@param list NextflowTask[]
---@return NextflowTask|nil
function M.failed_task(list)
  local last
  for i = #list, 1, -1 do
    local t = list[i]
    if t.status == "FAILED" then
      last = last or t
      local retried = false
      for j = i + 1, #list do
        if list[j].name == t.name and (list[j].status == "COMPLETED" or list[j].status == "CACHED") then
          retried = true
          break
        end
      end
      if not retried then
        return t
      end
    end
  end
  return last
end

---Load the task list of `run_name` (default: newest run) and call `cb(run_name, tasks)`.
local function load(buf, run_name, cb)
  local dir = util.launch_dir(buf)
  local entries, err = history.read(dir)
  if not entries or #entries == 0 then
    return util.notify(err or history.NO_HISTORY, vim.log.levels.WARN)
  end
  run_name = run_name or entries[1].run_name
  local cmd = vim.list_extend(util.expand_cmd(config.get().nextflow.cmd), { "log", run_name, "-f", M.FIELDS })
  util.run_async(cmd, { cwd = dir }, function(res)
    if res.code ~= 0 then
      local msg = vim.trim((res.stderr or "") .. "\n" .. (res.stdout or ""))
      return util.notify("nextflow log " .. run_name .. " failed:\n" .. msg, vim.log.levels.ERROR)
    end
    local list = M.parse(res.stdout or "")
    if #list == 0 then
      return util.notify("No tasks recorded for " .. run_name, vim.log.levels.WARN)
    end
    cb(run_name, list)
  end)
end

local function open(path)
  vim.cmd("vsplit " .. vim.fn.fnameescape(path))
end

---@param buf integer
---@param run_name? string
function M.pick(buf, run_name)
  load(buf, run_name, function(run, list)
    vim.ui.select(M.sort(list), { prompt = "Tasks of " .. run, format_item = M.label }, function(t)
      if not t then
        return
      end
      local files = M.files(t.workdir)
      if #files == 0 then
        return util.notify("Work directory missing: " .. t.workdir, vim.log.levels.WARN)
      end
      vim.ui.select(files, {
        prompt = t.name,
        format_item = function(f)
          return f.label
        end,
      }, function(f)
        if f then
          open(f.path)
        end
      end)
    end)
  end)
end

---@param buf integer
function M.open_failed(buf)
  load(buf, nil, function(run, list)
    local t = M.failed_task(list)
    if not t then
      return util.notify("No failed tasks in " .. run)
    end
    local file = M.failed_file(t.workdir)
    if not file then
      return util.notify(("%s failed, but %s has no .command.err/.command.log"):format(t.name, t.workdir), vim.log.levels.WARN)
    end
    util.notify(("%s failed (exit %s)"):format(t.name, t.exit), vim.log.levels.WARN)
    open(file)
  end)
end

function M.register_commands()
  local commands = require("nextflow.commands")
  commands.register("tasks", {
    run = function(args)
      M.pick(vim.api.nvim_get_current_buf(), args[1])
    end,
    complete = function()
      local entries = history.read(util.launch_dir(0)) or {}
      return vim.tbl_map(function(e)
        return e.run_name
      end, entries)
    end,
  })
  commands.register("failed", {
    run = function()
      M.open_failed(vim.api.nvim_get_current_buf())
    end,
  })
end

return M
