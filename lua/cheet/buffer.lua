-- Buffer: manages lines and highlights together
local Buffer = {}
Buffer.__index = Buffer

function Buffer:new()
  return setmetatable({ lines = {}, highlights = {} }, Buffer)
end

-- Add a line, optionally highlighting the whole line
function Buffer:add(text, hl_group)
  table.insert(self.lines, text)
  if hl_group then
    table.insert(self.highlights, { #self.lines, hl_group, 0, -1 })
  end
  return self
end

-- Add highlight to the current (last) line at specific columns
function Buffer:hl(hl_group, col_start, col_end)
  table.insert(self.highlights, { #self.lines, hl_group, col_start, col_end })
  return self
end

-- Get the last line's text length
function Buffer:last_len()
  return #self.lines[#self.lines]
end

function Buffer:get()
  return self.lines, self.highlights
end

return Buffer
