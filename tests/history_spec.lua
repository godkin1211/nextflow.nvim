local history = require("nextflow.history")

describe("history.parse", function()
  local entries = history.parse(table.concat(vim.fn.readfile("tests/fixtures/history"), "\n"))

  it("skips malformed lines and returns newest first", function()
    assert.equals(3, #entries)
    assert.equals("adoring_poitras", entries[1].run_name)
    assert.equals("suspicious_lattes", entries[3].run_name)
  end)

  it("keeps every field", function()
    local e = entries[1]
    assert.equals("2026-10-28 16:00:32", e.date)
    assert.equals("11m 52s", e.duration)
    assert.equals("OK", e.status)
    assert.equals("e5e1cd4c-5353-4caf-8bdf-e7ad3e6bc512", e.session_id)
    assert.equals("nextflow run nf-core/rarevariantburden -r dev -profile test,docker --outdir results", e.command)
  end)

  it("labels an entry with date, name, status, duration and command", function()
    assert.equals(
      "2026-10-28 16:00:32  adoring_poitras  OK  11m 52s  nextflow run nf-core/rarevariantburden -r dev -profile test,docker --outdir results",
      history.label(entries[1])
    )
  end)
end)

describe("history.resume_command", function()
  local function rc(cmd) return history.resume_command({ command = cmd, session_id = "S" }) end

  it("appends -resume <session>", function()
    assert.equals("nextflow run main.nf --x 1 -resume S", rc("nextflow run main.nf --x 1"))
  end)
  it("replaces a bare -resume", function()
    assert.equals("nextflow run main.nf --x 1 -resume S", rc("nextflow run main.nf --x 1 -resume"))
  end)
  it("replaces -resume <uuid> in the middle", function()
    assert.equals(
      "nextflow run main.nf --x 1 -resume S",
      rc("nextflow run main.nf -resume 66820406-49b4-4872-814f-044a096a3f72 --x 1")
    )
  end)
  it("replaces -resume <run name>", function()
    assert.equals("nextflow run main.nf -resume S", rc("nextflow run main.nf -resume happy_mccarthy"))
  end)
  it("does not swallow the script after a leading -resume", function()
    assert.equals("nextflow run main.nf --x 1 -resume S", rc("nextflow run -resume main.nf --x 1"))
  end)
end)

describe("history.read", function()
  it("explains when there is no history", function()
    local entries, err = history.read("/nonexistent")
    assert.is_nil(entries)
    assert.equals("No Nextflow runs found (no .nextflow/history)", err)
    local e2, err2 = history.read(nil)
    assert.is_nil(e2)
    assert.equals(err, err2)
  end)

  it("reads <dir>/.nextflow/history", function()
    local d = vim.fn.tempname()
    vim.fn.mkdir(d .. "/.nextflow", "p")
    vim.fn.writefile(vim.fn.readfile("tests/fixtures/history"), d .. "/.nextflow/history")
    assert.equals(3, #history.read(d))
  end)
end)
