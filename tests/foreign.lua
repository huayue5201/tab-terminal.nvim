-- 归属策略：不能把别人的终端当成自己的。
--
--   nvim --headless -u NONE -l tests/foreign.lua
--
-- 覆盖：
--   1. filetype 标记的插件终端（如 dap-view-term）不被收编，也不改它的 ft
--   2. 只靠 filetype 标记、窗口没锁的插件终端同样不收编
--   3. register_foreign_rule 注册的自定义规则生效
--   4. 手敲的 :terminal 仍然被收编（延迟判定的正向路径）
--   5. 焦点在插件窗口（winfixbuf）时开面板：不报错、不换别人的 buffer
--   6. hide/toggle 只动自己的面板
--   7. setup 时清掉历史遗留的「非自建」登记
--
-- 退出码：有失败 1，全通过 0。

vim.opt.rtp:prepend(vim.fn.getcwd())

local api = vim.api
local fails = {}

local function check(cond, msg)
	if not cond then
		fails[#fails + 1] = msg
	end
end

local term = require("tab_terminal")
local tstate = require("tab_terminal.state")

term.setup({ startinsert = false, sidebar = false })
vim.notify = function() end

local function tab()
	return api.nvim_get_current_tabpage()
end

--- 造一个「插件终端」：真实 terminal buffer，但像插件一样事后设 ft / 窗口变量，
--- 同步完成，早于我们的延迟收编。
local function fake_plugin_term(o)
	o = o or {}
	local buf = api.nvim_create_buf(true, false)
	api.nvim_buf_call(buf, function()
		vim.fn.termopen({ "sh" })
	end)
	vim.bo[buf].filetype = o.ft or "dap-view-term"
	if o.name then
		api.nvim_buf_set_name(buf, o.name)
	end
	if vim.wo.winfixbuf then
		vim.wo.winfixbuf = false
	end
	api.nvim_win_set_buf(0, buf)
	vim.wo.winfixbuf = o.lock ~= false
	return buf
end

local function flush()
	vim.wait(300, function()
		return false
	end)
end

-- 1. 插件终端不被收编
local foreign = fake_plugin_term()
flush()
check(tstate.tab_of(foreign) == nil, "dap-view 的终端不应进登记表")
check(vim.bo[foreign].filetype == "dap-view-term", "不应改别人的 filetype")
check(vim.bo[foreign].buflisted == true, "不应改别人的 buflisted")
check(not vim.b[foreign].tab_term_owned, "不应给别人打 owned 标记")

-- 2. 通用规则：没锁窗口、只用 ft 标记的插件终端同样不收编
local ft_marked = fake_plugin_term({ ft = "toggleterm", lock = false })
flush()
check(tstate.tab_of(ft_marked) == nil, "只靠 filetype 标记的插件终端也不应收编")
check(vim.bo[ft_marked].filetype == "toggleterm", "不应改别人的 filetype")

-- 3. 扩展 API：用户/其他插件可以自己加规则
term.register_foreign_rule({
	name = "test-rule",
	match = function(ctx)
		return ctx.name:find("forbidden") ~= nil
	end,
})
local custom = fake_plugin_term({ ft = "", name = "forbidden-term", lock = false })
flush()
check(tstate.tab_of(custom) == nil, "register_foreign_rule 注册的规则应生效")
term.unregister_foreign_rule("test-rule")

-- 4. 手敲 :terminal 仍然被收编
vim.wo.winfixbuf = false
local plain = api.nvim_create_buf(false, false)
api.nvim_buf_call(plain, function()
	vim.fn.termopen({ "sh" })
end)
api.nvim_win_set_buf(0, plain)
flush()
check(tstate.tab_of(plain) == tab(), "手动 :terminal 应被收编")
check(vim.b[plain].tab_term_owned == true, "收编后应有 owned 标记")
check(vim.bo[plain].filetype == "tab_terminal", "收编后应设 ft=tab_terminal")

-- 5. 焦点在插件窗口时开面板：不能动它
api.nvim_win_set_buf(0, foreign)
vim.wo.winfixbuf = true
local foreign_win = api.nvim_get_current_win()
local ok, err = pcall(term.new)
check(ok, "焦点在插件窗口时点 + 不应报错：" .. tostring(err))
check(api.nvim_win_is_valid(foreign_win), "插件窗口不应被关掉")
check(api.nvim_win_get_buf(foreign_win) == foreign, "插件窗口的 buffer 不应被换掉")
check(vim.wo[foreign_win].winfixbuf == true, "插件窗口的 winfixbuf 不应被我们改掉")

local panel
for _, win in ipairs(api.nvim_tabpage_list_wins(tab())) do
	if vim.w[win].tab_term_panel then
		panel = win
	end
end
check(panel ~= nil, "应新建一个面板窗口")
check(panel ~= foreign_win, "面板窗口不能复用插件窗口")

-- 6. hide/toggle 只动自己的面板
term.hide()
check(api.nvim_win_is_valid(foreign_win), "隐藏面板后插件窗口应还在")
term.toggle()
check(api.nvim_win_is_valid(foreign_win), "打开面板不能关掉插件窗口")
term.toggle()
check(api.nvim_win_is_valid(foreign_win), "再按一次也不能关掉插件窗口")

-- 7. setup 清掉历史遗留的非自建登记
vim.wo[foreign_win].winfixbuf = false
tstate.add(tab(), foreign)
check(tstate.tab_of(foreign) == tab(), "预置：foreign 应已在登记表里")
term.setup({ startinsert = false, sidebar = false })
check(tstate.tab_of(foreign) == nil, "setup 应清掉非自建的历史登记")
check(tstate.tab_of(plain) == tab(), "自建终端不应被 setup 清掉")

vim.wo[foreign_win].winfixbuf = false

if #fails > 0 then
	io.stderr:write("FAIL\n")
	for _, f in ipairs(fails) do
		io.stderr:write("  - " .. f .. "\n")
	end
	os.exit(1)
end
print("ok: 终端归属（插件终端不收编 / 面板只认自己的窗口）符合预期")
