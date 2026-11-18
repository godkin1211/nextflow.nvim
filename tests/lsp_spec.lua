local lsp = require("nextflow.lsp")

local function touch_exec(path)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile({ "#!/bin/sh" }, path)
  vim.uv.fs_chmod(path, tonumber("755", 8))
end

describe("lsp.resolve_cmd", function()
  local old_path
  before_each(function()
    old_path = vim.env.PATH
    -- hermetic PATH: a fake java only, no nextflow-lsp
    local bin = vim.fn.tempname()
    touch_exec(bin .. "/java")
    vim.env.PATH = bin .. ":/bin"
  end)
  after_each(function() vim.env.PATH = old_path end)

  it("prefers the newest native bundle", function()
    local d = vim.fn.tempname()
    touch_exec(d .. "/v26.04/nextflow-language-server-26.04.2-macos-arm64/bin/nextflow-lsp")
    touch_exec(d .. "/v26.10/nextflow-language-server-26.10.2-macos-arm64/bin/nextflow-lsp")
    local cmd = lsp.resolve_cmd({ cache_dir = d })
    assert.equals(1, #cmd)
    assert.truthy(cmd[1]:match("26%.10%.2%-macos%-arm64/bin/nextflow%-lsp$"))
  end)

  it("falls back to the newest jar via java", function()
    local d = vim.fn.tempname()
    vim.fn.mkdir(d .. "/v26.04", "p")
    vim.fn.writefile({}, d .. "/v26.04/v26.04.1.jar")
    vim.fn.writefile({}, d .. "/v26.04/v26.04.2.jar")
    local cmd = lsp.resolve_cmd({ cache_dir = d })
    assert.equals("java", cmd[1])
    assert.equals("-jar", cmd[2])
    assert.truthy(cmd[3]:match("v26%.04%.2%.jar$"))
  end)

  it("prefers nextflow-lsp on PATH", function()
    local bin = vim.fn.tempname()
    touch_exec(bin .. "/nextflow-lsp")
    vim.env.PATH = bin .. ":" .. vim.env.PATH
    assert.same({ "nextflow-lsp" }, lsp.resolve_cmd({ cache_dir = vim.fn.tempname() }))
  end)
end)

describe("lsp.dag_markdown", function()
  it("wraps mermaid in a titled markdown block", function()
    assert.same(
      { "# DAG: <entry>", "", "```mermaid", "flowchart TB", "  a", "```" },
      lsp.dag_markdown(nil, "flowchart TB\n  a")
    )
  end)
  it("uses the workflow name as title", function()
    assert.equals("# DAG: ALIGN", lsp.dag_markdown("ALIGN", "x")[1])
  end)
end)
