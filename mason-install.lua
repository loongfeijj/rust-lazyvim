-- 由 lazy-install.lua 执行；等待 Mason 安装完成，失败抛出异常，由调用方退出。
require('lazy').load({ plugins = { 'mason.nvim' } })
local registry = require('mason-registry')
local failures = {}
registry:on('package:install:failed', function(pkg, err)
  failures[#failures + 1] = pkg.name .. ': ' .. tostring(err)
end)

local refreshed, refresh_ok = false, false
registry.refresh(function(success)
  refreshed, refresh_ok = true, success
end)
assert(vim.wait(600000, function() return refreshed end, 100), 'Mason registry 刷新超时')
assert(refresh_ok, 'Mason registry 刷新失败')

local required = { 'codelldb', 'taplo', 'lua-language-server' }
vim.list_extend(required, LazyVim.opts('mason.nvim').ensure_installed or {})
for _, name in ipairs(required) do
  local pkg = registry.get_package(name)
  -- LazyVim 可能已经启动了安装；复用进行中的任务，避免重复安装异常。
  if not pkg:is_installed() and not pkg:is_installing() then
    pkg:install()
  end
end

local packages = registry.get_all_packages()
assert(vim.wait(600000, function()
  for _, pkg in ipairs(packages) do
    if pkg:is_installing() then
      return false
    end
  end
  return true
end, 100), 'Mason 工具安装超时')
assert(#failures == 0, table.concat(failures, '\n'))
for _, name in ipairs(required) do
  assert(registry.get_package(name):is_installed(), 'Mason 工具未安装: ' .. name)
end
