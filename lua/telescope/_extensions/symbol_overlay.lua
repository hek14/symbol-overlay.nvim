local symbol_overlay_builtin = require'telescope._extensions.symbol_overlay_builtin'

return require'telescope'.register_extension{
  exports = {
    list = symbol_overlay_builtin.list,
    fastgen = symbol_overlay_builtin.fastgen,
  },
}
