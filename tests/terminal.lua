-- 用户视角的核心行为：
--
--   nvim --headless -u NONE -l tests/terminal.lua
--
-- 覆盖：
--   1. cwd 回调：新终端落在宿主指定的目录
--   2. workspace_name 回调驱动侧栏组头
--   3. 终端按 tab 隔离
--   4. 侧栏组头的「+」：在该工作区新建终端（鼠标点击路径）
--   5. <> 只在终端 buffer 的普通模式生效（buffer-local），且能切换活动终端
--   6. :TabTerminal 命令存在
--
-- 退出码：有失败 1，全通过 0。

vim.opt.rtp:prepend(vim.fn.getcwd())
vim.cmd("runtime! plugin/tab_terminal.lua")

local api, fn = vim.api, vim.fn
local uv = vim.uv or vim.loop
local fails = {}

local function check(cond, msg)
	if not cond then
		fails[#fails + 1] = msg
	end
end

local function real(path)
	local ok, res = pcall(uv.fs_realpath, path)
	return (ok and res) or path
end

local base = fn.tempname()
local A, B = base .. "/projA", base .. "/projB"
for _, dir in ipairs({ A, B }) do
	fn.mkdir(dir, "p")
end

local term = require("tab_terminal")
local tstate = require("tab_terminal.state")
local sidebar = require("tab_terminal.sidebar")
vim.notify = function() end

local current_root = A
local names = {}

term.setup({
	startinsert = false,
	sidebar = true,
	cwd = function()
		return current_root
	end,
	workspace_name = function(tab)
		return names[tab]
	end,
	keys = {
		toggle = "<C-;>",
		prev = "<",
		next = ">",
	},
})

local function tab()
	return api.nvim_get_current_tabpage()
end

local function term_cwd(bufnr)
	return real(vim.b[bufnr].tab_term_cwd or "")
end

local function active()
	return tstate.active(tab())
end

----------------------------------------------------------------------
-- 1. cwd 回调
----------------------------------------------------------------------

current_root = A
local tab1 = tab()
names[tab1] = "projA +1"
local t1 = term.new()
check(term_cwd(t1) == real(A), ("cwd 回调 A 未生效，实际 %s"):format(term_cwd(t1)))

current_root = B
local t2 = term.new()
check(term_cwd(t2) == real(B), ("cwd 回调 B 未生效，实际 %s"):format(term_cwd(t2)))

----------------------------------------------------------------------
-- 2. tab 隔离
----------------------------------------------------------------------

vim.cmd("tabnew")
local tab2 = tab()
names[tab2] = "projB"
check(#tstate.list(tab2) == 0, ("新 tab 不应看到别的 tab 的终端，实际 %d"):format(#tstate.list(tab2)))
local t3 = term.new()
check(#tstate.list(tab2) == 1, "新 tab 开的终端只登记在新 tab")
check(term_cwd(t3) == real(B), "新 tab 的终端应在 projB")

vim.cmd("tabprevious")
check(#tstate.list(tab()) == 2, ("切回 tab1 后应只看到 2 个终端，实际 %d"):format(#tstate.list(tab())))

----------------------------------------------------------------------
-- 3. 侧栏组头 + 「+」点击
----------------------------------------------------------------------

local panel
for _, win in ipairs(api.nvim_tabpage_list_wins(tab())) do
	if vim.w[win].tab_term_panel then
		panel = win
	end
end
check(panel ~= nil, "应有终端面板窗口")

local sbar = sidebar.open(panel, tab())
local sbar_buf = api.nvim_win_get_buf(sbar)
local lines = api.nvim_buf_get_lines(sbar_buf, 0, -1, false)
local header = lines[1] or ""
check(header:find("projA", 1, true) ~= nil, "侧栏组头应带 workspace_name 回调的 projA，实际: " .. header)
check(header:find("+1", 1, true) ~= nil, "侧栏组头应保留宿主给的 +1，实际: " .. header)
check(header:sub(-1) == "+", "组头右端应有 + 按钮，实际: " .. header)

local before1 = #tstate.list(tab1)
local before2 = #tstate.list(tab2)
api.nvim_set_current_win(sbar)
sidebar.click_action({
	winid = sbar,
	line = 1,
	column = #header,
	wincol = api.nvim_win_get_width(sbar) - 1,
})
check(#tstate.list(tab1) == before1 + 1, "点击组头 + 应在该工作区新建终端")
check(#tstate.list(tab2) == before2, "点击组头 + 不应影响别的工作区")
check(tab() == tab1, "点击组头 + 应切到该工作区（已经是当前 tab）")

----------------------------------------------------------------------
-- 4. <> 映射：buffer-local，且能切换
----------------------------------------------------------------------

local function keys_of(bufnr)
	local out = {}
	for _, m in ipairs(api.nvim_buf_get_keymap(bufnr, "n")) do
		out[m.lhs] = m
	end
	return out
end

local k1 = keys_of(t1)
check(k1["<lt>"] ~= nil, "终端 buffer 普通模式应有 < 映射")
check(k1[">"] ~= nil, "终端 buffer 普通模式应有 > 映射")
for _, m in ipairs(api.nvim_get_keymap("n")) do
	check(m.lhs ~= ">" and m.lhs ~= "<", "> / < 不应有全局映射（实际有 " .. m.lhs .. "）")
end

local scratch = api.nvim_create_buf(false, true)
check(keys_of(scratch)[">"] == nil, "普通 buffer 不应拿到 > 映射")

term.open(t1)
check(active() == t1, "open(t1) 后活动终端应为 t1")
vim.api.nvim_feedkeys(api.nvim_replace_termcodes(">", true, false, true), "x", false)
check(active() == t2, ("按 > 应切到下一个终端 t2，实际 %s"):format(tostring(active())))
vim.api.nvim_feedkeys(api.nvim_replace_termcodes("<", true, false, true), "x", false)
check(active() == t1, ("按 < 应切回上一个终端 t1，实际 %s"):format(tostring(active())))

----------------------------------------------------------------------
-- 5. 命令
----------------------------------------------------------------------

check(fn.exists(":TabTerminal") == 2, ":TabTerminal 未注册")
local before_cmd = #tstate.list(tab())
vim.cmd("TabTerminal new")
check(#tstate.list(tab()) == before_cmd + 1, ":TabTerminal new 应新建终端")

----------------------------------------------------------------------
-- 收尾
----------------------------------------------------------------------

for _, b in ipairs(api.nvim_list_bufs()) do
	if vim.b[b].tab_term and api.nvim_buf_is_valid(b) then
		pcall(api.nvim_buf_delete, b, { force = true })
	end
end

if #fails > 0 then
	io.stderr:write("FAIL\n")
	for _, f in ipairs(fails) do
		io.stderr:write("  - " .. f .. "\n")
	end
	os.exit(1)
end
print("ok: per-tab 终端 / cwd 回调 / 侧栏 + / <> 切换")
