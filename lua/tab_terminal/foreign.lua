-- 终端归属策略：判断一个 terminal buffer / 窗口是不是「别的插件在管」。
--
-- 为什么需要：终端面板要 hide / 换 buffer / 写 winbar / 杀进程，一旦把插件
-- （nvim-dap-view 的 console、nvim-dap 的集成终端…）的终端当成自己的，轻则
-- 布局错乱，重则撞上 'winfixbuf' 报 E1513。
--
-- 设计：核心只放**与插件无关**的通用判据，具体插件的知识由集成层注册进来。
--
--   通用规则 1（filetype）：插件用 filetype 标记自己的终端很常见
--     （dap-view-term 等）。buftype=terminal 且 ft 既非空、也不是本模块的
--     tab_terminal → 不是我们的。
--   通用规则 2（winfixbuf）：窗口被插件锁在自己的 buffer 上（'winfixbuf'），
--     说明这个窗口有主，不能拿来当面板、也不能当切分基准；否则 set_buf 直接
--     E1513。
--
--   插件专属规则：由集成层注册，例如 dap 集成注册
--   「[dap-terminal] 命名」和「dapview_win_term 窗口变量」两条。
--
-- 扩展（任何模块 / 用户配置都可以加规则，核心不用改）：
--
--   require("tab_terminal").register_foreign_rule({
--     name = "toggleterm",
--     desc = "toggleterm 自己管终端",
--     match = function(ctx) return ctx.ft == "toggleterm" end,
--   })
--
-- ctx 字段：bufnr, ft, buftype, name, wins（显示该 buffer 的所有窗口）。
-- match 返回 true 即判定为「外来」，规则按注册顺序求值，第一个命中的生效。

local api, fn = vim.api, vim.fn

local M = {}

---@class TabTerminalForeignCtx
---@field bufnr integer
---@field ft string
---@field buftype string
---@field name string
---@field wins integer[]

---@class TabTerminalForeignRule
---@field name string 唯一名字（unregister / 排查用）
---@field desc? string
---@field match fun(ctx: TabTerminalForeignCtx): boolean

---@type table<string, TabTerminalForeignRule>
local rules = {}
---@type string[]
local order = {}

--- 注册一条归属规则（同名覆盖，顺序保持在首次注册的位置）
---@param rule TabTerminalForeignRule
function M.register(rule)
	assert(type(rule) == "table", "rule must be a table")
	assert(type(rule.name) == "string" and rule.name ~= "", "rule.name is required")
	assert(type(rule.match) == "function", "rule.match is required")
	if not rules[rule.name] then
		order[#order + 1] = rule.name
	end
	rules[rule.name] = rule
end

---@param name string
function M.unregister(name)
	if not rules[name] then
		return
	end
	rules[name] = nil
	for i, n in ipairs(order) do
		if n == name then
			table.remove(order, i)
			break
		end
	end
end

--- 已注册的规则名（排查 / 测试用）
---@return string[]
function M.registered()
	return vim.deepcopy(order)
end

--- 这个 buffer 是不是外来终端
---@param bufnr integer
---@return boolean foreign
---@return string|nil rule 命中的规则名（便于排查）
function M.is_foreign(bufnr)
	if not api.nvim_buf_is_valid(bufnr) then
		return true, "invalid-buffer"
	end
	local ctx = {
		bufnr = bufnr,
		ft = vim.bo[bufnr].filetype,
		buftype = vim.bo[bufnr].buftype,
		name = api.nvim_buf_get_name(bufnr),
		wins = fn.win_findbuf(bufnr),
	}
	for _, name in ipairs(order) do
		local ok, hit = pcall(rules[name].match, ctx)
		if ok and hit then
			return true, name
		end
	end
	return false
end

--- 这个窗口是否「有主」：插件锁住了它，或它显示的是外来的 terminal buffer。
--- 终端面板要切分窗口、要换 buffer 之前都应该先问一句。
---@param win integer
---@return boolean claimed
---@return string|nil reason
function M.window_claimed(win)
	if not api.nvim_win_is_valid(win) then
		return true, "invalid-window"
	end
	if fn.exists("&winfixbuf") == 1 and vim.wo[win].winfixbuf then
		return true, "winfixbuf"
	end
	local bufnr = api.nvim_win_get_buf(win)
	if vim.bo[bufnr].buftype == "terminal" then
		return M.is_foreign(bufnr)
	end
	return false
end

-- 通用规则：插件用 filetype 标记的终端
M.register({
	name = "foreign-filetype",
	desc = "buftype=terminal 且 filetype 已被别的插件占用",
	match = function(ctx)
		return ctx.buftype == "terminal" and ctx.ft ~= "" and ctx.ft ~= "tab_terminal"
	end,
})

-- 通用规则：没有宿主 job 的「假终端」。
-- 典型是「把命令输出灌进 nvim_open_term() 的 buffer，再丢进浮窗显示」的插件
-- （neotest 的 test output、各种 preview/console 面板）。它们没有 shell 可管，
-- 收编进来只会把别人的浮窗内容改名成 Term (N)、抢走活动终端；浮窗一关就留下
-- 一个「假面板」，下一次 C-; / 侧栏重开时拿到已失效的窗口句柄（E5108）。
-- 判据用 terminal_job_id：termopen() 建的终端它有值（进程退出后仍在），
-- nvim_open_term() 建的 buffer 永远是 nil。
M.register({
	name = "no-host-job",
	desc = "buftype=terminal 但没有关联 job（输出缓冲被当终端显示）",
	match = function(ctx)
		return ctx.buftype == "terminal" and vim.b[ctx.bufnr].terminal_job_id == nil
	end,
})

-- 通用规则：显示在 'winfixbuf' 窗口里的终端。窗口被锁在自己的 buffer 上，
-- 反过来也就说明它不归我们调度（换 buffer 会 E1513）。
M.register({
	name = "locked-window",
	desc = "终端显示在 winfixbuf 窗口里（插件锁住了窗口）",
	match = function(ctx)
		if ctx.buftype ~= "terminal" or fn.exists("&winfixbuf") ~= 1 then
			return false
		end
		for _, win in ipairs(ctx.wins) do
			if vim.wo[win].winfixbuf then
				return true
			end
		end
		return false
	end,
})

return M
