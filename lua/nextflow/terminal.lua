---@mod nextflow.terminal Built-in :terminal in a bottom split
local config = require("nextflow.config")

local M = {}

---@param cmd string shell command
---@param cwd string
function M.open(cmd, cwd)
  local height = math.max(5, math.floor(vim.o.lines * config.get().terminal.height))
  vim.cmd("botright " .. height .. "split")
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, buf)
  vim.fn.jobstart(cmd, { term = true, cwd = cwd })
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, desc = "Close Nextflow terminal" })
  vim.cmd("normal! G")
end

return M
