local parser = require("neo-tree.command.parser")
local log = require("neo-tree.log")
local manager = require("neo-tree.sources.manager")

local M = {}

M.complete_args = function (argLead, cmdLine, cursorPosition)
  local candidates = {}
  log.info("complete_args", argLead, cmdLine, cursorPosition)

  local eq = string.find(argLead, "=")
  if eq == nil then
    -- may be the start of a new key=value pair
    for key, _ in pairs(parser.valid_args) do
      key = tostring(key)
      if key ~= parser.NONE and key:find(argLead) then
        table.insert(candidates, key .. "=")
      end
    end
  else
    -- continuation of a key=value pair
    local key = string.sub(argLead, 1, eq - 1)
    local value = string.sub(argLead, eq + 1)
    local valid_values = parser.valid_args[key]
    if valid_values then
      for _, vv in ipairs(valid_values) do
        if vv ~= parser.NONE and vv:find(value) then
          table.insert(candidates, key .. "=" .. vv)
        end
      end
    end
  end

  -- may be a value without a key
  for key, _ in pairs(parser.reverse_lookup) do
    key = tostring(key)
    if key:find(argLead) then
      table.insert(candidates, key)
    end
  end
  return table.concat(candidates, "\n")
end


M.execute = function (...)
  local args = parser.parse(...)
  local nt = require("neo-tree")

  local state = manager.get_state(args.source)
  if args.position then
    if args.position == "split" or state.window.position == "split" then
      local winid = vim.api.nvim_get_current_win()
      state = manager.get_state(args.source, nil, winid)
    else
      state = manager.get_state(args.source, nil, nil)
    end
    state.current_position = args.position
  end

  if args.dir then
    state.path = vim.fn.expand(args.dir)
  end

  if args.action == "show" then
    nt.show(args.source, args.toggle)
  elseif args.action == "focus" then
    nt.show(args.source, args.toggle)
  elseif args.action == "reveal" then
    nt.reveal_current_file(args.source, args.toggle)
  end
  return args
end

return M
