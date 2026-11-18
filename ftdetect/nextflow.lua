-- Load filetype.lua by path, not require(): under lazy.nvim, require()-ing a module of a
-- lazy plugin loads the whole plugin at startup and defeats ft/cmd lazy-loading.
local here = vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))
dofile(vim.fs.joinpath(vim.fs.dirname(here), "lua", "nextflow", "filetype.lua")).setup()
