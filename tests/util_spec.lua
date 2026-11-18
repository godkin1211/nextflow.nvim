local util = require("nextflow.util")

describe("util.expand_cmd", function()
  it("expands ~ and splits a string on spaces", function()
    assert.same({ vim.fn.expand("~/a/nf-core"), "modules" }, util.expand_cmd("~/a/nf-core modules"))
  end)
  it("expands ~ in each element of a list", function()
    assert.same({ vim.fn.expand("~/b"), "x" }, util.expand_cmd({ "~/b", "x" }))
  end)
end)

describe("util.launch_dir", function()
  local old_cwd
  before_each(function() old_cwd = vim.fn.getcwd() end)
  after_each(function() vim.cmd.cd(old_cwd) end)

  it("returns the cwd when it contains .nextflow/history", function()
    local d = vim.fn.resolve(vim.fn.tempname())
    vim.fn.mkdir(d .. "/.nextflow", "p")
    vim.fn.writefile({}, d .. "/.nextflow/history")
    vim.cmd.cd(d)
    assert.equals(d, util.launch_dir(0))
  end)

  it("returns nil when no history exists", function()
    local d = vim.fn.resolve(vim.fn.tempname())
    vim.fn.mkdir(d, "p")
    vim.cmd.cd(d)
    vim.cmd("enew")
    assert.is_nil(util.launch_dir(0))
  end)
end)

describe("util.run_async", function()
  it("does not call back when the tool is missing", function()
    local called = false
    util.run_async({ "definitely-not-a-tool-xyz" }, {}, function() called = true end)
    vim.wait(200)
    assert.is_false(called)
  end)

  it("calls back with the completed result", function()
    local res
    util.run_async({ "echo", "hi" }, {}, function(r) res = r end)
    vim.wait(3000, function() return res ~= nil end)
    assert.equals("hi\n", res.stdout)
  end)
end)
