local Logger = require("99.logger.logger")
local Level = require("99.logger.level")
local ops = require("99.ops")
local Languages = require("99.language")
local Window = require("99.window")
local Prompt = require("99.prompt")
local geo = require("99.geo")
local Range = geo.Range
local Extensions = require("99.extensions")
local Agents = require("99.extensions.agents")
local Providers = require("99.providers")
local Throbber = require("99.ops.throbber")

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

--- @class _99.StateProps
--- @field model string
--- @field md_files string[]
--- @field prompts _99.Prompts
--- @field ai_stdout_rows number
--- @field show_in_flight_requests boolean
--- @field languages string[]
--- @field display_errors boolean
--- @field auto_add_skills boolean
--- @field provider_override _99.Providers.BaseProvider?
--- @field __view_log_idx number
--- @field __tmp_dir string | nil

--- @return _99.StateProps
local function create_99_state()
  return {
    model = "opencode/claude-sonnet-4-5",
    md_files = {},
    prompts = require("99.prompt-settings"),
    ai_stdout_rows = 3,
    show_in_flight_requests = false,
    languages = { "lua", "go", "java", "elixir", "cpp", "ruby" },
    display_errors = false,
    provider_override = nil,
    auto_add_skills = false,
    __view_log_idx = 1,
    __request_history = {},
    __request_by_id = {},
    tmp_dir = nil,
  }
end

--- @class _99.Completion
--- @field source "cmp" | "blink" | nil
--- @field custom_rules string[]
--- @field files _99.Files.Config?

--- @class _99.Options
--- @field logger _99.Logger.Options?
--- @field model string?
--- @field show_in_flight_requests boolean?
--- @field md_files string[]?
--- @field provider _99.Providers.BaseProvider?
--- @field debug_log_prefix string?
--- @field display_errors? boolean
--- @field auto_add_skills? boolean
--- @field completion _99.Completion?
--- @field tmp_dir? string

--- unanswered question -- will i need to queue messages one at a time or
--- just send them all...  So to prepare ill be sending around this state object
--- @class _99.State
--- @field completion _99.Completion
--- @field model string
--- @field md_files string[]
--- @field prompts _99.Prompts
--- @field ai_stdout_rows number
--- @field languages string[]
--- @field display_errors boolean
--- @field show_in_flight_requests boolean
--- @field show_in_flight_requests_window _99.window.Window | nil
--- @field show_in_flight_requests_throbber _99.Throbber | nil
--- @field provider_override _99.Providers.BaseProvider?
--- @field auto_add_skills boolean
--- @field rules _99.Agents.Rules
--- @field __view_log_idx number
--- @field __request_history _99.Prompt[]
--- @field __request_by_id table<number, _99.Prompt>
--- @field __active_marks _99.Mark[]
--- @field __tmp_dir string | nil
local _99_State = {}
_99_State.__index = _99_State

--- @return _99.State
function _99_State.new()
  local props = create_99_state()
  ---@diagnostic disable-next-line: return-type-mismatch
  return setmetatable(props, _99_State)
end

--- @return string
function _99_State:tmp_dir()
  local tmp_dir = self.__tmp_dir or "./tmp"
  if tmp_dir then
    tmp_dir = vim.fn.expand(tmp_dir)
  end
  return tmp_dir
end

--- TODO: This is something to understand.  I bet that this is going to need
--- a lot of performance tuning.  I am just reading every file, and this could
--- take a decent amount of time if there are lots of rules.
---
--- Simple perfs:
--- 1. read 4096 bytes at a tiem instead of whole file and parse out lines
--- 2. don't show the docs
--- 3. do the operation once at setup instead of every time.
---    likely not needed to do this all the time.
function _99_State:refresh_rules()
  self.rules = Agents.rules(self)
  Extensions.refresh(self)
end

--- @param tutorial _99.Prompt.Data.Tutorial
function _99_State:open_tutorial(tutorial)
  -- TODO: this is a task item for when i start the work item "Tutorial Navigation"
  _ = self
  _ = tutorial
end

--- @param context _99.Prompt
function _99_State:track_request(context)
  assert(context:valid(), "context is not valid")
  table.insert(self.__request_history, context)
  self.__request_by_id[context.xid] = context
end

--- @return number
function _99_State:previous_request_count()
  local count = 0
  for _, entry in ipairs(self.__request_history) do
    if entry.state ~= "requesting" then
      count = count + 1
    end
  end
  return count
