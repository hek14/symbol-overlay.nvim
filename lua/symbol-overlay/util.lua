local function echo(hlgroup, msg)
  vim.cmd(fmt('echohl %s', hlgroup))
  vim.cmd(fmt('echo "[symbol-overlay] %s"', msg))
  vim.cmd('echohl None')
end

local function error(msg)
  echo('DiagnosticError', msg)
end

local function warn(msg)
  echo('DiagnosticWarn', msg)
end

local detect_lsp = function(bufnr)
  local clients = vim.lsp.get_active_clients({bufnr=bufnr})
  if #clients == 0 then
    error('No active lsp clients')
    return
  end
  local found_client
  for _,client in ipairs(clients) do
    if client.supports_method('textDocument/documentHighlight') then
      found_client = client.name
      break
    end
  end
  if not found_client then
    error('no client supports textDocument/documentHighlight')
  end
end

local function r1_smaller_than_r2(r1, r2)
  if r1['start'].line < r2['start'].line then return true end
  if r2['start'].line < r1['start'].line then return false end
  if r1['start'].character < r2['start'].character then return true end
  return false
end

local function point_in_range(point, range)
    if point.line == range['start']['line'] and point.character < range['start']['character'] then
        return false
    end
    if point.line == range['end']['line'] and point.character > range['end']['character'] then
        return false
    end
    return point.line >= range['start']['line'] and point.line <= range['end']['line']
end

local function search(buf_highlights,range)
  -- result: index, buf_highlights[index] <= loc < buf_highlights[index+1]
  local total_len = #buf_highlights
  if total_len == 1 then
    if r1_smaller_than_r2(buf_highlights[1], range) then
      return 1
    else
      return 0
    end
  end

  if total_len == 2 then
    if r1_smaller_than_r2(range,buf_highlights[1]) then
      return 0
    else
      if r1_smaller_than_r2(range, buf_highlights[2]) then
        return 1
      else
        return 2
      end
    end
  end

  local left,right = 1,#buf_highlights
  if r1_smaller_than_r2(range,buf_highlights[1]) then
    return 0
  end
  if not r1_smaller_than_r2(range,buf_highlights[#buf_highlights]) then
    return #buf_highlights
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
  return left
end

local hit_ns = function(ranges,position)
  -- res: 'in','between','before_all','after_all'
  local make_range = {
    ['start'] = {line=position[1]-1,character=position[2]},
    ['end']   = {line=position[1]-1,character=position[2]+1}
  }
  local to_insert = search(ranges,make_range)
  if to_insert < 1 then
    return {'before_all'}
  end
  if to_insert == #ranges then
    if point_in_range(make_range.start,ranges[#ranges]) then
      return {'in',search=to_insert}
    else
      return {'after_all'}
    end
  end

  local prev = ranges[to_insert]
  local next = ranges[to_insert+1]

  if point_in_range(make_range.start,prev) then
    return {'in',search=to_insert}
  else
    return {'between',search=to_insert}
  end

end

return {
  warn = warn,
  error = error,
  search = search,
  hit_ns = hit_ns,
  r1_smaller_than_r2 = r1_smaller_than_r2,
}
