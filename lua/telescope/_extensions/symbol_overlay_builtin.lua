local actions = require'telescope.actions'
local actions_set = require'telescope.actions.set'
local actions_state = require'telescope.actions.state'
local conf = require'telescope.config'.values
local entry_display = require'telescope.pickers.entry_display'
local finders = require'telescope.finders'
local from_entry = require'telescope.from_entry'
local pickers = require'telescope.pickers'
local previewers = require'telescope.previewers.term_previewer'
local utils = require'telescope.utils'
local Sorters = require'telescope.sorters'
local Path = require('plenary.path')
local lsp_num_to_str = require('symbol-overlay.util').lsp_num_to_str

local os_home = vim.loop.os_homedir()

local M = {}

local function get_symbol_overlay(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local persistent_marks = require('symbol-overlay')._get_persistent_marks()
  if persistent_marks[bufnr] == nil then
    return {}
  end
  local ranges = require('symbol-overlay').marks2ranges(persistent_marks[bufnr],bufnr,false)
  for i,r in ipairs(ranges) do
    if r.start.line == r['end'].line then
      local line = vim.api.nvim_buf_get_lines(bufnr, r.start.line, r.start.line + 1, false)[1]
      ranges[i].text = string.sub(line,r.start.character+1,r['end'].character)
      ranges[i].line = string.gsub(line,' ','')
      ranges[i].kind = lsp_num_to_str[r.kind] -- defined in core.utils
      ranges[i].bufnr = bufnr
      ranges[i].path = vim.api.nvim_buf_get_name(bufnr)
      ranges[i].lnum = r.start.line + 1
      ranges[i].col = r.start.character + 1
    end
  end
  return ranges
end

local function entry_maker_symbol_overlay(opts)
  local displayer = entry_display.create{
    separator = ' ',
    items = {
      {width = 30, right_justify = false},
      {remaining = true},
    },
  }
  local function make_display(entry)
    return displayer{
      {('%s: %s'):format(entry.kind,entry.value), entry.hl_group},
      {('%s'):format(entry.line), entry.hl_group},
    }
  end

  return function(entry)
    -- vim.pretty_print(entry)
    return vim.tbl_extend('force',{
      value = entry.text,
      ordinal = entry.text .. entry.kind .. entry.line,
      display = make_display,
    },entry)
  end
end

M.list = function(opts)
  opts = opts or {}
  local cmd = vim.F.if_nil(opts.cmd, {vim.o.shell, '-c', 'z -l'})
  opts.cwd = utils.get_lazy_default(opts.cwd, vim.loop.cwd)
  opts.entry_maker = utils.get_lazy_default(opts.entry_maker, entry_maker_symbol_overlay, opts)

  pickers.new(opts, {
    prompt_title = 'Symbol Overlays',
    previewer = conf.qflist_previewer(opts),
    sorter = conf.generic_sorter(opts),
    finder = finders.new_table{
      results = get_symbol_overlay(),
      entry_maker = opts.entry_maker,
    },
    attach_mappings = function(prompt_bufnr)
      actions_set.select:enhance {
        post = function()
          local selection = actions_state.get_selected_entry()
          vim.api.nvim_win_set_cursor(0, { selection.lnum, selection.col })
        end,
      }
      return true
    end,
  }):find()
end

M.choose = function ()
end

return M
