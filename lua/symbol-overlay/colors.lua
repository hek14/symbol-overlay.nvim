local colors = {
  "#C70039",
  "#a89984",
  "#b16286",
  "#d79921",
  "#1F6C4A",
  "#d65d0e",
  "#458588",
  '#aeee00',
  '#ff0000',
  '#0000ff',
  '#b88823',
  '#ffa724',
  '#ff2c4b'
}
-- ========== state end

local groups = {}
for i, color in ipairs(colors) do
  vim.cmd (string.format('highlight! def persistent_highlight_%s_write gui=italic,bold guibg=%s guifg=black',i,color))
  vim.cmd (string.format('highlight! def persistent_highlight_%s_read guibg=%s guifg=black',i,color))
  table.insert(groups,{
    read=string.format('persistent_highlight_%s_read',i),
    write=string.format('persistent_highlight_%s_write',i)
  })
end
return groups