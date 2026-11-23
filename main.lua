-- Anticheat Probe v7 — outcome tracing, AC fingerprinting, stealth, recommendations.
-- Read-only except for explicit Probe button. Outcomes capture client-visible consequences.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

local SCHEMA = 7
if getgenv and getgenv().ACProbeV7Loaded then return end
if getgenv then getgenv().ACProbeV7Loaded = true end

-- ============================================================
-- Primitives
-- ============================================================
local getrawmt          = getrawmetatable or (debug and debug.getmetatable)
local newcclosure       = newcclosure or function(f) return f end
local setclipboard      = setclipboard or toclipboard or (syn and syn.write_clipboard)
local getnamecallmethod = getnamecallmethod or function() return nil end
local decompile         = decompile or (syn and syn.decompile)
local function safe(fn, ...) local ok, r = pcall(fn, ...) return ok and r or nil end

-- ============================================================
-- Executor identity (compact)
-- ============================================================
local Executor = {name="Unknown", version="?", os="unknown", confidence="low", evidence={}}
local function detectExecutor()
    local i = {name="Unknown", version="?", os="unknown", confidence="low", evidence={}}
    if type(identifyexecutor) == "function" then
        local n, v = identifyexecutor()
        if type(n) == "string" then i.name, i.version, i.confidence = n, tostring(v or "?"), "high"
            table.insert(i.evidence, "identifyexecutor() -> " .. n) end
    end
    if i.name == "Unknown" and type(getexecutorname) == "function" then
        local n = safe(getexecutorname)
        if type(n) == "string" then i.name, i.confidence = n, "high"
            table.insert(i.evidence, "getexecutorname() -> " .. n) end
    end
    local genv = type(getgenv) == "function" and safe(getgenv) or {}
    for _, s in ipairs({
        {"Opiumware", function() return opiumware ~= nil or (genv and genv.Opiumware) end},
        {"MacSploit", function() return macsploit ~= nil end},
        {"Synapse X", function() return syn and syn.protect_gui end},
        {"Script-Ware", function() return ScriptWare ~= nil end},
        {"KRNL", function() return (genv.KRNL_LOADED or KRNL_LOADED) ~= nil end},
        {"Fluxus", function() return fluxus ~= nil end},
        {"Hydrogen", function() return (h2 or Hydrogen) ~= nil end},
        {"Solara", function() return solara ~= nil end},
        {"Wave", function() return wave ~= nil end},
        {"Arceus X", function() return ArceusX ~= nil end},
    }) do
        if safe(s[2]) then
            if i.name == "Unknown" then i.name, i.confidence = s[1], "medium" end
            table.insert(i.evidence, "global: " .. s[1])
        end
    end
    local l = i.name:lower()
    if l:find("opium") or l:find("macsploit") or l:find("hydrogen") or l:find("ios") then i.os = "macOS / iOS"
    elseif l:find("synapse") or l:find("krnl") or l:find("fluxus") then i.os = "Windows" end
    return i
end
Executor = detectExecutor()

-- ============================================================
-- Compat (execution-based)
-- ============================================================
local Compat = {results={}, passed=0, failed=0, total=0, score=0, earned=0, possible=0}
local features = {}

local function runCompat()
    local tests = {
        {"identifyexecutor", "identity", 0, function()
            if type(identifyexecutor) ~= "function" then return false, "missing" end
            local ok, n = pcall(identifyexecutor)
            return ok and type(n) == "string", tostring(n)
        end},
        {"getgenv", "env", 3, function()
            if type(getgenv) ~= "function" then return false, "missing" end
            local env = safe(getgenv)
            if type(env) ~= "table" then return false, "non-table" end
            local k = "__acp_" .. math.random(1e6)
            env[k] = 1; local rb = env[k]; env[k] = nil
            return rb == 1, "read/write ok"
        end},
        {"getrawmetatable+setreadonly", "meta", 5, function()
            if type(getrawmt) ~= "function" or type(setreadonly) ~= "function" then return false, "missing" end
            local mt = safe(getrawmt, game)
            if type(mt) ~= "table" then return false, "no game mt" end
            if not pcall(setreadonly, mt, false) then return false, "unlock failed" end
            pcall(setreadonly, mt, true)
            return true, "metatable control"
        end},
        {"hookfunction", "hook", 4, function()
            if type(hookfunction) ~= "function" then return false, "missing" end
            local t = function(x) return x end
            local ok, orig = pcall(hookfunction, t, function(x) return x * 10 end)
            if not ok then return false, "hook threw" end
            local r = t(5); pcall(hookfunction, t, orig)
            return r == 50, "r=" .. tostring(r)
        end},
        {"hookmetamethod", "hook", 3, function()
            if type(hookmetamethod) ~= "function" then return false, "missing" end
            local obj = setmetatable({}, {__index = function() return "orig" end})
            local ok, orig = pcall(hookmetamethod, obj, "__index", function() return "hooked" end)
            if not ok then return false, "threw" end
            local r = obj.x; pcall(hookmetamethod, obj, "__index", orig)
            return r == "hooked", "works"
        end},
        {"getconnections", "signal", 3, function()
            if type(getconnections) ~= "function" then return false, "missing" end
            local conn = RunService.Heartbeat:Connect(function() end)
            task.wait()
            local ok, list = pcall(getconnections, RunService.Heartbeat)
            conn:Disconnect()
            if not ok or type(list) ~= "table" then return false, "threw" end
            return #list > 0, "count=" .. #list
        end},
        {"file I/O", "file", 4, function()
            if type(readfile) ~= "function" or type(writefile) ~= "function" then return false, "missing" end
            local p = "ACProbe_v7.tmp"; local c = "t" .. math.random(1e7)
            if not pcall(writefile, p, c) then return false, "write threw" end
            local rb = safe(readfile, p)
            if type(delfile) == "function" then pcall(delfile, p) end
            return rb == c, rb == c and "roundtrip ok" or "mismatch"
        end},
        {"decompile", "script", 3, function()
            if type(decompile) ~= "function" then return false, "missing" end
            for _, d in ipairs(game:GetDescendants()) do
                if d:IsA("LocalScript") then
                    local ok, src = pcall(decompile, d)
                    if ok and type(src) == "string" and #src > 0 then return true, "ok (" .. #src .. " chars)" end
                end
            end
            return false, "no testable"
        end},
        {"debug.getinfo", "reflection", 3, function()
            if not debug or type(debug.getinfo) ~= "function" then return false, "missing" end
            local info = safe(debug.getinfo, 1, "Sl")
            if not info then return false, "returned nil" end
            return true, "source=" .. tostring(info.source):sub(1, 20)
        end},
        {"setclipboard", "io", 1, function() return type(setclipboard) == "function", "available" end},
    }
    Compat.results = {}
    local pw, tw = 0, 0
    for _, t in ipairs(tests) do
        local ok, r = pcall(t[4])
        if not ok then r = "threw" end
        table.insert(Compat.results, {name=t[1], cat=t[2], weight=t[3], ok=ok, msg=tostring(r)})
        tw = tw + t[3]; if ok then pw = pw + t[3] end
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
            if r.name == "getrawmetatable+setreadonly" then features.getrawmetatable = true; features.setreadonly = true end
            if r.name == "getconnections" then features.getconnections = true end
            if r.name == "getgenv" then features.getgenv = true end
            if r.name == "decompile" then features.decompile = true end
            if r.name == "file I/O" then features.file_io = true end
            if r.name == "debug.getinfo" then features.debug_getinfo = true end
            if r.name == "hookfunction" then features.hookfunction = true end
        end
    end
end

-- ============================================================
-- sUNC shape check
-- ============================================================
local sUNC = {present={}, missing={}, count=0, total=0}
local function runSUNC()
    local names = {
        "getgenv","getrenv","getreg","getrawmetatable","setreadonly","isreadonly",
        "hookfunction","hookmetamethod","getnamecallmethod","newcclosure","checkcaller",
        "iscclosure","islclosure","clonefunction","getupvalue","setupvalue","getconstant",
        "setconstant","getconstants","getprotos","loadstring","identifyexecutor",
        "getexecutorname","getscriptclosure","getscriptbytecode","getloadedmodules",
        "getscripts","getconnections","firesignal","firetouchinterest","fireclickdetector",
        "fireproximityprompt","getinstances","getnilinstances","getgc","getcallbackvalue",
        "setcallbackvalue","gethiddenproperty","sethiddenproperty","readfile","writefile",
        "appendfile","isfile","isfolder","makefolder","delfile","deletefolder",
        "listfiles","getcustomasset","request","http_request","setclipboard",
        "setfpscap","getthreadidentity","setthreadidentity","Drawing",
    }
    sUNC.present = {}; sUNC.missing = {}
    for _, n in ipairs(names) do
        local ok = false
        if n == "Drawing" then ok = type(Drawing) == "table"
        else ok = type((getfenv and getfenv()[n]) or _G[n]) == "function" end
        if ok then table.insert(sUNC.present, n)
        else table.insert(sUNC.missing, n) end
    end
    sUNC.count, sUNC.total = #sUNC.present, #names
