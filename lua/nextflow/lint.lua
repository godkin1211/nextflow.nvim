---@mod nextflow.lint `nextflow lint -o json .` → quickfix list
local config = require("nextflow.config")
local util = require("nextflow.util")

local M = {}

---@param json_text string raw stdout (may have log lines before the JSON)
---@param root string directory lint ran in
---@return table[]|nil items, table|string summary_or_err
function M.parse(json_text, root)
  local ok, data = pcall(vim.json.decode, json_text:match("{.*}") or "")
  if not ok or type(data) ~= "table" then
    return nil, "could not parse `nextflow lint` output"
  end
  local items = {}
  for _, kind in ipairs({ { "errors", "E" }, { "warnings", "W" } }) do
    for _, d in ipairs(data[kind[1]] or {}) do
      items[#items + 1] = {
        filename = vim.fs.joinpath(root, d.filename),
        lnum = d.startLine or 1,
        col = d.startColumn or 1,
        text = d.message,
        type = kind[2],
      }
    end
  end
  return items, data.summary or {}
end

---@param res vim.SystemCompleted
---@return string
function M.failure_message(res)
  local detail = vim.trim(res.stderr or "")
  if detail == "" then
    detail = vim.trim(res.stdout or "")
  end
  return ("nextflow lint failed (exit %s)%s"):format(tostring(res.code), detail ~= "" and (":\n" .. detail) or "")
end

function M.lint(buf)
  local root = util.root(buf)
  util.notify("nextflow lint …")
  local cmd = vim.list_extend(util.expand_cmd(config.get().nextflow.cmd), { "lint", "-o", "json", "." })
  util.run_async(cmd, { cwd = root }, function(res)
    local items, summary = M.parse(res.stdout or "", root)
    if not items then
      return util.notify(M.failure_message(res), vim.log.levels.ERROR)
    end
    vim.fn.setqflist({}, " ", { title = "nextflow lint", items = items })
    util.notify(
      ("nextflow lint: %d error(s), %d warning(s)"):format(summary.errors or 0, summary.warnings or 0),
      (summary.errors or 0) > 0 and vim.log.levels.WARN or vim.log.levels.INFO
    )
    if #items > 0 then
      vim.cmd("copen")
    end
  end)
end

return M
