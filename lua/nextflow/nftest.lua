---@mod nextflow.nftest nf-test runs and script ↔ test jumps
local config = require("nextflow.config")
local terminal = require("nextflow.terminal")
local util = require("nextflow.util")

local M = {}

---Script ↔ test path: <dir>/main.nf ↔ <dir>/tests/main.nf.test, foo.nf ↔ tests/foo.nf.test.
---@param path string
---@return string|nil
function M.alt_path(path)
  local dir, base = vim.fs.dirname(path), vim.fs.basename(path)
  if base:match("%.nf%.test$") then
    local script = base:gsub("%.test$", "")
    if vim.fs.basename(dir) == "tests" then
      return vim.fs.dirname(dir) .. "/" .. script
    end
    return dir .. "/" .. script
  elseif base:match("%.nf$") then
    return dir .. "/tests/" .. base .. ".test"
  end
  return nil
end

local function test_name(line)
  return line:match("%f[%w_]test%s*%(%s*\"(.-)\"%s*%)") or line:match("%f[%w_]test%s*%(%s*'(.-)'%s*%)")
end

---The `test("…")` block containing `row` (1-based), and its 1-based ordinal in the file.
---@param lines string[]
---@param row integer
---@return string|nil name, integer|nil ordinal
function M.enclosing_test(lines, row)
  local ordinal = 0
  for start, line in ipairs(lines) do
    local name = test_name(line)
    if name then
      ordinal = ordinal + 1
      if start > row then
        return nil
      end
      -- find the end of the block by counting braces from the test( line
      local depth, opened, finish = 0, false, #lines
      for i = start, #lines do
        local l = lines[i]:gsub('"[^"]*"', ""):gsub("'[^']*'", "")
        for ch in l:gmatch("[{}]") do
          depth = depth + (ch == "{" and 1 or -1)
          opened = opened or ch == "{"
        end
        if opened and depth <= 0 then
          finish = i
          break
        end
      end
      if row <= finish then
        return name, ordinal
      end
    end
  end
  return nil
end

---Parse `nf-test list --silent <file>` output.
---@param stdout string
---@return {path: string, hash: string, name: string}[]
function M.parse_list(stdout)
  local list = {}
  local clean = stdout:gsub("\27%[[%d;]*m", "")
  for _, line in ipairs(vim.split(clean, "\n")) do
    local path, hash, name = line:match("^%s*%[(.-)@(%x+)%]%s+(.-)%s*$")
    if path then
      list[#list + 1] = { path = path, hash = hash, name = name }
    end
  end
  return list
end

---@param list {hash: string, name: string}[]
---@param name string
---@param ordinal integer
function M.pick_entry(list, name, ordinal)
  if list[ordinal] and list[ordinal].name == name then
    return list[ordinal]
  end
  for _, e in ipairs(list) do
    if e.name == name then
      return e
    end
  end
  return nil
end

---@param buf integer
---@return string
function M.root(buf)
  return vim.fs.root(buf, "nf-test.config") or util.root(buf)
end

local function nf_test()
  return util.expand_cmd(config.get().nf_test.cmd)
end

local function rel(path, root)
  if vim.startswith(path, root .. "/") then
    return path:sub(#root + 2)
  end
  return path
end

local function run_in_terminal(args, root)
  local parts = vim.tbl_map(vim.fn.shellescape, vim.list_extend(nf_test(), args))
  terminal.open(table.concat(parts, " "), root)
end

---The .nf.test file for the buffer (itself, or the script's test), or nil after notifying.
local function test_file(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  if name:match("%.nf%.test$") then
    return name
  end
  local alt = name:match("%.nf$") and M.alt_path(name)
  if alt and vim.uv.fs_stat(alt) then
    return alt
  end
  util.notify("No test file for " .. (name ~= "" and vim.fs.basename(name) or "this buffer"), vim.log.levels.WARN)
  return nil
end

---@param buf integer
---@param mode "file"|"nearest"|"all"|"update"
function M.run(buf, mode)
  local root = M.root(buf)
  if mode == "all" then
    return run_in_terminal({ "test" }, root)
  end
  local file = test_file(buf)
  if not file then
    return
  end
  local target = rel(file, root)
  if mode == "update" then
    return run_in_terminal({ "test", target, "--update-snapshot" }, root)
  end
  if mode == "nearest" then
    local is_current = file == vim.api.nvim_buf_get_name(buf)
    local name, ordinal
    if is_current then
      name, ordinal = M.enclosing_test(vim.api.nvim_buf_get_lines(buf, 0, -1, false), vim.api.nvim_win_get_cursor(0)[1])
    end
    if not name then
      util.notify("Cursor is not inside a test(); running the whole file")
      return run_in_terminal({ "test", target }, root)
    end
    local cmd = vim.list_extend(nf_test(), { "list", "--silent", target })
    return util.run_async(cmd, { cwd = root }, function(res)
      local entry = M.pick_entry(M.parse_list(res.stdout or ""), name, ordinal)
      if not entry then
        util.notify(("Could not find test %q via nf-test list; running the whole file"):format(name), vim.log.levels.WARN)
        return run_in_terminal({ "test", target }, root)
      end
      run_in_terminal({ "test", entry.path .. "@" .. entry.hash }, root)
    end)
  end
  run_in_terminal({ "test", target }, root)
end

---@param buf integer
function M.alt(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local target = M.alt_path(name)
  if not target then
    return util.notify("Not a Nextflow script or nf-test file", vim.log.levels.WARN)
  end
  if not vim.uv.fs_stat(target) then
    util.notify("New file: " .. target)
  end
  vim.cmd("edit " .. vim.fn.fnameescape(target))
end

function M.register_commands()
  local commands = require("nextflow.commands")
  commands.register("test", {
    run = function(args)
      local mode = args[1] or "file"
      if not vim.tbl_contains({ "file", "nearest", "all", "update" }, mode) then
        return util.notify("Usage: :Nextflow test [file|nearest|all|update]", vim.log.levels.WARN)
      end
      M.run(vim.api.nvim_get_current_buf(), mode)
    end,
    complete = function()
      return { "file", "nearest", "all", "update" }
    end,
  })
  commands.register("alt", {
    run = function()
      M.alt(vim.api.nvim_get_current_buf())
    end,
  })
end

return M
