local M = {}
local changed_ticks = {}
local persistent_marks = {}
local child_thread = {}
local t = {}
local clear_by_autocmd = {}
local group = vim.api.nvim_create_augroup('symbol-overlay',{clear=true})
local autocmd_exe_timer = {}
t.__index = function(self,k)
  if type(k) == 'number' then
    return rawget(self,tostring(k))
  else
    return rawget(self,k)
  end
end
t.__newindex = function(self,k,v)
  if type(k) == 'number' then
    rawset(self,tostring(k),v)
  else
    rawset(self,k,v)
  end
end
setmetatable(persistent_marks,t)

local color_index = 1
local hl_offset_encoding = "utf-16"
local uv = vim.loop
local protocol = require('vim.lsp.protocol')
local fmt = string.format

local document_highlight_kind = {
  [protocol.DocumentHighlightKind.Text] = 'read',
  [protocol.DocumentHighlightKind.Read] = 'read',
  [protocol.DocumentHighlightKind.Write] = 'write'
}

local util = require('symbol-overlay.util')
local r1_smaller_than_r2 = util.r1_smaller_than_r2
local hit_ns = util.hit_ns

local function highlight_range(bufnr, ns, higroup, start, finish)
  local regtype = 'v'
  local inclusive = false
  local priority = 202

  -- sanity check
  if start[2] < 0 or finish[1] < start[1] then
    return
  end

  local region = vim.region(bufnr, start, finish, regtype, inclusive)
  for linenr, cols in pairs(region) do
    local end_row
    if cols[2] == -1 then
      end_row = linenr + 1
      cols[2] = 0
    end
    local mark = vim.api.nvim_buf_set_extmark(bufnr, ns, linenr, cols[1], {
      hl_group = higroup,
      end_row = end_row,
      end_col = cols[2],
      priority = priority,
      strict = false,
    })
    if mark then
      return mark
    end
  end
end

local ranges2marks = function(ranges,bufnr,hl_groups,ns)
  -- PARAMS: a range: {start={line=,character=}, end={line=,character=}}
  local marks = {}
  for i,r in ipairs(ranges) do
    r['start'][1] = r['start'].line
    r['start'][2] = r['start'].character
    r['end'][1] = r['end'].line
    r['end'][2] = r['end'].character
    local mark = highlight_range(bufnr,ns,hl_groups[i],r['start'],r['end'])
    table.insert(marks,{mark=mark,ns=ns})
  end
  return marks
end

local marks2ranges = function(marks,bufnr,sorted)
  local ranges = {} 
  for i, m in ipairs(marks) do
    local mark = m['mark']
    local ns = m['ns']
    local loc = vim.api.nvim_buf_get_extmark_by_id(bufnr,ns,mark,{details=true})
    local _start = {line = loc[1], character = loc[2]}
    local _end = {line = loc[3].end_row, character = loc[3].end_col}
    table.insert(ranges,{start=_start,['end']=_end,ns=ns})
  end
  if sorted then
    table.sort(ranges, r1_smaller_than_r2)
  end
  return ranges
end

local extract_ranges = function(result)
  local ranges = {}
  for _,res in ipairs(result) do
    table.insert(ranges,res.range)
  end
  return ranges
end

local function handle_document_highlight(result, bufnr)
  assert(persistent_marks[bufnr]~=nil,"not attached")
  local colors = require('symbol-overlay.config').get().hl_groups
  local hl_groups = {}
  for _,res in ipairs(result) do
    table.insert(hl_groups,colors[color_index][document_highlight_kind[res.kind]])
  end
  local ranges = extract_ranges(result)
  local ns = vim.api.nvim_create_namespace('')
  local marks = ranges2marks(ranges,bufnr,hl_groups,ns)
  for _,mark in ipairs(marks) do
    table.insert(persistent_marks[bufnr],mark)
  end
  color_index = color_index +1 <= #colors and color_index + 1 or 1
end

local function del_marks(bufnr,ns)
  local index = 1
  for i,m in ipairs(persistent_marks[bufnr]) do
    if m.ns ~= ns then
      persistent_marks[bufnr][index] = m
      index = index + 1
    end
  end
  if index==1 then
    persistent_marks[bufnr] = {} -- reset
  end
  for j = index,#persistent_marks[bufnr] do
    persistent_marks[bufnr][j] = nil
  end
end

function M.debug()
  local bufnr = vim.api.nvim_get_current_buf()
  local marks = persistent_marks[bufnr]
  local ranges = marks2ranges(marks,bufnr,true)
  vim.pretty_print("persistent_marks: ",persistent_marks)
  vim.pretty_print('ranges: ',ranges)
end

local new_highlight = function(bufnr)
  changed_ticks[bufnr] = vim.b.changedtick
  local highlight_params = vim.tbl_deep_extend("force",vim.lsp.util.make_position_params(),{offset_encoding=hl_offset_encoding})
  if persistent_marks[bufnr] == nil then
    persistent_marks[bufnr] = {}
  end
  vim.lsp.buf_request(bufnr, 'textDocument/documentHighlight', highlight_params, function(err, result, ctx, config)
    assert(not err,err)
    if not result or type(result)~='table' or #result == 0 then
      return
    end
    if vim.b.changedtick == changed_ticks[ctx.bufnr] then
      handle_document_highlight(result,ctx.bufnr)
    else
      print("the buffer is changed since the last request")
      changed_ticks[bufnr] = vim.b.changedtick
    end
  end)
