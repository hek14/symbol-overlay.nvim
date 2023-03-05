local default_colors = {
  '#e67e80',
  '#e69875',
  '#dbbc7f',
  '#a7c080',
  '#83c092',
  '#7fbbb3',
  '#d699b6',
  '#859289',
  '#9da9a0',
  '#a7c080',
  '#d3c6aa',
  '#e67e80',
  '#7a8478',
  "#b16286",
  "#1F6C4A",
  "#458588",
  '#aeee00',
  '#ff0000',
  '#0000ff',
  '#ff2c4b',
  "#C70039",
}
-- ========== state end
local M = {colors=default_colors}
function M.get_hl_group(colors)
  if #colors==0 then
    colors = default_colors -- fallback
  end
  local groups = {}
  for i, color in ipairs(colors) do
    vim.defer_fn(function()
      vim.cmd (string.format('highlight def persistent_highlight_%s_write gui=italic guibg=%s guifg=white',i,color))
      vim.cmd (string.format('highlight def persistent_highlight_%s_read guibg=%s guifg=white',i,color))
    end,0)
    table.insert(groups,{
      read=string.format('persistent_highlight_%s_read',i),
      write=string.format('persistent_highlight_%s_write',i)
    })
  end
  return groups
end

return M