end

function _99_State:clear_previous_requests()
  local keep = {}
  for _, entry in ipairs(self.__request_history) do
    if entry.state == "requesting" then
      table.insert(keep, entry)
    else
      self.__request_by_id[entry.xid] = nil
    end
  end
  self.__request_history = keep
end

--- @param mark _99.Mark
function _99_State:add_mark(mark)
  table.insert(self.__active_marks, mark)
end

function _99_State:active_request_count()
  local count = 0
  for _, r in pairs(self.__request_history) do
    if r.state == "requesting" then
      count = count + 1
    end
  end
  return count
end

--- @param type "search" | "visual" | "tutorial"
--- @return _99.Prompt.Data
function _99_State:get_request_data_by_type(type)
  local out = {}
  for _, r in ipairs(self.__request_history) do
    local data = r.data
    if data and data.type == type then
      table.insert(out, data)
    end
  end
  return out
end

local _99_state = _99_State.new()

--- @class _99
local _99 = {
  DEBUG = Level.DEBUG,
  INFO = Level.INFO,
  WARN = Level.WARN,
  ERROR = Level.ERROR,
  FATAL = Level.FATAL,
}

--- you can only set those marks after the visual selection is removed
local function set_selection_marks()
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
    "x",
    false
  )
end

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
    string.format("Previous Requests: %d", _99_state:previous_request_count())
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
  local function perform_range()
    set_selection_marks()
    local range = Range.from_visual_selection()
    ops.over_range(context, range, opts)
  end
  if opts.additional_prompt then
    perform_range()
  else
    capture_prompt(perform_range, "Visual", context, opts)
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
  _99_state:clear_previous_requests()
end

--- if you touch this function you will be fired
--- @return _99.State
function _99.__get_state()
  return _99_state
end

local function shut_down_in_flight_requests_window()
  if _99_state.show_in_flight_requests_throbber then
    _99_state.show_in_flight_requests_throbber:stop()
  end

  local win = _99_state.show_in_flight_requests_window
  if win ~= nil then
    Window.close(win)
  end
  _99_state.show_in_flight_requests_window = nil
  _99_state.show_in_flight_requests_throbber = nil
end

local function show_in_flight_requests()
  if _99_state.show_in_flight_requests == false then
    return
  end
  vim.defer_fn(show_in_flight_requests, 1000)

  Window.refresh_active_windows()
  local current_win = _99_state.show_in_flight_requests_window
  if current_win ~= nil and not Window.is_active_window(current_win) then
    shut_down_in_flight_requests_window()
  end

  if Window.has_active_windows() or _99_state:active_request_count() == 0 then
    return
  end

  if _99_state.show_in_flight_requests_window == nil then
    local win = Window.status_window()
    local throb = Throbber.new(function(throb)
      local count = _99_state:active_request_count()
      if count == 0 or not Window.valid(win) then
        return shut_down_in_flight_requests_window()
      end

      --- @type string[]
      local lines = {
        throb .. " requests(" .. tostring(count) .. ") " .. throb,
      }

      for _, c in pairs(_99_state.__request_by_id) do
        if c.state == "requesting" then
          table.insert(lines, c.operation)
        end
      end

      Window.resize(win, #lines[1], #lines)
      vim.api.nvim_buf_set_lines(win.buf_id, 0, 1, false, lines)
    end)
    _99_state.show_in_flight_requests_window = win
    _99_state.show_in_flight_requests_throbber = throb

    throb:start()
  end
end

--- @param opts _99.Options?
function _99.setup(opts)
  opts = opts or {}

  _99_state = _99_State.new()
  _99_state.show_in_flight_requests = opts.show_in_flight_requests or false
  _99_state.provider_override = opts.provider
  _99_state.completion = opts.completion
    or {
      source = nil,
      custom_rules = {},
    }
  _99_state.completion.custom_rules = _99_state.completion.custom_rules or {}
  _99_state.auto_add_skills = opts.auto_add_skills or false
  _99_state.completion.files = _99_state.completion.files or {}

  local crules = _99_state.completion.custom_rules
  for i, rule in ipairs(crules) do
    local str = expand(rule)
    assert(type(str) == "string", "rule path must be a string")
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

  if _99_state.show_in_flight_requests then
    show_in_flight_requests()
  end
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
