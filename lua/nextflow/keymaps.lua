---@mod nextflow.keymaps Buffer-local <localleader> maps
local config = require("nextflow.config")

local M = {}

-- keymap option name → :Nextflow arguments
local actions = {
  run = { "run" },
  rerun = { "rerun" },
  resume = { "resume" },
  lint = { "lint" },
  format = { "format" },
  dag = { "dag" },
  failed = { "failed" },
  tasks = { "tasks" },
  test_file = { "test", "file" },
  test_nearest = { "test", "nearest" },
  test_all = { "test", "all" },
  test_update = { "test", "update" },
  alt = { "alt" },
  param = { "param" },
  modules = { "modules" },
}

---@param buf integer
---@return boolean
function M.is_nextflow_buf(buf)
  if vim.bo[buf].buftype ~= "" then
    return false -- previews and other scratch buffers are not pipeline files
  end
  local ft = vim.bo[buf].filetype
  return ft == "nextflow" or (ft == "groovy" and vim.api.nvim_buf_get_name(buf):match("%.nf%.test$") ~= nil)
end

---@param buf integer
function M.attach(buf)
  if not M.is_nextflow_buf(buf) then
    return
  end
  vim.bo[buf].commentstring = "// %s"
  local maps = config.get().keymaps
  if not maps then
    return
  end
  if package.loaded["which-key"] then
    pcall(function()
      require("which-key").add({ { "<localleader>", group = "nextflow", buffer = buf } })
    end)
  end
  for key, args in pairs(actions) do
    local lhs = maps[key]
    if lhs then
      vim.keymap.set("n", lhs, function()
        require("nextflow.commands").dispatch(args, false)
      end, { buffer = buf, desc = "Nextflow: " .. table.concat(args, " ") })
    end
  end
end

function M.setup()
  local group = vim.api.nvim_create_augroup("nextflow_keymaps", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "nextflow", "groovy" },
    callback = function(ev)
      M.attach(ev.buf)
    end,
  })
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      M.attach(buf)
    end
  end
end

return M
