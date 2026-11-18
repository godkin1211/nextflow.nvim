local config = require("nextflow.config")

describe("config", function()
  it("deep-merges user options over defaults", function()
    config.setup({ keymaps = { lint = false }, nf_core = { cmd = "~/x/nf-core" } })
    local c = config.get()
    assert.equals(false, c.keymaps.lint)
    assert.equals("<localleader>r", c.keymaps.run)
    assert.equals(86400, c.nf_core.cache_ttl)
    assert.equals("~/x/nf-core", c.nf_core.cmd)
    assert.equals("warnings", c.lsp.settings.nextflow.errorReportingMode)
  end)

  it("lets keymaps = false disable all keymaps", function()
    config.setup({ keymaps = false })
    assert.equals(false, config.get().keymaps)
  end)

  it("returns defaults before setup is called", function()
    package.loaded["nextflow.config"] = nil
    local fresh = require("nextflow.config")
    assert.equals("nextflow", fresh.get().nextflow.cmd)
  end)
end)
