local Window = require("99.window")
local utils = require("99.utils")

--- @class _99.Extension.Worker
local M = {}

--- @class _99.WorkOpts
--- @field description string | nil

--- @return string
local function get_work_item_file()
  local _99 = require("99")
  local state = _99.__get_state()
  local tmp = state:tmp_dir()
  return utils.named_tmp_file(tmp, "work-item")
end

--- @return string | nil
local function read_work_item()
  local ok, file = pcall(io.open, get_work_item_file(), "r")
  if not ok or not file then
    return nil
  end
  --- @type string
  local contents
  ok, contents = pcall(file.read, file, "*a")
  pcall(file.close, file)

  if not ok then
    return nil
  end
  return contents
end

--- @param success boolean
---@param result string
local function set_work_item_cb(success, result)
  if not success then
    return
  end
  M.current_work_item = result

  local file = io.open(get_work_item_file(), "w")
  if file then
    file:write(result)
    file:close()
  else
    error("unable to save work item")
  end
end

function M.updated_work()
  local work = M.current_work_item
    or "Put in the description of the work you want to complete"
  Window.capture_input(" Work ", {
    cb = set_work_item_cb,
    content = vim.split(work, "\n"),
  })
end

--- @param opts _99.WorkOpts | nil
function M.set_work(opts)
  opts = opts or {}
  local description = opts.description
  if description then
    M.current_work_item = description
  else
    Window.capture_input(" Work ", {
      cb = set_work_item_cb,
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
<OrderedSteps>
<Step>
Inspect and understand all changed code
* git diff
* git diff --staged
* commits that have not been pushed to remote
</Step>

<Step>
Take the current pending and commited changes and figure out what is
left to change to complete the work item. The work item is described in <Description>

Carefully review all the changes and <Description> before you respond.
respond with proper Search Format described in <Rule> and an example in <Output>

If you see bugs, also report those
</Step>

<Step>
if there are steps to test the project.  run the tests and add to the list the failures
and how to fix them
</Step>
</OrderedSteps>
</YourGoal>
<Description>
%s
</Description>
]],
    worker.current_work_item
  )
end

function M.work()
  local _99 = require("99")
  if M.current_work_item == nil then
    M.current_work_item = read_work_item()
  end

  assert(
    M.current_work_item,
    'you must call "set_work" and set your current work item before calling this'
  )

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
