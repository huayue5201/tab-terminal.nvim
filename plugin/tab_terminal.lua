-- 命令层：只注册 :TabTerminal，不自动 setup。
-- 插件能力全部由 require("tab_terminal").setup(opts) 打开。
if vim.g.loaded_tab_terminal == 1 then
	return
end
vim.g.loaded_tab_terminal = 1

local SUBCOMMANDS = { "toggle", "new", "select", "rename", "tabs", "kill", "kill-all" }

vim.api.nvim_create_user_command("TabTerminal", function(args)
	local m = require("tab_terminal")
	local sub = args.fargs[1] or "toggle"
	if sub == "toggle" then
		m.toggle()
	elseif sub == "new" then
		m.new()
	elseif sub == "select" then
		m.select()
	elseif sub == "rename" then
		m.rename(args.fargs[2] and table.concat(args.fargs, " ", 2) or nil)
	elseif sub == "tabs" then
		m.toggle_tabs()
	elseif sub == "kill" then
		m.kill()
	elseif sub == "kill-all" then
		local tab = vim.api.nvim_get_current_tabpage()
		for _, bufnr in ipairs(require("tab_terminal.state").list(tab)) do
			m.kill(bufnr)
		end
	else
		vim.notify("TabTerminal: unknown subcommand: " .. sub, vim.log.levels.ERROR)
	end
end, {
	nargs = "*",
	desc = "tab-terminal.nvim: per-tab terminals",
	complete = function()
		return SUBCOMMANDS
	end,
})
