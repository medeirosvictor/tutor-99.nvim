local Logger = require("99.logger.logger")
local Level = require("99.logger.level")
local ops = require("99.ops")
local Languages = require("99.language")
local Window = require("99.window")
local show_in_flight_requests = require("99.window.in-flight")
local Prompt = require("99.prompt")
local State = require("99.state")
local Extensions = require("99.extensions")
local Agents = require("99.extensions.agents")
local Providers = require("99.providers")

---@param path_or_rule string | _99.Agents.Rule
---@return _99.Agents.Rule | string
local function expand(path_or_rule)
  if type(path_or_rule) == "string" then
    return vim.fn.expand(path_or_rule)
  end
  return {
    name = path_or_rule.name,
    path = vim.fn.expand(path_or_rule.path),
  }
end

--- @param opts _99.ops.Opts?
--- @return _99.ops.Opts
local function process_opts(opts)
  opts = opts or {}
  for i, rule in ipairs(opts.additional_rules or {}) do
    local r = expand(rule)
    assert(
      type(r) ~= "string",
      "broken configuration.  additional_rules must never be a string"
    )
    opts.additional_rules[i] = r
  end
  return opts
end

--- @class _99.Completion
--- @docs included
--- @field source "cmp" | "blink" | nil
--- @field custom_rules string[]
--- @field files _99.Files.Config?

--- @class _99.Options
--- @docs base
--- @field logger? _99.Logger.Options
--- @field model? string
--- @field in_flight_options? _99.InFlight.Opts
--- @field md_files? string[]
--- @field provider? _99.Providers.BaseProvider
--- @field display_errors? boolean
--- @field auto_add_skills? boolean
--- @field completion? _99.Completion
--- @field tmp_dir? string

--- @type _99.State
local _99_state

--- @class _99
local _99 = {
  DEBUG = Level.DEBUG,
  INFO = Level.INFO,
  WARN = Level.WARN,
  ERROR = Level.ERROR,
  FATAL = Level.FATAL,
}

--- @param cb fun(context: _99.Prompt, o: _99.ops.Opts?): nil
--- @param name string
--- @param context _99.Prompt
--- @param opts _99.ops.Opts
--- @param capture_content string[] | nil
local function capture_prompt(cb, name, context, opts, capture_content)
  Window.capture_input(name, {
    content = capture_content,

    --- @param ok boolean
    --- @param response string
    cb = function(ok, response)
      context.logger:debug(
        "capture_prompt",
        "success",
        ok,
        "response",
        response
      )
      if not ok then
        return
      end
      local rules_and_names = Agents.by_name(_99_state.rules, response)
      opts.additional_rules = opts.additional_rules or {}
      for _, r in ipairs(rules_and_names.rules) do
        table.insert(opts.additional_rules, r)
      end
      opts.additional_prompt = response
      cb(context, opts)
    end,
    on_load = function()
      Extensions.setup_buffer(_99_state)
    end,
    rules = _99_state.rules,
  })
end

