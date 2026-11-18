-- Load filetype.lua by path, not require(): under lazy.nvim, require()-ing a module of a
-- lazy plugin loads the whole plugin at startup and defeats ft/cmd lazy-loading.
local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
dofile(vim.fs.joinpath(vim.fs.dirname(here), "lua", "nextflow", "filetype.lua")).setup()

-- Params files (params*.yml|yaml|json) can be opened before any .nf file has loaded the
-- plugin; hand them to nextflow.params when yamlls/jsonls attaches (loads the plugin then).
vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("nextflow_params_bootstrap", { clear = true }),
  callback = function(ev)
    local base = vim.fs.basename(vim.api.nvim_buf_get_name(ev.buf))
    if not (base:match("^params.*%.ya?ml$") or base:match("^params.*%.json$")) then
      return
    end
    local params = require("nextflow.params")
    local client = vim.lsp.get_client_by_id(ev.data.client_id)
    if client then
      params.attach(client, ev.buf)
    end
  end,
})