end

-- ============================================================
-- NEW: Known AC fingerprint database
-- Each entry: markers are weighted; >=80% match = high confidence
-- ============================================================
local FingerprintDB = {
    known = {
        {name="Hyperion / Byfron", type="client integrity", approach="binary + server",
         markers={
             {kind="remote", kw="byfron"},
             {kind="remote", kw="hyperion"},
             {kind="source", kw="integritycheck"},
             {kind="source", kw="memoryintegrity"},
             {kind="source", kw="byfron"},
             {kind="global", kw="byfron"},
             {kind="script", kw="byfron"},
             {kind="script", kw="hyperion"},
         },
         expectedOutcomes={"no client recovery — enforcement is process-level"},
         recommendation="Hyperion is process-level, not a client hook. Client-side hook detection is likely. Use data-only approach; avoid hookfunction on game metatables if not required.",
        },
        {name="Krampus", type="client-side hook", approach="metatable + server",
         markers={
             {kind="remote", kw="krampus"},
             {kind="script", kw="krampus"},
             {kind="source", kw="krampus"},
             {kind="remote", kw="detection"},
             {kind="remote", kw="sentry"},
         },
         expectedOutcomes={"WalkSpeed reset", "teleport back", "kick at high threshold"},
         recommendation="Krampus watches __namecall and __index. Avoid modifying metatables, or use hookmetamethod with clean upvalue names. Movement is validated server-side.",
        },
        {name="Adonis AC (common)", type="client observer", approach="player-moderated",
         markers={
             {kind="remote", kw="adonis"},
             {kind="script", kw="adonis"},
             {kind="remote", kw="report"},
             {kind="remote", kw="exploiter"},
         },
         expectedOutcomes={"GUI warning sent to admins", "no immediate client reaction"},
         recommendation="Adonis is detection + report, no automatic client action. Findings are logged to admins. Don't escalate — assume every flag is visible to staff.",
        },
        {name="UMG / Universal Moderation Guard", type="client observer + report",
         approach="player-moderated",
         markers={
             {kind="script", kw="umg"},
             {kind="remote", kw="umg"},
             {kind="remote", kw="moderat"},
             {kind="source", kw="violation"},
         },
         expectedOutcomes={"admin GUI", "player kick by human admin"},
         recommendation="Human-moderated. Findings trigger admin notification, not client recovery. Assume all detection is visible to staff.",
        },
        {name="AA / Anti-Anticheat (custom)", type="client-side hook",
         approach="movement + integrity",
         markers={
             {kind="remote", kw="aa_"},
             {kind="script", kw="aa_"},
             {kind="remote", kw="anticheat"},
             {kind="remote", kw="check"},
         },
         expectedOutcomes={"WalkSpeed reset", "position revert", "report"},
         recommendation="Custom Luau AC. Usually movement-focused. Probe thresholds incrementally: WS 20, 24, 28, 30, 32. Stop at first kick.",
        },
        {name="Sirhurt-Internal", type="client-side hook + kick",
         approach="detect exploit globals",
         markers={
             {kind="script", kw="sirhurt"},
             {kind="source", kw="sirhurt"},
             {kind="source", kw="injectdetect"},
         },
         expectedOutcomes={"immediate kick"},
         recommendation="Detects injected executor globals. Set getgenv()['namecall'] to nil before probing. Do not hook __namecall while this is loaded.",
        },
        {name="Generic Luau AC (movement)", type="client-side hook",
         approach="movement + physics validation",
         markers={
             {kind="remote", kw="walkspeed"},
             {kind="remote", kw="speed"},
             {kind="remote", kw="jump"},
             {kind="remote", kw="position"},
             {kind="remote", kw="check"},
         },
         expectedOutcomes={"reset", "revert"},
         recommendation="Movement-focused. Validate: is client WS reset immediately or on server tick? If immediate, it's a client observer; if delayed, server-side.",
        },
        {name="Generic Luau AC (integrity)", type="client-side hook",
         approach="script integrity + GC scan",
         markers={
             {kind="remote", kw="integrity"},
             {kind="source", kw="getgc"},
             {kind="source", kw="getloadedmodules"},
             {kind="remote", kw="module"},
         },
         expectedOutcomes={"kick", "report"},
         recommendation="GC scans for injected functions. Avoid leaving references in GC. Use newcclosure and clear references after use.",
        },
        {name="Custom remote validator", type="server-side",
         approach="server-only, no client observer",
         markers={
             {kind="remote", kw="verify"},
             {kind="remote", kw="validate"},
             {kind="remote", kw="check"},
             {kind="remote", kw="state"},
         },
         expectedOutcomes={"server rejects, teleports back"},
         recommendation="No client observer. Server-side only. Hook detection is not the issue — argument validation is. Match expected argument shape exactly.",
        },
    },
}

local Fingerprint = {matches = {}, primary = nil, confidence = "low"}

local function scoreFingerprint(fp)
    local matched, total = 0, 0
    local hits = {}
    for _, m in ipairs(fp.markers) do
        total = total + 1
        local hit = false
        if m.kind == "remote" then
            for _, e in ipairs(findings.remotes or {}) do
                if e.text:lower():find(m.kw, 1, true) then hit = true break end
            end
        elseif m.kind == "script" then
            for _, e in ipairs(findings.scripts or {}) do
                if e.text:lower():find(m.kw, 1, true) then hit = true break end
            end
        elseif m.kind == "source" then
            for _, e in ipairs(findings.scripts or {}) do
                if e.text:lower():find(m.kw, 1, true) or e.text:lower():find("source matched '" .. m.kw, 1, true) then
                    hit = true break
                end
            end
        elseif m.kind == "global" then
            if type(getgenv) == "function" then
                local env = safe(getgenv)
                if env then
                    for k in pairs(env) do
                        if type(k) == "string" and k:lower():find(m.kw, 1, true) then hit = true break end
                    end
                end
            end
        end
        if hit then matched = matched + 1; table.insert(hits, m.kind .. ":" .. m.kw) end
    end
    return matched, total, hits
end

local function classifyFingerprint()
    Fingerprint.matches = {}
    Fingerprint.primary, Fingerprint.confidence = nil, "low"
    for _, fp in ipairs(FingerprintDB.known) do
        local matched, total, hits = scoreFingerprint(fp)
        if matched > 0 then
            local ratio = matched / total
            table.insert(Fingerprint.matches, {
                name=fp.name, matched=matched, total=total, ratio=ratio,
                hits=hits, fp=fp,
            })
        end
    end
    table.sort(Fingerprint.matches, function(a, b)
        if a.ratio ~= b.ratio then return a.ratio > b.ratio end
        return a.matched > b.matched
    end)
    if #Fingerprint.matches > 0 then
        local top = Fingerprint.matches[1]
        if top.ratio >= 0.8 and top.matched >= 3 then
            Fingerprint.primary = top
            Fingerprint.confidence = top.ratio >= 0.9 and "high" or "medium"
        elseif top.ratio >= 0.5 and top.matched >= 2 then
            Fingerprint.primary = top
            Fingerprint.confidence = "medium"
        end
    end
end

-- ============================================================
-- NEW: Stealth check — is our hook detectable?
-- ============================================================
local Stealth = {tests = {}, score = 0, total = 0, detectable = false, findings = {}}

local function isC(fn)
    if typeof(fn) ~= "function" then return false end
    if type(iscclosure) == "function" then return iscclosure(fn) end
    if debug and debug.getinfo then
        local ok, info = pcall(debug.getinfo, fn)
        if ok and info then
            if info.what ~= "C" then return false end
            if debug.getupvalue then
                local ok2, _, v = pcall(debug.getupvalue, fn, 1)
                if ok2 and v ~= nil then return false end
            end
            return true
        end
    end
    return false
end

