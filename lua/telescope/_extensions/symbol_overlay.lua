local symbol_overlay_builtin = require'telescope._extensions.symbol_overlay_builtin'

return require'telescope'.register_extension{
  exports = {
    symbol_overlay = symbol_overlay_builtin.list,
  },
}
