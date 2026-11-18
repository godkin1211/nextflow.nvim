-- Final-review fix pass: one test per finding, written before the fix.

describe("tasks.failed_task (fix: retried failures)", function()
  local tasks = require("nextflow.tasks")
  local function t(status, name) return { status = status, name = name, exit = "1", workdir = "/w/" .. name } end
  it("skips a failed attempt that was retried successfully and picks the fatal one", function()
    local list = { t("FAILED", "FASTQC (s1)"), t("COMPLETED", "FASTQC (s1)"), t("COMPLETED", "TRIM (s1)"), t("FAILED", "MULTIQC") }
    assert.equals("MULTIQC", tasks.failed_task(list).name)
  end)
  it("still returns a failed task when every failure was retried", function()
    local list = { t("FAILED", "A"), t("COMPLETED", "A") }
    assert.equals("A", tasks.failed_task(list).name)
  end)
  it("returns nil without failures", function()
    assert.is_nil(tasks.failed_task({ t("COMPLETED", "A") }))
  end)
end)

describe("params.attach (fix: yamlls keeps every params file)", function()
  local params = require("nextflow.params")
  local dir = vim.fn.resolve(vim.fn.tempname())
  vim.fn.mkdir(dir, "p")
  vim.fn.writefile(vim.fn.readfile("tests/fixtures/schema_flat.json"), dir .. "/nextflow_schema.json")
  local client = { name = "yamlls", settings = {}, notify = function() end }
  for _, f in ipairs({ "params.yml", "params-test.yml", "params.yml" }) do
    local buf = vim.fn.bufadd(dir .. "/" .. f)
    params.attach(client, buf)
  end
  it("maps the schema to both files, once each", function()
    local schemas = client.settings.yaml.schemas
    local uri = next(schemas)
    assert.same({ dir .. "/params.yml", dir .. "/params-test.yml" }, schemas[uri])
  end)
end)

describe("filetype patterns (review: already anchored by vim.filetype)", function()
  require("nextflow.filetype").setup()
  local proj = vim.fn.resolve(vim.fn.tempname())
  vim.fn.mkdir(proj, "p")
  vim.fn.writefile({}, proj .. "/nextflow.config")
  it("does not match a longer suffix", function()
    assert.is_true(vim.filetype.match({ filename = "/x/foo.nf.testx" }) ~= "groovy")
    assert.is_true(vim.filetype.match({ filename = proj .. "/base.configx" }) ~= "nextflow")
  end)
  it("follows Neovim's backup-suffix rule (foo.nf.test.bak is detected as foo.nf.test)", function()
    assert.equals("groovy", vim.filetype.match({ filename = "/x/foo.nf.test.bak" }))
  end)
end)

describe("ftdetect (fix: does not load the plugin under lazy.nvim)", function()
  it("requires no nextflow.* module", function()
    local orig, seen = require, {}
    _G.require = function(m) if m:match("^nextflow") then seen[#seen + 1] = m end return orig(m) end
    local ok, err = pcall(dofile, "ftdetect/nextflow.lua")
    _G.require = orig
    assert.is_true(ok, err)
    assert.same({}, seen)
    assert.equals("nextflow", vim.filetype.match({ filename = "/x/main.nf" }))
  end)
end)

describe("health.parser_installed (fix: language.add returns nil on 0.11)", function()
  it("is false for a parser that does not exist", function()
    assert.is_false(require("nextflow.health").parser_installed("no_such_lang_xyz"))
  end)
end)

describe("lsp.dag_file (fix: DAG files no longer pile up in /tmp)", function()
  local lsp = require("nextflow.lsp")
  it("is a stable path in the plugin cache dir", function()
    local f = lsp.dag_file("MY WF")
    assert.equals(vim.fn.stdpath("cache") .. "/nextflow.nvim/dag/MY_WF_dag.md", f)
    assert.equals(f, lsp.dag_file("MY WF"))
    assert.truthy(lsp.dag_file(nil):find("/entry_dag.md$"))
  end)
end)

describe("lint.failure_message (fix: show why lint failed)", function()
  local lint = require("nextflow.lint")
  it("falls back to stdout and includes the exit code when stderr is empty", function()
    local msg = lint.failure_message({ code = 1, stdout = "ERROR ~ Unknown option -o", stderr = "" })
    assert.truthy(msg:find("exit 1", 1, true))
    assert.truthy(msg:find("Unknown option -o", 1, true))
  end)
  it("prefers stderr", function()
    assert.truthy(lint.failure_message({ code = 2, stdout = "", stderr = "boom" }):find("boom", 1, true))
  end)
end)
