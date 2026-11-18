local config = require("nextflow.config")

describe("commands with spaces in the path (list form)", function()
  after_each(function() config.setup({}) end)
  it("util.shell_join quotes every part", function()
    assert.equals("'/opt/My Tools/nextflow' run", require("nextflow.util").shell_join({ "/opt/My Tools/nextflow", "run" }))
  end)
  it("run uses the quoted nextflow command", function()
    config.setup({ nextflow = { cmd = { "/opt/My Tools/nextflow" } } })
    assert.equals("'/opt/My Tools/nextflow'", require("nextflow.run").nextflow_cmd())
  end)
  it("resume swaps the history's literal 'nextflow' for the configured command", function()
    local h = require("nextflow.history")
    assert.equals("'/opt/nf' run . -profile test -resume S",
      h.resume_command({ command = "nextflow run . -profile test", session_id = "S" }, "'/opt/nf'"))
    assert.equals("nextflow run . -resume S", h.resume_command({ command = "nextflow run .", session_id = "S" }))
  end)
end)

describe("terminal buffers", function()
  local terminal = require("nextflow.terminal")
  local cwd = vim.fn.getcwd()
  local function last_term() return vim.api.nvim_get_current_buf() end
  it("wipes finished, hidden terminals when a new one opens; keeps running ones", function()
    terminal.open("true", cwd)
    local done = last_term()
    vim.fn.jobwait({ vim.bo[done].channel }, 5000)
    vim.cmd("close")
    terminal.open("sleep 30", cwd)
    local running = last_term()
    vim.cmd("close")
    terminal.open("true", cwd)
    assert.is_false(vim.api.nvim_buf_is_valid(done))
    assert.is_true(vim.api.nvim_buf_is_valid(running))
    vim.fn.jobstop(vim.bo[running].channel)
  end)
end)

describe("nftest.enclosing_test", function()
  it("ignores braces in // comments", function()
    local lines = {
      'test("a") {',
      "  when { process { } } // }",
      "  then { assert true }",
      "}",
    }
    assert.equals("a", (require("nextflow.nftest").enclosing_test(lines, 3)))
  end)
end)

describe("ftdetect params bootstrap", function()
  it("loads nextflow.params on LspAttach only for params files", function()
    local seen, orig = {}, require
    _G.require = function(m) seen[m] = true return orig(m) end
    dofile("ftdetect/nextflow.lua")
    _G.require = orig
    assert.is_nil(seen["nextflow.params"])
    local function attach(name)
      seen = {}
      local b = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(b, vim.fn.tempname() .. "/" .. name)
      _G.require = function(m) seen[m] = true return orig(m) end
      pcall(vim.api.nvim_exec_autocmds, "LspAttach", { buffer = b, data = { client_id = 99999 } })
      _G.require = orig
      return seen["nextflow.params"] == true
    end
    assert.is_false(attach("docker-compose.yml"))
    assert.is_true(attach("params-test.yml"))
  end)
end)
