-- Anticheat Probe v6 — callstack attribution, auto-probes, timeline, sUNC.
-- Read-only by default. Auto-probe mode makes controlled, reverted state changes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

local SCHEMA = 6
if getgenv and getgenv().ACProbeV6Loaded then return end
if getgenv then getgenv().ACProbeV6Loaded = true end

-- ============================================================
-- Primitives (Mac-safe, sUNC-aware)
-- ============================================================
local getrawmt          = getrawmetatable or (debug and debug.getmetatable)
local newcclosure       = newcclosure or function(f) return f end
local setclipboard      = setclipboard or toclipboard or (syn and syn.write_clipboard)
local getnamecallmethod = getnamecallmethod or function() return nil end
local decompile         = decompile or (syn and syn.decompile)

local function safe(fn, ...)
    local ok, r = pcall(fn, ...)
    if ok then return r end
    return nil
end

-- ============================================================
-- Executor identity
-- ============================================================
local Executor = {name="Unknown", version="?", confidence="low", evidence={}, os="unknown"}

local function detectExecutor()
    local info = {name="Unknown", version="?", confidence="low", evidence={}, os="unknown"}
    if type(identifyexecutor) == "function" then
        local n, v = identifyexecutor()
        if type(n) == "string" then
            info.name, info.version, info.confidence = n, tostring(v or "?"), "high"
            table.insert(info.evidence, "identifyexecutor() -> " .. n)
        end
    end
    if info.name == "Unknown" and type(getexecutorname) == "function" then
        local n = safe(getexecutorname)
        if type(n) == "string" then
            info.name, info.confidence = n, "high"
            table.insert(info.evidence, "getexecutorname() -> " .. n)
        end
    end
    if type(getexecutorversion) == "function" then
        local v = safe(getexecutorversion)
        if v ~= nil then
            info.version = tostring(v)
            table.insert(info.evidence, "getexecutorversion() -> " .. tostring(v))
        end
    end
    local genv = type(getgenv) == "function" and safe(getgenv) or {}
    local sigs = {
        {"Opiumware", "opiumware global", function() return opiumware ~= nil or (genv and genv.Opiumware) end},
        {"MacSploit", "macsploit global", function() return macsploit ~= nil end},
        {"Synapse X", "syn.protect_gui", function() return syn and syn.protect_gui end},
        {"Script-Ware", "ScriptWare", function() return ScriptWare ~= nil end},
        {"KRNL", "KRNL_LOADED", function() return (genv.KRNL_LOADED or KRNL_LOADED) ~= nil end},
        {"Fluxus", "fluxus", function() return fluxus ~= nil end},
        {"Hydrogen", "h2", function() return (h2 or Hydrogen) ~= nil end},
        {"Electron", "electron", function() return electron ~= nil end},
        {"AWP", "AWP", function() return AWP ~= nil end},
        {"Solara", "solara", function() return solara ~= nil end},
        {"Wave", "wave", function() return wave ~= nil end},
        {"Trigon", "trigon", function() return trigon ~= nil end},
        {"Arceus X", "ArceusX", function() return ArceusX ~= nil end},
    }
    for _, s in ipairs(sigs) do
        if safe(s[3]) then
            if info.name == "Unknown" then info.name, info.confidence = s[1], "medium" end
            table.insert(info.evidence, s[2])
        end
    end
    local lname = info.name:lower()
    if lname:find("opiumware") or lname:find("macsploit") or lname:find("hydrogen") or lname:find("ios") then
        info.os = "macOS / iOS (likely)"
    elseif lname:find("synapse") or lname:find("krnl") or lname:find("fluxus") then
        info.os = "Windows (likely)"
    else
        info.os = "unknown"
    end
    return info
end
Executor = detectExecutor()

-- ============================================================
-- Compat test (execution-based, sUNC shape)
-- ============================================================
local Compat = {results={}, passed=0, failed=0, total=0, score=0, earned=0, possible=0}

local function T(name, cat, weight, fn) return {name=name, cat=cat, weight=weight, fn=fn} end

local compatTests = {
    T("identifyexecutor", "identity", 0, function()
        if type(identifyexecutor) ~= "function" then return false, "missing" end
        local ok, n = pcall(identifyexecutor)
        return ok and type(n) == "string", tostring(n)
    end),
    T("getgenv", "env", 3, function()
        if type(getgenv) ~= "function" then return false, "missing" end
        local env = safe(getgenv)
        if type(env) ~= "table" then return false, "non-table" end
        local k = "__acp_" .. math.random(1e6)
        env[k] = 1; local rb = env[k]; env[k] = nil
        return rb == 1, "read/write ok"
    end),
    T("getrenv", "env", 1, function() return type(safe(getrenv)) == "table", "returns table" end),
    T("getrawmetatable+setreadonly", "meta", 5, function()
        if type(getrawmt) ~= "function" or type(setreadonly) ~= "function" then return false, "missing" end
        local mt = safe(getrawmt, game)
        if type(mt) ~= "table" then return false, "no game mt" end
        if not pcall(setreadonly, mt, false) then return false, "unlock failed" end
        pcall(setreadonly, mt, true)
        return true, "metatable control works"
    end),
    T("hookfunction", "hook", 4, function()
        if type(hookfunction) ~= "function" then return false, "missing" end
        local t = function(x) return x end
        local ok, orig = pcall(hookfunction, t, function(x) return x * 10 end)
        if not ok then return false, "hook threw" end
        local r = t(5)
        pcall(hookfunction, t, orig)
        return r == 50, "r=" .. tostring(r)
    end),
    T("hookmetamethod", "hook", 3, function()
        if type(hookmetamethod) ~= "function" then return false, "missing" end
        local obj = setmetatable({}, {__index = function() return "orig" end})
        local ok, orig = pcall(hookmetamethod, obj, "__index", function() return "hooked" end)
        if not ok then return false, "threw" end
        local r = obj.x
        pcall(hookmetamethod, obj, "__index", orig)
        return r == "hooked", "works"
    end),
    T("getconnections", "signal", 3, function()
        if type(getconnections) ~= "function" then return false, "missing" end
        local conn = RunService.Heartbeat:Connect(function() end)
        task.wait()
        local ok, list = pcall(getconnections, RunService.Heartbeat)
        conn:Disconnect()
        if not ok or type(list) ~= "table" then return false, "threw" end
        return #list > 0, "count=" .. #list
    end),
    T("file I/O", "file", 4, function()
        if type(readfile) ~= "function" or type(writefile) ~= "function" then return false, "missing" end
        local p = "ACProbe_v6.tmp"
        local c = "t" .. math.random(1e7)
        if not pcall(writefile, p, c) then return false, "write threw" end
        local rb = safe(readfile, p)
        if type(delfile) == "function" then pcall(delfile, p) end
        return rb == c, rb == c and "roundtrip ok" or "mismatch"
    end),
    T("getscriptclosure", "script", 3, function()
        if type(getscriptclosure) ~= "function" then return false, "missing" end
        for _, d in ipairs(game:GetDescendants()) do
            if d:IsA("LocalScript") then
                local ok, fn = pcall(getscriptclosure, d)
                if ok and type(fn) == "function" then return true, "ok on " .. d.Name end
            end
        end
        return false, "no testable"
    end),
    T("decompile", "script", 3, function()
        if type(decompile) ~= "function" then return false, "missing" end
        for _, d in ipairs(game:GetDescendants()) do
            if d:IsA("LocalScript") then
                local ok, src = pcall(decompile, d)
                if ok and type(src) == "string" and #src > 0 then return true, "ok (" .. #src .. " chars)" end
            end
        end
        return false, "no testable"
    end),
    T("debug.getinfo", "reflection", 3, function()
        if not debug or type(debug.getinfo) ~= "function" then return false, "missing" end
        local info = safe(debug.getinfo, 1, "Sl")
        if not info then return false, "returned nil" end
        return true, "source=" .. tostring(info.source):sub(1, 20)
    end),
    T("getgc", "reflection", 2, function()
        return type(safe(getgc, false)) == "table", "table returned"
    end),
    T("getupvalue+setupvalue", "reflection", 2, function()
        if type(getupvalue) ~= "function" or type(setupvalue) ~= "function" then return false, "missing" end
        local x = 10
        local fn = function() return x end
        local ok, _, v = pcall(getupvalue, fn, 1)
        if not ok or v ~= 10 then return false, "getupvalue wrong" end
        pcall(setupvalue, fn, 1, 42)
        return fn() == 42, "upvalue control works"
    end),
    T("setclipboard", "io", 1, function() return type(setclipboard) == "function", "available" end),
    T("getnilinstances", "reflection", 1, function() return type(safe(getnilinstances)) == "table", "table returned" end),
    T("Drawing", "graphics", 1, function()
        if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then return false, "missing" end
        local ok, o = pcall(Drawing.new, "Square")
        if ok and o then pcall(function() o:Remove() end) end
        return ok, ok and "new ok" or "new failed"
    end),
    T("getthreadidentity", "identity", 1, function()
        if type(getthreadidentity) == "function" then
            return true, "id=" .. tostring(safe(getthreadidentity))
        elseif type(getidentity) == "function" then
            return true, "getidentity id=" .. tostring(safe(getidentity))
        end
        return false, "missing"
    end),
}

