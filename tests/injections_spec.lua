-- Language injections for process bodies (queries/groovy/injections.scm)
local src = {
  "process A {",                      -- 0
  "    script:",                      -- 1
  '    """',                          -- 2
  "    fastqc ${reads} -t $task.cpus", -- 3
  '    """',                          -- 4
  "}",                                -- 5
  "process B {",                      -- 6
  "    script:",                      -- 7
  '    """',                          -- 8
  "    #!/usr/bin/env python",        -- 9
  "    print(1)",                     -- 10
  '    """',                          -- 11
  "}",                                -- 12
  "process C {",                      -- 13
  "    shell:",                       -- 14
  "    '''",                          -- 15
  "    #!/usr/bin/env Rscript",       -- 16
  "    x <- 1",                       -- 17
  "    '''",                          -- 18
  "}",                                -- 19
  'def s = """',                      -- 20
  "    not shell",                    -- 21
  '"""',                              -- 22
}

local function lang_at(buf, row, col)
  local parser = vim.treesitter.get_parser(buf, "groovy")
  parser:parse(true)
  return parser:language_for_range({ row, col, row, col }):lang()
end

describe("process body injections", function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, src)
  it("highlights script: blocks as bash", function()
    assert.equals("bash", lang_at(buf, 3, 6))
  end)
  it("keeps ${...} interpolations in groovy", function()
    assert.equals("groovy", lang_at(buf, 3, 14))
  end)
  it("follows a python shebang", function()
    assert.equals("python", lang_at(buf, 10, 6))
  end)
  it("follows an Rscript shebang in shell: blocks", function()
    assert.equals("r", lang_at(buf, 17, 6))
  end)
  it("leaves other strings alone", function()
    assert.equals("groovy", lang_at(buf, 21, 6))
  end)
end)
