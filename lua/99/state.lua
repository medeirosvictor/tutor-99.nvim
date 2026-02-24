local Agents = require("99.extensions.agents")
local Extensions = require("99.extensions")

local function default_completion()
  return { source = nil, custom_rules = {} }
end

--- @class _99.StateProps
--- @field model string
--- @field md_files string[]
--- @field prompts _99.Prompts
--- @field ai_stdout_rows number
--- @field languages string[]
--- @field display_errors boolean
--- @field auto_add_skills boolean
--- @field provider_override _99.Providers.BaseProvider | nil
--- @field __view_log_idx number
--- @field __tmp_dir string | nil

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
--- @field in_flight_options _99.InFlight.Opts | nil
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
local State = {}
State.__index = State

--- @return _99.StateProps
local function create()
  return {
    model = "minimax/MiniMax-M2",
    md_files = {},
    prompts = require("99.prompt-settings"),
    ai_stdout_rows = 3,
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

--- @param opts _99.Options
--- @return _99.State
function State.new(opts)
  local props = create()
  local _99_state = setmetatable(props, State) --[[@as _99.State]]

  _99_state.in_flight_options = opts.in_flight_options or { enable = true }
  _99_state.provider_override = opts.provider
  _99_state.completion = opts.completion or default_completion()
  _99_state.completion.custom_rules = _99_state.completion.custom_rules or {}
  _99_state.auto_add_skills = opts.auto_add_skills or false
  _99_state.completion.files = _99_state.completion.files or {}

  return _99_state
end

--- @return string
function State:tmp_dir()
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
function State:refresh_rules()
  self.rules = Agents.rules(self)
  Extensions.refresh(self)
end

--- @param context _99.Prompt
function State:track_prompt_request(context)
  assert(context:valid(), "context is not valid")
  table.insert(self.__request_history, context)
  self.__request_by_id[context.xid] = context
end

--- @return number
function State:completed_prompts()
  local count = 0
  for _, entry in ipairs(self.__request_history) do
    if entry.state ~= "requesting" then
      count = count + 1
    end
  end
  return count
end

function State:clear_history()
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
function State:add_mark(mark)
  table.insert(self.__active_marks, mark)
end

function State:clear_marks()
  for _, active_mark in ipairs(self.__active_marks or {}) do
    active_mark:delete()
  end
  self.__active_marks = {}
end

function State:active_request_count()
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
function State:get_request_data_by_type(type)
  local out = {}
  for _, r in ipairs(self.__request_history) do
    local data = r.data
    if data and data.type == type then
      table.insert(out, data)
    end
  end
  return out
end

return State