-- sUNC shape check
local sUNC = {
    {name="getgenv", getter=function() return type(getgenv)=="function" end},
    {name="getrenv", getter=function() return type(getrenv)=="function" end},
    {name="getreg", getter=function() return type(getreg)=="function" end},
    {name="getrawmetatable", getter=function() return type(getrawmetatable)=="function" end},
    {name="setreadonly", getter=function() return type(setreadonly)=="function" end},
    {name="isreadonly", getter=function() return type(isreadonly)=="function" end},
    {name="hookfunction", getter=function() return type(hookfunction)=="function" end},
    {name="hookmetamethod", getter=function() return type(hookmetamethod)=="function" end},
    {name="getnamecallmethod", getter=function() return type(getnamecallmethod)=="function" end},
    {name="newcclosure", getter=function() return type(newcclosure)=="function" end},
    {name="checkcaller", getter=function() return type(checkcaller)=="function" end},
    {name="iscclosure", getter=function() return type(iscclosure)=="function" end},
    {name="islclosure", getter=function() return type(islclosure)=="function" end},
    {name="clonefunction", getter=function() return type(clonefunction)=="function" end},
    {name="getupvalue", getter=function() return type(getupvalue)=="function" end},
    {name="setupvalue", getter=function() return type(setupvalue)=="function" end},
    {name="getconstant", getter=function() return type(getconstant)=="function" end},
    {name="setconstant", getter=function() return type(setconstant)=="function" end},
    {name="getconstants", getter=function() return type(getconstants)=="function" end},
    {name="getprotos", getter=function() return type(getprotos)=="function" end},
    {name="loadstring", getter=function() return type(loadstring)=="function" end},
    {name="identifyexecutor", getter=function() return type(identifyexecutor)=="function" end},
    {name="getexecutorname", getter=function() return type(getexecutorname)=="function" end},
    {name="getscriptclosure", getter=function() return type(getscriptclosure)=="function" end},
    {name="getscriptbytecode", getter=function() return type(getscriptbytecode)=="function" end},
    {name="getloadedmodules", getter=function() return type(getloadedmodules)=="function" end},
    {name="getscripts", getter=function() return type(getscripts)=="function" end},
    {name="getconnections", getter=function() return type(getconnections)=="function" end},
    {name="firesignal", getter=function() return type(firesignal)=="function" end},
    {name="firetouchinterest", getter=function() return type(firetouchinterest)=="function" end},
    {name="fireclickdetector", getter=function() return type(fireclickdetector)=="function" end},
    {name="fireproximityprompt", getter=function() return type(fireproximityprompt)=="function" end},
    {name="getinstances", getter=function() return type(getinstances)=="function" end},
    {name="getnilinstances", getter=function() return type(getnilinstances)=="function" end},
    {name="getgc", getter=function() return type(getgc)=="function" end},
    {name="getcallbackvalue", getter=function() return type(getcallbackvalue)=="function" end},
    {name="setcallbackvalue", getter=function() return type(setcallbackvalue)=="function" end},
    {name="gethiddenproperty", getter=function() return type(gethiddenproperty)=="function" end},
    {name="sethiddenproperty", getter=function() return type(sethiddenproperty)=="function" end},
    {name="readfile", getter=function() return type(readfile)=="function" end},
    {name="writefile", getter=function() return type(writefile)=="function" end},
    {name="appendfile", getter=function() return type(appendfile)=="function" end},
    {name="isfile", getter=function() return type(isfile)=="function" end},
    {name="isfolder", getter=function() return type(isfolder)=="function" end},
    {name="makefolder", getter=function() return type(makefolder)=="function" end},
    {name="delfile", getter=function() return type(delfile)=="function" end},
    {name="deletefolder", getter=function() return type(deletefolder)=="function" end},
    {name="listfiles", getter=function() return type(listfiles)=="function" end},
    {name="getcustomasset", getter=function() return type(getcustomasset)=="function" end},
    {name="request", getter=function() return type(request)=="function" end},
    {name="http_request", getter=function() return type(http_request)=="function" end},
    {name="setclipboard", getter=function() return type(setclipboard)=="function" end},
    {name="setfpscap", getter=function() return type(setfpscap)=="function" end},
    {name="getthreadidentity", getter=function() return type(getthreadidentity)=="function" end},
    {name="setthreadidentity", getter=function() return type(setthreadidentity)=="function" end},
    {name="Drawing", getter=function() return type(Drawing)=="table" end},
}

local sUNCStatus = {present={}, missing={}, count=0, total=0}

local function runSUCNC()
    sUNCStatus.present = {}
    sUNCStatus.missing = {}
    for _, t in ipairs(sUNC) do
        local ok = false
        pcall(function() ok = t.getter() end)
        if ok then table.insert(sUNCStatus.present, t.name)
        else table.insert(sUNCStatus.missing, t.name) end
    end
    sUNCStatus.count = #sUNCStatus.present
    sUNCStatus.total = #sUNC
end

local features = {}

local function runCompat()
    Compat.results = {}
    local pw, tw = 0, 0
    for _, t in ipairs(compatTests) do
        local ok, r = pcall(t.fn)
        if not ok then r = "threw" end
        table.insert(Compat.results, {name=t.name, cat=t.cat, weight=t.weight, ok=ok, msg=tostring(r)})
        tw = tw + t.weight
        if ok then pw = pw + t.weight end
        task.wait()
    end
    Compat.passed, Compat.failed, Compat.total = 0, 0, #Compat.results
    for _, r in ipairs(Compat.results) do
        if r.ok then Compat.passed = Compat.passed + 1 else Compat.failed = Compat.failed + 1 end
    end
    Compat.earned, Compat.possible = pw, tw
    Compat.score = tw > 0 and math.floor(pw / tw * 100) or 0

    for k in pairs(features) do features[k] = false end
    for _, r in ipairs(Compat.results) do
        if r.ok then
            if r.name == "getrawmetatable+setreadonly" then features.getrawmetatable = true features.setreadonly = true end
            if r.name == "getconnections" then features.getconnections = true end
            if r.name == "getgenv" then features.getgenv = true end
            if r.name == "decompile" then features.decompile = true end
            if r.name == "file I/O" then features.file_io = true end
            if r.name == "debug.getinfo" then features.debug_getinfo = true end
        end
    end
end

-- ============================================================
-- Callstack attribution
-- ============================================================
local Callstack = {cache = {}}

local function getOurSource()
    local ok, s = pcall(function() return debug.info(1, "s") end)
    return ok and s or "=[unknown]"
end

local OUR_SOURCE = getOurSource()

function Callstack.trace()
    if not debug or type(debug.getinfo) ~= "function" then return nil end
    for i = 3, 15 do
        local ok, info = pcall(debug.getinfo, i, "Slf")
        if not ok or not info then break end
        local src = info.source
        if src and src ~= OUR_SOURCE and src ~= "=[C]" then
            local clean = src
            if clean:sub(1, 1) == "@" or clean:sub(1, 1) == "=" then clean = clean:sub(2) end
            local path = clean
            local line = info.currentline or 0
            local key = path .. ":" .. tostring(line)
            if not Callstack.cache[key] then
                Callstack.cache[key] = {path = path, line = line, func = info.name, count = 0, firstSeen = os.time()}
            end
            Callstack.cache[key].count = Callstack.cache[key].count + 1
            return Callstack.cache[key]
        end
    end
    return nil
end

-- ============================================================
-- Timeline
-- ============================================================
local Timeline = {events = {}, MAX = 800}

function Timeline.add(typ, text, extra)
    table.insert(Timeline.events, {
        t = os.clock(), realTime = os.time(),
        typ = typ, text = text, extra = extra or {},
    })
    if #Timeline.events > Timeline.MAX then table.remove(Timeline.events, 1) end
end

-- ============================================================
-- Behavioral profiler
-- ============================================================
local Profiler = {
    enabled = true, window = 60, stateWindow = 200,
    corrThreshold = 0.6, remotes = {}, states = {}, lastState = nil, installed = false,
}

function Profiler.newProfile(name)
    return {
        name = name, calls = 0,
        firstSeen = os.clock(), lastSeen = os.clock(),
        shapes = {}, callTimes = {}, corr = {},
        callers = {},
    }
end

local function getState()
    local char = player.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return nil end
    return {
        pos = hrp.Position, hp = hum.Health, walkspeed = hum.WalkSpeed,
        jumppower = hum.JumpPower, hipheight = hum.HipHeight or 0,
        state = (hum:GetState()).Name,
    }
end

local function diffState(a, b, field, thr)
    if not a or not b then return false end
    if field == "pos" then return (a.pos - b.pos).Magnitude >= (thr or 3) end
    if field == "hp" then return math.abs(a.hp - b.hp) >= (thr or 1) end
    if field == "walkspeed" then return math.abs(a.walkspeed - b.walkspeed) >= (thr or 0.5) end
    if field == "jumppower" then return math.abs(a.jumppower - b.jumppower) >= (thr or 0.5) end
    if field == "hipheight" then return math.abs(a.hipheight - b.hipheight) >= (thr or 0.5) end
    if field == "state" then return a.state ~= b.state end
    return false
end

function Profiler.snapshot()
    local s = getState()
    if not s then return end
    local prev = Profiler.lastState
    Profiler.lastState = s
    table.insert(Profiler.states, {t = os.clock(), snap = s})
    if #Profiler.states > Profiler.stateWindow then table.remove(Profiler.states, 1) end
    return s, prev
end

local function argShape(args)
    local parts = {}
    for i = 1, #args do
        local v = args[i]
        local t = typeof(v)
        if t == "table" then
            local ks = {}
            for k in pairs(v) do table.insert(ks, tostring(k)) end
            table.sort(ks)
            parts[i] = "{" .. table.concat(ks, ",") .. "}"
        elseif t == "Instance" then parts[i] = "I:" .. v.ClassName
        else parts[i] = t end
    end
    return table.concat(parts, "|")
end

