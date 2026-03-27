local convert = require "omp_maptype_info.convert"
local maptypes = require "omp_maptype_info.maptypes"

local M = {}

M.config = {
  keymaps = {
    hex = "<leader>oh",
    dec = "<leader>od",
    maptype = "<leader>om",
  },
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
    table.insert(lines, string.format("%s000000000000 = MEMBER_OF(%s)", member_of_bits, member_of_bits))
  end

  local types = get_map_types()
  for name, val in pairs(types) do
    if flags_int == 0 then
      break
    end
    local band = vim.fn["and"](flags_int, val)
    if band ~= 0 then
      table.insert(lines, string.format("0x%-16x = %s", val, display_name(name)))
      flags_int = vim.fn["and"](flags_int, vim.fn.invert(val))
    end
  end

  if flags_int ~= 0 then
    table.insert(lines, string.format("0x%-16x = UNKNOWN", flags_int))
  end

  show_popup("MAP_TYPE:" .. hex, lines)
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

  vim.api.nvim_create_user_command("OmpMapTypeSync", function()
    M.sync()
  end, { desc = "Fetch latest OpenMP map type flags from LLVM" })
end

return M
