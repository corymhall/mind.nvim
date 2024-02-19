-- Keymaps and keybindings.

local M = {}

local notify = require'mind.notify'.notify
local wk = require('which-key')

-- Selector for keymap.
--
-- A keymap selector is a way to pick which keymap should be used. When a command allows for UI, it can set the
-- currently active keymap. The keymap contains user-defined keybindings that will then be resolved when the user
-- presses their defined keys.
M.KeymapSelector = {
  NORMAL = 'normal',
  SELECTION = 'selection',
}

-- weird hack because the `defaults` table returns the values as functions
-- not strings
M.keymap_descriptions = {
  keymaps = {
    -- keybindings when navigating the tree normally
    normal = {
      ['<cr>'] = 'open node',
      ['<s-cr>'] = 'open data index',
      ['<tab>'] = 'toggle node',
      ['<s-tab>'] = 'toggle parent',
      ['/'] = 'select path',
      ['$'] = 'change icon menu',
      c = 'add inside end index',
      I = 'add inside start',
      i = 'add inside end',
      l = 'copy node link',
      L = 'copy node link index',
      d = 'delete',
      D = 'delete file',
      O = 'add above',
      o = 'add below',
      q = 'quit',
      r = 'rename',
      R = 'change icon',
      u = 'make url',
      x = 'select',
    },

    -- keybindings when a node is selected
    selection = {
      ['<cr>'] = 'open data',
      ['<tab>'] = 'toggle node',
      ['<s-tab>'] = 'toggle parent',
      ['/'] = 'select path',
      I = 'move inside start',
      i = 'move inside end',
      O = 'move above',
      o = 'move below',
      q = 'quit',
      x = 'select',
    },
  }
}

-- Keymaps.
--
-- A keymap is a map between a key and a command name.
--
-- If M.precompute_keymaps() is called, the mapping is not between a key and a command name anymore but between a key and a
-- Lua function directly, preventing the indirection.
M.keymaps = {
  -- Currently active keymap selector.
  selector = M.KeymapSelector.NORMAL,

  -- Normal mappings.
  normal = {},

  -- Selection mappings.
  selection = {},
}

-- Initialize keymaps.
M.init_keymaps = function(opts)
  M.keymaps.normal = opts.keymaps.normal
  M.keymaps.selection = opts.keymaps.selection
end

-- Set the currently active keymap.
M.set_keymap = function(selector)
  M.keymaps.selector = selector
end

-- Get the currently active keymap.
M.get_keymap = function()
  return M.keymaps[M.keymaps.selector]
end

-- Insert keymaps into the given buffer.
M.insert_keymaps = function(bufnr, get_tree, data_dir, save_tree, opts)
  local keyset = {}

    wk.register({
      m = {
        name = "+mind",
      },
    }, {
      buffer = bufnr,
      silent = true,
      noremap = true,
      prefix = ""
    })
  for key, _ in pairs(M.keymaps.normal) do
    keyset[key] = true
  end

  for key, _ in pairs(M.keymaps.selection) do
    keyset[key] = true
  end

  -- the input for the command function
  local args = {
    get_tree = get_tree,
    data_dir = data_dir,
    save_tree = save_tree,
    opts = opts
  }


  for key, _ in pairs(keyset) do
    local keymap = M.get_keymap()
    wk.register({
      ["m"..key] = { function()
        local cmd = keymap[key]
        cmd(args)
      end, M.keymap_descriptions.keymaps.normal[key]}
    })
    vim.keymap.set('n', key, function()

      if (keymap == nil) then
        notify('no active keymap', vim.log.levels.WARN)
        return
      end

      local cmd = keymap[key]

      if (cmd == nil) then
        notify('no command bound to ' .. tostring(key), vim.log.levels.WARN)
        return
      end

      cmd(args)
    end, { desc = M.keymap_descriptions.keymaps.normal[key], buffer = bufnr, noremap = true, silent = true })
  end
end

return M
