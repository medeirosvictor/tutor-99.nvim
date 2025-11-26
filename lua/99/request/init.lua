local Logger = require("99.logger.logger")
local editor = require("99.editor")
local geo = require("99.geo")
local Point = geo.Point

--- TODO: some people change their current working directory as they open new
--- directories.  if this is still the case in neovim land, then we will need
--- to make the _99_state have the project directory.
--- @return string
local function random_file()
	return string.format("%s/tmp/99-%d", vim.uv.cwd(), math.floor(math.random() * 10000))
end

--- no, i am not going to use a uuid, in case of collision, call the police
--- @return string
local function get_id()
	return tostring(math.floor(math.random() * 100000000))
end

--- @alias _99.Request.State "ready" | "calling-model" | "parsing-result" | "updating-file"

--- @class _99.Request.Opts
--- @field model string
--- @field md_files string[]

--- @class _99.Request
--- @field query string
--- @field tmp_name string
--- @field state _99.Request.State
--- @field buffer number
--- @field model string
--- @field id string
--- @field mark string
--- @field scopes Scope
--- @field system_prompt string
local Request = {}
Request.__index = Request

--- @param opts _99.Request.Opts
function Request.new(opts)
    assert(opts.model, "you must provide a model for hange requests to work")

	local ts = editor.treesitter
	local cursor = Point:from_cursor()
	local scopes = ts.function_scopes(cursor)
	local buffer = vim.api.nvim_get_current_buf()

    return setmetatable({
        cursor = cursor,
        scopes = scopes,
        buffer = buffer,
        model = opts.model,
        tmp_name = random_file(),
        id = get_id(),
        state = "ready",
        mark = "",
    }, Request)
end

function Request:has_scopes()
    return self.scopes ~= nil and #self.scopes.range > 0
end

function Request:get_inner_scope()
    assert(self:has_scopes(), "you cannot get inner scope if you dont have scopes")
    return self.scopes.range[#self.scopes.range]
end

--- @param prompt string
function Request:set_system_prompt(prompt)
    self.system_prompt = prompt
end

function Request:_retrieve_response()
	local success, result = pcall(function()
		return vim.fn.readfile(self.tmp_name)
	end)

	if not success then
		Logger:error("retrieve_results: failed to read file", "tmp_name", self.tmp_name, "error", result)
		return false, ""
	end

	return true, table.concat(result, "\n")
end

--- @param res string
function Request:_update_file_with_changes(res)
	local mark_pos = vim.api.nvim_buf_get_mark(self.buffer, self.mark)
	local mark_point = Point:new(mark_pos[1], mark_pos[2] + 1)

	local ts = editor.treesitter
	local scopes = ts.function_scopes(mark_point, self.buffer)
    print("update_file_with_changes buffer", self.buffer)

	if not scopes or not scopes:has_scope() then
		Logger:error("update_file_with_changes: unable to find function at mark location")
        error("update_file_with_changes: funable to find function at mark location")
		return
	end

	local range = scopes.range[#scopes.range]

	local function_start_row, _ = range.start:to_vim()
	local function_end_row, _ = range.end_:to_vim()

	local lines = vim.split(res, "\n")
	vim.api.nvim_buf_set_lines(self.buffer, function_start_row, function_end_row + 1, false, lines)

    local stuff = {
        buffer = self.buffer,
        f_start = function_start_row,
        f_end = function_end_row,
        res = res
    }
    print("setting lines in buffer", vim.inspect(stuff))
end

function Request:start()
    local query = self.system_prompt
	Logger:debug("99#make_query", "id", self.id, "query", query)
	vim.system({ "opencode", "run", "-m", "anthropic/claude-sonnet-4-5", query }, {
		text = true,
		stdout = vim.schedule_wrap(function(err, data)
			Logger:debug("STDOUT#data", "id", self.id, "data", data)
			Logger:debug("STDOUT#error", "id", self.id, "err", err)
		end),
		stderr = vim.schedule_wrap(function(err, data)
			Logger:debug("STDERR#data", "id", self.id, "data", data)
			Logger:debug("STDERR#error", "id", self.id, "err", err)
		end),
	}, function(obj)
		if obj.code ~= 0 then
			Logger:fatal("opencode make_query failed", "request", self, "obj from results", obj)
			return
		end
		vim.schedule(function()
			local ok, res = self:_retrieve_response()
			if ok then
				self:_update_file_with_changes(res)
			end
            print("finished")
		end)
	end)
end

return Request
