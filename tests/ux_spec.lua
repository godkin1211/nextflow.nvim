local util = require("nextflow.util")

describe("util.scratch (preview buffers)", function()
  it("is read-only and closes with q", function()
    local b = util.scratch({ "a", "b" })
    assert.is_false(vim.bo[b].modifiable)
    assert.equals("wipe", vim.bo[b].bufhidden)
    assert.equals(1, vim.fn.maparg("q", "n", false, true).buffer)
    assert.same({ "a", "b" }, vim.api.nvim_buf_get_lines(b, 0, -1, false))
  end)
end)

describe("keymaps.is_nextflow_buf", function()
  it("ignores non-file buffers such as the config preview", function()
    local b = vim.api.nvim_create_buf(false, true)
    vim.bo[b].filetype = "nextflow"
    assert.is_false(require("nextflow.keymaps").is_nextflow_buf(b))
  end)
end)

describe("config defaults", function()
  it("only sends settings the language server reads", function()
    local s = require("nextflow.config").defaults.lsp.settings.nextflow
    assert.is_nil(s.languageVersion) -- only used by the VS Code extension to pick a server bundle
    assert.is_nil(s.telemetry)
  end)
end)

describe("run.command", function()
  local run = require("nextflow.run")
  it("trims the arguments", function()
    assert.equals("nextflow run .", run.command("nextflow", "  "))
    assert.equals("nextflow run . -resume -profile test", run.command("nextflow", " -resume -profile test "))
  end)
end)
