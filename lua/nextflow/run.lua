---@mod nextflow.run Run / re-run the pipeline in a terminal
local config = require("nextflow.config")
local terminal = require("nextflow.terminal")
local util = require("nextflow.util")

local M = {}

---@type {cmd: string, cwd: string}|nil
M.last = nil

local function nextflow()
  return table.concat(util.expand_cmd(config.get().nextflow.cmd), " ")
end

function M.run(buf)
  local root = util.root(buf)
  vim.ui.input({ prompt = "nextflow run . ", default = M.args or config.get().run.default_args }, function(args)
    if not args then
      return
    end
    M.args = args
    M.last = { cmd = nextflow() .. " run . " .. args, cwd = root }
    terminal.open(M.last.cmd, root)
  end)
end

function M.rerun(buf)
  if not M.last then
    return M.run(buf)
  end
  terminal.open(M.last.cmd, M.last.cwd)
end

return M
