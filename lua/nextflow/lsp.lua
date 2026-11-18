---@mod nextflow.lsp Nextflow language server: cmd resolution, setup, code-lens commands
local config = require("nextflow.config")
local util = require("nextflow.util")

local M = {}

---Pick the path with the highest x.y.z version (looked up below `base`).
local function newest(paths, base)
  local function ver(p)
    return p:sub(#base + 1):match("(%d+%.%d+%.%d+)") or "0.0.0"
  end
  table.sort(paths, function(a, b)
    return vim.version.cmp(ver(a), ver(b)) > 0
  end)
  return paths[1]
end

---Resolve the server command: PATH → newest native bundle → newest jar (java) → Mason.
---@param opts? {cache_dir?: string}
---@return string[]|nil
function M.resolve_cmd(opts)
  if vim.fn.executable("nextflow-lsp") == 1 then
    return { "nextflow-lsp" }
  end
  local cache = (opts and opts.cache_dir) or vim.fn.expand("~/.nextflow/lsp")
  local native = newest(vim.fn.glob(cache .. "/*/nextflow-language-server-*/bin/nextflow-lsp", false, true), cache)
  if native and vim.fn.executable(native) == 1 then
    return { native }
  end
  local jar = newest(vim.fn.glob(cache .. "/*/v*.jar", false, true), cache)
  if jar and vim.fn.executable("java") == 1 then
    return { "java", "-jar", jar }
  end
  local mason = vim.fn.stdpath("data") .. "/mason/bin/nextflow-language-server"
  if vim.fn.executable(mason) == 1 then
    return { mason }
  end
  return nil
end

---@param name string|nil
---@param mermaid string
---@return string[]
function M.dag_markdown(name, mermaid)
  local lines = { "# DAG: " .. (name or "<entry>"), "", "```mermaid" }
  vim.list_extend(lines, vim.split(mermaid, "\n"))
  lines[#lines + 1] = "```"
  return lines
end

---Where the DAG markdown for workflow `name` is written (overwritten on each preview).
---@param name string|nil
---@return string
function M.dag_file(name)
  return ("%s/nextflow.nvim/dag/%s_dag.md"):format(vim.fn.stdpath("cache"), (name or "entry"):gsub("[^%w_]", "_"))
end

local function exec_server(client, command, args, cb)
  client:request("workspace/executeCommand", { command = command, arguments = args }, function(err, res)
    if err or not res or not res.result then
      local msg = err and err.message or (res and res.error) or "no result"
      return util.notify(command .. ": " .. tostring(msg), vim.log.levels.ERROR)
    end
    cb(res.result)
  end)
end

-- Client-side commands the server's code lenses invoke (same names as in VS Code).
M.commands = {
  ["nextflow.previewDag"] = function(command, ctx)
    local client = assert(vim.lsp.get_client_by_id(ctx.client_id))
    local uri, name = command.arguments[1], command.arguments[2]
    if name == vim.NIL then -- JSON null (entry workflow) arrives as userdata
      name = nil
    end
    exec_server(client, "nextflow.server.previewDag", { uri, name or vim.NIL }, function(mermaid)
      local file = M.dag_file(name)
      vim.fn.mkdir(vim.fs.dirname(file), "p")
      vim.fn.writefile(M.dag_markdown(name, mermaid), file)
      vim.cmd("vsplit " .. vim.fn.fnameescape(file))
      if config.get().dag.open_preview and vim.fn.exists(":MarkdownPreview") == 2 then
        vim.cmd("MarkdownPreview")
      end
    end)
  end,
  ["nextflow.previewConfig"] = function(command, ctx)
    local client = assert(vim.lsp.get_client_by_id(ctx.client_id))
    local a = command.arguments
    exec_server(client, "nextflow.server.previewConfig", { a[1], a[2], {}, a[3] or vim.NIL }, function(result)
      local text = type(result) == "string" and result
        or (type(result) == "table" and (result.content or result.text))
        or vim.inspect(result)
      util.scratch(vim.split(tostring(text), "\n"), "nextflow")
    end)
  end,
}

---Lenses to run for 0-based `row`: the innermost one whose range holds the row
---(the server puts "Preview DAG" on a workflow's first line but spans its whole body),
---else every lens in the buffer.
---@param lenses lsp.CodeLens[]
---@param row integer
---@return lsp.CodeLens[]
function M.lens_candidates(lenses, row)
  local runnable = vim.tbl_filter(function(l)
    return l.command ~= nil
  end, lenses)
  local inner
  for _, l in ipairs(runnable) do
    if l.range.start.line <= row and row <= l.range["end"].line then
      if not inner or l.range.start.line >= inner.range.start.line then
        inner = l
      end
    end
  end
  return inner and { inner } or runnable
end

---Run the code lens for the cursor (`:Nextflow dag`), asking when several apply.
---@param buf integer
function M.run_lens(buf)
  local client = vim.lsp.get_clients({ bufnr = buf, name = "nextflow_ls" })[1]
  if not client then
    return util.notify("nextflow_ls is not attached to this buffer", vim.log.levels.WARN)
  end
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local lenses = M.lens_candidates(vim.lsp.codelens.get(buf) or {}, row)
  local function run(l)
    client:exec_cmd(l.command, { bufnr = buf })
  end
  if #lenses == 0 then
    return util.notify("No code lens in this file (a workflow shows \"Preview DAG\")", vim.log.levels.WARN)
  elseif #lenses == 1 then
    return run(lenses[1])
  end
  vim.ui.select(lenses, {
    prompt = "Code lens",
    format_item = function(l)
      return ("%s  (line %d)"):format(l.command.title, l.range.start.line + 1)
    end,
  }, function(l)
    if l then
      run(l)
    end
  end)
end

local warned = false

function M.setup()
  for name, fn in pairs(M.commands) do
    vim.lsp.commands[name] = fn
  end

  local group = vim.api.nvim_create_augroup("nextflow_lsp", { clear = true })
  -- code lenses ("Preview DAG" above each workflow) need explicit refreshing
  vim.api.nvim_create_autocmd({ "LspAttach", "BufEnter", "InsertLeave", "BufWritePost" }, {
    group = group,
    callback = function(ev)
      if vim.bo[ev.buf].filetype ~= "nextflow" then
        return
      end
      if #vim.lsp.get_clients({ bufnr = ev.buf, name = "nextflow_ls" }) > 0 then
        vim.lsp.codelens.refresh({ bufnr = ev.buf })
      end
    end,
  })

  local opts = config.get().lsp
  if not opts.enable then
    return
  end
  local cmd = opts.cmd and util.expand_cmd(opts.cmd) or M.resolve_cmd()
  if not cmd then
    if not warned then
      warned = true
      util.notify("Nextflow language server not found (see :checkhealth nextflow)", vim.log.levels.WARN)
    end
    return
  end
  vim.lsp.config("nextflow_ls", {
    cmd = cmd,
    filetypes = { "nextflow" },
    root_markers = { "nextflow.config", "main.nf", ".git" },
    settings = opts.settings,
  })
  vim.lsp.enable("nextflow_ls")
end

return M
