---@mod nextflow.util Shared helpers
local M = {}

---@param msg string
---@param level? integer
function M.notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Nextflow" })
end

---Project root: dir with nextflow.config or main.nf, else cwd.
---@param buf? integer
---@return string
function M.root(buf)
  return vim.fs.root(buf or 0, { "nextflow.config", "main.nf" }) or vim.fn.getcwd()
end

local function has_history(dir)
  return vim.uv.fs_stat(dir .. "/.nextflow/history") ~= nil
end

---Directory a pipeline was launched from (holds .nextflow/history).
---The cwd wins; otherwise the nearest ancestor of the buffer's file.
---@param buf? integer
---@return string|nil
function M.launch_dir(buf)
  local cwd = vim.fn.getcwd()
  if has_history(cwd) then
    return cwd
  end
  local name = vim.api.nvim_buf_get_name(buf or 0)
  if name == "" then
    return nil
  end
  for dir in vim.fs.parents(name) do
    if has_history(dir) then
      return dir
    end
  end
  return nil
end

---@param cmd string|string[]
---@return string[]
function M.expand_cmd(cmd)
  local parts = type(cmd) == "string" and vim.split(cmd, " ", { trimempty = true }) or vim.deepcopy(cmd)
  for i, p in ipairs(parts) do
    if p:sub(1, 1) == "~" then
      parts[i] = vim.fn.expand(p)
    end
  end
  return parts
end

---Join a command for a shell, quoting only the parts that need it.
---@param parts string[]
---@return string
function M.shell_join(parts)
  return table.concat(vim.tbl_map(function(p)
    return p:match("^[%w%._/%-=:,+@%%]+$") and p or vim.fn.shellescape(p)
  end, parts), " ")
end

---Run a CLI asynchronously; `on_done` runs on the main loop.
---A missing executable gives one notification and no callback.
---@param cmd string[]
---@param opts? {cwd?: string}
---@param on_done fun(res: vim.SystemCompleted)
function M.run_async(cmd, opts, on_done)
  if vim.fn.executable(cmd[1]) ~= 1 then
    M.notify(cmd[1] .. " not found", vim.log.levels.ERROR)
    return
  end
  vim.system(cmd, { cwd = opts and opts.cwd, text = true }, function(res)
    vim.schedule(function()
      on_done(res)
    end)
  end)
end

---Open lines in a vertical-split scratch buffer.
---@param lines string[]
---@param ft? string
---@return integer buf
function M.scratch(lines, ft)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  vim.keymap.set("n", "q", "<cmd>bwipeout<cr>", { buffer = buf, nowait = true, desc = "Close preview" })
  if ft then
    vim.bo[buf].filetype = ft
  end
  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, buf)
  return buf
end

return M
