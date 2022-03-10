local parser = require("neo-tree.command.parser")
local log = require("neo-tree.log")
local manager = require("neo-tree.sources.manager")
local utils   = require("neo-tree.utils")
local renderer = require("neo-tree.ui.renderer")

local M = {}

local get_path_completions = function(key_prefix, base_path)
  local completions = {}
  local key_prefix = key_prefix or ""
  local path_completions = vim.fn.glob(base_path .. "*", false, true)
  for _, completion in ipairs(path_completions) do
    table.insert(completions, key_prefix .. completion)
  end
  return table.concat(completions, "\n")
end

M.complete_args = function (argLead, cmdLine, cursorPosition)
  local candidates = {}

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
    if key == "dir" or key == "reveal_path" then
      return get_path_completions(key .. "=", value)
    end
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

  if #candidates == 0 then
    local first = string.sub(argLead, 1, 1)
    if first == "~" or first == "/" then
      -- may be a path
      local path = string.sub(argLead, 2)
      return get_path_completions(nil, argLead)
    end
  end
  return table.concat(candidates, "\n")
end


M.execute = function (...)
  local args = parser.parse(...)
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
  -- Set any relevant state args
  state.current_position = args.position
  if args.dir then
    state.path = vim.fn.expand(args.dir)
  end

  -- Handle reveal logic
  if args.action == "reveal" and not utils.truthy(args.reveal_path) then
    args.reveal_path = manager.get_path_to_reveal()
    args.action = "focus"
  end

  -- All set, now show or focus the window
  if args.action == "show" then
    if not renderer.window_exists(state) then
      local current_win = vim.api.nvim_get_current_win()
      manager.navigate(state, state.path, args.reveal_path, function()
        vim.api.nvim_set_current_win(current_win)
      end)
    end
  elseif args.action == "focus" then
    if args.reveal_path then
      manager.navigate(state, state.path, args.reveal_path)
    else
      if not state.dirty and renderer.window_exists(state) then
        vim.api.nvim_set_current_win(state.winid)
      else
        manager.navigate(state, state.path, args.reveal_path)
      end
    end
  end
end

return M
