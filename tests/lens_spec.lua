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
