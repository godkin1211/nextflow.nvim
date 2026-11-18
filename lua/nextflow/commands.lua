---@mod nextflow.commands :Nextflow subcommands
local util = require("nextflow.util")

local M = {}

---@alias NextflowSubcommand {run: fun(args: string[], bang: boolean), complete?: fun(): string[]}
---@type table<string, NextflowSubcommand>
M.subcommands = {}

---@param name string
---@param spec NextflowSubcommand
function M.register(name, spec)
  M.subcommands[name] = spec
end

local buf = function()
  return vim.api.nvim_get_current_buf()
end

M.register("run", { run = function() require("nextflow.run").run(buf()) end })
M.register("rerun", { run = function() require("nextflow.run").rerun(buf()) end })
M.register("lint", { run = function() require("nextflow.lint").lint(buf()) end })
M.register("format", {
  run = function() vim.lsp.buf.format({ bufnr = buf(), name = "nextflow_ls" }) end,
})
M.register("dag", { run = function() require("nextflow.lsp").run_lens(buf()) end })
M.register("log", {
  run = function()
    local dir = util.launch_dir(buf()) or util.root(buf())
    local nf = require("nextflow.run").nextflow_cmd()
    require("nextflow.terminal").open(nf .. " log", dir)
  end,
})
M.register("health", { run = function() vim.cmd("checkhealth nextflow") end })

-- Feature modules register their own subcommands on first use.
local feature_modules = { "history", "tasks", "nftest", "params", "nfcore" }
local loaded = false
local function load_features()
  if loaded then
    return
  end
  loaded = true
  for _, name in ipairs(feature_modules) do
    if #vim.api.nvim_get_runtime_file("lua/nextflow/" .. name .. ".lua", false) > 0 then
      local mod = require("nextflow." .. name)
      if mod.register_commands then
        mod.register_commands()
      end
    end
  end
end

---@param fargs string[]
---@param bang boolean
function M.dispatch(fargs, bang)
  load_features()
  local name = fargs[1]
  -- `:Nextflow modules!` — Vim only gives the command itself a bang, so accept it on the subcommand
  if name and not M.subcommands[name] and name:sub(-1) == "!" and M.subcommands[name:sub(1, -2)] then
    name, bang = name:sub(1, -2), true
  end
  local spec = name and M.subcommands[name]
  if not spec then
    local names = vim.tbl_keys(M.subcommands)
    table.sort(names)
    return util.notify(
      ("Unknown subcommand %q. Available: %s"):format(name or "", table.concat(names, ", ")),
      vim.log.levels.WARN
    )
  end
  spec.run(vim.list_slice(fargs, 2), bang)
end

local function filter(list, prefix)
  return vim.tbl_filter(function(s)
    return vim.startswith(s, prefix)
  end, list)
end

---@param arglead string
---@param cmdline string
---@return string[]
function M.complete(arglead, cmdline)
  load_features()
  local rest = (cmdline:gsub("^%s*%S+%s*", ""))
  local sub = rest:match("^(%S+)%s")
  if not sub then
    local names = vim.tbl_keys(M.subcommands)
    table.sort(names)
    return filter(names, arglead)
  end
  local spec = M.subcommands[sub]
  if not (spec and spec.complete) then
    return {}
  end
  return filter(spec.complete(), arglead)
end

return M
