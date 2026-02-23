local Window = require("99.window")
local Consts = require("99.consts")
local Throbber = require("99.ops.throbber")

--- @param opts _99.InFlight.Opts | nil
--- @return _99.InFlight.Opts
local function default_opts(opts)
  opts = opts or {}
  opts.throbber_opts = opts.throbber_opts
    or {
      throb_time = Consts.throbber_throb_time,
      cooldown_time = Consts.throbber_cooldown_time,
      tick_time = Consts.throbber_tick_time,
    }
  opts.in_flight_interval = opts.in_flight_interval
    or Consts.show_in_flight_requests_loop_time
  opts.enable = opts.enable == nil and true or opts.enable
  return opts
end

--- @param _99 _99.State
local function shut_down_in_flight_requests_window(_99)
  if _99.show_in_flight_requests_throbber then
    _99.show_in_flight_requests_throbber:stop()
  end

  local win = _99.show_in_flight_requests_window
  if win ~= nil then
    Window.close(win)
  end
  _99.show_in_flight_requests_window = nil
  _99.show_in_flight_requests_throbber = nil
end

--- @class _99.InFlight.Opts
--- this is pure a class for testing.   helps controls timings
--- @docs include
--- @field throbber_opts _99.Throbber.Opts | nil
--- options for the throbber in the top left
--- @field in_flight_interval number | nil
--- frequency in which the in-flight interval checks to see if it should be
--- displayed / removed
--- @field enable boolean | nil
--- defaults to true

--- @param _99 _99.State
--- @param opts _99.InFlight.Opts | nil
local function show_in_flight_requests(_99, opts)
  --- TODO: I dont like this.  i dont like that i have to redo this every single
  --- time i cycle, but its not a big deal right now.  either way ill address this later
  opts = default_opts(opts)
  if opts.enable == false then
    return
  end
  vim.defer_fn(function()
    show_in_flight_requests(_99, opts)
  end, opts.in_flight_interval)

  Window.refresh_active_windows()
  local current_win = _99.show_in_flight_requests_window
  if current_win ~= nil and not Window.is_active_window(current_win) then
    shut_down_in_flight_requests_window(_99)
  end

  local active_window = Window.has_active_status_window()
  local active_other_window = Window.has_active_windows()
  local active_requests = _99:active_request_count()
  if
    active_window == false and active_other_window
    or active_window and active_requests > 0
    or active_window == false and active_requests == 0
  then
    return
  end

  if _99.show_in_flight_requests_window == nil then
    local ok, win = pcall(Window.status_window)
    if not ok then
      --- TODO: There needs to be a way to display logs for "all active requests"
      --- this is its own activity and should not be added to any work set
      return
    end

    local throb = Throbber.new(function(throb)
      local count = _99:active_request_count()
      local win_valid = Window.valid(win)

      if count == 0 or not win_valid then
        return shut_down_in_flight_requests_window(_99)
      end

      --- @type string[]
      local lines = {
        throb .. " requests(" .. tostring(count) .. ") " .. throb,
      }

      for _, c in pairs(_99.__request_by_id) do
        if c.state == "requesting" then
          table.insert(lines, c.operation)
        end
      end

      Window.resize(win, #lines[1], #lines)
      vim.api.nvim_buf_set_lines(win.buf_id, 0, -1, false, lines)
    end, opts.throbber_opts)

    _99.show_in_flight_requests_window = win
    _99.show_in_flight_requests_throbber = throb

    throb:start()
  end
end

return show_in_flight_requests
