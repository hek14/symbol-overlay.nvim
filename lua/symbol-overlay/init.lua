local util = require('core.utils') -- TODO: remove this when publish
local M = {}
local changed_ticks = {}
local persistent_marks = {}
local child_thread = {}
local t = {}
local clear_by_autocmd = {}
local group = vim.api.nvim_create_augroup('symbol-overlay',{clear=true})
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
local colors = require('symbol-overlay.colors')
local uv = vim.loop
local protocol = require('vim.lsp.protocol')
local fmt = string.format

local document_highlight_kind = {
  [protocol.DocumentHighlightKind.Text] = 'read',
  [protocol.DocumentHighlightKind.Read] = 'read',
  [protocol.DocumentHighlightKind.Write] = 'write'
}

local function point_in_range(point, range)
    if point.line == range['start']['line'] and point.character < range['start']['character'] then
        return false
    end
    if point.line == range['end']['line'] and point.character > range['end']['character'] then
        return false
    end
    return point.line >= range['start']['line'] and point.line <= range['end']['line']
end

local function r1_smaller_than_r2(r1, r2)
  if r1['start'].line < r2['start'].line then return true end
  if r2['start'].line < r1['start'].line then return false end
  if r1['start'].character < r2['start'].character then return true end
  return false
end

local function search(buf_highlights,range)
  -- To find: buf_highlights[index] <= loc < buf_highlights[index+1]
  local total_len = #buf_highlights
  if total_len == 1 then
    if r1_smaller_than_r2(buf_highlights[1], range) then
      return 2
    else
      return 1
    end
  end

  if total_len == 2 then
    if r1_smaller_than_r2(range,buf_highlights[1]) then
      return 1
    else
      if r1_smaller_than_r2(range, buf_highlights[2]) then
        return 2
      else
        return 3
      end
    end
  end

  local left,right = 1,#buf_highlights
  if r1_smaller_than_r2(range,buf_highlights[1]) then
    return 1
  end
  if not r1_smaller_than_r2(range,buf_highlights[#buf_highlights]) then
    return #buf_highlights + 1
  end

  local mid = math.floor((left+right)/2) -- [left,right)
  while true do
    if not r1_smaller_than_r2(range,buf_highlights[mid]) then
      left = mid
    else
      right = mid
    end
    mid = math.floor((left+right)/2) -- [left,right)
    if (right-left)<=1 then
      break
    end
  end
  return right
end

local hit_ns = function(ranges,current)
  local to_insert = search(ranges,current)
  if to_insert>1 then
    if point_in_range(current['start'],ranges[to_insert-1]) then
      return ranges[to_insert-1]['ns']
    end
  end
  return nil
end

local function range(bufnr, ns, higroup, start, finish)
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
    local mark = range(bufnr,ns,hl_groups[i],r['start'],r['end'])
    table.insert(marks,{mark=mark,ns=ns})
  end
  return marks
end

local marks2ranges = function(marks,bufnr)
    local ranges = {} 
    for i, m in ipairs(marks) do
      local mark = m['mark']
      local ns = m['ns']
      local loc = vim.api.nvim_buf_get_extmark_by_id(bufnr,ns,mark,{details=true})
      local _start = {line = loc[1], character = loc[2]}
      local _end = {line = loc[3].end_row, character = loc[3].end_col}
      table.insert(ranges,{start=_start,['end']=_end,ns=ns})
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
  color_index = color_index + 1
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
  local ranges = marks2ranges(marks,bufnr)
  p("persistent_marks: ",persistent_marks)
  p('ranges: ',ranges)
end

function M.highlight()
  M.clear()
  local bufnr = vim.api.nvim_get_current_buf()
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
      print("the buffer is changed since the last highlight request")
      changed_ticks[bufnr] = vim.b.changedtick
    end
  end)
end

function M.clear()
  local bufnr = vim.api.nvim_get_current_buf()
  if (not persistent_marks[bufnr]) or (#persistent_marks[bufnr]==0) then
    return
  end
  local position = vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win())
  local make_range = {
    ['start'] = {line=position[1]-1,character=position[2]},
    ['end']   = {line=position[1]-1,character=position[2]+1}
  }
  local ranges = marks2ranges(persistent_marks[bufnr],bufnr)

  local cb = uv.new_async(vim.schedule_wrap(function()
    table.sort(ranges, r1_smaller_than_r2)
    local found_ns = hit_ns(ranges,make_range)
    if found_ns then
      vim.api.nvim_buf_clear_namespace(bufnr,found_ns,0,-1)
      del_marks(bufnr,found_ns)
    end
  end))

  if child_thread[bufnr] then
    uv.thread_join(child_thread[bufnr])
  end
  child_thread[bufnr] = uv.new_thread(function(asy)
    asy:send()
  end,cb)
end

function M.clear_all()
  local bufnr = vim.api.nvim_get_current_buf()
  if (not persistent_marks[bufnr]) or (#persistent_marks[bufnr]==0) then
    return
  end
  local cb = uv.new_async(vim.schedule_wrap(function()
    local all_ns = {}
    for i,m in ipairs(persistent_marks[bufnr]) do
      if not vim.tbl_contains(all_ns,m.ns) then
        table.insert(all_ns,m.ns)
      end
    end
    for _,ns in ipairs(all_ns) do
      vim.api.nvim_buf_clear_namespace(bufnr,ns,0,-1)
    end
    persistent_marks[bufnr] = {}
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
    M.highlight()
    return
  end

  local position = vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win())
  local make_range = {
    ['start'] = {line=position[1]-1,character=position[2]},
    ['end']   = {line=position[1]-1,character=position[2]+1}
  }
  local ranges = marks2ranges(persistent_marks[bufnr],bufnr)
  table.sort(ranges, r1_smaller_than_r2)
  local found_ns = hit_ns(ranges,make_range)
  if found_ns then
    vim.api.nvim_buf_clear_namespace(bufnr,found_ns,0,-1)
    del_marks(bufnr,found_ns)
  else
    M.highlight()
  end
end

local function goto_range(r)
  local start = r.start
  vim.cmd("normal! m'")
  vim.api.nvim_win_set_cursor(0,{start.line+1,start.character})
  vim.cmd("normal! zv")
end

function M.next_highlight(direction)
  local bufnr = vim.api.nvim_get_current_buf()
  if (not persistent_marks[bufnr]) or (#persistent_marks[bufnr]==0) then
    print('nothing todo')
    return
  end
  local position = vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win())
  local make_range = {
    ['start'] = {line=position[1]-1,character=position[2]},
    ['end']   = {line=position[1]-1,character=position[2]+1}
  }
  local ranges = marks2ranges(persistent_marks[bufnr],bufnr)
  local to_insert = search(ranges,make_range)
  if to_insert==1 then
    if direction==1 then
      goto_range(ranges[1])
    else
      goto_range(ranges[#ranges])
    end
  else
    if direction==1 then
      if to_insert > #ranges then
        goto_range(ranges[1])
      else
        goto_range(ranges[to_insert])
      end
    else
      if point_in_range(make_range['start'],ranges[to_insert-1]) then
        if to_insert > 2 then
          goto_range(ranges[to_insert-2])
        else
          goto_range(ranges[#ranges])
        end
      else
        goto_range(ranges[to_insert-1])
      end
    end
  end
end

return M
