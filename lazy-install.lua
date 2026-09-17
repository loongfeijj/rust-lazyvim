-- 必须通过 --cmd 在 init.lua 之前加载，捕获配置阶段的错误通知。
local errors = {}
local notify = vim.notify
vim.notify = function(message, level, opts)
  if level and level >= vim.log.levels.ERROR then
    errors[#errors + 1] = tostring(message)
  end
  return notify(message, level, opts)
end

local function check_errors()
  local config = require('lazy.core.config')
  for _, notification in ipairs(config.spec.notifs) do
    if notification.level >= vim.log.levels.ERROR then
      errors[#errors + 1] = notification.msg
    end
  end
  if vim.v.errmsg ~= '' then
    errors[#errors + 1] = vim.v.errmsg
  end
  assert(#errors == 0, table.concat(errors, '\n'))
end

local function install()
  check_errors()
  require('lazy').sync({ wait = true, show = false })

  local config = require('lazy.core.config')
  for name, plugin in pairs(config.plugins) do
    for _, task in ipairs(plugin._.tasks or {}) do
      if task:has_errors() then
        error(('lazy: %s 安装失败\n%s'):format(name, task:output()))
      end
    end
    assert(plugin._.installed, ('lazy: %s 尚未安装'):format(name))
  end
  for _, extra in ipairs({ 'lang.rust', 'lang.toml' }) do
    assert(LazyVim.plugin.extra_idx(extra), 'LazyVim extra 未加载: ' .. extra)
  end
  check_errors()

  -- 在同一个 Neovim 进程中完成所有安装，不能在后台任务结束前退出。
  dofile('/tmp/mason-install.lua')
  require('lazy').load({ plugins = { 'nvim-treesitter' } })
  local treesitter = require('nvim-treesitter')
  local languages = LazyVim.opts('nvim-treesitter').ensure_installed
  assert(treesitter.install(languages, { summary = true }):wait(600000), 'Tree-sitter parser 安装失败')
  assert(treesitter.update(languages, { summary = true }):wait(600000), 'Tree-sitter parser 更新失败')
  -- 首次安装时 site/parser 在启动后才创建，需要刷新 runtimepath 的目录缓存。
  local parser_dir = require('nvim-treesitter.config').get_install_dir('parser')
  vim.opt.runtimepath:prepend(vim.fs.dirname(parser_dir))
  for _, language in ipairs(languages) do
    local loaded, err = vim.treesitter.language.add(language)
    assert(loaded, ('Tree-sitter parser 无法加载: %s (%s)'):format(language, tostring(err)))
  end
  check_errors()
end

vim.api.nvim_create_autocmd('VimEnter', {
  once = true,
  callback = function()
    vim.schedule(function()
      local ok, err = xpcall(install, debug.traceback)
      if not ok then
        vim.api.nvim_err_writeln(err)
        vim.cmd('cquit 1')
      else
        print('LazyVim extras、Mason 工具和 Tree-sitter parsers 安装验证通过')
        vim.cmd('qa!')
      end
    end)
  end,
})
