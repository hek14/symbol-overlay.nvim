local M = {}
local overlay = require('symbol-overlay')
local fmt = string.format
local options = {}

local defaults = {
  keymap = {
    toggle = '<C-t>t',
    clear_all = '<C-t>c',
    next_highlight = '<C-t>n',
    prev_highlight = '<C-t>p'
  },
  colors = require('symbol-overlay.colors').colors,
}


function M.set(opt)
  options = vim.tbl_extend('force',defaults,opt and opt or {})
  for k,v in pairs(options.keymap) do
    vim.keymap.set('n',v,overlay[k],{silent=true})
  end
  if #options.colors==0 then
    options.colors = require('symbol-overlay.colors').colors
  end
  options.hl_groups = require('symbol-overlay.colors').get_hl_group(options.colors)
end

function M.get()
  return options
end

return M
