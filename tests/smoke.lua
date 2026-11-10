-- 冒烟：setup 之后注入点接上、加载图无环。
--
--   nvim --headless -u NONE -l tests/smoke.lua

vim.opt.rtp:prepend(vim.fn.getcwd())

local fails = {}
local function check(cond, msg)
	if not cond then
		fails[#fails + 1] = msg
	end
end

local term = require("tab_terminal")
local sidebar = require("tab_terminal.sidebar")

term.setup({ keys = { prev = "<", next = ">" } })

check(type(sidebar.host) == "table", "sidebar.host 未注入（sidebar.setup(M) 没调用？）")
for _, name in ipairs({
	"close_icon",
	"open",
	"kill",
	"hide",
	"new_in_tab",
	"cycle",
	"key",
	"workspace_name",
	"plus_icon",
}) do
	check(type(sidebar.host[name]) == "function", "sidebar.host." .. name .. " 缺失")
end
check(sidebar.host.kill == term.kill, "sidebar.host.kill 与 terminal.kill 不是同一函数")
check(sidebar.host.open == term.open, "sidebar.host.open 与 terminal.open 不是同一函数")
check(term.key("prev") == "<", "keys.prev 未生效")
check(term.key("next") == ">", "keys.next 未生效")
check(term.key("toggle") == nil, "默认不应抢全局 toggle 键")
check(term.plus_icon() == "+", "默认 + 按钮图标不对")

-- 顶层回指会成环：sidebar 不得在文件顶部 require init
local hit = false
for _, line in ipairs(vim.fn.readfile("lua/tab_terminal/sidebar.lua")) do
	if line:match("^%S") and line:match("require%s*%(?%s*[\"']tab_terminal[\"']") then
		hit = true
	end
end
check(not hit, "sidebar.lua 顶层 require 'tab_terminal'（回指成环）")

if #fails > 0 then
	io.stderr:write("FAIL\n")
	for _, f in ipairs(fails) do
		io.stderr:write("  - " .. f .. "\n")
	end
	os.exit(1)
end
print("ok: 注入点连通 / 键位默认值 / 无顶层回指")