end

local clear_ns = function(bufnr,ns)
  if ns~='*' then
    vim.api.nvim_buf_clear_namespace(bufnr,ns,0,-1)
    del_marks(bufnr,ns)
  else
    -- all
    local all_ns = {}
    for i,m in ipairs(persistent_marks[bufnr]) do
      if not vim.tbl_contains(all_ns,m.ns) then
        table.insert(all_ns,m.ns)
      end
    end
    for _,i_ns in ipairs(all_ns) do
      vim.api.nvim_buf_clear_namespace(bufnr,i_ns,0,-1)
    end
    persistent_marks[bufnr] = {}
  end
end

function M.clear_all()
  local bufnr = vim.api.nvim_get_current_buf()
  if (not persistent_marks[bufnr]) or (#persistent_marks[bufnr]==0) then
    return
  end
  local cb = uv.new_async(vim.schedule_wrap(function()
    clear_ns(bufnr,"*")
  end))

  if child_thread[bufnr] then
    uv.thread_join(child_thread[bufnr])
  end
  child_thread[bufnr] = uv.new_thread(function(asy)
    asy:send()
  end,cb)
end

function M.toggle()
  local bufnr = vim.api.nvim_get_current_buf()
  if (not persistent_marks[bufnr]) or (#persistent_marks[bufnr]==0) then
    new_highlight(bufnr)
    return
  end

  local position = vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win())
  local ranges = marks2ranges(persistent_marks[bufnr],bufnr,true)
  local res = hit_ns(ranges,position)
  if res[1] == 'in' then
    local found_ns = ranges[res.search]['ns']
    clear_ns(bufnr,found_ns)
  else
    new_highlight(bufnr)
  end
end

local function goto_range(r)
  local start = r.start
  vim.cmd("normal! m'")
  vim.api.nvim_win_set_cursor(0,{start.line+1,start.character})
end

function M.next_highlight()
  local position = vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win())
  local bufnr = vim.api.nvim_get_current_buf()
  local ranges = marks2ranges(persistent_marks[bufnr],bufnr,true)
  local res = hit_ns(ranges,position)
  if res[1] == 'after_all' or res[1] == 'before_all' then
    goto_range(ranges[1])
    return
  end
  if res[1] == 'in' and res.search==#ranges then
    goto_range(ranges[1])
    return
  end
  if res[1] == 'in' or res[1] == 'between' then
    goto_range(ranges[res.search+1])
    return
  end
end

function M.prev_highlight()
  local position = vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win())
  local bufnr = vim.api.nvim_get_current_buf()
  local ranges = marks2ranges(persistent_marks[bufnr],bufnr,true)
  local res = hit_ns(ranges,position)
  if res[1] == 'after_all' or res[1] == 'before_all' then
    goto_range(ranges[#ranges])
    return
  end
  if res[1] == 'in' and res.search==1 then
    goto_range(ranges[#ranges])
    return
  end

  if res[1] == 'in' then
    goto_range(ranges[res.search-1])
    return
  end

  if res[1] == 'between' then
    goto_range(ranges[res.search])
    return
  end
end

local function check_validity()
  local start = vim.loop.hrtime()
  local bufnr = vim.api.nvim_get_current_buf()
  if (not persistent_marks[bufnr]) or (#persistent_marks[bufnr]==0) then
    return
  end
  local ranges = marks2ranges(persistent_marks[bufnr],bufnr)
  local checked_range = {}
  local changed_ns = {}
  for _,r in ipairs(ranges) do
    if vim.tbl_contains(changed_ns,r.ns) then
      goto continue
    end
    if not checked_range[r.ns] then
      checked_range[r.ns] = {
        r['end']['line']-r['start']['line'],
        r['end']['character']-r['start']['character'],
      }
    else
      local relative_r = {
        r['end']['line']-r['start']['line'],
        r['end']['character']-r['start']['character'],
      }
      if not vim.deep_equal(relative_r,checked_range[r.ns]) then
        table.insert(changed_ns,r.ns)
      end
    end
    ::continue::
  end
  vim.pretty_print('need to clear_ns: ',changed_ns)
  for _,ns in ipairs(changed_ns) do
    clear_ns(bufnr,ns)
  end
  print('profile: ',(vim.loop.hrtime()-start)/1000000)
  if autocmd_exe_timer[bufnr] then
    autocmd_exe_timer[bufnr]:stop()
    autocmd_exe_timer[bufnr]:close()
    autocmd_exe_timer[bufnr] = nil
  end
end

vim.api.nvim_create_autocmd({'TextChanged','TextChangedI'},{
  callback = function ()
    local bufnr = vim.api.nvim_get_current_buf()
    if autocmd_exe_timer[bufnr] then
      print('still running the last timer')
    else
      autocmd_exe_timer[bufnr] = vim.loop.new_timer()
      autocmd_exe_timer[bufnr]:start(100,0,vim.schedule_wrap(check_validity))
    end
  end,
  group = group,
  desc = "keep the validity of marks: all marks of a specific ns should be all the same"
})

function M.setup(opts)
  require('symbol-overlay.config').set(opts)
end

return M
