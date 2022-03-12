local parser = require("neo-tree.command.parser")
local log = require("neo-tree.log")
local manager = require("neo-tree.sources.manager")
local utils   = require("neo-tree.utils")
local renderer = require("neo-tree.ui.renderer")

local M = {}

local get_path_completions = function(key_prefix, base_path)
  local completions = {}
  local key_prefix = key_prefix or ""
  local expanded = vim.fn.expand(base_path)
  local path_completions = vim.fn.glob(expanded .. "*", false, true)
  for _, completion in ipairs(path_completions) do
    if expanded ~= base_path then
      completion = base_path .. string.sub(completion, #expanded + 1)
    end
    table.insert(completions, key_prefix .. completion)
  end

  return table.concat(completions, "\n")
end

M.complete_args = function (argLead, cmdLine, cursorPosition)
  local candidates = {}
  local existing = utils.split(cmdLine, " ")
  local parsed = parser.parse(existing, false, false)

  local eq = string.find(argLead, "=")
  if eq == nil then
    -- may be the start of a new key=value pair
    for _, key in ipairs(parser.list_args) do
      key = tostring(key)
      if key:find(argLead) and not parsed[key] then
        table.insert(candidates, key .. "=")
      end
    end

    for _, key in ipairs(parser.path_args) do
      key = tostring(key)
      if key:find(argLead) and not parsed[key] then
        table.insert(candidates, key .. "=./")
      end
    end
  else
    -- continuation of a key=value pair
    local key = string.sub(argLead, 1, eq - 1)
    local value = string.sub(argLead, eq + 1)
    local arg_type = parser.arg_type_lookup[key]
    if arg_type == parser.PATH then
      return get_path_completions(key .. "=", value)
    elseif arg_type == parser.LIST then
      local valid_values = parser.arguments[key].values
      if valid_values and not parsed[key] then
        for _, vv in ipairs(valid_values) do
          if vv ~= parser.NO_DEFAULT and vv:find(value) then
            table.insert(candidates, key .. "=" .. vv)
          end
        end
      end
    end
  end

  -- may be a value without a key
  for value, key  in pairs(parser.reverse_lookup) do
    value = tostring(value)
    local key_already_used = false
    if parser.arg_type_lookup[key] == parser.LIST then
      key_already_used = type(parsed[key]) ~= "nil"
    else
      key_already_used = type(parsed[value]) ~= "nil"
    end

    if not key_already_used and value:find(argLead) then
      table.insert(candidates, value)
    end
  end

  if #candidates == 0 then
    -- default to path completion
    return get_path_completions(nil, argLead)
  end
  return table.concat(candidates, "\n")
end


M.execute = function (...)
  local args = parser.parse({...}, true, true)
  local nt = require("neo-tree")

  -- First handle toggle, the rest is irrelevant if we need to toggle
  if args.toggle then
    if manager.close(args.source) then
      -- It was open, and now it's not.
      return
    end
  end
  nt.close_all_except(args.source)

  -- Now get the correct state
  local state
  local default_position = nt.config[args.source].window.position
  if args.position == "split" or default_position == "split" then
    local winid = vim.api.nvim_get_current_win()
    state = manager.get_state(args.source, nil, winid)
  else
    state = manager.get_state(args.source, nil, nil)
  end

  -- Handle position override
  state.current_position = args.position

  -- Handle setting directory if requested
  local path_changed = false
  if args.dir then
    if args.dir:sub(-1) == utils.path_separator then
      args.dir = args.dir:sub(1, -2)
    end
    path_changed = state.path ~= args.dir
    state.path = args.dir
  end

  -- Handle reveal logic
  local do_reveal = utils.truthy(args.reveal_file)
  if args.reveal and not do_reveal then
    args.reveal_file = manager.get_path_to_reveal()
    do_reveal = utils.truthy(args.reveal_file)
  end

  -- All set, now show or focus the window
  if args.action == "show" then
    if path_changed or do_reveal or not renderer.window_exists(state) then
      local current_win = vim.api.nvim_get_current_win()
      manager.navigate(state, state.path, args.reveal_file, function()
        vim.api.nvim_set_current_win(current_win)
      end)
    end
  elseif args.action == "focus" then
    if not path_changed or not do_reveal and not state.dirty and renderer.window_exists(state) then
      vim.api.nvim_set_current_win(state.winid)
    else
      manager.navigate(state, state.path, args.reveal_file)
    end
  end
end

return M
