local renderer = require'neo-tree.ui.renderer'
local manager = require'neo-tree.sources.manager'
local events = require'neo-tree.events'

local M = {}

local path = require'plenary.path'

function notify(msg, lvl)
  vim.notify(msg, lvl, { title = 'Mind', icon = '' })
end

-- FIXME: recursively ensure that the paths are created
local defaults = {
  state_path = '~/.local/share/mind.nvim/mind.json',
  data_dir = '~/.local/share/mind.nvim/data',
  width = 40,
  use_default_keys = true,
}

function expand_opts_paths()
  M.opts.state_path = vim.fn.expand(M.opts.state_path)
  M.opts.data_dir = vim.fn.expand(M.opts.data_dir)
end

M.setup = function(opts)
  M.opts = setmetatable(opts or {}, {__index = defaults})

  expand_opts_paths()

  M.load_state()
end

-- Load the state.
--
-- If CWD has a .mind/, the projects part of the state is overriden with its contents. However, the main tree remains in
-- M.opts.state_path.
M.load_state = function()
  M.state = {
    -- Main tree, used for when no specific project is wanted.
    tree = {
      name = 'Main'
    },

    -- Per-project trees; this is a map from the CWD of projects to the actual tree for that project.
    projects = {},
  }

  -- Local tree, for local projects.
  M.local_tree = nil

  if (M.opts == nil or M.opts.state_path == nil) then
    notify('cannot load shit', 4)
    return
  end

  local file = io.open(M.opts.state_path, 'r')

  if (file == nil) then
    notify('no global state', 4)
  else
    local encoded = file:read()
    file:close()

    if (encoded ~= nil) then
      M.state = vim.json.decode(encoded)
    end
  end

  -- if there is a local state, we get it and replace the M.state.projects[the_project] with it
  local cwd = vim.fn.getcwd()
  local local_mind = path:new(cwd, '.mind')
  if (local_mind:is_dir()) then
    -- we have a local mind; read the projects state from there
    file = io.open(path:new(cwd, '.mind', 'state.json'):expand(), 'r')

    if (file == nil) then
      notify('no local state', 4)
      M.local_tree = { name = cwd:match('^.+/(.+)$') }
    else
      encoded = file:read()
      file:close()

      if (encoded ~= nil) then
        M.local_tree = vim.json.decode(encoded)
      end
    end
  end
end

M.save_state = function()
  if (M.opts == nil or M.opts.state_path == nil) then
    return
  end

  local file = io.open(M.opts.state_path, 'w')

  if (file == nil) then
    notify(string.format('cannot save state at %s', M.opts.state_path), 4)
  else
    local encoded = vim.json.encode(M.state)
    file:write(encoded)
    file:close()
  end

  -- if there is a local state, we write the local project
  local cwd = vim.fn.getcwd()
  local local_mind = path:new(cwd, '.mind')
  if (local_mind:is_dir()) then
    -- we have a local mind
    file = io.open(path:new(cwd, '.mind', 'state.json'):expand(), 'w')

    if (file == nil) then
      notify(string.format('cannot save local project at %s', cwd), 4)
    else
      local encoded = vim.json.encode(M.local_tree)
      file:write(encoded)
      file:close()
    end
  end
end

M.Node = function(name, children)
  return { name = name, is_expanded = false, children = children }
end


-- Wrap a function call expecting a tree by extracting from the state the right tree, depending on CWD.
--
-- The `save` argument will automatically save the state after the function is done, if set to `true`.
M.wrap_tree_fn = function(f, save)
  local cwd = vim.fn.getcwd()
  local project_tree = M.state.projects[cwd]

  if (project_tree == nil) then
    M.wrap_main_tree_fn(f, save)
  else
    M.wrap_project_tree_fn(f, save, project_tree)
  end
end

-- Wrap a function call expecting a tree with the main tree.
M.wrap_main_tree_fn = function(f, save)
  f(M.state.tree)

  if (save) then
    M.save_state()
  end
end

-- Wrap a function call expecting a project tree.
--
-- If the projec tree doesn’t exist, it is automatically created.
M.wrap_project_tree_fn = function(f, save, tree, use_global)
  if (tree == nil) then
    if (M.local_tree == nil or use_global) then
      local cwd = vim.fn.getcwd()
      tree = M.state.projects[cwd]

      if (tree == nil) then
        tree = { name = cwd:match('^.+/(.+)$') }
        M.state.projects[cwd] = tree
      end
    else
      tree = M.local_tree
    end
  end

  f(tree)

  if (save) then
    M.save_state()
  end
end

function get_ith(parent, node, i)
  if (i == 0) then
    return parent, node, nil
  end

  i = i - 1

  if (node.children ~= nil and node.is_expanded) then
    for _, child in ipairs(node.children) do
      p, n, i = get_ith(node, child, i)

      if (n ~= nil) then
        return p, n, nil
      end
    end
  end

  return nil, nil, i
end

M.get_node_by_nb = function(tree, i)
  local _, node, _ = get_ith(nil, tree, i)
  return node
end

