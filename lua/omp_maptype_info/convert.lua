local ffi = require "ffi"

ffi.cdef [[
  unsigned long long strtoull(const char *str, char **endptr, int base);
  int sprintf(char *str, const char *format, ...);
]]

local buf = ffi.new("char[100]")

local M = {}

--- Convert a string (decimal or hex) to its hex representation.
--- @param str string
--- @return string
function M.to_hex(str)
  local val = ffi.C.strtoull(str, nil, 0)
  ffi.C.sprintf(buf, "0x%016llx", val)
  return ffi.string(buf)
end

--- Convert a string (decimal or hex) to its decimal representation.
--- @param str string
--- @return string
function M.to_dec(str)
  local val = ffi.C.strtoull(str, nil, 0)
  ffi.C.sprintf(buf, "%llu", val)
  return ffi.string(buf)
end

return M
