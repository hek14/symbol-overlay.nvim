local symbol_overlay_builtin = require'telescope._extensions.symbol_overlay_builtin'

return require'telescope'.register_extension{
  exports = {
    list = symbol_overlay_builtin.list,
    gen = symbol_overlay_builtin.gen,
  },
}
