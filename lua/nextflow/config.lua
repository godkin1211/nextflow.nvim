---@mod nextflow.config Defaults and user options
local M = {}

M.defaults = {
  lsp = {
    enable = true,
    cmd = nil, -- string[]; nil = auto-detect (PATH → ~/.nextflow/lsp native → jar → Mason)
    settings = {
      nextflow = {
        errorReportingMode = "warnings", -- off | errors | warnings | paranoid
        completion = { extended = true, maxItems = 100 },
        formatting = { harshilAlignment = false, maheshForm = false, sortDeclarations = false },
        files = { exclude = { ".git", ".lineage", ".nextflow", ".nf-test", ".pixi", ".venv", "work" } },
      },
    },
  },
  -- set the whole table, or any single entry, to false to disable
  keymaps = {
    run = "<localleader>r",
    rerun = "<localleader>R",
    resume = "<localleader>s",
    lint = "<localleader>l",
    format = "<localleader>f",
    dag = "<localleader>d",
    failed = "<localleader>e",
    tasks = "<localleader>k",
    test_file = "<localleader>t",
    test_nearest = "<localleader>n",
    test_all = "<localleader>T",
    test_update = "<localleader>u",
    alt = "<localleader>a",
    param = "<localleader>p",
    modules = "<localleader>m",
  },
  terminal = { height = 0.35 },
  run = { default_args = "-resume" },
  nextflow = { cmd = "nextflow" },
  nf_test = { cmd = "nf-test" },
  nf_core = { cmd = "nf-core", cache_ttl = 86400 },
  dag = {
    open_preview = true, -- open the metro map in the browser / run :MarkdownPreview
    renderer = "metro", -- "metro" (nf-metro, falls back to mermaid) | "mermaid"
    metro = { cmd = "nf-metro", theme = "nfcore", format = "html" }, -- format: html | svg
  },
}

local current

---@param opts? table
function M.setup(opts)
  opts = opts or {}
  local merged = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)
  if opts.keymaps == false then
    merged.keymaps = false
  end
  current = merged
end

---@return table
function M.get()
  if not current then
    M.setup({})
  end
  return current
end

return M
