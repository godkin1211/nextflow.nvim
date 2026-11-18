local config = require("nextflow.config")
local metro = require("nextflow.metro")

local function stub(body)
  local file = vim.fn.tempname() .. "-nf-metro"
  vim.fn.writefile({ "#!/bin/sh", body }, file)
  vim.fn.setfperm(file, "rwxr-xr-x")
  return file
end

describe("metro", function()
  after_each(function()
    for _, ext in ipairs({ "html", "mmd" }) do
      os.remove(metro.output_file("wf"):gsub("%.%w+$", "." .. ext))
    end
    config.setup({})
  end)

  it("builds the nf-metro render command from the config", function()
    config.setup({ dag = { metro = { cmd = "~/bin/nf-metro", theme = "seqera" } } })
    assert.same({
      vim.fn.expand("~/bin/nf-metro"), "render", "/c/x.mmd", "--from-nextflow",
      "--theme", "seqera", "--title", "my wf", "-o", "/c/x.html",
    }, metro.render_cmd("/c/x.mmd", "/c/x.html", "my wf"))
  end)

  it("names the output after the workflow and the format", function()
    config.setup({ dag = { metro = { format = "svg" } } })
    assert.truthy(metro.output_file(nil):match("/nextflow%.nvim/dag/entry_metro%.svg$"))
    assert.truthy(metro.output_file("QC:SUB"):match("/QC_SUB_metro%.svg$"))
  end)

  it("is used only when renderer is metro and nf-metro is executable", function()
    config.setup({ dag = { renderer = "metro", metro = { cmd = "definitely-not-nf-metro" } } })
    assert.is_false(metro.enabled())
    config.setup({ dag = { renderer = "metro", metro = { cmd = stub("exit 0") } } })
    assert.is_true(metro.enabled())
    config.setup({ dag = { renderer = "mermaid", metro = { cmd = stub("exit 0") } } })
    assert.is_false(metro.enabled())
  end)

  it("writes the mermaid source and returns the rendered file", function()
    -- the stub writes its -o argument ($9) like nf-metro does
    config.setup({ dag = { metro = { cmd = stub('echo "$1 $3" > "$9"') } } })
    local done
    metro.render("flowchart TB\n  v0([A])", "wf", "Title", function(ok, res)
      done = { ok, res }
    end)
    vim.wait(5000, function() return done ~= nil end)
    assert.is_true(done[1])
    assert.equals(metro.output_file("wf"), done[2])
    assert.equals("render --from-nextflow", vim.fn.readfile(done[2])[1])
    assert.same({ "flowchart TB", "  v0([A])" }, vim.fn.readfile((done[2]:gsub("%.html$", ".mmd"))))
  end)

  it("reports nf-metro's error when rendering fails", function()
    config.setup({ dag = { metro = { cmd = stub('echo "Error: the map defines no stations" >&2; exit 1') } } })
    local done
    metro.render("flowchart TB", "wf", "Title", function(ok, res)
      done = { ok, res }
    end)
    vim.wait(5000, function() return done ~= nil end)
    assert.is_false(done[1])
    assert.equals("Error: the map defines no stations", done[2])
  end)

  it("diagnoses the broken drawsvg 2.5.0 import", function()
    local hint = metro.diagnose("NameError: name 'SyncedAnimationConfig' is not defined")
    assert.truthy(hint:find('drawsvg<2.5', 1, true))
    assert.is_nil(metro.diagnose("Error: something else"))
  end)
end)

describe(":Nextflow dag mermaid", function()
  it("forces the mermaid renderer for one run", function()
    local lsp = require("nextflow.lsp")
    local orig = lsp.run_lens
    local seen
    lsp.run_lens = function()
      seen = lsp.renderer_override
    end
    require("nextflow.commands").dispatch({ "dag", "mermaid" }, false)
    lsp.run_lens = orig
    assert.equals("mermaid", seen)
  end)
end)

describe("health.metro_status", function()
  local health = require("nextflow.health")
  after_each(function()
    config.setup({})
  end)
  it("reports the version when nf-metro runs", function()
    config.setup({ dag = { metro = { cmd = stub('echo "nf-metro, version 2.1.0"') } } })
    assert.same({ "ok", "nf-metro 2.1.0 (DAG previews are metro maps)" }, { health.metro_status() })
  end)
  it("explains the drawsvg breakage", function()
    config.setup({ dag = { metro = { cmd = stub("echo \"NameError: name 'SyncedAnimationConfig' is not defined\" >&2; exit 1") } } })
    local level, msg = health.metro_status()
    assert.equals("error", level)
    assert.truthy(msg:find("drawsvg<2.5", 1, true))
  end)
  it("falls back to mermaid when nf-metro is missing or disabled", function()
    config.setup({ dag = { metro = { cmd = "definitely-not-nf-metro" } } })
    local level, msg = health.metro_status()
    assert.equals("info", level)
    assert.truthy(msg:find("uv tool install nf-metro", 1, true))
    config.setup({ dag = { renderer = "mermaid" } })
    assert.equals("info", (health.metro_status()))
  end)
end)
