-- cheet.nvim - YAML-based cheatsheet viewer for Neovim
-- Supports floating window and Telescope modes
local M = {}
local yaml = require('cheet.tinyyaml')

-- Telescope modules (lazy-loaded)
local pickers, finders, conf, actions, action_state, entry_display

local WIDTH = 81
local default_paths = { '~/.config/vim-cheatsheet.yaml' }
local config = { paths = default_paths }

-- Setup function for user configuration
function M.setup(opts)
  opts = opts or {}
  if opts.paths then
    config.paths = opts.paths
  end
end

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

-- Parse a single YAML config file
local function parse_config(filepath)
  local file = io.open(filepath, 'r')
  if not file then
    return nil, 'Could not open file: ' .. filepath
  end

  local content = file:read('*all')
  file:close()

  local ok, data = pcall(yaml.parse, content)
  if not ok then
    return nil, 'Failed to parse YAML: ' .. tostring(data)
  end

  return data
end

-- Load and merge all cheatsheets from configured paths
local function load_all_cheatsheets()
  local all = {}
  for _, path in ipairs(config.paths) do
    local expanded = vim.fn.expand(path)
    local data, _ = parse_config(expanded)
    if data and data.cheatsheets then
      for _, cs in ipairs(data.cheatsheets) do
        table.insert(all, cs)
      end
    end
  end
  return all
end

-- Get list of available cheatsheet IDs
local function get_cheatsheet_ids()
  local cheatsheets = load_all_cheatsheets()
  local ids = {}
  for _, sheet in ipairs(cheatsheets) do
    table.insert(ids, sheet.id)
  end
  return ids
end

-- Find cheatsheet by ID from all loaded cheatsheets
local function find_cheatsheet(id)
  local cheatsheets = load_all_cheatsheets()
  for _, sheet in ipairs(cheatsheets) do
    if sheet.id == id then
      return sheet
    end
  end
  return nil
end

-- Get the first available cheatsheet
local function get_first_cheatsheet()
  local cheatsheets = load_all_cheatsheets()
  return cheatsheets[1]
end

