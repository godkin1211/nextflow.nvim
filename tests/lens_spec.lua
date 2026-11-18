local lsp = require("nextflow.lsp")

local function lens(s, e, title)
  return { range = { start = { line = s, character = 0 }, ["end"] = { line = e, character = 1 } }, command = { title = title, command = "x" } }
end

describe("lsp.lens_candidates", function()
  local main = lens(28, 95, "Preview DAG")
  local sub = lens(40, 50, "Preview DAG (SUB)")
  local other = lens(100, 120, "Preview DAG (OTHER)")
  it("picks the lens whose range holds the cursor, not only its first line", function()
    assert.same({ main }, lsp.lens_candidates({ main, other }, 60))
  end)
  it("prefers the innermost lens", function()
    assert.same({ sub }, lsp.lens_candidates({ main, sub }, 45))
  end)
  it("offers every lens when the cursor is outside all of them", function()
    assert.same({ main, other }, lsp.lens_candidates({ main, other }, 0))
  end)
  it("skips lenses without a command", function()
    assert.same({}, lsp.lens_candidates({ { range = main.range } }, 60))
  end)
end)

describe("lsp.dag_error_message", function()
  local E = vim.diagnostic.severity.ERROR
  it("names the errors that block the DAG", function()
    local msg = lsp.dag_error_message({
      { lnum = 86, col = 13, severity = E, message = "Closure with signature (?, ?) -> ? is not compatible\nwith expected" },
      { lnum = 9, col = 0, severity = E, message = "`foo` is not defined" },
    })
    assert.truthy(msg:find("2 errors", 1, true))
    assert.truthy(msg:find("line 10: `foo` is not defined", 1, true))
    assert.truthy(msg:find("line 87: Closure with signature (?, ?) -> ? is not compatible", 1, true))
    assert.is_nil(msg:find("with expected", 1, true)) -- first line of each message only
    assert.is_true(msg:find("line 10", 1, true) < msg:find("line 87", 1, true))
  end)
  it("caps the list", function()
    local d = {}
    for i = 1, 7 do d[i] = { lnum = i, col = 0, severity = E, message = "e" .. i } end
    local msg = lsp.dag_error_message(d)
    assert.truthy(msg:find("7 errors", 1, true))
    assert.truthy(msg:find("… 4 more", 1, true))
  end)
  it("points to lint when no error is shown in the buffer", function()
    assert.truthy(lsp.dag_error_message({}):find(":Nextflow lint", 1, true))
  end)
end)
