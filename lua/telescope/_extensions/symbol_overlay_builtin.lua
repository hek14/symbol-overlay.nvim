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
      ranges[i].line = line:gsub('^ +',''):gsub(' +$','')
      ranges[i].kind = lsp_num_to_str[r.kind]
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
      {width = 25, right_justify = false},
      {remaining = true},
    },
  }
  local function make_display(entry)
    return displayer{
      {('%s: %s'):format(entry.kind,entry.value), "Normal"},
      {('%s'):format(entry.line), "Normal"},
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

M.gen = function(opts)
  local params = vim.lsp.util.make_position_params(opts.winnr or 0)
  vim.lsp.buf_request(opts.bufnr, "textDocument/documentSymbol", params, function(err, result, ctx, _)
    if err then
      vim.api.nvim_err_writeln("Error when finding document symbols: " .. err.message)
      return
    end

    if not result or vim.tbl_isempty(result) then
      utils.notify("builtin.lsp_document_symbols", {
        msg = "No results from textDocument/documentSymbol",
        level = "INFO",
      })
      return
    end

    local locations = vim.lsp.util.symbols_to_items(result or {}, opts.bufnr) or {}
    locations = utils.filter_symbols(locations, opts)
    print('ctx.bufnr',ctx.bufnr)
    for i,loc in ipairs(locations) do
      locations[i].bufnr = ctx.bufnr
    end
    if locations == nil then
      return
    end

    if vim.tbl_isempty(locations) then
      utils.notify("builtin.lsp_document_symbols", {
        msg = "No document_symbol locations found",
        level = "INFO",
      })
      return
    end

    opts.path_display = { "hidden" }
    pickers
    .new(opts, {
      prompt_title = "LSP Document Symbols",
      finder = finders.new_table {
        results = locations,
        entry_maker = opts.entry_maker or require"telescope.make_entry".gen_from_lsp_symbols(opts),
      },
      previewer = conf.qflist_previewer(opts),
      sorter = conf.prefilter_sorter {
        tag = "symbol_type",
        sorter = conf.generic_sorter(opts),
      },
      push_cursor_on_edit = true,
      push_tagstack_on_edit = true,
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function ()
          local picker = actions_state.get_current_picker(prompt_bufnr)
          local num_selections = #picker:get_multi_selection()
          if num_selections <= 1 then
            local entry = actions_state.get_selected_entry()
            vim.defer_fn(function ()
              require('symbol-overlay').toggle(entry.value.bufnr,{entry.value.lnum,entry.value.col-1})
            end,0)
          else
            for i, entry in ipairs(picker:get_multi_selection()) do
              vim.defer_fn(function ()
                require('symbol-overlay').toggle(entry.value.bufnr,{entry.value.lnum,entry.value.col-1})
              end,0)
            end
          end
          actions.close(prompt_bufnr)
        end)
        return true
      end
    })
    :find()
  end)
end

return M
