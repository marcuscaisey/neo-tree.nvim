local parser = require("neo-tree.command.parser")
local log = require("neo-tree.log")
local manager = require("neo-tree.sources.manager")
local utils   = require("neo-tree.utils")
local renderer = require("neo-tree.ui.renderer")

local M = {
  show_key_value_completions = false,
}

local get_path_completions = function(key_prefix, base_path)
  key_prefix = key_prefix or ""
  local completions = {}
  local expanded = parser.resolve_path(base_path)
  local path_completions = vim.fn.glob(expanded .. "*", false, true)
  for _, completion in ipairs(path_completions) do
    if expanded ~= base_path then
      completion = base_path .. string.sub(completion, #expanded + 1)
    end
    table.insert(completions, key_prefix .. completion)
  end

  return table.concat(completions, "\n")
end

M.complete_args = function (argLead, cmdLine)
  local candidates = {}
  local existing = utils.split(cmdLine, " ")
  local parsed = parser.parse(existing, false)

  local eq = string.find(argLead, "=")
  if eq == nil then
    if M.show_key_value_completions then
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
          if vv:find(value) then
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

---Executes a Neo-tree action from outside of a Neo-tree window,
---such as show, hide, navigate, etc.
---@param args table The action to execute. The table can have the following keys:
---  action = string   The action to execute, can be one of:
---                    "close",
---                    "focus", <-- default value
---                    "show",
---  source = string   The source to use for this action. This will default
---                    to the default_source specified in the user's config.
---                    Can be one of:
---                    "filesystem",
---                    "buffers",
---                    "git_status",
---  position = string The position this action will affect. This will default
---                    to the the last used position or the position specified
---                    in the user's config for the given source. Can be one of:
---                    "left",
---                    "right",
---                    "float",
---                    "split"
---  toggle = boolean  Whether to toggle the visibility of the Neo-tree window.
---  reveal = boolean  Whether to reveal the current file in the Neo-tree window.
---  reveal_file = string The specific file to reveal.
---  dir = string      The root directory to set.
M.execute = function(args)
  local nt = require("neo-tree")

  args.action = args.action or "focus"

  -- handle close action, which can specify a source and/or position
  if args.action == "close" then
    if args.source then
      manager.close(args.source, args.position)
    else
      manager.close_all(args.position)
    end
    return
  end

  -- The rest of the actions require a source
  args.source = args.source or nt.config.default_source

  -- First handle toggle, the rest is irrelevant if we need to toggle
  if args.toggle then
    if manager.close(args.source) then
      -- It was open, and now it's not.
      return
    end
  end

  -- Now get the correct state
  local state
  local default_position = nt.config[args.source].window.position
  if args.position == "split" or default_position == "split" then
    local winid = vim.api.nvim_get_current_win()
    state = manager.get_state(args.source, nil, winid)
  else
    state = manager.get_state(args.source, nil, nil)
  end

  -- If position=split was requested, but we are currently in a neo-tree window,
  -- then we need to override that and to prevent confusing situations.
  if args.position == "split" and vim.bo.filetype == "neo-tree" then
    local position = vim.api.nvim_buf_get_var(0, "neo_tree_position")
    if position then
      args.position = position
    end
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
  local force_navigate = path_changed or do_reveal or state.dirty
  local window_exists = renderer.window_exists(state)
  local function close_other_sources()
    if not window_exists then
      -- Clear the space in case another source is already open
      local target_position = args.position or state.current_position or state.window.position
      manager.close_all(target_position)
    end
  end

  if args.action == "show" then
    -- "show" means show the window without focusing it
    if window_exists and not force_navigate then
      -- There's nothing to do here, we are already at the target state
      return
    end
    close_other_sources()
    local current_win = vim.api.nvim_get_current_win()
    manager.navigate(state, state.path, args.reveal_file, function()
      -- navigate changes the window to neo-tree, so just quickly hop back to the original window
      vim.api.nvim_set_current_win(current_win)
    end)
  elseif args.action == "focus" then
    -- "focus" mean open and jump to the window if closed, and just focus it if already opened
    if window_exists and not force_navigate then
      vim.api.nvim_set_current_win(state.winid)
    else
      close_other_sources()
      manager.navigate(state, state.path, args.reveal_file)
    end
  end
end

---Parses and executes the command line. Use execute(args) instead.
---@param ... string Argument as strings.
M.command = function (...)
  local args = parser.parse({...}, true)
  M.execute(args)
end

return M
