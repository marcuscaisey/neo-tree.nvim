local utils = require("neo-tree.utils")

local M = {
  NO_DEFAULT = "<NO_DEFAULT>",
  FLAG = "<FLAG>",
  LIST = "<LIST>",
  PATH = "<PATH>",
}

-- For lists, the first value is the default value.
local arguments = {
  action = {
    type = M.LIST,
    values = {
      "focus",
      "show",
      "close",
    },
  },
  position = {
    type = M.LIST,
    values = {
      M.NO_DEFAULT,
      "left",
      "right",
      "top",
      "bottom",
      "float",
      "split"
    }
  },
  source = {
    type = M.LIST,
    values = {
      "filesystem",
      "buffers",
      "git_status",
    }
  },
  dir = { type = M.PATH, stat_type = "directory" },
  reveal_file = { type = M.PATH, stat_type = "file" },
  toggle = { type = M.FLAG },
  reveal = { type = M.FLAG },
}

local arg_type_lookup = {}
local list_args = {}
local path_args = {}
local flag_args = {}
local reverse_lookup = {}
for name, def in pairs(arguments) do
  arg_type_lookup[name] = def.type
  if def.type == M.LIST then
    table.insert(list_args, name)
    for _, vv in ipairs(def.values) do
      if vv ~= M.NO_DEFAULT then
        reverse_lookup[tostring(vv)] = name
      end
    end
  elseif def.type == M.PATH then
    table.insert(path_args, name)
  elseif def.type == M.FLAG then
    table.insert(flag_args, name)
    reverse_lookup[name] = M.FLAG
  else
    error("Unknown type: " .. def.type)
  end
end

M.arguments = arguments
M.list_args = list_args
M.path_args = path_args
M.flag_args = flag_args
M.arg_type_lookup = arg_type_lookup
M.reverse_lookup = reverse_lookup

local parse_arg = function(result, arg)
  if type(arg) == "string" then
    local eq = arg:find("=")
    if eq then
      local key = arg:sub(1, eq - 1)
      local value = arg:sub(eq + 1)
      local def = arguments[key]
      if not def.type then
        error("Invalid argument: " .. arg)
      end

      if def.type == M.PATH then
        local path = vim.fn.fnamemodify(value, ":p")
        local stat = vim.loop.fs_stat(path)
        if stat.type == def.stat_type then
          result[key] = path
        else
          error("Invalid argument for " .. key .. ": " .. value .. " is not a " .. def.stat_type)
        end
      elseif def.type == M.FLAG then
        if value == "true" then
          result[key] = true
        elseif value == "false" then
          result[key] = false
        else
          error("Invalid value for " .. key .. ": " .. value)
        end
      else
        result[key] = value
      end
    else
      local value = arg
      local key = reverse_lookup[value]
      if key == nil then
        -- maybe it's a path
        local path = vim.fn.fnamemodify(value, ":p")
        local stat = vim.loop.fs_stat(path)
        if stat then
          if stat.type == "directory" then
            result["dir"] = path
          elseif stat.type == "file" then
            result["reveal_file"] = path
          end
        else
          error("Invalid argument: " .. arg)
        end
      elseif key == M.FLAG then
        result[value] = true
      else
        result[key] = value
      end
    end
  end
end

M.parse = function(args, include_defaults, strict_checking)
  local result = {}
  if include_defaults then
    for _, key in ipairs(list_args) do
      local def = arguments[key]
      if def.values[1] ~= M.NO_DEFAULT then
        result[key] = def.values[1]
      end
    end
  end

  -- read args from user
  for _, arg in ipairs(args) do
    local success, err = pcall(parse_arg, result, arg)
    if strict_checking and not success then
      error(err)
    end
  end

  return result
end

return M
