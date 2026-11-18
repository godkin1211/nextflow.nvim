if vim.g.loaded_nextflow then
  return
end
vim.g.loaded_nextflow = true

vim.api.nvim_create_user_command("Nextflow", function(o)
  require("nextflow.commands").dispatch(o.fargs, o.bang)
end, {
  nargs = "*",
  bang = true,
  desc = "Nextflow: run, lint, tasks, resume, test, modules, …",
  complete = function(arglead, cmdline)
    return require("nextflow.commands").complete(arglead, cmdline)
  end,
})
