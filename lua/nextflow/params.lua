---@mod nextflow.params Parameter docs and params-file validation from nextflow_schema.json
local util = require("nextflow.util")

local M = {}

---@param buf integer
---@return string|nil
function M.find_schema(buf)
  local root = vim.fs.root(buf, "nextflow_schema.json")
  return root and (root .. "/nextflow_schema.json") or nil
end

local cache = {} ---@type table<string, {mtime: integer, schema: table}>

---Read and decode a schema file (cached by path + mtime).
---@param path string
---@return table|nil
function M.load(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil
  end
  local hit = cache[path]
  if hit and hit.mtime == stat.mtime.sec then
    return hit.schema
  end
  local ok, schema = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"), { luanil = { object = true } })
  if not ok or type(schema) ~= "table" then
    return nil
  end
  cache[path] = { mtime = stat.mtime.sec, schema = schema }
  return schema
end

---Every object-with-properties in the schema: the top level, $defs.*, definitions.*.
local function groups(schema)
  local out = { schema }
  for _, key in ipairs({ "$defs", "definitions" }) do
    if type(schema[key]) == "table" then
      local names = vim.tbl_keys(schema[key])
      table.sort(names)
      for _, n in ipairs(names) do
        out[#out + 1] = schema[key][n]
      end
    end
  end
  return out
end

---@param schema table
---@param name string
---@return table|nil entry, boolean|nil required
function M.lookup(schema, name)
  for _, g in ipairs(groups(schema)) do
    local entry = type(g) == "table" and type(g.properties) == "table" and g.properties[name]
    if entry then
      return entry, vim.tbl_contains(g.required or {}, name)
    end
  end
  return nil
end

---Merge all groups into one draft-07 object schema (what yamlls/jsonls understand).
---@param schema table
---@return table
function M.flatten(schema)
  local properties, required = {}, {}
  for _, g in ipairs(groups(schema)) do
    if type(g) == "table" then
      for k, v in pairs(g.properties or {}) do
        properties[k] = v
      end
      for _, r in ipairs(g.required or {}) do
        if not vim.tbl_contains(required, r) then
          required[#required + 1] = r
        end
      end
    end
  end
  return {
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
    type = "object",
    properties = properties,
    required = required,
  }
end

local function show_value(v)
  return type(v) == "string" and v or vim.json.encode(v)
end

---@param name string
---@param entry table
---@param required? boolean
---@return string[]
function M.format_entry(name, entry, required)
  local head = ("`params.%s`"):format(name)
  if entry.type then
    head = head .. " (" .. show_value(entry.type) .. ")"
  end
  if required then
    head = head .. " — **required**"
  end
  local lines = { head }
  local function para(text)
    lines[#lines + 1] = ""
    vim.list_extend(lines, vim.split(text, "\n"))
  end
  if entry.description then
    para(entry.description)
  end
  if entry.help_text then
    para(entry.help_text)
  end
  local facts = {}
  if entry.default ~= nil then
    facts[#facts + 1] = "- default: `" .. show_value(entry.default) .. "`"
  end
  if type(entry.enum) == "table" then
    facts[#facts + 1] = "- one of: " .. table.concat(vim.tbl_map(function(v)
      return "`" .. show_value(v) .. "`"
    end, entry.enum), ", ")
  end
  if entry.pattern then
    facts[#facts + 1] = "- pattern: `" .. entry.pattern .. "`"
  end
  if entry.format then
    facts[#facts + 1] = "- format: " .. entry.format
  end
  if #facts > 0 then
    lines[#lines + 1] = ""
    vim.list_extend(lines, facts)
  end
  return lines
end

---Name of the `params.<name>` under 0-based byte column `col`, if any.
---@param line string
---@param col integer
---@return string|nil
function M.word_at(line, col)
  local init = 1
  while true do
    local s, e, name = line:find("%f[%w_]params%.([%a_][%w_]*)", init)
    if not s then
      return nil
    end
    if col + 1 >= s and col + 1 <= e then
      return name
    end
    init = e + 1
  end
end

---@param path string
---@return boolean
function M.is_params_file(path)
  local base = vim.fs.basename(path)
  return base:match("^params.*%.ya?ml$") ~= nil or base:match("^params.*%.json$") ~= nil
end

---@param buf integer
function M.show(buf)
  local schema_path = M.find_schema(buf)
  local schema = schema_path and M.load(schema_path)
  if not schema then
    return util.notify("No nextflow_schema.json found", vim.log.levels.WARN)
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1] or ""
  local name = M.word_at(line, cursor[2])
  if not name then
    return util.notify("Cursor is not on params.<name>", vim.log.levels.WARN)
  end
  local entry, required = M.lookup(schema, name)
  if not entry then
    return util.notify(("params.%s is not in nextflow_schema.json"):format(name), vim.log.levels.WARN)
  end
  vim.lsp.util.open_floating_preview(M.format_entry(name, entry, required), "markdown", { border = "rounded" })
end

---Write the flattened schema to the cache; returns its file URI.
local function cached_schema_uri(schema_path, schema)
  local dir = vim.fn.stdpath("cache") .. "/nextflow.nvim/schemas"
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/" .. vim.fn.sha256(schema_path) .. ".json"
  vim.fn.writefile({ vim.json.encode(M.flatten(schema)) }, file)
  return vim.uri_from_fname(file)
end

---Point yamlls/jsonls at the pipeline schema for a params file.
---@param client vim.lsp.Client
---@param buf integer
function M.attach(client, buf)
  if client.name ~= "yamlls" and client.name ~= "jsonls" then
    return
  end
  local path = vim.api.nvim_buf_get_name(buf)
  if not M.is_params_file(path) then
    return
  end
  local schema_path = M.find_schema(buf)
  local schema = schema_path and M.load(schema_path)
  if not schema then
    return
  end
  local uri = cached_schema_uri(schema_path, schema)
  client.settings = client.settings or {}
  if client.name == "yamlls" then
    client.settings.yaml = client.settings.yaml or {}
    client.settings.yaml.schemas = client.settings.yaml.schemas or {}
    client.settings.yaml.schemas[uri] = path
  else
    client.settings.json = client.settings.json or {}
    client.settings.json.schemas = client.settings.json.schemas or {}
    for _, s in ipairs(client.settings.json.schemas) do
      if s.url == uri and vim.tbl_contains(s.fileMatch or {}, path) then
        return
      end
    end
    table.insert(client.settings.json.schemas, { fileMatch = { path }, url = uri })
  end
  client:notify("workspace/didChangeConfiguration", { settings = client.settings })
end

function M.setup()
  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("nextflow_params", { clear = true }),
    callback = function(ev)
      local client = vim.lsp.get_client_by_id(ev.data.client_id)
      if client then
        M.attach(client, ev.buf)
      end
    end,
  })
end

function M.register_commands()
  require("nextflow.commands").register("param", {
    run = function()
      M.show(vim.api.nvim_get_current_buf())
    end,
  })
end

return M
