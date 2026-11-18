---@mod nextflow.metro Render the DAG as a metro map with nf-metro
local config = require("nextflow.config")
local util = require("nextflow.util")

local M = {}

local function opts()
  return config.get().dag.metro
end

---@return boolean
function M.enabled()
  return config.get().dag.renderer == "metro" and vim.fn.executable(util.expand_cmd(opts().cmd)[1]) == 1
end

---@param name? string workflow name; nil = entry workflow
---@return string
function M.output_file(name)
  return ("%s/nextflow.nvim/dag/%s_metro.%s"):format(
    vim.fn.stdpath("cache"),
    (name or "entry"):gsub("[^%w_]", "_"),
    opts().format
  )
end

---@param mmd string
---@param out string
---@param title string
---@return string[]
function M.render_cmd(mmd, out, title)
  return vim.list_extend(util.expand_cmd(opts().cmd), {
    "render", mmd, "--from-nextflow", "--theme", opts().theme, "--title", title, "-o", out,
  })
end

---Write the server's Mermaid DAG next to the output and render it with nf-metro.
---@param mermaid string
---@param name? string
---@param title string
---@param cb fun(ok: boolean, result: string) result: the rendered file, or nf-metro's error
function M.render(mermaid, name, title, cb)
  local out = M.output_file(name)
  local mmd = out:gsub("%.%w+$", ".mmd")
  vim.fn.mkdir(vim.fs.dirname(out), "p")
  vim.fn.writefile(vim.split(mermaid, "\n"), mmd)
  vim.system(M.render_cmd(mmd, out, title), { text = true }, vim.schedule_wrap(function(res)
    if res.code == 0 then
      return cb(true, out)
    end
    local err = vim.trim((res.stderr or "") ~= "" and res.stderr or (res.stdout or ""))
    cb(false, err ~= "" and err or ("nf-metro exited with " .. res.code))
  end))
end

---Advice for a known nf-metro install problem in its error output.
---@param err string
---@return string|nil
function M.diagnose(err)
  if err:find("SyncedAnimationConfig", 1, true) then
    return 'drawsvg 2.5.0 breaks nf-metro; reinstall with: uv tool install nf-metro --with "drawsvg<2.5"'
  end
end

return M
