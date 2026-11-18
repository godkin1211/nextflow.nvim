local commands = require("nextflow.commands")

describe("commands", function()
  it("completes top-level subcommands", function()
    local all = commands.complete("", "Nextflow ")
    assert.truthy(vim.tbl_contains(all, "lint"))
    assert.truthy(vim.tbl_contains(all, "run"))
  end)

  it("filters top-level completion by prefix", function()
    local r = commands.complete("re", "Nextflow re")
    assert.truthy(vim.tbl_contains(r, "rerun"))
    assert.is_false(vim.tbl_contains(r, "lint"))
  end)

  it("dispatches registered subcommands with args and bang", function()
    local got
    commands.register("zz_probe", {
      run = function(args, bang) got = { args = args, bang = bang } end,
      complete = function() return { "alpha", "beta" } end,
    })
    commands.dispatch({ "zz_probe", "x", "y" }, true)
    assert.same({ args = { "x", "y" }, bang = true }, got)
    assert.same({ "beta" }, commands.complete("b", "Nextflow zz_probe b"))
  end)

  it("notifies on unknown subcommands", function()
    local msg
    local orig = vim.notify
    vim.notify = function(m) msg = m end
    commands.dispatch({ "nope" }, false)
    vim.notify = orig
    assert.truthy(msg and msg:match("nope"))
  end)
end)