function _99.info()
  local info = {}
  _99_state:refresh_rules()
  table.insert(
    info,
    string.format("Previous Requests: %d", _99_state:completed_prompts())
  )
  table.insert(
    info,
    string.format("custom rules(%d):", #(_99_state.rules.custom or {}))
  )
  for _, rule in ipairs(_99_state.rules.custom or {}) do
    table.insert(info, string.format("* %s", rule.name))
  end
  Window.display_centered_message(info)
end

--- @param tutorials _99.Prompt.Data.Tutorial[]
--- @return string[]
local function tutorial_to_string(tutorials)
  local out = {}
  for _, t in ipairs(tutorials) do
    table.insert(out, string.format("%d: %s", t.xid, t.tutorial[1]))
  end
  return out
end

--- @param xid number | nil
--- @param opts? _99.window.SplitWindowOpts
function _99.open_tutorial(xid, opts)
  opts = opts or { split_direction = "vertical" }
  if xid == nil then
    --- @type _99.Prompt.Data.Tutorial[]
    local tutorials = _99_state:get_request_data_by_type("tutorial")
    if #tutorials == 0 then
      print("no tutorials available")
      return
    elseif #tutorials == 1 then
      local data = tutorials[1]
      assert(data, "tutorial is malformed")
      Window.create_split(data.tutorial, data.buffer, opts)
      return
    else
      --- TODO: Complete this task when i work through tutorials
      error([[not implemented.  right now tutorials are not sccrollable.
This is a later change required.  I want a next/prev tutorial navigation
much like qfix list.  then i to have a capture input style window where you
can press enter
]])
    end
    return
  end

  --- @type _99.Prompt | nil
  local context = _99_state.__request_by_id[xid]
  assert(context, "could not find request")
  assert(context.state == "success", "tutorial found had a non success state")

  local tutorial = context:tutorial_data()
  Window.create_split(tutorial.tutorial, tutorial.buffer, opts)
end

--- @param path string
function _99:rule_from_path(path)
  _ = self
  path = expand(path) --[[ @as string]]
  return Agents.get_rule_by_path(_99_state.rules, path)
end

--- @param opts? _99.ops.SearchOpts
--- @return number
function _99.search(opts)
  local o = process_opts(opts) --[[ @as _99.ops.SearchOpts ]]
  local context = Prompt.search(_99_state)
  if o.additional_prompt then
    ops.search(context, o)
  else
    capture_prompt(ops.search, "Search", context, o)
  end
  return context.xid
end

--- @param opts _99.ops.Opts
function _99.tutorial(opts)
  opts = process_opts(opts)
  local context = Prompt.tutorial(_99_state)
  if opts.additional_prompt then
    ops.tutorial(context, opts)
  else
    capture_prompt(ops.tutorial, "Tutorial", context, opts)
  end
end

--- @param opts _99.ops.Opts?
function _99.visual(opts)
  opts = process_opts(opts)
  local context = Prompt.visual(_99_state)
  if opts.additional_prompt then
    ops.over_range(context, opts)
  else
    capture_prompt(ops.over_range, "Visual", context, opts)
  end
end

--- View all the logs that are currently cached.  Cached log count is determined
--- by _99.Logger.Options that are passed in.
function _99.view_logs()
  _99_state.__view_log_idx = 1
  local logs = Logger.logs()
  if #logs == 0 then
    print("no logs to display")
    return
  end
  Window.display_full_screen_message(logs[1])
end

function _99.prev_request_logs()
  local logs = Logger.logs()
  if #logs == 0 then
    print("no logs to display")
    return
  end
  _99_state.__view_log_idx = math.min(_99_state.__view_log_idx + 1, #logs)
  Window.display_full_screen_message(logs[_99_state.__view_log_idx])
end

function _99.next_request_logs()
  local logs = Logger.logs()
  if #logs == 0 then
    print("no logs to display")
    return
  end
  _99_state.__view_log_idx = math.max(_99_state.__view_log_idx - 1, 1)
  Window.display_full_screen_message(logs[_99_state.__view_log_idx])
end

--- @class _99.QFixEntry
--- @field filename string
--- @field lnum number
--- @field col number
--- @field text string

function _99.stop_all_requests()
  for _, c in pairs(_99_state.__request_by_id) do
    if c.state == "requesting" then
      c:stop()
    end
  end
end

function _99.clear_all_marks()
  for _, mark in ipairs(_99_state.__active_marks or {}) do
    mark:delete()
  end
  _99_state.__active_marks = {}
end

--- @param xid number | nil
function _99.qfix_search_results(xid)
  --- @type _99.Prompt
  local entry = _99_state.__request_by_id[xid]
  assert(entry, "qfix_search_results could not find id: " .. xid)

  local data = entry:search_data()
  local items = data.qfix_items
  vim.fn.setqflist({}, "r", { title = "99 Search Results", items = items })
  vim.cmd("copen")
end

function _99.clear_previous_requests()
  _99_state:clear_history()
end

--- if you touch this function you will be fired
--- @return _99.State
function _99.__get_state()
  return _99_state
end

--- @param opts _99.Options?
function _99.setup(opts)
  opts = opts or {}

  _99_state = State.new(opts)

  local crules = _99_state.completion.custom_rules
  for i, rule in ipairs(crules) do
    local str = expand(rule)
    assert(type(str) == "string", "error parsing rule: path must be a string")
    crules[i] = str
  end

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      _99.stop_all_requests()
    end,
  })

  Logger:configure(opts.logger)

  if opts.model then
    assert(type(opts.model) == "string", "opts.model is not a string")
    _99_state.model = opts.model
  else
    local provider = opts.provider or Providers.OpenCodeProvider
    if provider._get_default_model then
      _99_state.model = provider._get_default_model()
    end
  end

  if opts.md_files then
    assert(type(opts.md_files) == "table", "opts.md_files is not a table")
    for _, md in ipairs(opts.md_files) do
      _99.add_md_file(md)
    end
  end

  if opts.tmp_dir then
    assert(type(opts.tmp_dir) == "string", "opts.tmp_dir must be a string")
  end
  _99_state.__tmp_dir = opts.tmp_dir

  _99_state.display_errors = opts.display_errors or false
  _99_state:refresh_rules()
  Languages.initialize(_99_state)
  Extensions.init(_99_state)
  Extensions.capture_project_root()

  show_in_flight_requests(_99_state, _99_state.in_flight_options)
end

--- @param md string
--- @return _99
function _99.add_md_file(md)
  table.insert(_99_state.md_files, md)
  return _99
end

--- @param md string
--- @return _99
function _99.rm_md_file(md)
  for i, name in ipairs(_99_state.md_files) do
    if name == md then
      table.remove(_99_state.md_files, i)
      break
    end
  end
  return _99
end

--- @param model string
--- @return _99
function _99.set_model(model)
  _99_state.model = model
  return _99
end

--- @return string
function _99.get_model()
  return _99_state.model
end

--- @return _99.Providers.BaseProvider
function _99.get_provider()
  return _99_state.provider_override or Providers.OpenCodeProvider
end

--- @param provider _99.Providers.BaseProvider
--- @return _99
function _99.set_provider(provider)
  _99_state.provider_override = provider
  if provider._get_default_model then
    _99_state.model = provider._get_default_model()
  end
  return _99
end

function _99.__debug()
  Logger:configure({
    path = nil,
    level = Level.DEBUG,
  })
end

_99.Providers = Providers
_99.Extensions = {
  Worker = require("99.extensions.work.worker"),
}
return _99
