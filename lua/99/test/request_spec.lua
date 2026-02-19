-- luacheck: globals describe it assert
local _99 = require("99")
local test_utils = require("99.test.test_utils")
local eq = assert.are.same

local content = {
  "local function foo()",
  "    -- TODO: implement",
  "end",
}

describe("request test", function()
  it("should replace visual selection with AI response", function()
    local p = test_utils.test_setup(content, 2, 1, "lua")
    local state = _99.__get_state()
    local Request = require("99.request")
    local RequestContext = require("99.request-context")

    local context = RequestContext.from_current_buffer(state, 100)
    context.operation = "test_request"
    context:finalize()

    local request = Request.new(context)

    local finished_called = false
    local finished_status = nil

    eq("ready", request.state)

    eq(0, state:active_request_count())
    request:start({
      on_start = function()
        print("on_start")
      end,
      on_complete = function(status, _)
        finished_called = true
        finished_status = status
      end,
      on_stdout = function() end,
      on_stderr = function() end,
    })
    test_utils.next_frame()
    eq(1, state:active_request_count())

    eq("requesting", request.state)

    p:resolve("success", "    return 'implemented!'")
    assert.is_true(finished_called)

    eq(0, state:active_request_count())
    eq("success", request.state)
    eq("success", finished_status)
  end)
end)
