local CleanUp = require("99.ops.clean-up")
local Window = require("99.window")
local make_prompt = require("99.ops.make-prompt")

local make_clean_up = CleanUp.make_clean_up
local make_observer = CleanUp.make_observer

--- @param context _99.Prompt
---@param response string
---@return _99.Prompt.Data.Tutorial
local function open_tutorial(context, response)
  local content = vim.split(response, "\n")
  local win = Window.create_split(content)

  --- @type _99.Prompt.Data.Tutorial
  local data = {
    type = "tutorial",
    buffer = win.buffer,
    window = win.win,
    xid = context.xid,
    tutorial = content,
  }
  context.data = data
  return data
end

--- @param context _99.Prompt
---@param opts _99.ops.Opts
local function tutorial(context, opts)
  opts = opts or {}

  local logger = context.logger:set_area("tutorial")
  logger:debug("starting", "with opts", opts)

  local clean_up = make_clean_up(function()
    context:stop()
  end)

  local prompt, refs =
    make_prompt(context, context._99.prompts.prompts.tutorial(), opts)

  context:add_references(refs)
  context:add_prompt_content(prompt)
  context:add_clean_up(clean_up)

  context:start_request(make_observer(clean_up, function(status, response)
    vim.schedule(clean_up)
    if status == "cancelled" then
      logger:debug("cancelled")
    elseif status == "failed" then
      logger:error(
        "failed",
        "error response",
        response or "no response provided"
      )
    elseif status == "success" then
      local data = open_tutorial(context, response)
      context._99:open_tutorial(data)
    end
  end))
end
return tutorial
