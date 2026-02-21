local make_prompt = require("99.ops.make-prompt")
local CleanUp = require("99.ops.clean-up")

local make_clean_up = CleanUp.make_clean_up
local make_observer = CleanUp.make_observer

--- @class _99.Search.Result
--- @field filename string
--- @field lnum number
--- @field col number
--- @field text string

--- @return _99.Search.Result | nil
local function parse_line(line)
  local parts = vim.split(line, ":", { plain = true })
  if #parts ~= 3 then
    return nil
  end

  local filepath = parts[1]
  local lnum = parts[2]
  local comma_parts = vim.split(parts[3], ",", { plain = true })
  local col = comma_parts[1]
  local notes = nil

  if #comma_parts >= 2 then
    notes = table.concat(comma_parts, ",", 2)
  end

  return {
    filename = filepath,
    lnum = tonumber(lnum) or 1,
    col = tonumber(col) or 1,
    text = notes or "",
  }
end

--- @param context _99.Prompt
--- @param response string
local function create_search_locations(context, response)
  local lines = vim.split(response, "\n")
  local qf_list = {}

  for _, line in ipairs(lines) do
    local res = parse_line(line)
    if res then
      table.insert(qf_list, res)
    end
  end
  context.data = {
    type = "search",
    qfix_items = qf_list,
  }

  if #qf_list > 0 then
    require("99").qfix_search_results(context.xid)
  else
    vim.notify("No search results found", vim.log.levels.INFO)
  end
end

--- @param context _99.Prompt
---@param opts _99.ops.SearchOpts
local function search(context, opts)
  opts = opts or {}

  local logger = context.logger:set_area("search")
  logger:debug("search", "with opts", opts.additional_prompt)

  local clean_up = make_clean_up(function()
    context:stop()
  end)

  local prompt, refs =
    make_prompt(context, context._99.prompts.prompts.semantic_search(), opts)

  context:add_prompt_content(prompt)
  context:add_references(refs)
  context:add_clean_up(clean_up)

  --- TODO: part of the context request clean up there needs to be a refactoring of
  --- make observer... it really should just be within the context observer creation.
  --- same with cleanup.. that should just be clean_ups from context, instead of a
  --- once cleanup function wrapper.
  ---
  --- i think an interface, CleanUpI could be something that is worth it :)
  context:start_request(make_observer(clean_up, function(status, response)
    if status == "cancelled" then
      logger:debug("request cancelled for search")
    elseif status == "failed" then
      logger:error(
        "request failed for search",
        "error response",
        response or "no response provided"
      )
    elseif status == "success" then
      create_search_locations(context, response)
    end
  end))
end
return search
