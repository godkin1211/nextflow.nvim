---@mod nextflow.nfcore nf-core module pickers (remote list, installed modules)
local config = require("nextflow.config")
local terminal = require("nextflow.terminal")
local util = require("nextflow.util")

local M = {}

---@return string
function M.cache_path()
  return vim.fn.stdpath("cache") .. "/nextflow.nvim/remote_modules.json"
end

---@param path string
---@param ttl integer seconds
---@param now? integer
---@return boolean
function M.cache_fresh(path, ttl, now)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return false
  end
  return (now or os.time()) - stat.mtime.sec < ttl
end

---Decode the JSON string array in nf-core output (which may be preceded by log lines).
local function decode_list(text)
  local start = text:find("^%s*%[") and 1 or text:find("\n%s*%[")
  if not start then
    return {}
  end
  local ok, list = pcall(vim.json.decode, text:sub(start))
  if not ok or type(list) ~= "table" then
    return {}
  end
  local names = vim.tbl_filter(function(v)
    return type(v) == "string"
  end, list)
  table.sort(names)
  return names
end

---@param json string stdout of `nf-core modules list remote --json`
---@return string[]
function M.parse_remote(json)
  return decode_list(json)
end

---@param json string stdout of `nf-core modules list local --json -d <dir>`
---@return string[]
function M.parse_local(json)
  return decode_list(json)
end

local function nf_core()
  return util.expand_cmd(config.get().nf_core.cmd)
end

---Pipeline root: the dir with .nf-core.yml / modules.json, else the project root.
local function root(buf)
  return vim.fs.root(buf, { ".nf-core.yml", "modules.json" }) or util.root(buf)
end

local function in_terminal(args, dir)
  local parts = vim.tbl_map(vim.fn.shellescape, vim.list_extend(nf_core(), args))
  terminal.open(table.concat(parts, " "), dir)
end

---@param title string
---@param items string[]
---@param actions {label: string, run: fun(m: string)}[]
local function pick(title, items, actions)
  vim.ui.select(items, { prompt = title }, function(m)
    if not m then
      return
    end
    vim.ui.select(actions, {
      prompt = m,
      format_item = function(a)
        return a.label
      end,
    }, function(a)
      if a then
        a.run(m)
      end
    end)
  end)
end

---@param buf integer
---@param force boolean refresh the cached remote list
function M.pick_remote(buf, force)
  local dir = root(buf)
  local actions = {
    { label = "info", run = function(m) in_terminal({ "modules", "info", m }, dir) end },
    { label = "install", run = function(m) in_terminal({ "modules", "install", m, "-d", dir }, dir) end },
  }
  local path = M.cache_path()
  if not force and M.cache_fresh(path, config.get().nf_core.cache_ttl) then
    local list = M.parse_remote(table.concat(vim.fn.readfile(path), "\n"))
    if #list > 0 then
      return pick("nf-core modules", list, actions)
    end
  end
  local cmd = vim.list_extend(nf_core(), { "modules", "list", "remote", "--json" })
  if vim.fn.executable(cmd[1]) == 1 then
    util.notify("Fetching nf-core module list…")
  end
  util.run_async(cmd, { cwd = dir }, function(res)
    local list = M.parse_remote(res.stdout or "")
    if res.code ~= 0 or #list == 0 then
      local msg = vim.trim(res.stderr or "")
      return util.notify("nf-core modules list remote failed" .. (msg ~= "" and (":\n" .. msg) or ""), vim.log.levels.ERROR)
    end
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    vim.fn.writefile({ vim.json.encode(list) }, path)
    pick("nf-core modules", list, actions)
  end)
end

---@param buf integer
function M.pick_local(buf)
  local dir = root(buf)
  local actions = {
    { label = "info", run = function(m) in_terminal({ "modules", "info", m, "-d", dir }, dir) end },
    { label = "update", run = function(m) in_terminal({ "modules", "update", m, "-d", dir }, dir) end },
    { label = "remove", run = function(m) in_terminal({ "modules", "remove", m, "-d", dir }, dir) end },
    {
      label = "open main.nf",
      run = function(m)
        local file = dir .. "/modules/nf-core/" .. m .. "/main.nf"
        if not vim.uv.fs_stat(file) then
          return util.notify("Not found: " .. file, vim.log.levels.WARN)
        end
        vim.cmd("edit " .. vim.fn.fnameescape(file))
      end,
    },
  }
  local cmd = vim.list_extend(nf_core(), { "modules", "list", "local", "--json", "-d", dir })
  util.run_async(cmd, { cwd = dir }, function(res)
    if res.code ~= 0 then
      return util.notify("nf-core modules list local failed:\n" .. vim.trim(res.stderr or ""), vim.log.levels.ERROR)
    end
    local list = M.parse_local(res.stdout or "")
    if #list == 0 then
      return util.notify("No nf-core modules installed in " .. dir)
    end
    pick("Installed nf-core modules", list, actions)
  end)
end

function M.register_commands()
  require("nextflow.commands").register("modules", {
    run = function(args, bang)
      local buf = vim.api.nvim_get_current_buf()
      if args[1] == "local" then
        return M.pick_local(buf)
      end
      M.pick_remote(buf, bang == true)
    end,
    complete = function()
      return { "local" }
    end,
  })
end

return M
