local M = {}

--- Default map types from upstream LLVM OMPConstants.h.
--- Used as fallback when no cached version is available.
M.defaults = {
  OMP_MAP_TO = 0x001,
  OMP_MAP_FROM = 0x002,
  OMP_MAP_ALWAYS = 0x004,
  OMP_MAP_DELETE = 0x008,
  OMP_MAP_PTR_AND_OBJ = 0x010,
  OMP_MAP_TARGET_PARAM = 0x020,
  OMP_MAP_RETURN_PARAM = 0x040,
  OMP_MAP_PRIVATE = 0x080,
  OMP_MAP_LITERAL = 0x100,
  OMP_MAP_IMPLICIT = 0x200,
  OMP_MAP_CLOSE = 0x400,
  OMP_MAP_PRESENT = 0x1000,
  OMP_MAP_OMPX_HOLD = 0x2000,
  OMP_MAP_ATTACH = 0x4000,
  OMP_MAP_FB_NULLIFY = 0x8000,
  OMP_MAP_NON_CONTIG = 0x100000000000,
}

--- Return the path to the cache file.
--- @return string
local function cache_path()
  return vim.fn.stdpath("data") .. "/omp-maptype-info/maptypes.json"
end

--- Parse the OpenMPOffloadMappingFlags enum from OMPConstants.h content.
--- @param content string raw file content
--- @return table<string, number> map of flag name to value
function M.parse(content)
  local types = {}
  -- Match lines like:  OMP_MAP_TO = 0x01,
  for name, hex in content:gmatch("(OMP_MAP_%w+)%s*=%s*(0x%x+)") do
    -- Skip the MEMBER_OF mask and NONE
    if name ~= "OMP_MAP_MEMBER_OF" and name ~= "OMP_MAP_NONE" then
      local val = tonumber(hex)
      if val then
        types[name] = val
      end
    end
  end
  return types
end

--- Build the fetch command for the header file.
--- Uses `gh api` for authenticated access if available, otherwise falls back to curl.
--- @param source table with repo, branch, path fields
--- @return string[] command, string description (for error messages)
local function build_fetch_cmd(source)
  if vim.fn.executable("gh") == 1 then
    local api_path = string.format(
      "repos/%s/contents/%s?ref=%s",
      source.repo,
      source.path,
      source.branch
    )
    return {
      "gh", "api", api_path, "--jq", ".content",
    }, "gh api " .. source.repo
  end

  local url = string.format(
    "https://raw.githubusercontent.com/%s/%s/%s",
    source.repo,
    source.branch,
    source.path
  )
  return { "curl", "-fsSL", url }, url
end

--- Fetch OMPConstants.h from GitHub and update the cache.
--- @param source table source config (repo, branch, path)
--- @param callback function called with (err, types) when done
function M.sync(source, callback)
  local cmd, desc = build_fetch_cmd(source)
  local uses_gh = cmd[1] == "gh"

  vim.system(
    cmd,
    { text = true },
    vim.schedule_wrap(function(result)
      if result.code ~= 0 then
        callback("Failed to fetch " .. desc .. ": " .. (result.stderr or "unknown error"))
        return
      end

      local content = result.stdout
      -- gh api returns base64-encoded content; decode it
      if uses_gh then
        content = vim.base64.decode(content:gsub("%s+", ""))
      end

      local types = M.parse(content)
      if vim.tbl_isempty(types) then
        callback("Parsed zero map types from " .. desc .. " — header format may have changed")
        return
      end

      -- Write cache
      local dir = vim.fn.fnamemodify(cache_path(), ":h")
      vim.fn.mkdir(dir, "p")
      local json = vim.json.encode(types)
      local f = io.open(cache_path(), "w")
      if f then
        f:write(json)
        f:close()
      end

      callback(nil, types)
    end)
  )
end

--- Load map types from cache, or return defaults if no cache exists.
--- @return table<string, number>
function M.load()
  local f = io.open(cache_path(), "r")
  if f then
    local json = f:read("*a")
    f:close()
    local ok, types = pcall(vim.json.decode, json)
    if ok and not vim.tbl_isempty(types) then
      return types
    end
  end
  return M.defaults
end

return M
