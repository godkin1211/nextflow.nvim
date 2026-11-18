---@mod nextflow.filetype Filetype detection (independent of setup/lazy-loading)
local M = {}

function M.setup()
  if vim.g.nextflow_filetypes_added then
    return
  end
  vim.g.nextflow_filetypes_added = true
  vim.filetype.add({
    extension = { nf = "nextflow" },
    filename = {
      ["nextflow.config"] = "nextflow",
      ["nf-test.config"] = "groovy",
    },
    pattern = {
      -- (vim.filetype anchors user patterns as ^...$ itself; do not add $)
      -- nf-test specs are a Groovy DSL, not Nextflow scripts
      [".*%.nf%.test"] = "groovy",
      -- any *.config inside a Nextflow project (conf/base.config, conf/modules.config, …)
      [".*%.config"] = {
        function(path)
          if vim.fs.root(path, "nextflow.config") then
            return "nextflow"
          end
        end,
        { priority = -math.huge },
      },
    },
  })
  vim.treesitter.language.register("groovy", "nextflow")
end

return M
