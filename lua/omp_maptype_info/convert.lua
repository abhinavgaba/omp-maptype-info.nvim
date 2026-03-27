local ffi = require "ffi"

ffi.cdef [[
  const char* getAsHex(const char*);
  const char* getAsDec(const char*);
]]

local lib

local M = {}

--- Load the compiled C shared library from the plugin directory.
function M.load()
  if lib then
    return
  end
  local source = debug.getinfo(1, "S").source:sub(2)
  local plugin_root = vim.fn.fnamemodify(source, ":h:h:h")
  local ext = vim.fn.has("win32") == 1 and "dll" or "so"
  local so_path = plugin_root .. "/c_utils." .. ext
  lib = ffi.load(so_path)
end

--- Convert a string to its hex representation.
--- @param str string
--- @return string
function M.to_hex(str)
  M.load()
  return ffi.string(lib.getAsHex(str))
end

--- Convert a string to its decimal representation.
--- @param str string
--- @return string
function M.to_dec(str)
  M.load()
  return ffi.string(lib.getAsDec(str))
end

return M