function Profiler.recordCall(remoteName, method, args, caller)
    if not Profiler.enabled then return end
    local p = Profiler.remotes[remoteName]
    if not p then p = Profiler.newProfile(remoteName) Profiler.remotes[remoteName] = p end
    p.calls = p.calls + 1
    p.lastSeen = os.clock()
    local shape = argShape(args)
    p.shapes[shape] = (p.shapes[shape] or 0) + 1
    table.insert(p.callTimes, os.clock())
    while #p.callTimes > 0 and p.callTimes[1] < os.clock() - Profiler.window do
        table.remove(p.callTimes, 1)
    end
    if caller and caller.path then
        local key = caller.path .. ":" .. caller.line
        p.callers[key] = (p.callers[key] or 0) + 1
        Timeline.add("remote", string.format("%s ← %s:%s", remoteName, caller.path, caller.line),
            {remote = remoteName, caller = caller.path, line = caller.line})
    else
        Timeline.add("remote", remoteName .. " ← unknown", {remote = remoteName})
    end

    local cur, prev = Profiler.snapshot()
    if prev and cur then
        for _, field in ipairs({"pos", "hp", "walkspeed", "jumppower", "hipheight", "state"}) do
            if diffState(prev, cur, field) then
                local c = p.corr[field] or {matched = 0, total = 0}
                c.matched = c.matched + 1
                p.corr[field] = c
                Timeline.add("corr", remoteName .. " correlates with " .. field .. " change", {remote = remoteName, field = field})
            end
        end
    end
    if #Profiler.states >= 2 then
        local older = Profiler.states[1].snap
        local newer = Profiler.states[#Profiler.states].snap
        for _, field in ipairs({"pos", "hp", "walkspeed", "jumppower", "hipheight"}) do
            if diffState(older, newer, field) then
                local c = p.corr[field]
                if c then c.total = c.total + 1 end
            end
        end
    end
end

function Profiler.shapeEntropy(p)
    local total = 0
    for _, c in pairs(p.shapes) do total = total + c end
    if total <= 1 then return 0 end
    local h = 0
    for _, c in pairs(p.shapes) do
        local pr = c / total
        h = h - pr * math.log(pr)
    end
    local maxH = math.log(math.max(total, 2))
    return maxH > 0 and h / maxH or 0
end

function Profiler.rate(p)
    if #p.callTimes < 2 then return 0 end
    local span = p.callTimes[#p.callTimes] - p.callTimes[1]
    return span > 0 and #p.callTimes / span or 0
end

function Profiler.correlations(p)
    local out = {}
    for field, c in pairs(p.corr) do
        if c.matched > 0 and c.total > 0 then
            table.insert(out, {field=field, ratio=c.matched/c.total, matched=c.matched, total=c.total})
        end
    end
    table.sort(out, function(a, b) return a.ratio > b.ratio end)
    return out
end

local function installProfilerHook()
    if Profiler.installed then return end
    if not features.getrawmetatable or not features.setreadonly or type(getnamecallmethod) ~= "function" then return end
    local ok, mt = pcall(getrawmt, game)
    if not ok or not mt then return end
    local old = mt.__namecall
    pcall(setreadonly, mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local m = getnamecallmethod()
        if m == "FireServer" or m == "InvokeServer" then
            local nm = "?"
            pcall(function() nm = self.Name end)
            local args = table.pack(...)
            local caller = Callstack.trace()
            Profiler.recordCall(nm, m, args, caller)
        elseif m == "Kick" and self == player then
            currentSession.endReason = "kicked"
            currentSession.kickMessage = tostring((select(1, ...)) or "")
            currentSession.ended = os.time()
            saveNow()
        end
        return old(self, ...)
    end)
    pcall(setreadonly, mt, true)
    Profiler.installed = true
end

-- ============================================================
-- Auto-probe (opt-in, controlled state changes with revert)
-- ============================================================
local AutoProbe = {results = {}, running = false, riskyEnabled = false}

local function snapshotCounts()
    local counts = {}
    for name, p in pairs(Profiler.remotes) do counts[name] = p.calls end
    return counts
end

local function diffCounts(before, after)
    local fired = {}
    for name, count in pairs(after) do
        local prev = before[name] or 0
        if count > prev then fired[name] = count - prev end
    end
    return fired
end

local function waitRemoteWindow(seconds)
    local t0 = os.clock()
    while os.clock() - t0 < seconds do task.wait(0.05) end
end

local function probe(name, setup, teardown, waitSec, risky)
    if risky and not AutoProbe.riskyEnabled then
        return {name=name, level="skip", msg="risky probe disabled"}
    end
    local before = snapshotCounts()
    local okS, errS = pcall(setup)
    if not okS then
        pcall(teardown)
        return {name=name, level="fail", msg="setup error: " .. tostring(errS)}
    end
    waitRemoteWindow(waitSec or 2)
    local after = snapshotCounts()
    local okT, errT = pcall(teardown)
    local fired = diffCounts(before, after)
    local count = 0
    for _, c in pairs(fired) do count = count + c end
    local summary = {}
    for rn, c in pairs(fired) do table.insert(summary, rn .. "(" .. c .. ")") end
    table.sort(summary)
    local level = count > 0 and "warn" or "ok"
    local msg = count > 0 and ("remotes: " .. table.concat(summary, ", ")) or "no remotes fired"
    if not okT then msg = msg .. " [teardown failed: " .. tostring(errT) .. "]" end
    return {name=name, level=level, msg=msg, fired=fired, count=count, risky=risky}
end

local function runAutoProbes()
    if AutoProbe.running then return end
    AutoProbe.running = true
    AutoProbe.results = {}
    titleLabel.Text = "  Anticheat Probe v6 — probing..."

    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then
        table.insert(AutoProbe.results, {name="init", level="fail", msg="no character"})
        AutoProbe.running = false
        renderAll()
        return
    end

    local baseWS = hum.WalkSpeed
    local baseJP = hum.JumpPower
    local baseHH = hum.HipHeight or 0
    local baseCF = hrp.CFrame

    local p1 = probe("WalkSpeed +20%",
        function() hum.WalkSpeed = baseWS * 1.2 end,
        function() hum.WalkSpeed = baseWS end, 2, false)
    table.insert(AutoProbe.results, p1)
    if p1.count and p1.count > 0 then
        for rn in pairs(p1.fired) do
            push("remotes", "warn", 6, string.format("Probe: '%s' fired after WalkSpeed change", rn), {remoteName = rn})
        end
    end
    task.wait(0.5)

    local p2 = probe("JumpPower +50%",
        function() hum.JumpPower = baseJP * 1.5 end,
        function() hum.JumpPower = baseJP end, 2, false)
    table.insert(AutoProbe.results, p2)
    if p2.count and p2.count > 0 then
        for rn in pairs(p2.fired) do
            push("remotes", "warn", 6, string.format("Probe: '%s' fired after JumpPower change", rn), {remoteName = rn})
        end
    end
    task.wait(0.5)

    local p3 = probe("HipHeight +3",
        function() hum.HipHeight = baseHH + 3 end,
        function() hum.HipHeight = baseHH end, 2, false)
    table.insert(AutoProbe.results, p3)
    if p3.count and p3.count > 0 then
        for rn in pairs(p3.fired) do
            push("remotes", "warn", 6, string.format("Probe: '%s' fired after HipHeight change", rn), {remoteName = rn})
        end
    end
    task.wait(0.5)

    local p4 = probe("Position +10 studs X",
        function() hrp.CFrame = baseCF + Vector3.new(10, 0, 0) end,
        function() if hrp and hrp.Parent then hrp.CFrame = baseCF end end, 2, false)
    table.insert(AutoProbe.results, p4)
    if p4.count and p4.count > 0 then
        for rn in pairs(p4.fired) do
            push("remotes", "warn", 6, string.format("Probe: '%s' fired after position shift", rn), {remoteName = rn})
        end
    end
    task.wait(0.5)

    if AutoProbe.riskyEnabled then
        local p5 = probe("Noclip 2s",
            function()
                for _, d in ipairs(char:GetDescendants()) do
                    if d:IsA("BasePart") then d.CanCollide = false end
                end
            end,
            function()
                for _, d in ipairs(char:GetDescendants()) do
                    if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then d.CanCollide = true end
                end
            end, 2, true)
        table.insert(AutoProbe.results, p5)
        if p5.count and p5.count > 0 then
            for rn in pairs(p5.fired) do
                push("remotes", "warn", 6, string.format("Probe: '%s' fired after noclip", rn), {remoteName = rn})
            end
        end
        task.wait(0.5)
    end

    Timeline.add("system", "Auto-probe suite complete (" .. #AutoProbe.results .. " probes)")
    saveNow()
    renderAll()
    titleLabel.Text = "  Anticheat Probe v6"
    AutoProbe.running = false
end

-- ============================================================
-- Architecture classifier
-- ============================================================
local Arch = {classification="None detected", confidence="low", reasons={}}

local function classifyArch()
    local hookCount, connectionHits, remoteHits, sourceHits, correlated, confirmedAC = 0, 0, 0, 0, 0, 0
    for _, e in ipairs(findings.hooks or {}) do
        if e.level == "warn" or e.level == "fail" then hookCount = hookCount + 1 end
    end
    for _, e in ipairs(findings.connections or {}) do
        if e.level == "fail" then connectionHits = connectionHits + 1 end
    end
    for _, e in ipairs(findings.remotes or {}) do
        if e.level == "warn" or e.level == "fail" then remoteHits = remoteHits + 1 end
    end
    for _, e in ipairs(findings.scripts or {}) do
        if e.level == "fail" then sourceHits = sourceHits + 1 end
    end
    for _, p in pairs(Profiler.remotes) do
        for _, c in ipairs(Profiler.correlations(p)) do
            if c.ratio >= 0.7 and c.matched >= 3 then correlated = correlated + 1 break end
        end
    end
    for _, e in pairs(Reputation.entries) do
        if e.class == "confirmed_ac" then confirmedAC = confirmedAC + 1 end
    end

    Arch.reasons = {}
    local score = 0
    if hookCount > 0 then score = score + 2; table.insert(Arch.reasons, hookCount .. " suspicious Lua hook(s)") end
    if connectionHits > 0 then score = score + 2; table.insert(Arch.reasons, connectionHits .. " AC-shaped connection(s)") end
    if remoteHits > 0 then score = score + 1; table.insert(Arch.reasons, remoteHits .. " name-matched remote(s)") end
    if correlated > 0 then score = score + 3; table.insert(Arch.reasons, correlated .. " behavioral correlation(s)") end
    if sourceHits > 0 then score = score + 2; table.insert(Arch.reasons, sourceHits .. " source match(es)") end
    if confirmedAC > 0 then score = score + 2; table.insert(Arch.reasons, confirmedAC .. " confirmed AC") end

    if score == 0 then Arch.classification, Arch.confidence = "None detected", "high"
    elseif hookCount > 0 or sourceHits > 0 then
        Arch.classification, Arch.confidence = "Client-side (custom)", score >= 6 and "high" or "medium"
    elseif connectionHits > 0 then
        Arch.classification, Arch.confidence = "Client-side (behavioral)", score >= 4 and "high" or "medium"
    elseif correlated > 0 then
        Arch.classification, Arch.confidence = "Server-side (validated remotes)", "medium"
    elseif remoteHits > 0 then
        Arch.classification, Arch.confidence = "Server-side (remote endpoints)", "low"
    else
        Arch.classification, Arch.confidence = "Undetermined", "low"
    end
end

-- ============================================================
-- Findings + reputation
-- ============================================================
local sessionId = tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
local currentSession = {
    id=sessionId, account=player.Name, userId=player.UserId,
    placeId=game.PlaceId, started=os.time(),
    executor=Executor.name, executorVersion=Executor.version,
    compatScore=0, sUNC=sUNCStatus.count .. "/" .. sUNCStatus.total,
    findingCount=0,
}

local findings, findingsIndex = {}, {}
local CATEGORIES = {"environment","hooks","remotes","scripts","character","attributes","connections","tags"}
for _, c in ipairs(CATEGORIES) do findings[c] = {} end

local Reputation = {entries = {}}

function Reputation.Get(key) local e = Reputation.entries[key] return e and e.class or "unknown" end
function Reputation.Set(key, class, reason)
    if class == "unknown" then Reputation.entries[key] = nil
    else Reputation.entries[key] = {class=class, reason=reason or "", setAt=os.time()} end
    local f = findingsIndex[key]
    if f then
        if class == "confirmed_ac" then f.weight = math.max(f.weight or 0, 20); f.level = "fail"
        elseif class == "confirmed_benign" or class == "benign" then f.weight = 0
        elseif class == "suspect" then f.weight = math.max(f.weight or 0, 5) end
    end
    saveNow()
end

local SEV = {skip=0, ok=1, info=2, warn=3, fail=4}

local function push(cat, level, weight, text, extra)
    if not findings[cat] then findings[cat] = {} end
    local key = cat .. "|" .. text
    local rep = Reputation.Get(key)
    if rep == "confirmed_ac" then weight = math.max(weight or 0, 20) level = "fail"
    elseif rep == "confirmed_benign" then weight = 0 level = "ok"
    elseif rep == "benign" then weight = 0
    elseif rep == "suspect" then weight = math.max(weight or 0, 5) end

    local e = findingsIndex[key]
    if e then
        e.lastSeen = os.time()
        e.count = e.count + 1
        if weight > (e.weight or 0) then e.weight = weight end
        if (SEV[level] or 0) > (SEV[e.level] or 0) then e.level = level end
        if not table.find(e.sessions, sessionId) then table.insert(e.sessions, sessionId) end
        if not table.find(e.accounts, currentSession.account) then table.insert(e.accounts, currentSession.account) end
    else
        e = {
            level=level, weight=weight or 0, text=text,
            firstSeen=os.time(), lastSeen=os.time(), count=1,
            sessions={sessionId}, accounts={currentSession.account},
            remoteName = extra and extra.remoteName or nil,
            scriptPath = extra and extra.scriptPath or nil,
            callerPath = extra and extra.callerPath or nil,
        }
        findingsIndex[key] = e
        table.insert(findings[cat], e)
        if #findings[cat] > 500 then
            local r = table.remove(findings[cat], 1)
            if r then findingsIndex[cat .. "|" .. r.text] = nil end
        end
    end
end

-- ============================================================
-- Persistence
-- ============================================================
local STORAGE_FOLDER = "ACProbeV6"
local storagePath
local sessionHistory = {}

local function storagePathGet()
    if storagePath then return storagePath end
    if type(makefolder) == "function" and type(isfolder) == "function" then
        if not isfolder(STORAGE_FOLDER) then pcall(makefolder, STORAGE_FOLDER) end
        storagePath = STORAGE_FOLDER .. "/" .. tostring(game.PlaceId) .. ".json"
    else
        storagePath = "ACProbe_" .. tostring(game.PlaceId) .. ".json"
    end
    return storagePath
end

local function persistAvailable()
    return features.file_io
end

local function buildSnapshot()
    local fs = {}
    for _, cat in ipairs(CATEGORIES) do
        fs[cat] = {}
        for _, e in ipairs(findings[cat]) do
            table.insert(fs[cat], {
                level=e.level, weight=e.weight, text=e.text,
                firstSeen=e.firstSeen, lastSeen=e.lastSeen, count=e.count,
                sessions=e.sessions, accounts=e.accounts,
                remoteName=e.remoteName, scriptPath=e.scriptPath, callerPath=e.callerPath,
            })
        end
    end
    local hist, found = {}, false
    for _, s in ipairs(sessionHistory) do
        if s.id == sessionId then hist[#hist+1]=currentSession found=true
        else hist[#hist+1]=s end
    end
    if not found then hist[#hist+1]=currentSession end
    if #hist > 60 then
        local t = {}
        for i = #hist-59, #hist do t[#t+1] = hist[i] end
        hist = t
    end
    local rep = {}
    for k, v in pairs(Reputation.entries) do rep[k] = v end
    local prof = {}
    for name, p in pairs(Profiler.remotes) do
        prof[name] = {calls=p.calls, shapes=p.shapes, corr=p.corr, callers=p.callers,
                      firstSeen=p.firstSeen, lastSeen=p.lastSeen}
    end
    local probes = {}
    for _, r in ipairs(AutoProbe.results) do
        table.insert(probes, {name=r.name, level=r.level, msg=r.msg, fired=r.fired})
    end
    return {
        schema=SCHEMA, placeId=game.PlaceId, placeName=game.Name, updated=os.time(),
        executor={name=Executor.name, version=Executor.version, os=Executor.os},
        compat={score=Compat.score, passed=Compat.passed, failed=Compat.failed},
        sUNC={count=sUNCStatus.count, total=sUNCStatus.total, missing=sUNCStatus.missing},
        sessions=hist, findings=fs, reputation=rep, profiler=prof, probes=probes,
        architecture={classification=Arch.classification, confidence=Arch.confidence, reasons=Arch.reasons},
    }
end

local function saveNow()
    if not persistAvailable() then return end
    currentSession.compatScore = Compat.score
    currentSession.findingCount = 0
    for _, cat in ipairs(CATEGORIES) do currentSession.findingCount = currentSession.findingCount + #findings[cat] end
    local ok, enc = pcall(HttpService.JSONEncode, HttpService, buildSnapshot())
    if ok and type(enc) == "string" then pcall(writefile, storagePathGet(), enc) end
end

local function persistLoad()
    if not persistAvailable() then return nil end
    local p = storagePathGet()
    local ok, ex = pcall(isfile, p)
    if not ok or not ex then return nil end
    local okR, content = pcall(readfile, p)
    if not okR or type(content) ~= "string" or content == "" then return nil end
    local okD, data = pcall(HttpService.JSONDecode, HttpService, content)
    if not okD or type(data) ~= "table" then return nil end
    if data.placeId and data.placeId ~= game.PlaceId then return nil end
    return data
end

local function persistDelete()
    if not persistAvailable() then return end
    if type(delfile) == "function" then
        local ok, ex = pcall(isfile, storagePathGet())
        if ok and ex then pcall(delfile, storagePathGet()) end
    end
end

local function mergeLoaded(loaded)
    if type(loaded) ~= "table" then return 0, 0 end
    local merged, sess = 0, 0
    if type(loaded.sessions) == "table" then
        for _, s in ipairs(loaded.sessions) do
            if s.id ~= sessionId then
                if not s.endReason and not s.ended then s.endReason = "unknown" end
                table.insert(sessionHistory, s); sess = sess + 1
            end
        end
    end
    if type(loaded.findings) == "table" then
        for _, cat in ipairs(CATEGORIES) do
            local list = loaded.findings[cat]
            if type(list) == "table" then
                for _, e in ipairs(list) do
                    if type(e) == "table" and type(e.text) == "string" then
                        local key = cat .. "|" .. e.text
                        local ex = findingsIndex[key]
                        if ex then
                            ex.count = (ex.count or 1) + (e.count or 1) - 1
                            if e.firstSeen and (not ex.firstSeen or e.firstSeen < ex.firstSeen) then ex.firstSeen = e.firstSeen end
                            if e.lastSeen and (not ex.lastSeen or e.lastSeen > ex.lastSeen) then ex.lastSeen = e.lastSeen end
                            if (e.weight or 0) > (ex.weight or 0) then ex.weight = e.weight end
                            if (SEV[e.level] or 0) > (SEV[ex.level] or 0) then ex.level = e.level end
                            if type(e.sessions) == "table" then
                                for _, s in ipairs(e.sessions) do
                                    if not table.find(ex.sessions, s) then table.insert(ex.sessions, s) end
                                end
                            end
                            if type(e.accounts) == "table" then
                                for _, a in ipairs(e.accounts) do
                                    if not table.find(ex.accounts, a) then table.insert(ex.accounts, a) end
                                end
                            end
                        else
                            local entry = {
                                level=e.level or "info", weight=e.weight or 0, text=e.text,
                                firstSeen=e.firstSeen or os.time(), lastSeen=e.lastSeen or os.time(),
                                count=e.count or 1, sessions=e.sessions or {}, accounts=e.accounts or {},
                                remoteName=e.remoteName, scriptPath=e.scriptPath, callerPath=e.callerPath,
                            }
                            findingsIndex[key] = entry
                            table.insert(findings[cat], entry)
                        end
                        merged = merged + 1
                    end
                end
            end
        end
    end
    if type(loaded.reputation) == "table" then
        for k, v in pairs(loaded.reputation) do Reputation.entries[k] = v end
    end
    if type(loaded.profiler) == "table" then
        for name, p in pairs(loaded.profiler) do
            if not Profiler.remotes[name] then
                Profiler.remotes[name] = {
                    name=name, calls=p.calls or 0,
                    firstSeen=p.firstSeen or os.clock(), lastSeen=p.lastSeen or os.clock(),
                    shapes=p.shapes or {}, callTimes={}, corr=p.corr or {}, callers=p.callers or {},
                }
            end
        end
    end
    return merged, sess
end

-- ============================================================
-- Probes
-- ============================================================
local function pathOf(inst)
    local p, cur, g = {}, inst, 0
    while cur and cur ~= game and g < 40 do table.insert(p, 1, cur.Name); cur = cur.Parent; g = g + 1 end
    return "game." .. table.concat(p, ".")
end
local function fnSource(fn)
    if typeof(fn) ~= "function" or not debug or not debug.info then return nil end
    local ok, s = pcall(debug.info, fn, "s"); return ok and s or nil
end
local function safeDecompile(fn)
    if type(decompile) ~= "function" or typeof(fn) ~= "function" then return nil end
    local ok, src = pcall(decompile, fn)
    return (ok and type(src) == "string") and src or nil
end
local function isCClosure(fn)
    if typeof(fn) ~= "function" then return false end
    if type(iscclosure) == "function" then return iscclosure(fn) end
    if debug and debug.getinfo then
        local ok, i = pcall(debug.getinfo, fn)
        if ok and i then
            if i.what ~= "C" then return false end
            if debug.getupvalue then
                local ok2, _, v = pcall(debug.getupvalue, fn, 1)
                if ok2 and v ~= nil then return false end
            end
            return true
        end
    end
    return false
end
local function upvalues(fn)
    if not debug or not debug.getupvalue then return {} end
    local out, i = {}, 1
    while i <= 60 do
        local ok, n = pcall(debug.getupvalue, fn, i)
        if not ok or n == nil then break end
        if type(n) == "string" and not n:match("^%(") then table.insert(out, n) end
        i = i + 1
    end
    return out
end
local function fmtAgo(t)
    if not t then return "?" end
    local d = os.time() - t
    if d < 60 then return d .. "s ago" end
    if d < 3600 then return math.floor(d/60) .. "m ago" end
    if d < 86400 then return math.floor(d/3600) .. "h ago" end
    return math.floor(d/86400) .. "d ago"
end

local SIG = {
    remote = {"report","detect","flag","kick","ban","punish","cheat","hack","guard","sentry","trust","security","verify","validate","integrity","audit","suspicious","anomaly","violation","strike","warn","moderat","byfron","hyperion","krampus","anticheat","_ac","ac_","watchdog","monitor","sanction","enforce","patrol"},
    script = {"anti","ac_","_ac","guard","sentry","watch","detect","security","shield","protect","suspicious","moderat","integrity","trust","byfron","hyperion","krampus","watchdog","patrol","enforce","monitor"},
    source = {"anticheat","anti_cheat","anti-cheat","detection","suspicious","violation","integritycheck","integrity_check","tamper","kickplayer","banplayer","flagplayer","reportplayer","report_","hyperion","byfron","watchdog","humanoidstate","walkspeedcheck","speedcheck","jumpcheck"},
    attr = {"detect","flag","kick","report","ban","suspicious","violation","trust","verify","warn","strike","count","score","anomaly","cheater","hacker","exploiter","suspicion","threat"},
    tag = {"anticheat","ac_","_ac","sentry","guard","watch","flagged","suspicious","hacker","exploiter","cheater"},
    hookAC = {"reportremote","reportremoteevent","detectioncallback","flagcallback","detect","punish","kickcallback","acreport"},
    hookExec = {"oldnamecall","orig_namecall","original","old_index","hooktarget","originalnamecall"},
}

local function anyMatch(str, list)
    if not str then return nil end
    local l = str:lower()
    for _, kw in ipairs(list) do if l:find(kw, 1, true) then return kw end end
    return nil
end

local function probe_environment()
    for k, v in pairs(features) do
        push("environment", v and "ok" or "warn", v and 0 or 2, k .. (v and " available" or " MISSING"))
    end
    push("environment", "info", 0, string.format("Session %s · %s · %s", sessionId, currentSession.account, Executor.os))
end

local function probe_hooks()
    if not (features.getrawmetatable and features.setreadonly) then
        push("hooks", "skip", 0, "Skipped: getrawmetatable/setreadonly failed compat")
        return
    end
    local targets = {
        {name="game", obj=game}, {name="Instance", obj=Instance.new("Part")},
        {name="Humanoid", obj=Instance.new("Humanoid")}, {name="Player", obj=player},
    }
    for _, t in ipairs(targets) do
        local ok, mt = pcall(getrawmt, t.obj)
        if ok and mt then
            for _, key in ipairs({"__namecall", "__index", "__newindex"}) do
                local fn = rawget(mt, key)
                if typeof(fn) == "function" and not isCClosure(fn) then
                    local names = upvalues(fn)
                    local src = fnSource(fn)
                    local label = string.format("%s.%s is a Lua function (hooked)", t.name, key)
                    if src then label = label .. " — " .. tostring(src) end
                    if #names > 0 then label = label .. " — upvalues: " .. table.concat(names, ",") end
                    local attributed, weight = "unknown", 8
                    for _, kw in ipairs(SIG.hookAC) do
                        for _, n in ipairs(names) do
                            if n:lower():find(kw, 1, true) then
                                attributed, weight = "likely anticheat (upvalue '" .. n .. "')", 25
                                break
                            end
                        end
                        if attributed ~= "unknown" then break end
                    end
                    if attributed == "unknown" then
                        for _, kw in ipairs(SIG.hookExec) do
                            for _, n in ipairs(names) do
                                if n:lower():find(kw, 1, true) then
                                    attributed, weight = "likely executor (upvalue '" .. n .. "')", 2
                                    break
                                end
                            end
                            if attributed ~= "unknown" then break end
                        end
                    end
                    local dsrc = safeDecompile(fn)
                    if dsrc then
                        local kw = anyMatch(dsrc, SIG.source)
                        if kw then attributed = "confirmed anticheat (source matched '" .. kw .. "')" weight = 30 end
                    end
                    push("hooks", weight >= 20 and "fail" or (weight >= 5 and "warn" or "info"),
                        weight, label .. " — " .. attributed)
                end
            end
        end
    end
    local okS, smt = pcall(getrawmt, "")
    if okS and smt then
        for _, key in ipairs({"__index", "__newindex"}) do
            local fn = rawget(smt, key)
            if typeof(fn) == "function" and not isCClosure(fn) then
                push("hooks", "warn", 10, "string." .. key .. " is a Lua function (executor hook?)")
            end
        end
    end
end

local function probe_remotes()
    local ok, descs = pcall(function() return ReplicatedStorage:GetDescendants() end)
    if not ok then push("remotes", "fail", 5, "RS scan failed") return end
    local hits, total = 0, 0
    for _, d in ipairs(descs) do
        if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") or d:IsA("UnreliableRemoteEvent") then
            total = total + 1
            local kw = anyMatch(d.Name, SIG.remote)
            if kw then
                hits = hits + 1
                if hits <= 30 then
                    local p = Profiler.remotes[d.Name]
                    local info = p and string.format(" | %d calls", p.calls) or ""
                    push("remotes", "warn", 4,
                        string.format("'%s' [%s] at %s (kw: %s)%s", d.Name, d.ClassName, pathOf(d), kw, info),
                        {remoteName = d.Name})
                end
            end
        end
    end
    if total == 0 then push("remotes", "skip", 0, "No remotes in RS")
    elseif hits == 0 then push("remotes", "ok", 0, string.format("%d remotes, no name matches", total))
    elseif hits > 30 then push("remotes", "warn", 2, string.format("... and %d more", hits - 30)) end
end

local function probe_scripts()
    local roots = {
        player:FindFirstChild("PlayerScripts"), player:FindFirstChild("PlayerGui"),
        game:FindFirstChild("StarterPlayer"), game:FindFirstChild("StarterGui"),
        game:FindFirstChild("StarterPack"),
    }
    local scanned, nameHits, srcHits = 0, 0, 0
    local budget = 40
    for _, root in ipairs(roots) do
        if root then
            local ok, descs = pcall(function() return root:GetDescendants() end)
            if ok then
                for _, d in ipairs(descs) do
                    if d:IsA("BaseScript") then
                        scanned = scanned + 1
                        local kw = anyMatch(d.Name, SIG.script)
                        if kw then
                            nameHits = nameHits + 1
                            if nameHits <= 25 then
                                push("scripts", "warn", 3,
                                    string.format("'%s' (%s) at %s (name kw: %s)", d.Name, d.ClassName, pathOf(d), kw),
                                    {scriptPath = pathOf(d)})
                            end
                        end
                        if features.decompile and budget > 0 and d:IsA("LocalScript") then
                            budget = budget - 1
                            local path = pathOf(d)
                            local fnSrc
                            if type(getscriptclosure) == "function" then
                                local okC, fn = pcall(getscriptclosure, d)
                                if okC and typeof(fn) == "function" then fnSrc = safeDecompile(fn) end
                            end
                            if not fnSrc and type(getscriptbytecode) == "function" then
                                local okB, bc = pcall(getscriptbytecode, d)
                                if okB then
                                    local okD, s = pcall(decompile, bc)
                                    if okD and type(s) == "string" then fnSrc = s end
                                end
                            end
                            if fnSrc then
                                local kw2 = anyMatch(fnSrc, SIG.source)
                                if kw2 then
                                    srcHits = srcHits + 1
                                    push("scripts", "fail", 12,
                                        string.format("'%s' source matched '%s' at %s", d.Name, kw2, path),
                                        {scriptPath = path})
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if scanned == 0 then push("scripts", "skip", 0, "No scripts under scanned roots")
    else push("scripts", "info", 0, string.format("%d scanned, %d name, %d source", scanned, nameHits, srcHits)) end
end

local function probe_character()
    local char = player.Character
    if not char then push("character", "skip", 0, "Character not spawned") return end
    local allowed = {
        Head=true, Torso=true, ["Left Arm"]=true, ["Right Arm"]=true, ["Left Leg"]=true, ["Right Leg"]=true,
        HumanoidRootPart=true, UpperTorso=true, LowerTorso=true,
        LeftUpperArm=true, LeftLowerArm=true, LeftHand=true, RightUpperArm=true,
        RightLowerArm=true, RightHand=true, LeftUpperLeg=true, LeftLowerLeg=true,
        LeftFoot=true, RightUpperLeg=true, RightLowerLeg=true, RightFoot=true, Handle=true,
    }
    local extra, hidden = 0, 0
    for _, inst in ipairs(char:GetChildren()) do
        if inst:IsA("BasePart") and not allowed[inst.Name] then
            extra = extra + 1
            if extra <= 8 then
                push("character", "warn", 4, string.format("Non-body part '%s' (Transparency=%s)",
                    inst.Name, tostring(inst.Transparency)))
            end
            if inst.Transparency >= 1 and inst.CanCollide == false then
                hidden = hidden + 1
                push("character", "warn", 6, "Hidden non-colliding part '" .. inst.Name .. "'")
            end
        end
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        push("character", "info", 0, string.format("WS=%s JP=%s HipH=%s",
            tostring(hum.WalkSpeed), tostring(hum.JumpPower), tostring(hum.HipHeight or "?")))
        if hum.WalkSpeed > 32 then push("character", "warn", 6, "WalkSpeed > 32") end
    else push("character", "warn", 5, "No Humanoid") end
end

local function probe_attributes()
    local scanned, hits = 0, 0
    local function scan(inst, label)
        for name in pairs(inst:GetAttributes()) do
            scanned = scanned + 1
            local kw = anyMatch(name, SIG.attr)
            if kw then
                hits = hits + 1
                if hits <= 25 then push("attributes", "warn", 4, string.format("%s.%s (kw: %s)", label, name, kw)) end
            end
        end
    end
    scan(player, "Player")
    if player.Character then scan(player.Character, "Character") end
    push("attributes", "info", 0, string.format("%d attrs, %d hits", scanned, hits))
end

local function probe_tags()
    local ok, all = pcall(function() return CollectionService:GetAllTags() end)
    if not ok or type(all) ~= "table" then push("tags", "skip", 0, "CollectionService unavailable") return end
    local hits = 0
    for _, tag in ipairs(all) do
        local kw = anyMatch(tag, SIG.tag)
        if kw then
            hits = hits + 1
            if hits <= 20 then push("tags", "warn", 3, string.format("Tag '%s' (kw: %s)", tag, kw)) end
        end
    end
    if hits == 0 then push("tags", "ok", 0, string.format("%d tags, none suspicious", #all)) end
end

local function probe_connections()
    if not features.getconnections then push("connections", "skip", 0, "getconnections failed") return end
    local targets = {}
    local char = player.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            table.insert(targets, {name="Humanoid.Changed", signal=hum.Changed})
            table.insert(targets, {name="Humanoid.StateChanged", signal=hum.StateChanged})
        end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            table.insert(targets, {name="HRP.Touched", signal=hrp.Touched})
            table.insert(targets, {name="HRP.ChildAdded", signal=hrp.ChildAdded})
        end
    end
    table.insert(targets, {name="player.CharacterAdded", signal=player.CharacterAdded})
    local suspicious = 0
    for _, t in ipairs(targets) do
        local ok, conns = pcall(getconnections, t.signal)
        if ok and conns then
            push("connections", #conns > 25 and "warn" or (ok and "ok" or "info"), #conns > 25 and 4 or 0,
                string.format("%s: %d connection(s)", t.name, #conns))
            for i, c in ipairs(conns) do
                if i > 25 then break end
                local fn = c.Function or c.function
                if fn then
                    local src = fnSource(fn)
                    if src then
                        local kw = anyMatch(src, SIG.source) or anyMatch(src, SIG.script)
                        if kw then
                            suspicious = suspicious + 1
                            push("connections", "fail", 10,
                                string.format("%s -> '%s' matched '%s'", t.name, tostring(src), kw))
                        end
                    end
                end
            end
        end
    end
    if suspicious == 0 then push("connections", "ok", 0, "No AC-attributed connections") end
end

local function probe_behavioral()
    for name, p in pairs(Profiler.remotes) do
        if p.calls >= 3 then
            for _, c in ipairs(Profiler.correlations(p)) do
                if c.ratio >= 0.6 and c.matched >= 3 then
                    push("remotes", "warn", 5, string.format(
                        "Behavioral: '%s' correlates with %s change (%d/%d = %d%%)",
                        name, c.field, c.matched, c.total, math.floor(c.ratio*100)),
                        {remoteName = name})
                    break
                end
            end
            if Profiler.rate(p) >= 30 then
                push("remotes", "warn", 4, string.format("Behavioral: '%s' rate %.1f calls/s", name, Profiler.rate(p)),
                    {remoteName = name})
            end
        end
    end
end

-- ============================================================
-- GUI
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ACProbeV6_" .. math.random(1000, 9999)
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
local okP = pcall(function()
    if gethui then screenGui.Parent = gethui()
    else screenGui.Parent = game:GetService("CoreGui") end
end)
if not okP then screenGui.Parent = player:WaitForChild("PlayerGui") end

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 920, 0, 660)
main.Position = UDim2.new(0.5, -460, 0.5, -330)
main.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true
main.Parent = screenGui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 36)
titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
titleBar.BorderSizePixel = 0
titleBar.Parent = main
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 8)

local titleLabel = Instance.new("TextLabel")
titleLabel.Text = "  Anticheat Probe v6"
titleLabel.Size = UDim2.new(1, -350, 1, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.TextColor3 = Color3.fromRGB(230, 230, 235)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 14
titleLabel.Parent = titleBar

local headerInfo = Instance.new("TextLabel")
headerInfo.Text = ""
headerInfo.Size = UDim2.new(0, 340, 1, 0)
headerInfo.Position = UDim2.new(1, -345, 0, 0)
headerInfo.BackgroundTransparency = 1
headerInfo.TextColor3 = Color3.fromRGB(140, 160, 210)
headerInfo.TextXAlignment = Enum.TextXAlignment.Right
headerInfo.Font = Enum.Font.Code
headerInfo.TextSize = 11
headerInfo.Parent = titleBar

local summaryBar = Instance.new("Frame")
summaryBar.Size = UDim2.new(1, -16, 0, 56)
summaryBar.Position = UDim2.new(0, 8, 0, 42)
summaryBar.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
summaryBar.BorderSizePixel = 0
summaryBar.Parent = main
Instance.new("UICorner", summaryBar).CornerRadius = UDim.new(0, 6)

local threatFill = Instance.new("Frame")
threatFill.Size = UDim2.new(0, 0, 1, 0)
threatFill.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
threatFill.BorderSizePixel = 0
threatFill.Parent = summaryBar
Instance.new("UICorner", threatFill).CornerRadius = UDim.new(0, 6)

local threatLabel = Instance.new("TextLabel")
threatLabel.Text = "  Threat: --"
threatLabel.Size = UDim2.new(1, -8, 0, 24)
threatLabel.BackgroundTransparency = 1
threatLabel.TextColor3 = Color3.fromRGB(240, 240, 245)
threatLabel.TextXAlignment = Enum.TextXAlignment.Left
threatLabel.Font = Enum.Font.GothamBold
threatLabel.TextSize = 13
threatLabel.ZIndex = 2
threatLabel.Parent = summaryBar

local archLabel = Instance.new("TextLabel")
archLabel.Text = "  Architecture: --"
archLabel.Size = UDim2.new(1, -8, 0, 24)
archLabel.Position = UDim2.new(0, 0, 0, 26)
archLabel.BackgroundTransparency = 1
archLabel.TextColor3 = Color3.fromRGB(200, 200, 215)
archLabel.TextXAlignment = Enum.TextXAlignment.Left
archLabel.Font = Enum.Font.GothamMedium
archLabel.TextSize = 12
archLabel.ZIndex = 2
archLabel.Parent = summaryBar

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -16, 0, 30)
tabBar.Position = UDim2.new(0, 8, 0, 104)
tabBar.BackgroundTransparency = 1
tabBar.Parent = main
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 4)
tabLayout.Parent = tabBar

local tabs = {"Overview","Detections","Probes","Live","Timeline","Hooks","Scripts","Test","Reputation"}
local tabButtons, tabContents = {}, {}

local contentHolder = Instance.new("Frame")
contentHolder.Size = UDim2.new(1, -16, 1, -236)
contentHolder.Position = UDim2.new(0, 8, 0, 140)
contentHolder.BackgroundTransparency = 1
contentHolder.Parent = main

local function makeTab(name)
    local b = Instance.new("TextButton")
    b.Text = name
    b.Size = UDim2.new(0, 92, 1, 0)
    b.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
    b.TextColor3 = Color3.fromRGB(200, 200, 210)
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = 11
    b.BorderSizePixel = 0
    b.Parent = tabBar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    tabButtons[name] = b

    local sf = Instance.new("ScrollingFrame")
    sf.Size = UDim2.new(1, 0, 1, 0)
    sf.BackgroundColor3 = Color3.fromRGB(14, 14, 18)
    sf.BorderSizePixel = 0
    sf.ScrollBarThickness = 6
    sf.CanvasSize = UDim2.new(0, 0, 0, 0)
    sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
    sf.Visible = false
    sf.Parent = contentHolder
    Instance.new("UICorner", sf).CornerRadius = UDim.new(0, 6)
    local ll = Instance.new("UIListLayout", sf)
    ll.Padding = UDim.new(0, 2)
    ll.SortOrder = Enum.SortOrder.LayoutOrder
    tabContents[name] = sf
end
for _, n in ipairs(tabs) do makeTab(n) end

local function setTab(name)
    for n, b in pairs(tabButtons) do
        b.BackgroundColor3 = (n == name) and Color3.fromRGB(50, 90, 70) or Color3.fromRGB(28, 28, 34)
        b.TextColor3 = (n == name) and Color3.fromRGB(240, 240, 245) or Color3.fromRGB(200, 200, 210)
    end
    for n, sf in pairs(tabContents) do sf.Visible = (n == name) end
end
for name, btn in pairs(tabButtons) do
    btn.MouseButton1Click:Connect(function() setTab(name) end)
end

local bottom = Instance.new("Frame")
bottom.Size = UDim2.new(1, -16, 0, 40)
bottom.Position = UDim2.new(0, 8, 1, -48)
bottom.BackgroundTransparency = 1
bottom.Parent = main

local function makeButton(text, xScale, xOffset, color)
    local b = Instance.new("TextButton")
    b.Text = text
    b.Size = UDim2.new(xScale, xOffset, 1, 0)
    b.BackgroundColor3 = color or Color3.fromRGB(45, 45, 55)
    b.TextColor3 = Color3.fromRGB(230, 230, 235)
    b.Font = Enum.Font.GothamSemibold
    b.TextSize = 12
    b.BorderSizePixel = 0
    b.Parent = bottom
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

local runBtn    = makeButton("Run All",   0.14, -2, Color3.fromRGB(40, 120, 80));  runBtn.Position    = UDim2.new(0,    0, 0, 0)
local probeBtn  = makeButton("Probe",     0.12, -2, Color3.fromRGB(180, 120, 40)); probeBtn.Position  = UDim2.new(0.14, 2, 0, 0)
local liveBtn   = makeButton("Live: Off", 0.12, -2, Color3.fromRGB(45, 45, 55));   liveBtn.Position   = UDim2.new(0.26, 4, 0, 0)
local riskBtn   = makeButton("Risk: Off", 0.11, -2, Color3.fromRGB(45, 45, 55));   riskBtn.Position   = UDim2.new(0.38, 6, 0, 0)
local exportBtn = makeButton("JSON",      0.10, -2, Color3.fromRGB(45, 100, 150));  exportBtn.Position = UDim2.new(0.49, 8, 0, 0)
local wipeBtn   = makeButton("Wipe",      0.10, -2, Color3.fromRGB(100, 50, 50));   wipeBtn.Position   = UDim2.new(0.59, 10, 0, 0)
local closeBtn  = makeButton("Close",     0.10, -2, Color3.fromRGB(120, 50, 50));   closeBtn.Position  = UDim2.new(0.88, 14, 0, 0)

-- Render helpers
local levels = {
    ok={icon="✓",color=Color3.fromRGB(80,200,120)}, info={icon="•",color=Color3.fromRGB(140,160,210)},
    warn={icon="!",color=Color3.fromRGB(230,180,80)}, fail={icon="✗",color=Color3.fromRGB(230,90,90)},
    skip={icon="─",color=Color3.fromRGB(120,120,130)},
}
local orderCounter = 0
local function nextOrder() orderCounter = orderCounter + 1 return orderCounter end
local function clearTab(name)
    for _, c in ipairs(tabContents[name]:GetChildren()) do if c:IsA("Frame") or c:IsA("TextButton") then c:Destroy() end end
end
local function addHeader(tab, text)
    local h = Instance.new("Frame")
    h.Size = UDim2.new(1, 0, 0, 24)
    h.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    h.BorderSizePixel = 0
    h.Parent = tabContents[tab]
    h.LayoutOrder = nextOrder()
    local l = Instance.new("TextLabel")
    l.Text = "  " .. text
    l.Size = UDim2.new(1, 0, 1, 0)
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.fromRGB(200, 200, 220)
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Font = Enum.Font.GothamBold
    l.TextSize = 12
    l.Parent = h
end
local function addRow(tab, level, text, meta, onClick)
    local info = levels[level] or levels.info
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 20)
    btn.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = onClick ~= nil
    btn.Text = ""
    btn.Parent = tabContents[tab]
    btn.LayoutOrder = nextOrder()
    if onClick then btn.MouseButton1Click:Connect(onClick) end

    local icon = Instance.new("TextLabel")
    icon.Text = info.icon
    icon.Size = UDim2.new(0, 22, 1, 0)
    icon.Position = UDim2.new(0, 4, 0, 0)
    icon.BackgroundTransparency = 1
    icon.TextColor3 = info.color
    icon.Font = Enum.Font.Code
    icon.TextSize = 12
    icon.Parent = btn

    local lbl = Instance.new("TextLabel")
    lbl.Text = text
    lbl.Size = UDim2.new(1, meta and -170 or -30, 1, 0)
    lbl.Position = UDim2.new(0, 26, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = Color3.fromRGB(210, 210, 220)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 11
    lbl.TextTruncate = Enum.TextTruncate.AtEnd
    lbl.Parent = btn

    if meta then
        local m = Instance.new("TextLabel")
        m.Text = meta
        m.Size = UDim2.new(0, 140, 1, 0)
        m.Position = UDim2.new(1, -142, 0, 0)
        m.BackgroundTransparency = 1
        m.TextColor3 = Color3.fromRGB(140, 150, 170)
        m.TextXAlignment = Enum.TextXAlignment.Right
        m.Font = Enum.Font.Code
        m.TextSize = 10
        m.Parent = btn
    end
end

local function entryMeta(e)
    local parts = {}
    if (e.count or 1) > 1 then parts[#parts+1] = "×" .. e.count end
    if e.accounts and #e.accounts > 1 then parts[#parts+1] = #e.accounts .. " accts" end
    if e.firstSeen and (os.time() - e.firstSeen) > 60 then parts[#parts+1] = fmtAgo(e.firstSeen) end
    return #parts > 0 and table.concat(parts, " · ") or nil
end

local function updateHeader()
    headerInfo.Text = string.format("%s v%s · %s · sUNC %d/%d · compat %d%%",
        Executor.name, Executor.version, Executor.os, sUNCStatus.count, sUNCStatus.total, Compat.score)
end

local function scoreAll()
    local t = 0
    for _, list in pairs(findings) do
        for _, f in ipairs(list) do t = t + (f.weight or 0) end
    end
    return math.min(100, t)
end
local function threatBand(s)
    if s < 15 then return "Clean", Color3.fromRGB(80,200,120)
    elseif s < 35 then return "Minor", Color3.fromRGB(90,160,230)
    elseif s < 60 then return "Moderate", Color3.fromRGB(230,190,80)
    elseif s < 85 then return "Heavy", Color3.fromRGB(230,130,70)
    else return "Aggressive", Color3.fromRGB(230,80,80) end
end

local function renderOverview()
    local score = scoreAll()
    local band, color = threatBand(score)
    threatFill.Size = UDim2.new(score / 100, 0, 1, 0)
    threatFill.BackgroundColor3 = color
    threatLabel.Text = string.format("  Threat: %d / 100  —  %s", score, band)
    archLabel.Text = string.format("  Architecture: %s  (%s confidence)", Arch.classification, Arch.confidence)

    addHeader("Overview", "Executor")
    addRow("Overview", Compat.score >= 80 and "ok" or (Compat.score >= 50 and "warn" or "fail"),
        string.format("%s v%s · %s", Executor.name, Executor.version, Executor.os),
        string.format("compat %d%%", Compat.score))
    addRow("Overview", sUNCStatus.count >= sUNCStatus.total * 0.9 and "ok" or "warn",
        string.format("sUNC: %d/%d functions present", sUNCStatus.count, sUNCStatus.total),
        sUNCStatus.count == sUNCStatus.total and "full" or "partial")

    addHeader("Overview", "Analysis")
    addRow("Overview", score >= 60 and "fail" or (score >= 30 and "warn" or "ok"),
        string.format("%s · %d reasons · %d sessions loaded",
            Arch.classification, #Arch.reasons, #sessionHistory + 1))
    for _, r in ipairs(Arch.reasons) do addRow("Overview", "info", "  · " .. r) end
    if #Arch.reasons == 0 then addRow("Overview", "ok", "No architectural indicators found") end

    addHeader("Overview", "Category weights")
    for _, cat in ipairs(CATEGORIES) do
        local list = findings[cat]
        local w, bad = 0, 0
        for _, f in ipairs(list) do w = w + (f.weight or 0); if f.level == "warn" or f.level == "fail" then bad = bad + 1 end end
        addRow("Overview", bad > 0 and "warn" or "ok",
            string.format("%-12s  %d findings, %d flagged, weight %d", cat, #list, bad, w))
    end

    addHeader("Overview", "Top evidence")
    local all = {}
    for cat, list in pairs(findings) do
        for _, f in ipairs(list) do if (f.weight or 0) >= 5 then all[#all+1] = {cat=cat, f=f} end end
    end
    table.sort(all, function(a, b) return (a.f.weight or 0) > (b.f.weight or 0) end)
    for i = 1, math.min(12, #all) do
        local it = all[i]
        local key = it.cat .. "|" .. it.f.text
        local rep = Reputation.Get(key)
        local tag = rep ~= "unknown" and (" [" .. rep .. "]") or ""
        addRow("Overview", it.f.level, "[" .. it.cat .. "] " .. it.f.text .. tag, entryMeta(it.f))
    end
    if #all == 0 then addRow("Overview", "ok", "No findings with weight >= 5") end

    addHeader("Overview", "Session history")
    local allS = {}
    for _, s in ipairs(sessionHistory) do allS[#allS+1] = s end
    if not table.find(allS, currentSession) then allS[#allS+1] = currentSession end
    table.sort(allS, function(a, b) return (a.started or 0) > (b.started or 0) end)
    for i = 1, math.min(6, #allS) do
        local s = allS[i]
        local status = s.endReason or "open"
        if status == "open" and s.id ~= sessionId then status = "unknown" end
        local ts = s.started and os.date("%m-%d %H:%M", s.started) or "?"
        addRow("Overview", (status == "kicked" and "fail") or "info",
            string.format("%s  %s  %s  %d findings  %s",
                ts, (s.account or "?"):sub(1, 10), (s.executor or "?"):sub(1, 14), s.findingCount or 0, status))
    end
end

local function renderDetections()
    local cats = {"remotes", "connections", "attributes", "tags", "character", "environment"}
    local all = {}
    for _, cat in ipairs(cats) do
        for _, f in ipairs(findings[cat] or {}) do
            if f.level == "warn" or f.level == "fail" then all[#all+1] = {cat=cat, f=f} end
        end
    end
    table.sort(all, function(a, b) return (a.f.weight or 0) > (b.f.weight or 0) end)

    addHeader("Detections", string.format("%d active detections (click to classify)", #all))
    if #all == 0 then addRow("Detections", "ok", "No active detections") return end
    for i = 1, math.min(60, #all) do
        local it = all[i]
        local key = it.cat .. "|" .. it.f.text
        local rep = Reputation.Get(key)
        local tag = rep ~= "unknown" and ("[" .. rep .. "] ") or ""
        local text = tag .. "[" .. it.cat .. "] " .. it.f.text
        -- Enrich with caller information if available
        if it.f.remoteName and Profiler.remotes[it.f.remoteName] then
            local p = Profiler.remotes[it.f.remoteName]
            local callerList = {}
            for path in pairs(p.callers) do
                table.insert(callerList, path)
                if #callerList >= 1 then break end
            end
            if #callerList > 0 then text = text .. "  ← " .. callerList[1] end
        end
        addRow("Detections", it.f.level, text, entryMeta(it.f),
            function()
                local cur = Reputation.Get(key)
                local nxt = cur == "unknown" and "suspect"
                    or cur == "suspect" and "confirmed_ac"
                    or cur == "confirmed_ac" and "benign"
                    or cur == "benign" and "confirmed_benign"
                    or "unknown"
                Reputation.Set(key, nxt)
                renderAll()
            end)
    end
end

local function renderProbes()
    addHeader("Probes", "Controlled state-change tests")
    addRow("Probes", "info", "Risky probes: " .. (AutoProbe.riskyEnabled and "ENABLED" or "disabled (Risk button to toggle)"))
    if #AutoProbe.results == 0 then
        addRow("Probes", "skip", "No probes run yet — click Probe to start")
        return
    end
    for _, r in ipairs(AutoProbe.results) do
        local lvl = r.level == "warn" and "warn" or (r.level == "fail" and "fail" or (r.level == "skip" and "skip" or "ok"))
        addRow("Probes", lvl, r.name .. " — " .. (r.msg or ""))
    end
    addHeader("Probes", "Interpretation")
    addRow("Probes", "info", "Remotes fired during a specific probe are causally linked to that state change.")
    addRow("Probes", "info", "A remote that fires ONLY on WalkSpeed change is a movement validator.")
end

local function renderLive()
    addHeader("Live", "Behavioral remote profiles (with callstack)")
    local sorted = {}
    for name, p in pairs(Profiler.remotes) do
        if p.calls >= 1 then sorted[#sorted+1] = p end
    end
    table.sort(sorted, function(a, b) return a.calls > b.calls end)
    if #sorted == 0 then
        addRow("Live", "skip", "No remote calls observed — enable Live and play")
        return
    end
    for i = 1, math.min(20, #sorted) do
        local p = sorted[i]
        local rate = Profiler.rate(p)
        local entropy = Profiler.shapeEntropy(p)
        local shapeCount = 0
        for _ in pairs(p.shapes) do shapeCount = shapeCount + 1 end
        local rep = Reputation.Get(p.name)
        local tag = rep ~= "unknown" and (" [" .. rep .. "]") or ""
        addRow("Live", "info", string.format(
            "%-30s  calls=%d rate=%.1f/s shapes=%d entropy=%.2f%s",
            p.name:sub(1, 30), p.calls, rate, shapeCount, entropy, tag),
            nil,
            function() Reputation.Set(p.name, "confirmed_ac", "from Live") renderAll() end)
        -- Callers
        local callerList = {}
        for path, count in pairs(p.callers) do table.insert(callerList, {path=path, count=count}) end
        table.sort(callerList, function(a, b) return a.count > b.count end)
        for i2, c in ipairs(callerList) do
            if i2 > 3 then break end
            addRow("Live", "info", string.format("  ← %s (%d×)", c.path, c.count))
        end
        -- Correlations
        for _, c in ipairs(Profiler.correlations(p)) do
            if c.ratio >= 0.5 and c.matched >= 2 then
                addRow("Live", c.ratio >= 0.8 and "warn" or "info",
                    string.format("  ↳ %s: %d/%d = %d%%", c.field, c.matched, c.total, math.floor(c.ratio*100)))
            end
        end
    end
    if #sorted > 20 then addRow("Live", "info", string.format("... and %d more", #sorted - 20)) end
end

local function renderTimeline()
    addHeader("Timeline", string.format("%d events (last 20s shown newest-first)", #Timeline.events))
    local startT = os.clock() - 20
    local shown = 0
    for i = #Timeline.events, 1, -1 do
        local e = Timeline.events[i]
        if e.t < startT then break end
        shown = shown + 1
        if shown > 80 then break end
        local lvl = "info"
        if e.typ == "remote" then lvl = "info"
        elseif e.typ == "corr" then lvl = "warn"
        elseif e.typ == "state" then lvl = "info"
        elseif e.typ == "system" then lvl = "ok" end
        addRow("Timeline", lvl, string.format("[%s] %s", e.typ, e.text))
    end
    if shown == 0 then
        addRow("Timeline", "skip", "No recent events — enable Live and play")
    end
end

local function renderHooks()
    addHeader("Hooks", "Metatable hooks (Lua-level)")
    local hooks = findings.hooks or {}
    if #hooks == 0 then addRow("Hooks", "skip", "No hooks detected")
    else for _, f in ipairs(hooks) do addRow("Hooks", f.level, f.text, entryMeta(f)) end end
end

local function renderScripts()
    addHeader("Scripts", "Script findings")
    local scripts = findings.scripts or {}
    if #scripts == 0 then addRow("Scripts", "skip", "No script findings")
    else for _, f in ipairs(scripts) do
        addRow("Scripts", f.level, f.text, entryMeta(f),
            function()
                local key = "scripts|" .. f.text
                local cur = Reputation.Get(key)
                Reputation.Set(key, cur == "unknown" and "confirmed_ac" or "unknown")
                renderAll()
            end)
    end end
    addHeader("Scripts", "Callstack-attributed callers")
    local seen = {}
    for _, p in pairs(Profiler.remotes) do
        for path in pairs(p.callers) do
            if not seen[path] then
                seen[path] = true
                addRow("Scripts", "info", path)
            end
        end
    end
    local c = 0
    for _ in pairs(seen) do c = c + 1 end
    if c == 0 then addRow("Scripts", "skip", "No callers attributed yet") end
end

local function renderTest()
    addHeader("Test", string.format("Compat %d/%d (%d%%) · sUNC %d/%d",
        Compat.passed, Compat.total, Compat.score, sUNCStatus.count, sUNCStatus.total))
    addRow("Test", sUNCStatus.count == sUNCStatus.total and "ok" or "warn",
        string.format("sUNC: %d/%d present", sUNCStatus.count, sUNCStatus.total),
        sUNCStatus.count == sUNCStatus.total and "full sUNC" or "partial")
    if #sUNCStatus.missing > 0 then
        addRow("Test", "info", "sUNC missing: " .. table.concat(sUNCStatus.missing, ", "))
    end

    local byCat = {}
    for _, r in ipairs(Compat.results) do
        if not byCat[r.cat] then byCat[r.cat] = {} end
        byCat[r.cat][#byCat[r.cat]+1] = r
    end
    for _, cat in ipairs({"identity","env","meta","hook","signal","file","script","reflection","io","graphics"}) do
        local list = byCat[cat]
        if list and #list > 0 then
            addHeader("Test", cat:upper())
            for _, r in ipairs(list) do
                addRow("Test", r.ok and "ok" or "fail",
                    string.format("[w%d] %s — %s", r.weight, r.name, r.msg),
                    r.ok and "pass" or "FAIL")
            end
        end
    end
end

local function renderReputation()
    addHeader("Reputation", "Confirmed classifications (click to clear)")
    local n = 0
    local byClass = {}
    for k, e in pairs(Reputation.entries) do
        byClass[e.class] = byClass[e.class] or {}
        table.insert(byClass[e.class], k)
    end
    for _, class in ipairs({"confirmed_ac","suspect","confirmed_benign","benign"}) do
        local list = byClass[class]
        if list and #list > 0 then
            addHeader("Reputation", class:upper() .. " (" .. #list .. ")")
            for i = 1, math.min(30, #list) do
                n = n + 1
                addRow("Reputation", class == "confirmed_ac" and "fail" or (class == "suspect" and "warn" or "ok"),
                    list[i], nil, function()
                        Reputation.entries[list[i]] = nil
                        saveNow()
                        renderAll()
                    end)
            end
        end
    end
    if n == 0 then addRow("Reputation", "info", "No reputations set — click any finding to classify") end
end

local function renderAll()
    orderCounter = 0
    for _, t in ipairs(tabs) do clearTab(t) end
    classifyArch()
    updateHeader()
    renderOverview()
    renderDetections()
    renderProbes()
    renderLive()
    renderTimeline()
    renderHooks()
    renderScripts()
    renderTest()
    renderReputation()
end

-- ============================================================
-- Runner
-- ============================================================
local running = false
local probes = {
    {"environment", probe_environment},
    {"hooks",       probe_hooks},
    {"remotes",     probe_remotes},
    {"scripts",     probe_scripts},
    {"character",   probe_character},
    {"attributes",  probe_attributes},
    {"tags",        probe_tags},
    {"connections", probe_connections},
    {"behavioral",  probe_behavioral},
}

local function runAll()
    if running then return end
    running = true
    for i, p in ipairs(probes) do
        titleLabel.Text = string.format("  Anticheat Probe v6 — %d/%d: %s", i, #probes, p[1])
        local ok, err = pcall(p[2])
        if not ok then push(p[1], "fail", 5, "Crashed: " .. tostring(err)) end
        saveNow()
        task.wait()
    end
    renderAll()
    titleLabel.Text = "  Anticheat Probe v6"
    running = false
end

local liveOn = false
local function liveTick()
    if not liveOn then return end
    Profiler.snapshot()
    if not Profiler.installed then installProfilerHook() end
    renderAll()
end
local function startLive()
    if liveOn then return end
    liveOn = true
    installProfilerHook()
    Profiler.snapshot()
    task.spawn(function()
        while liveOn do pcall(liveTick) task.wait(2) end
    end)
    liveBtn.Text = "Live: On"
    liveBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 80)
end
local function stopLive()
    liveOn = false
    liveBtn.Text = "Live: Off"
    liveBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
end

-- ============================================================
-- Buttons
-- ============================================================
runBtn.MouseButton1Click:Connect(runAll)
probeBtn.MouseButton1Click:Connect(function()
    if AutoProbe.running then return end
    task.spawn(runAutoProbes)
end)
liveBtn.MouseButton1Click:Connect(function() if liveOn then stopLive() else startLive() end end)
riskBtn.MouseButton1Click:Connect(function()
    AutoProbe.riskyEnabled = not AutoProbe.riskyEnabled
    riskBtn.Text = AutoProbe.riskyEnabled and "Risk: On" or "Risk: Off"
    riskBtn.BackgroundColor3 = AutoProbe.riskyEnabled and Color3.fromRGB(150, 60, 40) or Color3.fromRGB(45, 45, 55)
    renderAll()
end)
exportBtn.MouseButton1Click:Connect(function()
    if not features.setclipboard then exportBtn.Text = "No clip" task.wait(1) exportBtn.Text = "JSON" return end
    local payload = buildSnapshot()
    payload.score = scoreAll()
    payload.band = (threatBand(scoreAll()))
    payload.sUNCStatus = {present=sUNCStatus.present, missing=sUNCStatus.missing, count=sUNCStatus.count, total=sUNCStatus.total}
    payload.compat = {score=Compat.score, passed=Compat.passed, failed=Compat.failed, results=Compat.results}
    payload.exportedAt = os.time()
    local ok, json = pcall(HttpService.JSONEncode, HttpService, payload)
    if not ok then exportBtn.Text = "Enc err" task.wait(1) exportBtn.Text = "JSON" return end
    setclipboard(json)
    exportBtn.Text = "Copied!"
    task.wait(1)
    exportBtn.Text = "JSON"
end)
wipeBtn.MouseButton1Click:Connect(function()
    wipeBtn.Text = "Sure?"
    local armed = true
    task.delay(3, function() if armed then armed = false wipeBtn.Text = "Wipe" end end)
    local conn
    conn = wipeBtn.MouseButton1Click:Connect(function()
        if not armed then return end
        armed = false
        conn:Disconnect()
        persistDelete()
        for _, c in ipairs(CATEGORIES) do
            for i = #findings[c], 1, -1 do findings[c][i] = nil end
        end
        findingsIndex = {}
        sessionHistory = {}
        Reputation.entries = {}
        Profiler.remotes = {}
        AutoProbe.results = {}
        Timeline.events = {}
        saveNow()
        renderAll()
        wipeBtn.Text = "Wiped"
        task.wait(1)
        wipeBtn.Text = "Wipe"
    end)
end)
closeBtn.MouseButton1Click:Connect(function()
    saveNow()
    screenGui:Destroy()
end)

-- ============================================================
-- Kickoff
-- ============================================================
setTab("Overview")
titleLabel.Text = "  Anticheat Probe v6 — compat test..."

task.spawn(function()
    runCompat()
    runSUCNC()
    currentSession.compatScore = Compat.score
    currentSession.sUNC = sUNCStatus.count .. "/" .. sUNCStatus.total

    local loaded = persistLoad()
    local merged, sess = 0, 0
    if loaded then merged, sess = mergeLoaded(loaded) end

    installProfilerHook()
    renderAll()

    if merged > 0 then
        titleLabel.Text = string.format("  Anticheat Probe v6 — resumed %d findings", merged)
        task.wait(2)
    end
    task.spawn(runAll)
end)