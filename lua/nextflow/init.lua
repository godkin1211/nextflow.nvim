---@mod nextflow Nextflow support for Neovim
local M = {}

---@param opts? table
function M.setup(opts)
  require("nextflow.config").setup(opts)
  require("nextflow.filetype").setup()
  require("nextflow.lsp").setup()
  require("nextflow.keymaps").setup()
  require("nextflow.params").setup()
end

return M
