---@mod nextflow.health :checkhealth nextflow
local config = require("nextflow.config")
local util = require("nextflow.util")

local M = {}

local h = vim.health

---First non-empty output line of `cmd`, or nil when it fails.
local function first_line(cmd)
  local ok, res = pcall(function()
    return vim.system(cmd, { text = true }):wait(15000)
  end)
  if not ok or res.code ~= 0 then
    return nil
  end
  for _, line in ipairs(vim.split((res.stdout or "") .. "\n" .. (res.stderr or ""), "\n")) do
    local l = vim.trim((line:gsub("\27%[[%d;]*m", "")))
    if l ~= "" then
      return l
    end
  end
  return nil
end

---Version line of a tool, or nil if it is not executable.
local function tool(cmd, version_args, pattern)
  if vim.fn.executable(cmd[1]) ~= 1 then
    return nil
  end
  local res = vim.system(vim.list_extend(vim.deepcopy(cmd), version_args), { text = true }):wait(30000)
  local out = (res.stdout or "") .. "\n" .. (res.stderr or "")
  return out:gsub("\27%[[%d;]*m", ""):match(pattern) or "found"
end

local function check_neovim()
  h.start("Neovim")
  if vim.fn.has("nvim-0.11") == 1 then
    h.ok("Neovim " .. tostring(vim.version()))
  else
    h.error("Neovim ≥ 0.11 is required (vim.lsp.config / vim.lsp.enable)")
  end
end

local function check_lsp()
  h.start("Language server")
  local opts = config.get().lsp
  if not opts.enable then
    return h.info("Disabled (lsp.enable = false)")
  end
  local cmd = opts.cmd and util.expand_cmd(opts.cmd) or require("nextflow.lsp").resolve_cmd()
  if not cmd then
    return h.warn("Nextflow language server not found", {
      "Open any .nf file in VS Code with the Nextflow extension once (it downloads to ~/.nextflow/lsp), or",
      "install `nextflow-language-server` with Mason, or",
      "set `lsp.cmd` in setup()",
    })
  end
  h.ok("cmd: " .. table.concat(cmd, " "))
  if cmd[1] == "java" then
    local line = first_line({ "java", "-version" })
    local major = line and tonumber(line:match('version "(%d+)'))
    if major and major >= 17 then
      h.ok("Java: " .. line)
    else
      h.error("The jar server needs Java ≥ 17; found: " .. (line or "none"))
    end
  end
  local clients = vim.lsp.get_clients({ name = "nextflow_ls" })
  if #clients > 0 then
    h.ok("nextflow_ls running (" .. #clients .. " client)")
  else
    h.info("nextflow_ls not running (open a .nf file to start it)")
  end
end

local function check_tools()
  h.start("Command-line tools")
  local c = config.get()
  local tools = {
    { "nextflow", util.expand_cmd(c.nextflow.cmd), { "-version" }, "version%s+([%d%.]+[%w%.%-]*)", "run, lint, log, tasks" },
    { "nf-test", util.expand_cmd(c.nf_test.cmd), { "version" }, "nf%-test%s+([%d%.]+)", ":Nextflow test" },
    { "nf-core", util.expand_cmd(c.nf_core.cmd), { "--version" }, "version%s+([%d%.]+)", ":Nextflow modules" },
  }
  for _, t in ipairs(tools) do
    local name, cmd, args, pattern, used_by = unpack(t)
    local version = tool(cmd, args, pattern)
    if version then
      h.ok(("%s %s (%s)"):format(name, version, table.concat(cmd, " ")))
    else
      h.warn(("%s not found: `%s` (needed for %s)"):format(name, table.concat(cmd, " "), used_by))
    end
  end
end

---@param lang string
---@return boolean
function M.parser_installed(lang)
  local ok, loaded = pcall(vim.treesitter.language.add, lang)
  return ok and loaded == true
end

local function check_extras()
  h.start("Optional")
  if M.parser_installed("groovy") then
    h.ok("groovy treesitter parser (used for nextflow highlighting)")
  else
    h.warn("groovy treesitter parser not installed", { ":TSInstall groovy" })
  end
  if vim.fn.exists(":MarkdownPreview") == 2 then
    h.ok(":MarkdownPreview available (DAG preview opens in the browser)")
  else
    h.info(":MarkdownPreview not available; DAG previews open as markdown files")
  end
end

function M.check()
  check_neovim()
  check_lsp()
  check_tools()
  check_extras()
end

return M
