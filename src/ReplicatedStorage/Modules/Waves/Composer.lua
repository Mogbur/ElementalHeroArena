local Composer = {}

-- very light rules; tune later
local roster = {
	{ kind="Basic",  w=1.0 },
	{ kind="Runner", w=0.2 },  -- drip them in
	{ kind="Archer", w=0.3 },
}

local function pickKind(wave)
	-- scale ranged weight upward slowly
	local r = {}
	local sum = 0
	for _,e in ipairs(roster) do
		local w = e.w
		if e.kind == "Archer" then w = w * (1.0 + math.min(0.8, (wave-1)/30)) end
		sum += w; r[#r+1] = {kind=e.kind, w=sum}
	end
	local t = math.random() * sum
	for _,e in ipairs(r) do if t <= e.w then return e.kind end end
	return "Basic"
end

function Composer.build(args)
	local wave     = args.wave or 1
	local count    = args.count or 3
	local list     = {}
	for i=1,count do
		local k = pickKind(wave)
		list[k] = (list[k] or 0) + 1
	end
	-- clamp per-kind counts (simple balance guard)
	local maxA = math.max(1, math.floor(count * 0.5))   -- ≤50% archers
	local maxR = math.max(1, math.floor(count * 0.7))   -- ≤60% runners
	if (list["Archer"] or 0) > maxA then list["Archer"] = maxA end
	if (list["Runner"] or 0) > maxR then list["Runner"] = maxR end
	local out = {}
	for k,n in pairs(list) do out[#out+1] = {kind=k, n=n} end
	table.sort(out, function(a,b) return a.kind<b.kind end)
	return { list = out }
end

return Composer