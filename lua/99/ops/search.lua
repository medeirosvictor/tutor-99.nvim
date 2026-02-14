local Request = require("99.request")
local make_clean_up = require("99.ops.clean-up")
local make_prompt = require("99.ops.make-prompt")

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

--- @param _99 _99.State
--- @param response string
local function create_search_locations(_99, response)
  _ = _99
  local lines = vim.split(response, "\n")
  local qf_list = {}

  for _, line in ipairs(lines) do
    local res = parse_line(line)
    if res then
      table.insert(qf_list, res)
    end
  end

  if #qf_list > 0 then
    vim.fn.setqflist(qf_list, "r")
    vim.cmd("copen")
  else
    vim.notify("No search results found", vim.log.levels.INFO)
  end
end

--- @param context _99.RequestContext
---@param opts _99.ops.SearchOpts
local function search(context, opts)
  opts = opts or {}

  local logger = context.logger:set_area("search")
  local request = Request.new(context)

  logger:debug("search", "with opts", opts.additional_prompt)

  local clean_up = make_clean_up(context, "Search", function()
    request:cancel()
  end)

  local prompt, rules, refs =
    make_prompt(context, context._99.prompts.prompts.semantic_search(), opts)

  context:add_agent_rules(rules)
  request:add_prompt_content(prompt)
  context:add_references(refs)

  request:start({
    on_complete = function(status, response)
      vim.schedule(clean_up)
      if status == "cancelled" then
        logger:debug("request cancelled for search")
      elseif status == "failed" then
        logger:error(
          "request failed for search",
          "error response",
          response or "no response provided"
        )
      elseif status == "success" then
        create_search_locations(context._99, response)
      end
    end,
    on_stdout = function(line)
      --- TODO: i need to figure out how to surface this information
      _ = line
    end,
    on_stderr = function(line)
      logger:debug("visual_selection#on_stderr received", "line", line)
    end,
  })
end
return search