local function runStealth()
    Stealth.tests = {}; Stealth.findings = {}
    local function add(name, ok, msg, weight)
        table.insert(Stealth.tests, {name=name, ok=ok, msg=msg, weight=weight})
    end
    -- 1. Is our own hook a C closure?
    local mt = features.getrawmetatable and safe(getrawmt, game) or nil
    if mt then
        local fn = rawget(mt, "__namecall")
        if typeof(fn) == "function" then
            add("__namecall is C closure", isC(fn), isC(fn) and "clean" or "Lua — visible to AC via debug.getinfo", 3)
        end
    else
        add("__namecall is C closure", false, "cannot inspect (getrawmetatable failed)", 3)
    end
    -- 2. Do our upvalues reveal us?
    if mt then
        local fn = rawget(mt, "__namecall")
        if typeof(fn) == "function" and not isC(fn) and debug and debug.getupvalue then
            local revealing = 0
            local i = 1
            while i <= 10 do
                local ok, name = pcall(debug.getupvalue, fn, i)
                if not ok or name == nil then break end
                if type(name) == "string" and name:lower():find("acprobe") then revealing = revealing + 1 end
                i = i + 1
            end
            add("upvalue names clean", revealing == 0, revealing == 0 and "no ACProbe-named upvalues" or (revealing .. " ACProbe-named upvalues visible"), 2)
        end
    end
    -- 3. Is the AC hooking debug.getinfo?
    if debug and type(debug.getinfo) == "function" then
        local clean = isC(debug.getinfo) or safe(iscclosure, debug.getinfo) == true
        add("debug.getinfo clean", clean, clean and "C closure" or "Lua — likely AC hook", 3)
    end
    -- 4. Is the AC hooking checkcaller?
    if type(checkcaller) == "function" then
        local clean = isC(checkcaller)
        add("checkcaller clean", clean, clean and "C closure" or "Lua — AC can subvert caller detection", 2)
    end
    -- 5. Are we running at elevated thread identity?
    local tid
    if type(getthreadidentity) == "function" then tid = safe(getthreadidentity)
    elseif type(getidentity) == "function" then tid = safe(getidentity) end
    if tid then
        add("thread identity", tid >= 7, "identity=" .. tostring(tid) .. (tid >= 7 and " (elevated, expected)" or " (low)"), 1)
    end
    -- 6. Is the AC watching __namecall upvalues?
    if mt then
        local fn = rawget(mt, "__namecall")
        if typeof(fn) == "function" and not isC(fn) and debug and debug.getinfo then
            local ok, info = pcall(debug.getinfo, fn, "S")
            if ok and info and type(info.source) == "string" then
                local acLike = info.source:lower():find("ac") or info.source:lower():find("guard")
                add("hook source not AC-adjacent", not acLike,
                    acLike and ("hook source is '" .. info.source .. "' — may be AC hook itself") or "hook source looks clean",
                    3)
            end
        end
    end

    Stealth.score, Stealth.total = 0, 0
    for _, t in ipairs(Stealth.tests) do
        Stealth.total = Stealth.total + t.weight
        if t.ok then Stealth.score = Stealth.score + t.weight end
    end
    Stealth.detectable = Stealth.total > 0 and (Stealth.score / Stealth.total) < 0.5
end

-- ============================================================
-- Findings + reputation + persistence
-- ============================================================
local sessionId = tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
local currentSession = {
    id=sessionId, account=player.Name, userId=player.UserId,
    placeId=game.PlaceId, started=os.time(),
    executor=Executor.name, executorVersion=Executor.version, os=Executor.os,
    compatScore=0, sUNC=sUNC.count .. "/" .. sUNC.total,
    findingCount=0,
}

local findings, findingsIndex = {}, {}
local CATEGORIES = {"environment","hooks","remotes","scripts","character","attributes","connections","tags"}
for _, c in ipairs(CATEGORIES) do findings[c] = {} end

local Reputation = {entries = {}}
function Reputation.Get(key)
    local e = Reputation.entries[key]
    return e and e.class or "unknown"
end
function Reputation.Set(key, class, reason)
    if class == "unknown" then Reputation.entries[key] = nil
    else Reputation.entries[key] = {class=class, reason=reason or "", setAt=os.time()} end
    local f = findingsIndex[key]
    if f then
        if class == "confirmed_ac" then f.weight = math.max(f.weight or 0, 20); f.level = "fail"
        elseif class == "confirmed_benign" or class == "benign" then f.weight = 0
        elseif class == "suspect" then f.weight = math.max(f.weight or 0, 5) end
    end
end

local Baseline = {}  -- set of keys marked baseline (excluded from score)

local SEV = {skip=0, ok=1, info=2, warn=3, fail=4}

local function push(cat, level, weight, text, extra)
    if not findings[cat] then findings[cat] = {} end
    local key = cat .. "|" .. text
    local rep = Reputation.Get(key)
    if rep == "confirmed_ac" then weight = math.max(weight or 0, 20); level = "fail"
    elseif rep == "confirmed_benign" then weight = 0; level = "ok"
    elseif rep == "benign" then weight = 0
    elseif rep == "suspect" then weight = math.max(weight or 0, 5) end
    if Baseline[key] then weight = 0 end

    local e = findingsIndex[key]
    if e then
        e.lastSeen = os.time(); e.count = e.count + 1
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
        }
        findingsIndex[key] = e
        table.insert(findings[cat], e)
        if #findings[cat] > 500 then
            local r = table.remove(findings[cat], 1)
            if r then findingsIndex[cat .. "|" .. r.text] = nil end
        end
    end
end

local STORAGE_FOLDER = "ACProbeV7"
local storagePath
local sessionHistory = {}