local function build_header(buf, cs_data)
  local title = cs_data.title or 'CHEATSHEET'
  local header_line = string.format('|%s|',
    string.rep(' ', math.floor((WIDTH - 2 - #title) / 2)) ..
    title ..
    string.rep(' ', math.ceil((WIDTH - 2 - #title) / 2)))

  buf:add('+' .. string.rep('=', WIDTH - 2) .. '+', 'HlHeader')
  buf:add(header_line, 'HlHeader')
  buf:add('+' .. string.rep('=', WIDTH - 2) .. '+', 'HlHeader')
  buf:add('')
end

local function build_plugins_section(buf, entries)
  local col_width = 40
  for i = 1, #entries, 2 do
    local e1 = entries[i]
    local e2 = entries[i + 1]

    local left = string.format('  %-14s %s', e1.key, e1.desc or '')
    local right = e2 and string.format('%-14s %s', e2.key, e2.desc or '') or ''

    buf:add(left .. string.rep(' ', col_width - #left) .. right)
    buf:hl('HlPlugin', 2, 2 + #e1.key)
    if e2 then
      buf:hl('HlPlugin', col_width, col_width + #e2.key)
    end
  end
end

local function build_settings_section(buf, entries)
  local parts = {}
  for _, entry in ipairs(entries) do
    table.insert(parts, { key = entry.key, desc = entry.desc })
  end

  for i = 1, #parts, 3 do
    local line_parts = {}
    local col_positions = {}
    local col = 2

    for j = 0, 2 do
      local p = parts[i + j]
      if p then
        local part = p.key .. ': ' .. p.desc
        table.insert(line_parts, part)
        table.insert(col_positions, { value_start = col + #p.key + 2, value_len = #p.desc })
        col = col + #part + 4
      end
    end

    buf:add('  ' .. table.concat(line_parts, '    '))
    for _, pos in ipairs(col_positions) do
      buf:hl('HlValue', pos.value_start, pos.value_start + pos.value_len)
    end
  end
end

local function build_keybindings_section(buf, entries)
  for _, entry in ipairs(entries) do
    local key = entry.key or ''
    local desc = entry.desc or ''
    local prefix = entry.arrow and '-> ' or ''
    local note = entry.note and (' ' .. entry.note) or ''

    buf:add(string.format('  %-18s    %s%s%s', key, prefix, desc, note))
    buf:hl('HlKey', 2, 2 + #key)

    if entry.note then
      buf:hl('HlDim', buf:last_len() - #entry.note, buf:last_len())
    end
  end
end

-- Build content lines from cheatsheet data
local function build_content(cs_data)
  local buf = Buffer:new()

  build_header(buf, cs_data)

  for _, section in ipairs(cs_data.sections) do
    local section_header = '--- ' .. section.name .. ' '
    buf:add(section_header .. string.rep('-', WIDTH - #section_header), 'HlSection')

    if section.type == 'plugins' then
      build_plugins_section(buf, section.entries)
    elseif section.type == 'settings' then
      build_settings_section(buf, section.entries)
    else
      build_keybindings_section(buf, section.entries)
    end

    buf:add('')
  end

  local footer = 'Press / to search, <Esc> or q to close'
  buf:add(string.rep(' ', math.floor((WIDTH - #footer) / 2)) .. footer, 'HlDim')

  return buf:get()
end

-- Define highlight groups
local function setup_highlights()
  vim.api.nvim_set_hl(0, 'HlHeader', { fg = '#5fafaf', bold = true })
  vim.api.nvim_set_hl(0, 'HlSection', { fg = '#d7af5f', bold = true })
  vim.api.nvim_set_hl(0, 'HlKey', { fg = '#5faf5f', bold = true })
  vim.api.nvim_set_hl(0, 'HlPlugin', { fg = '#af87d7' })
  vim.api.nvim_set_hl(0, 'HlValue', { fg = '#5fafaf' })
  vim.api.nvim_set_hl(0, 'HlDim', { fg = '#808080' })
end

-- Apply highlights to buffer
local function apply_highlights(buf, highlights)
  local ns = vim.api.nvim_create_namespace('cheet')
  for _, hl in ipairs(highlights) do
    local row, group, col_start, col_end = hl[1], hl[2], hl[3], hl[4]
    vim.api.nvim_buf_add_highlight(buf, ns, group, row - 1, col_start, col_end)
  end
end

local function create_window(lines, highlights, cheatsheet_id)
  -- Calculate window size
  local height = #lines
  local ui = vim.api.nvim_list_uis()[1]
  local col = math.floor((ui.width - WIDTH) / 2)
  local row = math.floor((ui.height - height) / 2)

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Buffer options
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_option(buf, 'filetype', 'cheet')

  -- Create floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = WIDTH,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded',
  })

  -- Window options
  vim.api.nvim_win_set_option(win, 'cursorline', true)
  vim.api.nvim_win_set_option(win, 'winblend', 0)

  -- Apply syntax highlighting
  apply_highlights(buf, highlights)

  -- Close on Esc or q
  for _, key in ipairs({ '<Esc>', 'q' }) do
    vim.api.nvim_buf_set_keymap(buf, 'n', key, ':close<CR>', {
      noremap = true,
      silent = true,
      nowait = true,
    })
  end

  -- Close when cursor leaves the buffer
  vim.api.nvim_create_autocmd('BufLeave', {
    buffer = buf,
    once = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })

  -- Allow search with /
  vim.api.nvim_buf_set_keymap(buf, 'n', '/', '/', { noremap = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', 'n', 'n', { noremap = true })
  vim.api.nvim_buf_set_keymap(buf, 'n', 'N', 'N', { noremap = true })

  -- Switch to Telescope mode with <Tab>
  vim.keymap.set('n', '<Tab>', function()
    vim.api.nvim_win_close(win, true)
    M.telescope(cheatsheet_id)
  end, { buffer = buf, noremap = true, silent = true })
end

function M.open(id)
  setup_highlights()

  local cheatsheet
  if id and id ~= '' then
    cheatsheet = find_cheatsheet(id)
    if not cheatsheet then
      vim.notify('Cheet: No cheatsheet found with id "' .. id .. '"', vim.log.levels.ERROR)
      return
    end
  else
    cheatsheet = get_first_cheatsheet()
    if not cheatsheet then
      vim.notify('Cheet: No cheatsheets found in configured paths', vim.log.levels.ERROR)
      return
    end
  end

  local lines, highlights = build_content(cheatsheet)

  create_window(lines, highlights, cheatsheet.id)
end


-- Tab completion for cheatsheet IDs
local function complete_cheatsheet(arg_lead, _, _)
  local ids = get_cheatsheet_ids()
  local matches = {}
  for _, id in ipairs(ids) do
    if id:find('^' .. arg_lead) then
      table.insert(matches, id)
    end
  end
  return matches
end

-- Load Telescope modules (lazy)
local function load_telescope()
  if pickers then return true end

  local ok, _ = pcall(require, 'telescope')
  if not ok then
    vim.notify('Cheet: Telescope is required for fuzzy search', vim.log.levels.ERROR)
    return false
  end

  pickers = require('telescope.pickers')
  finders = require('telescope.finders')
  conf = require('telescope.config').values
  actions = require('telescope.actions')
  action_state = require('telescope.actions.state')
  entry_display = require('telescope.pickers.entry_display')
  return true
end

-- Flatten cheatsheet data into a list of searchable entries
local function flatten_entries(cs_data)
  local entries = {}

  for _, section in ipairs(cs_data.sections) do
    for _, entry in ipairs(section.entries) do
      table.insert(entries, {
        section = section.name,
        key = entry.key or '',
        desc = entry.desc or '',
        note = entry.note,
        arrow = entry.arrow,
        type = section.type or 'keybinding',
      })
    end
  end

  return entries
end

-- Open cheatsheet in Telescope picker
function M.telescope(id)
  if not load_telescope() then return end

  local cheatsheet
  if id and id ~= '' then
    cheatsheet = find_cheatsheet(id)
    if not cheatsheet then
      vim.notify('Cheet: No cheatsheet found with id "' .. id .. '"', vim.log.levels.ERROR)
      return
    end
  else
    cheatsheet = get_first_cheatsheet()
    if not cheatsheet then
      vim.notify('Cheet: No cheatsheets found in configured paths', vim.log.levels.ERROR)
      return
    end
  end

  local entries = flatten_entries(cheatsheet)

  local displayer = entry_display.create({
    separator = ' ',
    items = {
      { width = 20 },  -- key
      { width = 15 },  -- section
      { remaining = true },  -- description
    },
  })

  local make_display = function(entry)
    local desc = entry.value.desc
    if entry.value.arrow then
      desc = '-> ' .. desc
    end
    if entry.value.note then
      desc = desc .. ' ' .. entry.value.note
    end

    return displayer({
      { entry.value.key, 'TelescopeResultsIdentifier' },
      { entry.value.section, 'TelescopeResultsComment' },
      { desc, 'TelescopeResultsNormal' },
    })
  end

  pickers.new({}, {
    prompt_title = cheatsheet.title or 'Cheatsheet',
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        local ordinal = entry.key .. ' ' .. entry.section .. ' ' .. entry.desc
        return {
          value = entry,
          display = make_display,
          ordinal = ordinal,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection and selection.value.key then
          vim.fn.setreg('+', selection.value.key)
          vim.notify('Copied: ' .. selection.value.key, vim.log.levels.INFO)
        end
      end)

      -- Switch to float mode with <Tab>
      map({ 'i', 'n' }, '<Tab>', function()
        actions.close(prompt_bufnr)
        M.open(cheatsheet.id)
      end)

      return true
    end,
  }):find()
end

-- Open cheatsheet using configured display mode
function M.show(id)
  local cheatsheet
  if id and id ~= '' then
    cheatsheet = find_cheatsheet(id)
    if not cheatsheet then
      vim.notify('Cheet: No cheatsheet found with id "' .. id .. '"', vim.log.levels.ERROR)
      return
    end
  else
    cheatsheet = get_first_cheatsheet()
    if not cheatsheet then
      vim.notify('Cheet: No cheatsheets found in configured paths', vim.log.levels.ERROR)
      return
    end
  end

  local display_mode = cheatsheet.display or 'telescope'

  if display_mode == 'float' then
    M.open(id)
  else
    M.telescope(id)
  end
end

-- Create user commands with completion
vim.api.nvim_create_user_command('Cheet', function(opts)
  M.show(opts.args)
end, {
  nargs = '?',
  complete = complete_cheatsheet,
  desc = 'Open cheatsheet using configured display mode',
})

vim.api.nvim_create_user_command('CheetFloat', function(opts)
  M.open(opts.args)
end, {
  nargs = '?',
  complete = complete_cheatsheet,
  desc = 'Open cheatsheet in floating window (optional: specify id)',
})

vim.api.nvim_create_user_command('CheetTelescope', function(opts)
  M.telescope(opts.args)
end, {
  nargs = '?',
  complete = complete_cheatsheet,
  desc = 'Open cheatsheet in Telescope (optional: specify id)',
})

return M
