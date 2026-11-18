---@mod nextflow.filetype Filetype detection (independent of setup/lazy-loading)
local M = {}

local done = false

function M.setup()
  if done then
    return
  end
  done = true
  vim.filetype.add({
    extension = { nf = "nextflow" },
    filename = {
      ["nextflow.config"] = "nextflow",
      ["nf-test.config"] = "groovy",
    },
    pattern = {
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