local function getStoragePath()
    if storagePath then return storagePath end
    if type(makefolder) == "function" and type(isfolder) == "function" then
        if not isfolder(STORAGE_FOLDER) then pcall(makefolder, STORAGE_FOLDER) end
        storagePath = STORAGE_FOLDER .. "/" .. tostring(game.PlaceId) .. ".json"
    else
        storagePath = "ACProbe_" .. tostring(game.PlaceId) .. ".json"
    end
    return storagePath
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
                remoteName=e.remoteName, scriptPath=e.scriptPath,
            })
        end
    end
    local hist, found = {}, false
    for _, s in ipairs(sessionHistory) do
        if s.id == sessionId then hist[#hist+1]=currentSession; found=true
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
    local base = {}
    for k, v in pairs(Baseline) do base[k] = v end
    return {
        schema=SCHEMA, placeId=game.PlaceId, placeName=game.Name, updated=os.time(),
        executor={name=Executor.name, version=Executor.version, os=Executor.os},
        compat={score=Compat.score, passed=Compat.passed, failed=Compat.failed},
        sUNC={count=sUNC.count, total=sUNC.total, missing=sUNC.missing},
        stealth={score=Stealth.score, total=Stealth.total, tests=Stealth.tests},
        fingerprint=Fingerprint.primary and {name=Fingerprint.primary.name, ratio=Fingerprint.primary.ratio, hits=Fingerprint.primary.hits} or nil,
        sessions=hist, findings=fs, reputation=rep, baseline=base,
        outcomes=Outcomes.serialise(),
        architecture={classification=Arch.classification, confidence=Arch.confidence, reasons=Arch.reasons},
    }
end

local function saveNow()
    if not features.file_io then return end
    currentSession.compatScore = Compat.score
    currentSession.findingCount = 0
    for _, cat in ipairs(CATEGORIES) do currentSession.findingCount = currentSession.findingCount + #findings[cat] end
    local ok, enc = pcall(HttpService.JSONEncode, HttpService, buildSnapshot())
    if ok and type(enc) == "string" then pcall(writefile, getStoragePath(), enc) end
end

local function persistLoad()
    if not features.file_io then return nil end
    local p = getStoragePath()
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
    if not features.file_io then return end
    if type(delfile) == "function" then
        local ok, ex = pcall(isfile, getStoragePath())
        if ok and ex then pcall(delfile, getStoragePath()) end
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
                        else
                            local entry = {
                                level=e.level or "info", weight=e.weight or 0, text=e.text,
                                firstSeen=e.firstSeen or os.time(), lastSeen=e.lastSeen or os.time(),
                                count=e.count or 1, sessions=e.sessions or {}, accounts=e.accounts or {},
                                remoteName=e.remoteName, scriptPath=e.scriptPath,
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
    if type(loaded.baseline) == "table" then
        for k, v in pairs(loaded.baseline) do Baseline[k] = v end
    end
    return merged, sess
end

-- ============================================================
-- NEW: Outcome tracer — what does the server do after a suspicious fire?
-- ============================================================
local Outcomes = {
    entries = {},  -- array of {remote, at, deltas...}
    active = {},   -- remoteName -> {startT, baseline, monitorThread}
    monitorSeconds = 4,
    MAX = 200,
}

function Outcomes.serialise()
    local out = {}
    for _, e in ipairs(Outcomes.entries) do
        table.insert(out, {
            remote = e.remote, at = e.at,
            consequences = e.consequences,
        })
    end
    return out
end

local function getCharSnapshot()
    local char = player.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return nil end
    return {
        pos = hrp.Position,
        ws = hum.WalkSpeed,
        jp = hum.JumpPower,
        hh = hum.HipHeight or 0,
        hp = hum.Health,
        tools = (function()
            local t = {}
            for _, c in ipairs(char:GetChildren()) do if c:IsA("Tool") then table.insert(t, c.Name) end end
            return t
        end)(),
        guiCount = player:FindFirstChild("PlayerGui") and #player.PlayerGui:GetChildren() or 0,
    }
end

function Outcomes.startMonitor(remoteName)
    if Outcomes.active[remoteName] then return end
    local base = getCharSnapshot()
    if not base then return end
    Outcomes.active[remoteName] = {startT = os.clock(), baseline = base}

    task.spawn(function()
        local start = os.clock()
        local consequences = {}
        while os.clock() - start < Outcomes.monitorSeconds do
            task.wait(0.2)
            local cur = getCharSnapshot()
            if not cur then
                table.insert(consequences, "character removed")
                break
            end
            if (cur.pos - base.pos).Magnitude > 15 and not table.find(consequences, "teleported") then
                table.insert(consequences, string.format("teleported %.1f studs", (cur.pos - base.pos).Magnitude))
            end
            if math.abs(cur.ws - base.ws) > 0.5 and not table.find(consequences, "walkSpeed changed") then
                table.insert(consequences, string.format("WalkSpeed %s→%s", base.ws, cur.ws))
            end
            if math.abs(cur.jp - base.jp) > 0.5 and not table.find(consequences, "jumpPower changed") then
                table.insert(consequences, string.format("JumpPower %s→%s", base.jp, cur.jp))
            end
            if math.abs(cur.hh - base.hh) > 0.5 and not table.find(consequences, "hipHeight changed") then
                table.insert(consequences, string.format("HipHeight %s→%s", base.hh, cur.hh))
            end
            if cur.hp < base.hp - 1 and not table.find(consequences, "health dropped") then
                table.insert(consequences, string.format("health %s→%s", base.hp, cur.hp))
            end
            if #cur.tools < #base.tools and not table.find(consequences, "tool removed") then
                table.insert(consequences, "tool removed")
            end
            if cur.guiCount ~= base.guiCount and not table.find(consequences, "gui changed") then
                table.insert(consequences, string.format("PlayerGui %d→%d", base.guiCount, cur.guiCount))
            end
        end
        Outcomes.active[remoteName] = nil
        if #consequences > 0 then
            table.insert(Outcomes.entries, {
                remote = remoteName, at = os.time(),
                consequences = consequences,
            })
            if #Outcomes.entries > Outcomes.MAX then table.remove(Outcomes.entries, 1) end
            -- Auto-attribute consequences as evidence
            for _, c in ipairs(consequences) do
                if c:find("teleport") then
                    push("remotes", "fail", 15, string.format("OUTCOME: '%s' → %s", remoteName, c), {remoteName=remoteName})
                elseif c:find("kick") then
                    push("remotes", "fail", 20, string.format("OUTCOME: '%s' → %s", remoteName, c), {remoteName=remoteName})
                elseif c:find("health dropped") or c:find("tool removed") then
                    push("remotes", "fail", 10, string.format("OUTCOME: '%s' → %s", remoteName, c), {remoteName=remoteName})
                elseif c:find("WalkSpeed") or c:find("JumpPower") or c:find("HipHeight") then
                    push("remotes", "warn", 8, string.format("OUTCOME: '%s' → %s (movement reset)", remoteName, c), {remoteName=remoteName})
                elseif c:find("gui changed") then
                    push("remotes", "warn", 6, string.format("OUTCOME: '%s' → %s (warning GUI)", remoteName, c), {remoteName=remoteName})
                end
            end
            saveNow()
        end
    end)
end

-- ============================================================
-- Behavioral profiler (condensed from v6, with outcome integration)
-- ============================================================
local Profiler = {
    window = 60, stateWindow = 200,
    remotes = {}, states = {}, lastState = nil, installed = false,
}

local function getState()
    local char = player.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return nil end
    return {pos=hrp.Position, hp=hum.Health, ws=hum.WalkSpeed,
            jp=hum.JumpPower, hh=hum.HipHeight or 0, state=(hum:GetState()).Name}
end

local function diffState(a, b, field, thr)
    if not a or not b then return false end
    if field == "pos" then return (a.pos - b.pos).Magnitude >= (thr or 3) end
    if field == "hp" then return math.abs(a.hp - b.hp) >= (thr or 1) end
    if field == "ws" then return math.abs(a.ws - b.ws) >= (thr or 0.5) end
    if field == "jp" then return math.abs(a.jp - b.jp) >= (thr or 0.5) end
    if field == "hh" then return math.abs(a.hh - b.hh) >= (thr or 0.5) end
    if field == "state" then return a.state ~= b.state end
    return false
end

local function snapState()
    local s = getState()
    if not s then return end
    local prev = Profiler.lastState
    Profiler.lastState = s
    table.insert(Profiler.states, {t=os.clock(), snap=s})
    if #Profiler.states > Profiler.stateWindow then table.remove(Profiler.states, 1) end
    return s, prev
end

local function argShape(args)
    local parts = {}
    for i = 1, #args do
        local v = args[i]; local t = typeof(v)
        if t == "table" then
            local ks = {}
            for k in pairs(v) do table.insert(ks, tostring(k)) end
            table.sort(ks); parts[i] = "{" .. table.concat(ks, ",") .. "}"
        elseif t == "Instance" then parts[i] = "I:" .. v.ClassName
        else parts[i] = t end
    end
    return table.concat(parts, "|")
end

local function recordCall(remoteName, method, args, caller)
    local p = Profiler.remotes[remoteName]
    if not p then
        p = {name=remoteName, calls=0, firstSeen=os.clock(), lastSeen=os.clock(),
             shapes={}, callTimes={}, corr={}, callers={}, suspicious=false}
        Profiler.remotes[remoteName] = p
    end
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
    end
    -- Check if this is a known suspicious remote — if so, start outcome monitor
    local isSuspicious = false
    for _, e in ipairs(findings.remotes or {}) do
        if e.remoteName == remoteName and (e.level == "warn" or e.level == "fail") then
            isSuspicious = true break
        end
    end
    if isSuspicious then
        p.suspicious = true
        Outcomes.startMonitor(remoteName)
    end
    -- Correlation
    local cur, prev = snapState()
    if prev and cur then
        for _, field in ipairs({"pos","hp","ws","jp","hh","state"}) do
            if diffState(prev, cur, field) then
                local c = p.corr[field] or {matched=0, total=0}
                c.matched = c.matched + 1
                p.corr[field] = c
            end
        end
    end
end

local function callstackTrace()
    if not debug or type(debug.getinfo) ~= "function" then return nil end
    local ourSource = "=[unknown]"
    pcall(function() ourSource = debug.info(1, "s") end)
    for i = 3, 15 do
        local ok, info = pcall(debug.getinfo, i, "Slf")
        if not ok or not info then break end
        local src = info.source
        if src and src ~= ourSource and src ~= "=[C]" then
            local clean = src:gsub("^[@=]", "")
            return {path = clean, line = info.currentline or 0}
        end
    end
    return nil
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
            local caller = callstackTrace()
            recordCall(nm, m, args, caller)
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
-- Architecture classifier
-- ============================================================
local Arch = {classification="None detected", confidence="low", reasons={}}

local function classifyArch()
    local hooks, conns, remotes, sources, correlated = 0, 0, 0, 0, 0
    for _, e in ipairs(findings.hooks or {}) do if e.level == "warn" or e.level == "fail" then hooks = hooks + 1 end end
    for _, e in ipairs(findings.connections or {}) do if e.level == "fail" then conns = conns + 1 end end
    for _, e in ipairs(findings.remotes or {}) do if e.level == "warn" or e.level == "fail" then remotes = remotes + 1 end end
    for _, e in ipairs(findings.scripts or {}) do if e.level == "fail" then sources = sources + 1 end end
    for _, p in pairs(Profiler.remotes) do
        for _, c in pairs(p.corr) do
            if c.total > 0 and c.matched / c.total >= 0.7 and c.matched >= 3 then correlated = correlated + 1 break end
        end
    end
    Arch.reasons = {}
    local score = 0
    if hooks > 0 then score = score + 2; table.insert(Arch.reasons, hooks .. " Lua hook(s)") end
    if conns > 0 then score = score + 2; table.insert(Arch.reasons, conns .. " AC connection(s)") end
    if remotes > 0 then score = score + 1; table.insert(Arch.reasons, remotes .. " name-matched remote(s)") end
    if correlated > 0 then score = score + 3; table.insert(Arch.reasons, correlated .. " behavioral correlation(s)") end
    if sources > 0 then score = score + 2; table.insert(Arch.reasons, sources .. " source match(es)") end
    if score == 0 then Arch.classification, Arch.confidence = "None detected", "high"
    elseif hooks > 0 or sources > 0 then
        Arch.classification, Arch.confidence = "Client-side (custom)", score >= 6 and "high" or "medium"
    elseif conns > 0 then
        Arch.classification, Arch.confidence = "Client-side (behavioral)", score >= 4 and "high" or "medium"
    elseif correlated > 0 then
        Arch.classification, Arch.confidence = "Server-side (validated remotes)", "medium"
    elseif remotes > 0 then
        Arch.classification, Arch.confidence = "Server-side (endpoints)", "low"
    else
        Arch.classification, Arch.confidence = "Undetermined", "low"
    end
end

-- ============================================================
-- NEW: Recommendation engine
-- ============================================================
local Recommendations = {items = {}}

local function generateRecommendations()
    Recommendations.items = {}

    -- From fingerprint
    if Fingerprint.primary then
        table.insert(Recommendations.items, {
            priority = "high",
            text = "Detected: " .. Fingerprint.primary.name ..
                   " (" .. string.format("%.0f%%", Fingerprint.primary.ratio*100) .. " marker match)",
        })
        for _, line in ipairs({Fingerprint.primary.fp.recommendation}) do
            table.insert(Recommendations.items, {priority="info", text=line})
        end
    end

    -- From outcomes
    local movementOutcome, positionOutcome, kickOutcome = false, false, false
    for _, e in ipairs(Outcomes.entries) do
        for _, c in ipairs(e.consequences) do
            if c:find("WalkSpeed") or c:find("JumpPower") or c:find("HipHeight") then movementOutcome = true end
            if c:find("teleport") then positionOutcome = true end
            if c:find("kick") then kickOutcome = true end
        end
    end
    if movementOutcome then
        table.insert(Recommendations.items, {priority="high", text="Movement reset observed — the AC actively reverts movement. Test in increments: WS 20, 24, 28, 30, 32. Stop at first kick or reset."})
    end
    if positionOutcome then
        table.insert(Recommendations.items, {priority="high", text="Position teleport-back observed — hard position validation. Direct CFrame sets are unsafe. Use WalkSpeed/HipHeight only, or avoid position manipulation."})
    end
    if kickOutcome then
        table.insert(Recommendations.items, {priority="fail", text="Kick observed — one probe already triggered the ban/kick threshold. Do not repeat this probe or any probe above it."})
    end
    if #Outcomes.entries > 0 and not (movementOutcome or positionOutcome or kickOutcome) then
        table.insert(Recommendations.items, {priority="info", text="Suspicious remotes fired but no client-visible consequence was observed. Likely server-side logging only — the AC reports but does not revert."})
    end

    -- From stealth
    if Stealth.total > 0 and (Stealth.score / Stealth.total) < 0.5 then
        table.insert(Recommendations.items, {priority="warn", text="Stealth score " .. Stealth.score .. "/" .. Stealth.total .. " — your hook is likely visible to the AC. Reinstall hook with newcclosure and clean upvalue names."})
    end

    -- From architecture
    if Arch.classification == "Client-side (custom)" then
        table.insert(Recommendations.items, {priority="info", text="Client-side AC observed. Hook detection is the primary risk. Verify Stealth tab before probing further."})
    elseif Arch.classification == "Server-side (validated remotes)" then
        table.insert(Recommendations.items, {priority="info", text="Server-side validation only. Client hooks are safe; match expected remote argument shape exactly."})
    end

    -- From behavioral
    for name, p in pairs(Profiler.remotes) do
        if p.calls >= 5 then
            for field, c in pairs(p.corr) do
                if c.total > 0 and c.matched / c.total >= 0.7 and c.matched >= 3 then
                    local label = (field == "ws" and "WalkSpeed") or (field == "jp" and "JumpPower")
                        or (field == "hh" and "HipHeight") or (field == "pos" and "position") or field
                    table.insert(Recommendations.items, {priority="info", text=string.format("'%s' validates %s (%d/%d correlation). This is the remote to study for the %s threshold.", name, label, c.matched, c.total, label)})
                end
            end
        end
    end

    -- Baseline filter hint
    local noiseCount = 0
    for cat, list in pairs(findings) do
        for _, e in ipairs(list) do
            if (e.level == "warn" or e.level == "fail") and (e.count or 1) <= 1 and not Baseline[cat .. "|" .. e.text] then
                noiseCount = noiseCount + 1
            end
        end
    end
    if noiseCount >= 5 then
        table.insert(Recommendations.items, {priority="info", text=noiseCount .. " single-observation findings. Consider marking cosmetic ones as baseline (click on Detection)."})
    end

    -- Sort: fail > high > warn > info
    local order = {fail=0, high=1, warn=2, info=3}
    table.sort(Recommendations.items, function(a, b)
        return (order[a.priority] or 99) < (order[b.priority] or 99)
    end)
end

-- ============================================================
-- Probes (condensed from v6)
-- ============================================================
local function pathOf(inst)
    local p, cur, g = {}, inst, 0
    while cur and cur ~= game and g < 40 do table.insert(p, 1, cur.Name); cur = cur.Parent; g = g + 1 end
    return "game." .. table.concat(p, ".")
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
    source = {"anticheat","anti_cheat","anti-cheat","detection","suspicious","violation","integritycheck","integrity_check","tamper","kickplayer","banplayer","flagplayer","reportplayer","hyperion","byfron","krampus","watchdog","humanoidstate","walkspeedcheck","speedcheck","jumpcheck"},
    attr = {"detect","flag","kick","report","ban","suspicious","violation","trust","verify","warn","strike","count","score","anomaly"},
    tag = {"anticheat","ac_","_ac","sentry","guard","watch","flagged","suspicious"},
}

local function anyMatch(str, list)
    if not str then return nil end
    local l = str:lower()
    for _, kw in ipairs(list) do if l:find(kw, 1, true) then return kw end end
    return nil
end

local function probe_hooks()
    if not (features.getrawmetatable and features.setreadonly) then
        push("hooks", "skip", 0, "Skipped: compat failed"); return
    end
    for _, t in ipairs({{name="game",obj=game}, {name="Instance",obj=Instance.new("Part")},
                         {name="Humanoid",obj=Instance.new("Humanoid")}, {name="Player",obj=player}}) do
        local ok, mt = pcall(getrawmt, t.obj)
        if ok and mt then
            for _, key in ipairs({"__namecall", "__index", "__newindex"}) do
                local fn = rawget(mt, key)
                if typeof(fn) == "function" and not isC(fn) then
                    local names = {}
                    if debug and debug.getupvalue then
                        local i = 1
                        while i <= 40 do
                            local ok2, n = pcall(debug.getupvalue, fn, i)
                            if not ok2 or n == nil then break end
                            if type(n) == "string" and not n:match("^%(") then table.insert(names, n) end
                            i = i + 1
                        end
                    end
                    local src = safe(function() return debug.info(fn, "s") end)
                    local label = string.format("%s.%s — Lua function (hooked)", t.name, key)
                    if src then label = label .. " source=" .. tostring(src) end
                    if #names > 0 then label = label .. " upvalues=" .. table.concat(names, ",") end
                    local attributed, weight = "unknown", 8
                    for _, kw in ipairs({"reportremote","detectioncallback","flagcallback","kickcallback"}) do
                        for _, n in ipairs(names) do
                            if n:lower():find(kw, 1, true) then attributed, weight = "likely AC (upvalue '" .. n .. "')", 25 break end
                        end
                        if attributed ~= "unknown" then break end
                    end
                    if attributed == "unknown" then
                        for _, kw in ipairs({"oldnamecall","orig_namecall","original","hooktarget"}) do
                            for _, n in ipairs(names) do
                                if n:lower():find(kw, 1, true) then attributed, weight = "likely executor (upvalue '" .. n .. "')", 2 break end
                            end
                            if attributed ~= "unknown" then break end
                        end
                    end
                    if features.decompile and typeof(fn) == "function" then
                        local dsrc = safe(decompile, fn)
                        if dsrc then
                            local kw = anyMatch(dsrc, SIG.source)
                            if kw then attributed, weight = "confirmed AC (source matched '" .. kw .. "')", 30 end
                        end
                    end
                    push("hooks", weight >= 20 and "fail" or (weight >= 5 and "warn" or "info"),
                        weight, label .. " — " .. attributed)
                end
            end
        end
    end
end

local function probe_remotes()
    local ok, descs = pcall(function() return ReplicatedStorage:GetDescendants() end)
    if not ok then push("remotes", "fail", 5, "RS scan failed"); return end
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
                                    string.format("'%s' (%s) at %s (kw: %s)", d.Name, d.ClassName, pathOf(d), kw),
                                    {scriptPath = pathOf(d)})
                            end
                        end
                        if features.decompile and budget > 0 and d:IsA("LocalScript") then
                            budget = budget - 1
                            local path = pathOf(d)
                            local fnSrc
                            if type(getscriptclosure) == "function" then
                                local okC, fn = pcall(getscriptclosure, d)
                                if okC and typeof(fn) == "function" then fnSrc = safe(decompile, fn) end
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
    if scanned == 0 then push("scripts", "skip", 0, "No scripts under roots")
    else push("scripts", "info", 0, string.format("%d scanned, %d name, %d source", scanned, nameHits, srcHits)) end
