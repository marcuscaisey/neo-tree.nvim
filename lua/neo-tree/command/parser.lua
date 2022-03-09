local utils = require("neo-tree.utils")

local M = {}

-- for lists, first value is the default value
local valid_args = {
  action = {
    "focus",
    "show",
    "hide",
    "reveal"
  },
  position = {
    "left",
    "right",
    "top",
    "bottom",
    "float",
    "split"
  },
  toggle = {
    true,
    false,
  },
  source = {
    "filesystem",
    "buffers",
    "git_status",
  },
  dir = ".",
  reveal_file = "%:p",
}

local reverse_lookup = {}
for k, v in pairs(valid_args) do
  if type(v) == "table" then
    for _, vv in ipairs(v) do
      reverse_lookup[vv] = k
    end
  else
    reverse_lookup[v] = k
  end
end

M.parse = function(...)
  local args = {}
  -- assign defaults
  for key, value in pairs(valid_args) do
    if type(value) == "table" then
      args[key] = value[1]
    else
      args[key] = value
    end
  end

  -- read args from user
  for _, arg in ipairs(...) do
    if type(arg) == "string" then
      local eq = arg:find("=")
      if eq then
        local key = arg:sub(1, eq - 1)
        local value = arg:sub(eq + 1)
        if not valid_args[key] then
          error("Invalid argument: " .. arg)
        end
        args[key] = value
      end
    else
      local value = arg
      local key = reverse_lookup[value]
      if not key then
        error("Invalid argument: " .. value)
      end
      args[key] = value
    end
  end

  return args
end

return M