M.get_node_and_parent_by_nb = function(tree, i)
  local parent, node, _ = get_ith(nil, tree, i)
  return parent, node
end

-- Add a node as children of another node.
function add_node(tree, i, name)
  local parent = M.get_node_by_nb(tree, i)

  if (parent == nil) then
    notify('add_node nope', 4)
    return
  end

  local node = M.Node(name, nil)

  if (parent.children == nil) then
    parent.children = {}
  end

  parent.children[#parent.children + 1] = node
  parent.is_expanded = true

  M.rerender(tree)
end

-- Ask the user for input and add as a node at the current location.
M.input_node_cursor = function(tree)
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  vim.ui.input({ prompt = 'Node name: ' }, function(input)
    if (input ~= nil) then
      add_node(tree, line, input)
    end
  end)
end

-- Delete a node at a given location.
function delete_node(tree, i)
  local parent, node = M.get_node_and_parent_by_nb(tree, i)

  if (node == nil) then
    notify('add_node nope', 4)
    return
  end

  if (parent == nil) then
    return false
  end

  local children = {}
  for _, child in ipairs(parent.children) do
    if (child ~= node) then
      children[#children + 1] = child
    end
  end

  if (#children == 0) then
    children = nil
  end

  parent.children = children

  M.rerender(tree)
  return true
end

-- Delete the node under the cursor.
M.delete_node_cursor = function(tree)
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  delete_node(tree, line)
end

-- Rename a node at a given location.
function rename_node(tree, i)
  local parent, node = M.get_node_and_parent_by_nb(tree, i)

  if (node == nil) then
    notify('rename_node nope', 4)
    return
  end

  vim.ui.input({ prompt = string.format('Rename node: %s -> ', node.name) }, function(input)
    if (input ~= nil) then
      node.name = input
    end
  end)

  M.rerender(tree)
  return true
end

-- Rename the node under the cursor.
M.rename_node_cursor = function(tree)
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  rename_node(tree, line)
end

function render_node(node, depth, lines)
  local line = string.rep(' ', depth * 2)

  if (node.children ~= nil) then
    if (node.is_expanded) then
      lines[#lines + 1] = line .. ' ' .. node.name

      depth = depth + 1
      for _, child in ipairs(node.children) do
        render_node(child, depth, lines)
      end
    else
      lines[#lines + 1] = line .. ' ' .. node.name
    end
  else
    lines[#lines + 1] = line .. node.name
  end
end

M.to_lines = function(tree)
  local lines = {}
  render_node(tree, 0, lines)
  return lines
end

M.render = function(tree, bufnr)
  local lines = M.to_lines(tree)

  vim.api.nvim_buf_set_option(bufnr, 'modifiable', true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, lines)
  vim.api.nvim_buf_set_option(bufnr, 'modifiable', false)
end

-- Re-render a tree if it was already rendered buffer.
M.rerender = function(tree)
  M.render(tree, 0)
end

M.open_tree = function(tree, default_keys)
  -- window
  vim.api.nvim_cmd({ cmd = 'vsplit'}, {})
  vim.api.nvim_win_set_width(0, M.opts.width or 40)

  -- buffer
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, bufnr)
  vim.api.nvim_buf_set_option(bufnr, 'filetype', 'mind')
  vim.api.nvim_win_set_option(0, 'nu', false)

  -- tree
  M.render(tree, bufnr)

  -- keymaps for debugging
  if (default_keys) then
    vim.keymap.set('n', '<cr>', function()
      M.toggle_node_cursor(tree)
      M.save_state()
    end, { buffer = true, noremap = true, silent = true })

    vim.keymap.set('n', '<tab>', function()
      M.toggle_node_cursor(tree)
      M.save_state()
    end, { buffer = true, noremap = true, silent = true })

    vim.keymap.set('n', 'q', M.close, { buffer = true, noremap = true, silent = true })

    vim.keymap.set('n', 'a', function()
      M.input_node_cursor(tree)
      M.save_state()
    end, { buffer = true, noremap = true, silent = true })

    vim.keymap.set('n', 'd', function()
      M.delete_node_cursor(tree)
      M.save_state()
    end, { buffer = true, noremap = true, silent = true })

    vim.keymap.set('n', 'r', function()
      M.rename_node_cursor(tree)
      M.save_state()
    end, { buffer = true, noremap = true, silent = true })
  end
end


M.open_main = function()
  M.wrap_main_tree_fn(function(tree) M.open_tree(tree, M.opts.use_default_keys) end)
end

M.open_project = function(use_global)
  M.wrap_project_tree_fn(function(tree) M.open_tree(tree, M.opts.use_default_keys) end, false, nil, use_global)
end

M.close = function()
  vim.api.nvim_win_hide(0)
end

M.toggle_node = function(tree, i)
  local node = M.get_node_by_nb(tree, i)

  if (node ~= nil) then
    node.is_expanded = not node.is_expanded
  end

  M.rerender(tree)
end

M.toggle_node_cursor = function(tree)
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  M.toggle_node(tree, line)
end

return M