end

local function probe_character()
    local char = player.Character
    if not char then push("character", "skip", 0, "Character not spawned"); return end
    local allowed = {
        Head=true, Torso=true, ["Left Arm"]=true, ["Right Arm"]=true, ["Left Leg"]=true, ["Right Leg"]=true,
        HumanoidRootPart=true, UpperTorso=true, LowerTorso=true, LeftUpperArm=true, LeftLowerArm=true,
        LeftHand=true, RightUpperArm=true, RightLowerArm=true, RightHand=true, LeftUpperLeg=true,
        LeftLowerLeg=true, LeftFoot=true, RightUpperLeg=true, RightLowerLeg=true, RightFoot=true, Handle=true,
    }
    local extra, hidden = 0, 0
    for _, inst in ipairs(char:GetChildren()) do
        if inst:IsA("BasePart") and not allowed[inst.Name] then
            extra = extra + 1
            if extra <= 8 then
                push("character", "warn", 4, string.format("Non-body part '%s'", inst.Name))
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
    if not ok or type(all) ~= "table" then push("tags", "skip", 0, "CollectionService unavailable"); return end
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
    if not features.getconnections then push("connections", "skip", 0, "getconnections failed"); return end
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
        end
    end
    for _, t in ipairs(targets) do
        local ok, conns = pcall(getconnections, t.signal)
        if ok and conns then
            push("connections", #conns > 25 and "warn" or "ok", #conns > 25 and 4 or 0,
                string.format("%s: %d connection(s)", t.name, #conns))
        end
    end
end

local function probe_behavioral()
    for name, p in pairs(Profiler.remotes) do
        if p.calls >= 3 then
            for field, c in pairs(p.corr) do
                if c.total > 0 and c.matched / c.total >= 0.6 and c.matched >= 3 then
                    push("remotes", "warn", 5, string.format(
                        "Behavioral: '%s' correlates with %s (%d/%d)", name, field, c.matched, c.total),
                        {remoteName = name})
                end
            end
        end
    end
end

-- ============================================================
-- GUI
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ACProbeV7_" .. math.random(1000, 9999)
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
local okP = pcall(function()
    if gethui then screenGui.Parent = gethui()
    else screenGui.Parent = game:GetService("CoreGui") end
end)
if not okP then screenGui.Parent = player:WaitForChild("PlayerGui") end

local main = Instance.new("Frame")
main.Size = UDim2.new(0, 940, 0, 680)
main.Position = UDim2.new(0.5, -470, 0.5, -340)
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
titleLabel.Text = "  Anticheat Probe v7"
titleLabel.Size = UDim2.new(1, -380, 1, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.TextColor3 = Color3.fromRGB(230, 230, 235)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 14
titleLabel.Parent = titleBar

local headerInfo = Instance.new("TextLabel")
headerInfo.Text = ""
headerInfo.Size = UDim2.new(0, 370, 1, 0)
headerInfo.Position = UDim2.new(1, -375, 0, 0)
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
tabLayout.Padding = UDim.new(0, 3)
tabLayout.Parent = tabBar

local tabs = {"Recs","Overview","Outcomes","Detections","Probes","Live","Stealth","Test","Fingerprint"}
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
local probeBtn  = makeButton("Probe",     0.11, -2, Color3.fromRGB(180, 120, 40)); probeBtn.Position  = UDim2.new(0.14, 2, 0, 0)
local liveBtn   = makeButton("Live: Off", 0.12, -2, Color3.fromRGB(45, 45, 55));   liveBtn.Position   = UDim2.new(0.25, 4, 0, 0)
local exportBtn = makeButton("JSON",      0.10, -2, Color3.fromRGB(45, 100, 150));  exportBtn.Position = UDim2.new(0.37, 6, 0, 0)
local wipeBtn   = makeButton("Wipe",      0.10, -2, Color3.fromRGB(100, 50, 50));   wipeBtn.Position   = UDim2.new(0.47, 8, 0, 0)
local closeBtn  = makeButton("Close",     0.10, -2, Color3.fromRGB(120, 50, 50));   closeBtn.Position  = UDim2.new(0.88, 14, 0, 0)

-- Render helpers
local levels = {
    ok={icon="✓",color=Color3.fromRGB(80,200,120)}, info={icon="•",color=Color3.fromRGB(140,160,210)},
    warn={icon="!",color=Color3.fromRGB(230,180,80)}, fail={icon="✗",color=Color3.fromRGB(230,90,90)},
    skip={icon="─",color=Color3.fromRGB(120,120,130)},
}
local orderCounter = 0
local function nextOrder() orderCounter = orderCounter + 1; return orderCounter end
local function clearTab(name)
    for _, c in ipairs(tabContents[name]:GetChildren()) do
        if c:IsA("Frame") or c:IsA("TextButton") then c:Destroy() end
    end
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
    if e.firstSeen and (os.time() - e.firstSeen) > 60 then parts[#parts+1] = fmtAgo(e.firstSeen) end
    return #parts > 0 and table.concat(parts, " · ") or nil
end

local function scoreAll()
    local t = 0
    for _, list in pairs(findings) do
        for _, f in ipairs(list) do
            local key = "?"
            for c, l in pairs(findings) do
                for _, e in ipairs(l) do if e == f then key = c .. "|" .. f.text break end end
                if key ~= "?" then break end
            end
            if not Baseline[key] then t = t + (f.weight or 0) end
        end
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

local function renderRecommendations()
    addHeader("Recs", "Recommended next steps")
    if #Recommendations.items == 0 then
        addRow("Recs", "info", "No recommendations yet — run probes and outcomes will populate this")
        return
    end
    for _, r in ipairs(Recommendations.items) do
        local lvl = (r.priority == "fail" and "fail") or (r.priority == "high" and "warn")
                    or (r.priority == "warn" and "warn") or "info"
        addRow("Recs", lvl, r.text)
    end
    addHeader("Recs", "Quick actions")
    addRow("Recs", "info", "→ Probe tab: click Probe to test state changes (safe, auto-reverts)")
    addRow("Recs", "info", "→ Stealth tab: verify your hook isn't visible before probing further")
    addRow("Recs", "info", "→ Detections tab: click any finding to mark baseline/confirmed_ac")
end

local function renderOverview()
    local score = scoreAll()
    local band, color = threatBand(score)
    threatFill.Size = UDim2.new(score / 100, 0, 1, 0)
    threatFill.BackgroundColor3 = color
    threatLabel.Text = string.format("  Threat: %d / 100  —  %s", score, band)
    if Fingerprint.primary then
        archLabel.Text = string.format("  Detected: %s (%s)  ·  Architecture: %s",
            Fingerprint.primary.name, Fingerprint.confidence, Arch.classification)
    else
        archLabel.Text = string.format("  Architecture: %s (%s confidence)", Arch.classification, Arch.confidence)
    end

    addHeader("Overview", "Executor + Compat")
    addRow("Overview", Compat.score >= 80 and "ok" or (Compat.score >= 50 and "warn" or "fail"),
        string.format("%s v%s · %s", Executor.name, Executor.version, Executor.os),
        string.format("compat %d%%", Compat.score))
    addRow("Overview", sUNC.count >= sUNC.total * 0.9 and "ok" or "warn",
        string.format("sUNC: %d/%d functions present", sUNC.count, sUNC.total),
        sUNC.count == sUNC.total and "full" or "partial")

    addHeader("Overview", "Analysis")
    addRow("Overview", score >= 60 and "fail" or (score >= 30 and "warn" or "ok"),
        string.format("%s · %d reasons · %d sessions loaded",
            Arch.classification, #Arch.reasons, #sessionHistory + 1))
    for _, r in ipairs(Arch.reasons) do addRow("Overview", "info", "  · " .. r) end

    addHeader("Overview", "Category weights")
    for _, cat in ipairs(CATEGORIES) do
        local list = findings[cat]
        local w, bad = 0, 0
        for _, f in ipairs(list) do
            if not Baseline[cat .. "|" .. f.text] then w = w + (f.weight or 0) end
            if f.level == "warn" or f.level == "fail" then bad = bad + 1 end
        end
        addRow("Overview", bad > 0 and "warn" or "ok",
            string.format("%-12s  %d findings, %d flagged, weight %d", cat, #list, bad, w))
    end

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

local function renderOutcomes()
    addHeader("Outcomes", string.format("%d outcome(s) captured", #Outcomes.entries))
    if #Outcomes.entries == 0 then
        addRow("Outcomes", "skip", "No outcomes yet — enable Live and let the AC react to normal play")
        addRow("Outcomes", "info", "Outcomes capture what the SERVER does after a suspicious remote fires.")
        addRow("Outcomes", "info", "Watch for: teleport-back, WalkSpeed reset, HP drop, kick, GUI change.")
        return
    end
    for i = #Outcomes.entries, 1, -1 do
        local e = Outcomes.entries[i]
        local lvl = "info"
        for _, c in ipairs(e.consequences) do
            if c:find("kick") or c:find("teleport") then lvl = "fail" break end
            if c:find("WalkSpeed") or c:find("JumpPower") or c:find("health") then lvl = "warn" end
        end
        addRow("Outcomes", lvl, string.format("%s  →  %s", e.remote, table.concat(e.consequences, " · ")),
            os.date("%H:%M:%S", e.at))
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

    addHeader("Detections", string.format("%d active (click to cycle reputation)", #all))
    if #all == 0 then addRow("Detections", "ok", "No active detections"); return end
    for i = 1, math.min(60, #all) do
        local it = all[i]
        local key = it.cat .. "|" .. it.f.text
        local rep = Reputation.Get(key)
        local base = Baseline[key]
        local tag = ""
        if rep ~= "unknown" then tag = "[" .. rep .. "] " end
        if base then tag = tag .. "[baseline] " end
        addRow("Detections", it.f.level, tag .. "[" .. it.cat .. "] " .. it.f.text, entryMeta(it.f),
            function()
                -- Cycle: unknown → baseline → suspect → confirmed_ac → confirmed_benign → unknown
                local cur = Reputation.Get(key)
                if Baseline[key] then
                    Baseline[key] = nil
                    Reputation.Set(key, "suspect", "unbaselined")
                else
                    local nxt = cur == "unknown" and "suspect"
                        or cur == "suspect" and "confirmed_ac"
                        or cur == "confirmed_ac" and "confirmed_benign"
                        or "unknown"
                    if nxt == "unknown" then Reputation.Set(key, "unknown") end
                    if nxt ~= "unknown" then Reputation.Set(key, nxt) end
                end
                renderAll()
            end)
    end
    addHeader("Detections", "Baseline controls")
    addRow("Detections", "info", "Shift-click any row to mark/unmark baseline (excluded from score).")
    addRow("Detections", "info", string.format("Baseline count: %d", (function()
        local c = 0 for _ in pairs(Baseline) do c = c + 1 end return c
    end)()))
end

local function renderProbes()
    addHeader("Probes", "Controlled state-change tests (auto-revert)")
    if #AutoProbe.results == 0 then
        addRow("Probes", "skip", "No probes run yet — click Probe button")
        addRow("Probes", "info", "Each probe: set state → wait 2s → observe → revert")
        addRow("Probes", "info", "Remotes that fire ONLY during a specific probe are causally linked.")
        return
    end
    for _, r in ipairs(AutoProbe.results) do
        local lvl = (r.level == "warn" and "warn") or (r.level == "fail" and "fail")
                    or (r.level == "skip" and "skip") or "ok"
        addRow("Probes", lvl, r.name .. " — " .. (r.msg or ""))
    end
end

local function renderLive()
    addHeader("Live", "Behavioral profiles + callstack")
    local sorted = {}
    for _, p in pairs(Profiler.remotes) do if p.calls >= 1 then sorted[#sorted+1] = p end end
    table.sort(sorted, function(a, b) return a.calls > b.calls end)
    if #sorted == 0 then addRow("Live", "skip", "No remote calls observed"); return end
    for i = 1, math.min(20, #sorted) do
        local p = sorted[i]
        local shapeCount = 0
        for _ in pairs(p.shapes) do shapeCount = shapeCount + 1 end
        local corrStr = ""
        for field, c in pairs(p.corr) do
            if c.total > 0 and c.matched / c.total >= 0.5 then
                corrStr = corrStr .. string.format(" %s=%d%%", field, math.floor(c.matched/c.total*100))
            end
        end
        addRow("Live", p.suspicious and "warn" or "info",
            string.format("%-28s  calls=%d shapes=%d%s",
                p.name:sub(1, 28), p.calls, shapeCount, corrStr))
        local callers = {}
        for path, count in pairs(p.callers) do table.insert(callers, {path=path, count=count}) end
        table.sort(callers, function(a, b) return a.count > b.count end)
        for i2 = 1, math.min(2, #callers) do
            addRow("Live", "info", string.format("  ← %s (%d×)", callers[i2].path, callers[i2].count))
        end
    end
end

local function renderStealth()
    addHeader("Stealth", string.format("Score: %d/%d — %s",
        Stealth.score, Stealth.total,
        (Stealth.total > 0 and Stealth.score / Stealth.total >= 0.7) and "good" or "DETECTABLE"))
    if #Stealth.tests == 0 then
        addRow("Stealth", "skip", "No stealth tests run")
        return
    end
    for _, t in ipairs(Stealth.tests) do
        addRow("Stealth", t.ok and "ok" or (t.weight >= 3 and "fail" or "warn"),
            string.format("[w%d] %s — %s", t.weight, t.name, t.msg))
    end
    addHeader("Stealth", "Why this matters")
    addRow("Stealth", "info", "If __namecall is a Lua function with ACProbe-named upvalues,")
    addRow("Stealth", "info", "the AC can identify and target your hook.")
    addRow("Stealth", "info", "newcclosure() + clean upvalue names is standard mitigation.")
end

local function renderTest()
    addHeader("Test", string.format("Compat %d/%d (%d%%) · sUNC %d/%d",
        Compat.passed, Compat.total, Compat.score, sUNC.count, sUNC.total))
    addRow("Test", sUNC.count == sUNC.total and "ok" or "warn",
        string.format("sUNC: %d/%d present", sUNC.count, sUNC.total),
        sUNC.count == sUNC.total and "full sUNC" or "partial")
    if #sUNC.missing > 0 then
        addRow("Test", "info", "sUNC missing: " .. table.concat(sUNC.missing, ", "))
    end
    addHeader("Test", "Detailed")
    for _, r in ipairs(Compat.results) do
        addRow("Test", r.ok and "ok" or "fail",
            string.format("[w%d] %s — %s", r.weight, r.name, r.msg),
            r.ok and "pass" or "FAIL")
    end
end

local function renderFingerprint()
    addHeader("Fingerprint", "Known AC matches (weighted marker scoring)")
    if #Fingerprint.matches == 0 then
        addRow("Fingerprint", "skip", "No fingerprint matches yet — run Run All first")
        return
    end
    for _, m in ipairs(Fingerprint.matches) do
        local lvl = m.ratio >= 0.8 and "fail" or (m.ratio >= 0.5 and "warn" or "info")
        addRow("Fingerprint", lvl,
            string.format("%s — %d/%d markers (%.0f%%)", m.name, m.matched, m.total, m.ratio*100))
        for _, hit in ipairs(m.hits) do
            addRow("Fingerprint", "info", "  · " .. hit)
        end
        if m.ratio >= 0.5 then
            addRow("Fingerprint", "info", "  Rec: " .. m.fp.recommendation)
        end
    end
    addHeader("Fingerprint", "How it works")
    addRow("Fingerprint", "info", "Each known AC has weighted markers: remote names, script names,")
    addRow("Fingerprint", "info", "decompiled-source keywords, global names. Hit ≥80% = high confidence.")
end

local function renderAll()
    orderCounter = 0
    for _, t in ipairs(tabs) do clearTab(t) end
    classifyArch()
    classifyFingerprint()
    generateRecommendations()
    headerInfo.Text = string.format("%s · %s · sUNC %d/%d · compat %d%%",
        Executor.name, Executor.os, sUNC.count, sUNC.total, Compat.score)
    renderRecommendations()
    renderOverview()
    renderOutcomes()
    renderDetections()
    renderProbes()
    renderLive()
    renderStealth()
    renderTest()
    renderFingerprint()
end

-- ============================================================
-- AutoProbe (safe defaults; risky probes stay disabled unless toggled)
-- ============================================================
local AutoProbe = {results = {}, running = false, riskyEnabled = false}

local function snapshotCounts()
    local c = {}
    for name, p in pairs(Profiler.remotes) do c[name] = p.calls end
    return c
end

local function probeOne(name, setup, teardown, waitSec, risky)
    if risky and not AutoProbe.riskyEnabled then
        return {name=name, level="skip", msg="risky (disabled)"}
    end
    local before = snapshotCounts()
    local okS, errS = pcall(setup)
    if not okS then pcall(teardown); return {name=name, level="fail", msg="setup: " .. tostring(errS)} end
    local t0 = os.clock()
    while os.clock() - t0 < (waitSec or 2) do task.wait(0.05) end
    local after = snapshotCounts()
    pcall(teardown)
    local fired = {}
    for rn, c in pairs(after) do
        if c > (before[rn] or 0) then fired[rn] = c - (before[rn] or 0) end
    end
    local summary = {}
    for rn, c in pairs(fired) do table.insert(summary, rn .. "(" .. c .. ")") end
    table.sort(summary)
    local count = 0
    for _, c in pairs(fired) do count = count + c end
    return {
        name=name, level=count > 0 and "warn" or "ok",
        msg=count > 0 and ("remotes: " .. table.concat(summary, ", ")) or "no remotes fired",
        fired=fired, count=count, risky=risky,
    }
end

local function runAutoProbes()
    if AutoProbe.running then return end
    AutoProbe.running = true
    AutoProbe.results = {}
    titleLabel.Text = "  Antichat Probe v7 — probing (state changes auto-revert)..."

    local char = player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then
        table.insert(AutoProbe.results, {name="init", level="fail", msg="no character"})
        AutoProbe.running = false; renderAll(); return
    end
    local baseWS, baseJP, baseHH = hum.WalkSpeed, hum.JumpPower, hum.HipHeight or 0
    local baseCF = hrp.CFrame

    local p1 = probeOne("WalkSpeed +20%",
        function() hum.WalkSpeed = baseWS * 1.2 end,
        function() hum.WalkSpeed = baseWS end, 2, false)
    table.insert(AutoProbe.results, p1)
    if p1.count and p1.count > 0 then
        for rn in pairs(p1.fired) do
            push("remotes", "warn", 6, string.format("Probe: '%s' fired on WalkSpeed change", rn), {remoteName=rn})
        end
    end
    task.wait(0.5)

    local p2 = probeOne("JumpPower +50%",
        function() hum.JumpPower = baseJP * 1.5 end,
        function() hum.JumpPower = baseJP end, 2, false)
    table.insert(AutoProbe.results, p2)
    if p2.count and p2.count > 0 then
        for rn in pairs(p2.fired) do
            push("remotes", "warn", 6, string.format("Probe: '%s' fired on JumpPower change", rn), {remoteName=rn})
        end
    end
    task.wait(0.5)

    local p3 = probeOne("HipHeight +3",
        function() hum.HipHeight = baseHH + 3 end,
        function() hum.HipHeight = baseHH end, 2, false)
    table.insert(AutoProbe.results, p3)
    if p3.count and p3.count > 0 then
        for rn in pairs(p3.fired) do
            push("remotes", "warn", 6, string.format("Probe: '%s' fired on HipHeight change", rn), {remoteName=rn})
        end
    end
    task.wait(0.5)

    local p4 = probeOne("Position +10 studs X",
        function() hrp.CFrame = baseCF + Vector3.new(10, 0, 0) end,
        function() if hrp and hrp.Parent then hrp.CFrame = baseCF end end, 2, false)
    table.insert(AutoProbe.results, p4)
    if p4.count and p4.count > 0 then
        for rn in pairs(p4.fired) do
            push("remotes", "warn", 6, string.format("Probe: '%s' fired on position shift", rn), {remoteName=rn})
        end
    end
    task.wait(0.5)

    if AutoProbe.riskyEnabled then
        local p5 = probeOne("Noclip 2s",
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
                push("remotes", "warn", 6, string.format("Probe: '%s' fired on noclip", rn), {remoteName=rn})
            end
        end
    end

    saveNow()
    renderAll()
    titleLabel.Text = "  Anticheat Probe v7"
    AutoProbe.running = false
end

-- ============================================================
-- Runner + Live + Buttons
-- ============================================================
local running = false
local probes = {
    {"hooks", probe_hooks}, {"remotes", probe_remotes}, {"scripts", probe_scripts},
    {"character", probe_character}, {"attributes", probe_attributes},
    {"tags", probe_tags}, {"connections", probe_connections},
    {"behavioral", probe_behavioral},
}

local function runAll()
    if running then return end
    running = true
    for i, p in ipairs(probes) do
        titleLabel.Text = string.format("  Anticheat Probe v7 — %d/%d: %s", i, #probes, p[1])
        local ok, err = pcall(p[2])
        if not ok then push(p[1], "fail", 5, "Crashed: " .. tostring(err)) end
        saveNow()
        task.wait()
    end
    runStealth()
    renderAll()
    titleLabel.Text = "  Anticheat Probe v7"
    running = false
end

local liveOn = false
local function startLive()
    if liveOn then return end
    liveOn = true
    installProfilerHook()
    snapState()
    task.spawn(function()
        while liveOn do
            snapState()
            if not Profiler.installed then installProfilerHook() end
            renderAll()
            task.wait(2)
        end
    end)
    liveBtn.Text = "Live: On"
    liveBtn.BackgroundColor3 = Color3.fromRGB(40, 120, 80)
end
local function stopLive()
    liveOn = false
    liveBtn.Text = "Live: Off"
    liveBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
end

runBtn.MouseButton1Click:Connect(runAll)
probeBtn.MouseButton1Click:Connect(function()
    if AutoProbe.running then return end
    task.spawn(runAutoProbes)
end)
liveBtn.MouseButton1Click:Connect(function() if liveOn then stopLive() else startLive() end end)
exportBtn.MouseButton1Click:Connect(function()
    if not features.setclipboard then exportBtn.Text = "No clip"; task.wait(1); exportBtn.Text = "JSON"; return end
    local payload = buildSnapshot()
    payload.score = scoreAll()
    payload.band = (threatBand(scoreAll()))
    payload.sUNCStatus = {present=sUNC.present, missing=sUNC.missing, count=sUNC.count, total=sUNC.total}
    payload.fingerprintMatches = Fingerprint.matches
    payload.recommendations = Recommendations.items
    payload.compat = {score=Compat.score, passed=Compat.passed, failed=Compat.failed, results=Compat.results}
    payload.exportedAt = os.time()
    local ok, json = pcall(HttpService.JSONEncode, HttpService, payload)
    if not ok then exportBtn.Text = "Enc err"; task.wait(1); exportBtn.Text = "JSON"; return end
    setclipboard(json)
    exportBtn.Text = "Copied!"
    task.wait(1); exportBtn.Text = "JSON"
end)
wipeBtn.MouseButton1Click:Connect(function()
    wipeBtn.Text = "Sure?"
    local armed = true
    task.delay(3, function() if armed then armed = false; wipeBtn.Text = "Wipe" end end)
    local conn
    conn = wipeBtn.MouseButton1Click:Connect(function()
        if not armed then return end
        armed = false; conn:Disconnect()
        persistDelete()
        for _, c in ipairs(CATEGORIES) do
            for i = #findings[c], 1, -1 do findings[c][i] = nil end
        end
        findingsIndex = {}; sessionHistory = {}
        Reputation.entries = {}; Baseline = {}
        Profiler.remotes = {}
        Outcomes.entries = {}; AutoProbe.results = {}
        renderAll()
        wipeBtn.Text = "Wiped"
        task.wait(1); wipeBtn.Text = "Wipe"
    end)
end)
closeBtn.MouseButton1Click:Connect(function()
    saveNow(); screenGui:Destroy()
end)

-- ============================================================
-- Kickoff
-- ============================================================
setTab("Recs")
titleLabel.Text = "  Anticheat Probe v7 — compat test..."

task.spawn(function()
    runCompat()
    runSUNC()
    currentSession.compatScore = Compat.score
    currentSession.sUNC = sUNC.count .. "/" .. sUNC.total

    local loaded = persistLoad()
    local merged, sess = 0, 0
    if loaded then merged, sess = mergeLoaded(loaded) end

    installProfilerHook()
    runStealth()
    renderAll()

    if merged > 0 then
        titleLabel.Text = string.format("  Anticheat Probe v7 — resumed %d findings", merged)
        task.wait(2)
    end
    task.spawn(runAll)
end)