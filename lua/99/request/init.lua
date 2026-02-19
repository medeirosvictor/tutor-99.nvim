--- @alias _99.Request.ResponseState "failed" | "success" | "cancelled"
--- @alias _99.Request.State "ready" | "requesting" | _99.Request.ResponseState

local Providers = require("99.providers")

--- @class _99.Request.Opts
--- @field model string
--- @field tmp_file string
--- @field provider _99.Providers.BaseProvider?
--- @field xid number

--- @class _99.Request.Config
--- @field model string
--- @field tmp_file string
--- @field provider _99.Providers.BaseProvider
--- @field xid number

--- @class _99.Request
--- @field context _99.RequestContext
--- @field state _99.Request.State
--- @field provider _99.Providers.BaseProvider
--- @field logger _99.Logger
--- @field _content string[]
---@diagnostic disable-next-line: undefined-doc-name
--- @field _proc vim.SystemObj?
local Request = {}
Request.__index = Request

--- @param context _99.RequestContext
--- @return _99.Request
function Request.new(context)
  local provider = context._99.provider_override or Providers.OpenCodeProvider
  return setmetatable({
    context = context,
    provider = provider,
    state = "ready",
    logger = context.logger:set_area("Request"),
    _content = {},
    _proc = nil,
  }, Request)
end

---@diagnostic disable-next-line: undefined-doc-name
--- @param proc vim.SystemObj?
function Request:_set_process(proc)
  self._proc = proc
end

function Request:cancel()
  if self.state == "success" or self.state == "failed" then
    return
  end

  self.logger:debug("cancel")
  self.state = "cancelled"
  local proc = self._proc
  ---@diagnostic disable-next-line: undefined-field
  if proc and proc.pid then
    self._proc = nil
    pcall(function()
      local sigterm = (vim.uv and vim.uv.constants and vim.uv.constants.SIGTERM)
        or 15
      ---@diagnostic disable-next-line: undefined-field
      proc:kill(sigterm)
    end)
  end
end

function Request:is_cancelled()
  return self.state == "cancelled"
end

--- @param content string
--- @return self
function Request:add_prompt_content(content)
  table.insert(self._content, content)
  return self
end

--- @param r _99.Request
--- @param obs _99.Providers.Observer | nil
local function observer_from_request(r, obs)
  local context = r.context
  return {
    on_start = function()
      r.state = "requesting"
      context._99:track_request(context)
      if obs then
        obs.on_start()
      end
    end,
    on_complete = function(status, res)
      r.state = status
      context._99:finish_request(context, status)
      if obs then
        obs.on_complete(status, res)
      end
    end,
    on_stderr = function(line)
      if obs then
        obs.on_stderr(line)
      end
    end,
    on_stdout = function(line)
      if obs then
        obs.on_stdout(line)
      end
    end,
  }
end

--- @param observer _99.Providers.Observer?
function Request:start(observer)
  self.logger:assert(
    self.state == "ready",
    "request is not in state ready when attempting to start a request"
  )
  local ok = self.context:finalize()
  self.logger:assert(
    ok,
    "request has failed due to context finalization: check logs for more details"
  )

  for _, content in ipairs(self.context.ai_context) do
    self:add_prompt_content(content)
  end
  local prompt = table.concat(self._content, "\n")

  self.context:save_prompt(prompt)
  self.logger:debug("start", "prompt", prompt)
  self.provider:make_request(
    prompt,
    self,
    observer_from_request(self, observer)
  )
end

return Request
