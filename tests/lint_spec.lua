local lint = require("nextflow.lint")

local function fixture(name)
  return table.concat(vim.fn.readfile("tests/fixtures/" .. name), "\n")
end

describe("lint.parse", function()
  it("turns errors and warnings into quickfix items", function()
    local items, summary = lint.parse(fixture("lint.json"), "/r")
    assert.equals(3, #items)
    assert.same({ filename = "/r/broken.nf", lnum = 3, col = 1, text = "Unexpected input: '}'", type = "E" }, items[1])
    assert.equals("/r/main.nf", items[2].filename)
    assert.equals(87, items[2].lnum)
    assert.equals("W", items[3].type)
    assert.equals(2, summary.errors)
    assert.equals(1, summary.warnings)
  end)

  it("tolerates log lines before the JSON", function()
    local items = lint.parse("Nextflow 26.10.2 is available\n" .. fixture("lint.json"), "/r")
    assert.equals(3, #items)
  end)

  it("returns nil and a message for non-JSON output", function()
    local items, err = lint.parse("ERROR ~ Unknown command: lint", "/r")
    assert.is_nil(items)
    assert.truthy(err)
  end)
end)
