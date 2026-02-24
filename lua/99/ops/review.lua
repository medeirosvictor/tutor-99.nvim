local Mark = require("99.ops.marks")
local geo = require("99.geo")
local make_prompt = require("99.ops.make-prompt")
local CleanUp = require("99.ops.clean-up")
local Window = require("99.window")

local make_clean_up = CleanUp.make_clean_up
local make_observer = CleanUp.make_observer

local Range = geo.Range
local Point = geo.Point

--- @param context _99.Prompt
--- @param opts? _99.ops.Opts
local function review(context, opts)
  opts = opts or {}
  local logger = context.logger:set_area("review")

  local data = context:visual_data()
  local range = data.range
  local top_mark = Mark.mark_above_range(range)
  local bottom_mark = Mark.mark_point(range.buffer, range.end_)
  context.marks.top_mark = top_mark
  context.marks.bottom_mark = bottom_mark

  logger:debug(
    "review request start",
    "start",
    Point.from_mark(top_mark),
    "end",
    Point.from_mark(bottom_mark)
  )

  local clean_up = make_clean_up(function()
    context:clear_marks()
    context:stop()
  end)

  local system_cmd = context._99.prompts.prompts.review_selection(range)
  local prompt, refs = make_prompt(context, system_cmd, opts)

  context:add_prompt_content(prompt)
  context:add_references(refs)
  context:add_clean_up(clean_up)

  context:start_request(make_observer(clean_up, {
    on_complete = function(status, response)
      if status == "cancelled" then
        logger:debug("request cancelled for review")
      elseif status == "failed" then
        logger:error(
          "request failed for review",
          "error response",
          response or "no response provided"
        )
        Window.display_error("Review request failed: " .. (response or "unknown error"))
      elseif status == "success" then
        local valid = top_mark:is_valid() and bottom_mark:is_valid()
        if not valid then
          logger:fatal("visual selection was destroyed during review request")
          return
        end

        if vim.trim(response) == "" then
          print("response was empty")
          return
        end

        local lines = vim.split(response, "\n")
        table.insert(lines, 1, "")
        table.insert(lines, "")
        table.insert(lines, "---")
        table.insert(lines, "Press `q` or `<Esc>` to close. Feel free to ask follow-up questions!")

        Window.display_full_screen_message(lines)
      end
    end,
  }))
end

return review
