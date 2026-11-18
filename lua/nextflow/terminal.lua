---@mod nextflow.terminal Built-in :terminal in a bottom split
local config = require("nextflow.config")

local M = {}

local opened = {} ---@type integer[]

---Wipe earlier terminals whose job has ended and that no window shows.
local function prune()
  opened = vim.tbl_filter(function(b)
    if not vim.api.nvim_buf_is_valid(b) then
      return false
    end
    local finished = vim.fn.jobwait({ vim.bo[b].channel }, 0)[1] ~= -1
    if finished and #vim.fn.win_findbuf(b) == 0 then
      vim.api.nvim_buf_delete(b, { force = true })
      return false
    end
    return true
  end, opened)
end

---@param cmd string shell command
---@param cwd string
function M.open(cmd, cwd)
  prune()
  local height = math.max(5, math.floor(vim.o.lines * config.get().terminal.height))
  vim.cmd("botright " .. height .. "split")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  vim.fn.jobstart(cmd, { term = true, cwd = cwd })
  opened[#opened + 1] = buf
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, desc = "Close Nextflow terminal" })
  vim.cmd("normal! G")
end

return M
