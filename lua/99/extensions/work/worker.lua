local Window = require("99.window")

--- @class _99.Extension.Worker
local M = {}

--- @class _99.WorkOpts
--- @field description string | nil

--- @param opts _99.WorkOpts | nil
function M.set_work(opts)
  opts = opts or {}
  local description = opts.description
  if description then
    M.current_work_item = description
  else
    Window.capture_input(" Work ", {
      cb = function(success, result)
        if not success then
          return
        end
        M.current_work_item = result
      end,

      content = { "Put in the description of the work you want to complete" },
    })
  end

  -- i think this makes sense.  last work search should be cleared
  M.last_work_search = nil
end

--- craft_prompt can be overridden so you can create your own prompt
--- @param worker _99.Extension.Worker
--- @return string
function M.craft_prompt(worker)
  return string.format(
    [[
<YourGoal>
You are to take the current git diff and git diff --staged and figure out what is
left to change to complete the work item. The work item is described in <Description>

Carefully review everything in git diff and git diff --staged and <Description> before you respond.
respond with proper Search Format described in <Rule> and an example in <Output>

If you see bugs, also report those
</YourGoal>
<Description>
%s
</Description>
]],
    worker.current_work_item
  )
end

function M.work()
  assert(
    M.current_work_item,
    'you must call "set_work" and set your current work item before calling this'
  )
  local _99 = require("99")
  M.last_work_search = _99.search({
    additional_prompt = M.craft_prompt(M),
  })
end

function M.last_search_results()
  if M.last_work_search == nil then
    print("no previous search results")
    return
  end

  require("99").qfix_search_results(M.last_work_search)
end

return M
