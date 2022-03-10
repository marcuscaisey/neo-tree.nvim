local utils = require("neo-tree.utils")

local M = {
  NONE = "NONE"
}

-- For lists, the first value is the default value. "NONE" implies no default value.
local valid_args = {
  action = {
    "focus",
    "show",
    "hide",
    "reveal"
  },
  position = {
    M.NONE,
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
  dir = M.NONE,
  reveal_file = M.NONE,
}

local reverse_lookup = {}
for k, v in pairs(valid_args) do
  if type(v) == "table" then
    for _, vv in ipairs(v) do
      if vv ~= M.NONE then
        reverse_lookup[vv] = k
      end
    end
  else
    if v ~= M.NONE then
      reverse_lookup[v] = k
    end
  end
end

M.valid_args = valid_args
M.reverse_lookup = reverse_lookup

M.parse = function(...)
  local args = {}
  -- assign defaults
  for key, value in pairs(valid_args) do
    if type(value) == "table" then
      if value[1] ~= M.NONE then
        args[key] = value[1]
      end
    else
      if value ~= M.NONE then
        args[key] = value
      end
    end
  end

  -- read args from user
  for _, arg in ipairs({...}) do
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
