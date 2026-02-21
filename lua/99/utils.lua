local M = {}

function M.copy(t)
  assert(type(t) == "table", "passed in non table into table")
  local out = {}
  for k, v in pairs(t) do
    out[k] = v
  end
  for i, v in ipairs(t) do
    out[i] = v
  end
  return out
end

--- @param dir string
--- @return string
function M.random_file(dir)
  return string.format("%s/99-%d", dir, math.floor(math.random() * 10000))
end

--- @param dir string
--- @param name string
--- @return string
function M.named_tmp_file(dir, name)
  return string.format("%s/99-%s", dir, name)
end

return M
