local convert = require "omp_maptype_info.convert"
local maptypes = require "omp_maptype_info.maptypes"

local M = {}

M.config = {
  keymaps = {
    hex = "<leader>oh",
    dec = "<leader>od",
    maptype = "<leader>om",
    cheatsheet = "<leader>oc",
  },
  -- "hex", "dec", or "both"
  member_of_format = "both",
  source = {
    repo = "llvm/llvm-project",
    branch = "main",
    path = "llvm/include/llvm/Frontend/OpenMP/OMPConstants.h",
  },
}

-- Active map types (loaded from cache or defaults)
local map_types = nil

local function get_map_types()
  if not map_types then
    map_types = maptypes.load()
  end
  return map_types
end

--- Strip the OMP_MAP_ prefix for display.
--- @param name string
--- @return string
local function display_name(name)
  return name:gsub("^OMP_MAP_", "")
end

--- Show a popup at the cursor with the given title and body lines.
--- @param title string
--- @param body table
local function show_popup(title, body)
  local NuiPopup = require "nui.popup"
  local popup_height = vim.fn.max { #body, 1 }
  local popup_width = string.len(title) + 2
  for _, str in pairs(body) do
    popup_width = vim.fn.max { popup_width, string.len(str) }
  end

  local popup = NuiPopup {
    enter = false,
    focusable = false,
    border = {
      style = "rounded",
      text = { top = title },
    },
    buf_options = {
      modifiable = true,
      readonly = false,
    },
    win_options = {
      winblend = 10,
      winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
    },
    relative = "cursor",
    position = "2",
    size = {
      width = popup_width,
      height = popup_height,
    },
  }

  popup:mount()
  vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, body)

  vim.api.nvim_create_autocmd({ "CursorMoved" }, {
    desc = "Close OMP MapType popup",
    callback = function()
      if popup and popup.winid then
        vim.api.nvim_win_close(popup.winid, true)
      end
      popup:unmount()
    end,
    once = true,
  })
end

--- Get the word under the cursor, converted to hex.
--- @return string hex string, or empty string on failure
local function get_cword_hex()
  local word = vim.fn.expand "<cword>"
  if word == "" then
    vim.notify("No word under the cursor", vim.log.levels.WARN)
    return ""
  end
  return convert.to_hex(word)
end

--- Display the word under the cursor in hex.
function M.show_hex()
  local hex = get_cword_hex()
  if hex ~= "" then
    show_popup("In Hex", { hex })
  end
end

--- Display the word under the cursor in decimal.
function M.show_dec()
  local word = vim.fn.expand "<cword>"
  if word == "" then
    vim.notify("No word under the cursor", vim.log.levels.WARN)
    return
  end
  show_popup("In Dec", { convert.to_dec(word) })
end

--- Decode the word under the cursor as an OpenMP map-type bitmask.
function M.show_maptype()
  local hex = get_cword_hex()
  if hex == "" then
    return
  end
  -- hex is already "0x%016x" formatted from the C library

  -- Split off the MEMBER_OF field (top 16 bits) to avoid 64-bit arithmetic issues
  local member_of_bits = string.sub(hex, 1, 6)
  local flag_bits = "0x" .. string.sub(hex, 7)
  local flags_int = tonumber(flag_bits, 10)

  local lines = {}
  if member_of_bits ~= "0x0000" then
    local member_dec = tonumber(member_of_bits)
    local fmt = M.config.member_of_format
    local member_str
    if fmt == "dec" then
      member_str = string.format("%d", member_dec)
    elseif fmt == "hex" then
      member_str = member_of_bits
    else -- "both"
      member_str = string.format("%d = %s", member_dec, member_of_bits)
    end
    local member_hex = string.format("%s000000000000", member_of_bits)
    table.insert(lines, string.format("%18s = MEMBER_OF(%s)", member_hex, member_str))
  end

  local types = get_map_types()
  for name, val in pairs(types) do
    if flags_int == 0 then
      break
    end
    local band = vim.fn["and"](flags_int, val)
    if band ~= 0 then
      table.insert(lines, string.format("%18s = %s", string.format("0x%x", val), display_name(name)))
      flags_int = vim.fn["and"](flags_int, vim.fn.invert(val))
    end
  end

  if flags_int ~= 0 then
    table.insert(lines, string.format("%18s = UNKNOWN", string.format("0x%x", flags_int)))
  end

  show_popup("MAP_TYPE:" .. hex, lines)
end

--- Show a cheat-sheet of all known map-type flags with hex and decimal values.
function M.show_cheatsheet()
  local types = get_map_types()

  -- Sort by value for consistent display
  local sorted = {}
  for name, val in pairs(types) do
    table.insert(sorted, { name = name, val = val })
  end
  table.sort(sorted, function(a, b) return a.val < b.val end)

  -- Find the longest display name for alignment
  local max_name_len = #"MEMBER_OF"
  for _, entry in ipairs(sorted) do
    max_name_len = math.max(max_name_len, #display_name(entry.name))
  end

  local lines = {}
  local fmt = "%18s = %-" .. max_name_len .. "s (%d)"
  for _, entry in ipairs(sorted) do
    table.insert(lines, string.format(
      fmt,
      string.format("0x%x", entry.val),
      display_name(entry.name),
      entry.val
    ))
  end
  table.insert(lines, string.format(
    "%18s = %-" .. max_name_len .. "s (bits 48-63)",
    "0xffff000000000000",
    "MEMBER_OF"
  ))

  show_popup("OpenMP Map-Type Cheat-Sheet", lines)
end

--- Fetch the latest map types from the configured source repo.
function M.sync()
  vim.notify("Syncing OpenMP map types from " .. M.config.source.repo .. "...", vim.log.levels.INFO)
  maptypes.sync(M.config.source, function(err, types)
    if err then
      vim.notify(err, vim.log.levels.ERROR)
      return
    end
    map_types = types
    vim.notify(
      string.format("OpenMP map types updated: %d flags loaded", vim.tbl_count(types)),
      vim.log.levels.INFO
    )
  end)
end

function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend("force", M.config, opts)

  local km = M.config.keymaps
  if km.hex then
    vim.keymap.set("n", km.hex, M.show_hex, { desc = "Display current word in Hex" })
  end
  if km.dec then
    vim.keymap.set("n", km.dec, M.show_dec, { desc = "Display current word in Dec" })
  end
  if km.maptype then
    vim.keymap.set("n", km.maptype, M.show_maptype, { desc = "Display OpenMP map-types for current word" })
  end
  if km.cheatsheet then
    vim.keymap.set("n", km.cheatsheet, M.show_cheatsheet, { desc = "Show OpenMP map-type cheat-sheet" })
  end

  vim.api.nvim_create_user_command("OmpMapTypeSync", function()
    M.sync()
  end, { desc = "Fetch latest OpenMP map type flags from LLVM" })
end

return M
