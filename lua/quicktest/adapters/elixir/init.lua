local Job = require("plenary.job")
local fs = require("quicktest.fs_utils")
local query = require("quicktest.adapters.elixir.query")
local ts = require("quicktest.ts")

local M = {
  name = "elixir",
}

---@class ElixirRunParams
---@field func_names string[]
---@field file string?
---@field cwd string
---@field pos number
---@field mode 'all' | 'dir' | 'file' | 'line'

--- @param bufnr integer
--- @return string | nil
local function find_cwd(bufnr)
  local buffer_name = vim.api.nvim_buf_get_name(bufnr) -- Get the current buffer's file path
  local path = vim.fn.fnamemodify(buffer_name, ":p:h") -- Get the full path of the directory containing the file

  return fs.find_ancestor_of_file(path, "mix.exs")
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return ElixirRunParams | nil, string | nil
M.build_line_run_params = function(bufnr, cursor_pos)
  local file = vim.api.nvim_buf_get_name(bufnr) -- Get the current buffer's file path
  local cwd = find_cwd(bufnr) or vim.fn.getcwd()

  local test_pos = ts.get_current_test_range(query, bufnr, cursor_pos, "test")
  local ns_pos = ts.get_current_test_range(query, bufnr, cursor_pos, "namespace")

  local pos = nil

  if test_pos then
    pos = test_pos[1] + 1
  elseif ns_pos then
    pos = ns_pos[1] + 1
  end

  return {
    func_names = {},
    file = file,
    mode = "line",
    pos = pos,
    cwd = cwd,
  }, nil
end

---@param bufnr integer
---@return ElixirRunParams | nil, string | nil
M.build_file_run_params = function(bufnr)
  local file = vim.api.nvim_buf_get_name(bufnr) -- Get the current buffer's file path
  local cwd = find_cwd(bufnr) or vim.fn.getcwd()

  return {
    func_names = {},
    file = file,
    mode = "file",
    cwd = cwd,
  }, nil
end

---@param bufnr integer
---@param cursor_pos integer[]
---@return ElixirRunParams | nil, string | nil
M.build_all_run_params = function(bufnr, cursor_pos)
  local cwd = find_cwd(bufnr) or vim.fn.getcwd()

  return {
    func_names = {},
    cwd = cwd,
    mode = "all",
  }, nil
end

--- Executes the test with the given parameters.
---@param params ElixirRunParams
---@param send fun(data: any)
---@return integer
M.run = function(params, send)
  local args = {
    "test",
    "--color",
  }

  if params.file then
    local f = params.file

    if params.pos then
      f = f .. ":" .. params.pos
    end

    table.insert(args, f)
  end

  local job = Job:new({
    command = "mix",
    args = args, -- Modify based on how your test command needs to be structured
    cwd = params.cwd,
    on_stdout = function(_, data)
      for k, v in pairs(vim.split(data, "\n")) do
        send({ type = "stdout", output = v })
      end
    end,
    on_stderr = function(_, data)
      for k, v in pairs(vim.split(data, "\n")) do
        send({ type = "stderr", output = v })
      end
    end,
    on_exit = function(_, return_val)
      send({ type = "exit", code = return_val })
    end,
  })

  job:start()

  return job.pid
end

---@param bufnr integer
---@return boolean
M.is_enabled = function(bufnr)
  local file_path = vim.api.nvim_buf_get_name(bufnr)

  return vim.endswith(file_path, "test.exs")
end

M.title = function(params)
  if params.mode == "file" then
    return "Running test: " .. fs.extract_filename(params.cwd, params.file)
  elseif params.mode == "all" then
    return "Running all tests"
  elseif params.mode == "line" then
    return "Running test: " .. fs.extract_filename(params.cwd, params.file) .. ":" .. params.pos
  end

  return "Running tests"
end

return M
