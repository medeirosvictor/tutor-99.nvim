--- @class _99.window.Module
--- @field active_windows _99.window.Window[]
local M = {
    active_windows = {},
}
local nsid = vim.api.nvim_create_namespace("99.window.error")

--- @class _99.window.Config
--- @field width number
--- @field height number
--- @field row number?
--- @field col number?
--- @field anchor string?

--- @class _99.window.Window
--- @field config _99.window.Config
--- @field win_id number
--- @field buf_id number

--- @param lines string[]
--- @return string[]
local function ensure_no_new_lines(lines)
    local display_lines = {}
    for _, line in ipairs(lines) do
        local split_lines = vim.split(line, "\n")
        for _, clean_line in ipairs(split_lines) do
            table.insert(display_lines, clean_line)
        end
    end
    return display_lines
end

--- @return number
--- @return number
local function get_ui_dimensions()
    local ui = vim.api.nvim_list_uis()[1]
    return ui.width, ui.height
end

--- @return _99.window.Config
local function create_window_top_config()
    local width, _ = get_ui_dimensions()
    return {
        width = width - 2,
        height = 3,
        anchor = "NE",
    }
end

--- @return _99.window.Config
local function create_window_top_left_config()
    local width, _ = get_ui_dimensions()
    return {
        width = math.floor(width / 3),
        height = 3,
        anchor = "NE",
    }
end

--- @return _99.window.Config
local function create_window_full_screen()
    local width, height = get_ui_dimensions()
    return {
        width = width - 2,
        height = height - 2,
        anchor = "NE",
    }
end

--- @return _99.window.Config
local function create_centered_window()
    local width, height = get_ui_dimensions()
    local win_width = math.floor(width * 2 / 3)
    local win_height = math.floor(height / 3)
    return {
        width = win_width,
        height = win_height,
        row = math.floor((height - win_height) / 2),
        col = math.floor((width - win_width) / 2),
    }
end

--- @param config _99.window.Config
--- @return _99.window.Window
local function create_floating_window(config)
    local buf_id = vim.api.nvim_create_buf(false, true)
    local win_id = vim.api.nvim_open_win(buf_id, true, {
        relative = "editor",
        width = config.width,
        height = config.height,
        row = config.row or 0,
        col = config.col or 0,
        anchor = config.anchor,
        style = "minimal",
    })
    local window = {
        config = config,
        win_id = win_id,
        buf_id = buf_id,
    }
    vim.wo[win_id].wrap = true

    table.insert(M.active_windows, window)
    return window
end

--- @param window _99.window.Window
local function highlight_error(window)
    local line_count = vim.api.nvim_buf_line_count(window.buf_id)

    if line_count > 0 then
        vim.api.nvim_buf_set_extmark(window.buf_id, nsid, 0, 0, {
            end_row = 1,
            hl_group = "Normal",
            hl_eol = true,
        })
    end

    if line_count > 1 then
        vim.api.nvim_buf_set_extmark(window.buf_id, nsid, 1, 0, {
            end_row = line_count,
            hl_group = "ErrorMsg",
            hl_eol = true,
        })
    end
end

--- @param error_text string
--- @return _99.window.Window
function M.display_error(error_text)
    local window = create_floating_window(create_window_top_config())
    local lines = vim.split(error_text, "\n")

    table.insert(lines, 1, "")
    table.insert(
        lines,
        1,
        "99: Fatal operational error encountered (error logs may have more in-depth information)"
    )

    vim.api.nvim_buf_set_lines(window.buf_id, 0, -1, false, lines)
    highlight_error(window)
    return window
end

--- @param window _99.window.Window
local function window_close(window)
    if vim.api.nvim_win_is_valid(window.win_id) then
        vim.api.nvim_win_close(window.win_id, true)
    end
    if vim.api.nvim_buf_is_valid(window.buf_id) then
        vim.api.nvim_buf_delete(window.buf_id, { force = true })
    end

    local found = false
    for i, w in ipairs(M.active_windows) do
        if w.buf_id == window.buf_id and w.win_id == window.win_id then
            found = true
            table.remove(M.active_windows, i)
            break
        end
    end

    assert(
        found,
        "somehow we have closed a window that did not belong to the windows library"
    )
end

--- @param text string
function M.display_cancellation_message(text)
    local config = create_window_top_left_config()
    local window = create_floating_window(config)
    local lines = vim.split(text, "\n")

    vim.api.nvim_buf_set_lines(window.buf_id, 0, -1, false, lines)

    vim.api.nvim_buf_set_extmark(window.buf_id, nsid, 0, 0, {
        end_row = vim.api.nvim_buf_line_count(window.buf_id),
        hl_group = "WarningMsg",
        hl_eol = true,
    })

    vim.defer_fn(function()
        window_close(window)
    end, 5000)

    return window
end

--- TODO: i dont like how the other interfaces have text being passed in
--- but this one is lines.  probably need to revisit this
--- @param lines string[]
function M.display_full_screen_message(lines)
    --- TODO: i really dislike that i am closing and opening windows
    --- i think it would be better to perserve the one that is already open
    --- but i just want this to work and then later... ohh much later, ill fix
    --- this basic nonsense
    M.clear_active_popups()
    local window = create_floating_window(create_window_full_screen())
    local display_lines = ensure_no_new_lines(lines)
    vim.api.nvim_buf_set_lines(window.buf_id, 0, -1, false, display_lines)
end

--- @param message string[]
function M.display_centered_message(message)
    M.clear_active_popups()
    local config = create_centered_window()
    local window = create_floating_window(config)
    local display_lines = ensure_no_new_lines(message)

    vim.api.nvim_buf_set_lines(window.buf_id, 0, -1, false, display_lines)

    return window
end

--- not worried about perf, we will likely only ever have 1 maybe 2 windows
--- ever open at the same time
function M.clear_active_popups()
    while #M.active_windows > 0 do
        local window = M.active_windows[1]
        window_close(window)
    end
end

return M
