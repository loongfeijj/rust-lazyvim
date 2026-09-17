-- 配合 Dockerfile 在构建阶段用 headless nvim 跑一次，
-- 把 mason 安装 codelldb（异步）的过程等完，再退出进程。
-- 用法：nvim --headless -c "luafile mason-install.lua"

-- mason.nvim 一般是懒加载的，强制先加载它
require('lazy').load({ plugins = { 'mason.nvim' } })

local registry = require('mason-registry')

registry.refresh(function()
  local ok, pkg = pcall(registry.get_package, registry, 'codelldb')
  if not ok then
    vim.notify('mason: 找不到 codelldb 包', vim.log.levels.WARN)
    vim.cmd('qa')
    return
  end

  if pkg:is_installed() then
    vim.cmd('qa')
    return
  end

  pkg:install():once('closed', function()
    vim.schedule(function()
      vim.cmd('qa')
    end)
  end)
end)
