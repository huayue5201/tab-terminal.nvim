local M = {}

function M.check()
	vim.health.start("tab-terminal.nvim")

	if vim.fn.has("nvim-0.10") == 1 then
		vim.health.ok("Neovim >= 0.10")
	else
		vim.health.error("Neovim >= 0.10 required")
	end

	local ok, term = pcall(require, "tab_terminal")
	if not ok then
		vim.health.error("cannot load tab_terminal: " .. tostring(term))
		return
	end
	vim.health.ok("tab_terminal loads")

	local keys = { "toggle", "new", "select", "rename", "tabs", "kill", "kill_all", "prev", "next" }
	local missing = {}
	for _, name in ipairs(keys) do
		if term.key(name) == nil then
			missing[#missing + 1] = name
		end
	end
	if #missing > 0 then
		vim.health.info("unmapped keys: " .. table.concat(missing, ", "))
	end

	local n = 0
	for _, tab in ipairs(require("tab_terminal.state").tabs()) do
		n = n + #require("tab_terminal.state").list(tab)
	end
	vim.health.ok(("%d terminal(s) tracked across %d tab(s)"):format(n, #require("tab_terminal.state").tabs()))
end

return M
