---@mod nextflow.history .nextflow/history and the resume picker
local terminal = require("nextflow.terminal")
local util = require("nextflow.util")

local M = {}

---@class NextflowHistoryEntry
---@field date string
---@field duration string
---@field run_name string
---@field status string
---@field revision string
---@field session_id string
---@field command string

M.NO_HISTORY = "No Nextflow runs found (no .nextflow/history)"

---@param text string
---@return NextflowHistoryEntry[] newest first
function M.parse(text)
  local entries = {}
  for _, line in ipairs(vim.split(text, "\n", { trimempty = true })) do
    local f = vim.split(line, "\t", { plain = true })
    if #f >= 7 then
      table.insert(entries, 1, {
        date = vim.trim(f[1]),
        duration = vim.trim(f[2]),
        run_name = vim.trim(f[3]),
        status = vim.trim(f[4]),
        revision = vim.trim(f[5]),
        session_id = vim.trim(f[6]),
        command = vim.trim(table.concat(f, "\t", 7)),
      })
    end
  end
  return entries
end

---@param launch_dir string|nil
---@return NextflowHistoryEntry[]|nil, string|nil
function M.read(launch_dir)
  local path = launch_dir and (launch_dir .. "/.nextflow/history")
  if not (path and vim.uv.fs_stat(path)) then
    return nil, M.NO_HISTORY
  end
  return M.parse(table.concat(vim.fn.readfile(path), "\n")), nil
end

local function is_resume_target(tok)
  return tok ~= nil
    and (tok:match("^%x+%-%x+%-%x+%-%x+%-%x+$") ~= nil or tok:match("^%l+_%l+$") ~= nil)
end

---Original command with any `-resume [id]` removed, plus `-resume <session_id>`.
---@param entry NextflowHistoryEntry
---@param nf? string configured nextflow command; replaces a leading `nextflow`
---@return string
function M.resume_command(entry, nf)
  local toks = vim.split(entry.command, "%s+", { trimempty = true })
  local out, i = {}, 1
  while i <= #toks do
    local t = toks[i]
    if t == "-resume" then
      i = i + (is_resume_target(toks[i + 1]) and 2 or 1)
    elseif t:match("^%-resume=") then
      i = i + 1
    else
      out[#out + 1] = t
      i = i + 1
    end
  end
  if nf and out[1] == "nextflow" then
    out[1] = nf
  end
  return table.concat(out, " ") .. " -resume " .. entry.session_id
end

---@param e NextflowHistoryEntry
---@return string
function M.label(e)
  return table.concat({ e.date, e.run_name, e.status, e.duration, e.command }, "  ")
end

function M.pick_resume(buf)
  local dir = util.launch_dir(buf)
  local entries, err = M.read(dir)
  if not entries or #entries == 0 then
    return util.notify(err or M.NO_HISTORY, vim.log.levels.WARN)
  end
  vim.ui.select(entries, { prompt = "Resume which run?", format_item = M.label }, function(e)
    if not e then
      return
    end
    vim.ui.input({ prompt = "Command: ", default = M.resume_command(e, require("nextflow.run").nextflow_cmd()) }, function(cmd)
      if cmd and cmd ~= "" then
        terminal.open(cmd, dir)
      end
    end)
  end)
end

function M.register_commands()
  require("nextflow.commands").register("resume", {
    run = function()
      M.pick_resume(vim.api.nvim_get_current_buf())
    end,
  })
end

return M
