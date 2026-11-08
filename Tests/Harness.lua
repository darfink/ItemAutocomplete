-- Simulation harness for the addon's non-UI modules
--
-- It stubs the WoW API, including an item server that answers late, drops
-- queries or never answers them, and checks the item database and search
-- against it. Run it from the repository root with LuaJIT (or Lua 5.1):
--
--   luajit Tests/Harness.lua
local root = arg[1] or '.'
local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    print('FAIL: ' .. msg)
  else
    print('ok:   ' .. msg)
  end
end

math.randomseed(42)

------------------------------------------------------------------ WoW stubs
local now = 0
local frames = {}
local combat = false
local build = '70783'
_G.GetTime = function() return now end
local serverTimeOffset = 1800000000
_G.GetServerTime = function() return math.floor(now) + serverTimeOffset end
_G.InCombatLockdown = function() return combat end
_G.GetLocale = function() return 'enUS' end
_G.GetRealmName = function() return 'Realm' end
_G.UnitName = function() return 'Player' end
local interface = 120105
_G.GetBuildInfo = function() return '12.1.5', build, 'Nov 4 2026', interface end
_G.WOW_PROJECT_ID = 1
_G.WOW_PROJECT_MAINLINE = 1
_G.WOW_PROJECT_CLASSIC = 2
_G.geterrorhandler = function() return function(e) error(e, 0) end end
_G.ITEM_QUALITY_COLORS = { [1] = { hex = '|cffffffff' }, [4] = { hex = '|cffa335ee' } }
_G.C_AddOns = {
  GetAddOnMetadata = function(_, field)
    return ({ ['X-ItemDatabaseVersion'] = '10', Version = '2.2.0', Title = 'IA', Author = 'x',
              Notes = 'n' })[field]
  end,
}

local eventFrames = {}
function _G.CreateFrame()
  local f = { scripts = {}, shown = true, events = {} }
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:RegisterEvent(e) self.events[e] = true end
  function f:UnregisterEvent(e) self.events[e] = nil end
  frames[#frames + 1] = f
  eventFrames[#eventFrames + 1] = f
  return f
end
local function fire(event, ...)
  for _, f in ipairs(eventFrames) do
    if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
  end
end
local function tick(dt)
  now = now + (dt or 1 / 60)
  for _, f in ipairs(frames) do
    if f.shown and f.scripts.OnUpdate then f.scripts.OnUpdate(f, dt) end
  end
end

-- Simulated item server
local server = {}
local function resetServer(opts)
  server = {
    items = opts.items, -- [id] = { name, quality }
    local_ = opts.localIds, -- ids the client's item table knows
    cache = {},
    inFlight = {}, -- { id, at }
    dropRate = opts.dropRate or 0,
    latency = opts.latency or 0.1,
    maxInFlight = opts.maxInFlight or 1e9,
    requests = 0,
    overloadDrops = 0,
  }
end
local function serverTick()
  local remaining = {}
  for _, req in ipairs(server.inFlight) do
    if now - req.at >= server.latency then
      if not req.dropped then
        local item = server.items[req.id]
        if item then
          server.cache[req.id] = true
          fire('GET_ITEM_INFO_RECEIVED', req.id, true)
        elseif server.local_[req.id] then
          fire('GET_ITEM_INFO_RECEIVED', req.id, false)
        else
          fire('GET_ITEM_INFO_RECEIVED', req.id, nil)
        end
      end
    else
      remaining[#remaining + 1] = req
    end
  end
  server.inFlight = remaining
end
_G.C_Item = {
  GetItemInfoInstant = function(id)
    if server.local_[id] then return id, 'Armor' end
  end,
  GetItemInfo = function(id)
    if _G.blockedId == id then return nil end
    local item = server.items[id]
    if item and server.cache[id] then
      return item[1], ('|cff|Hitem:%d|h[%s]|h|r'):format(id, item[1]), item[2]
    end
    -- request
    for _, r in ipairs(server.inFlight) do if r.id == id then return nil end end
    server.requests = server.requests + 1
    server.perId = server.perId or {}
    server.perId[id] = (server.perId[id] or 0) + 1
    local dropped = math.random() < server.dropRate
    if #server.inFlight >= server.maxInFlight then
      dropped = true
      server.overloadDrops = server.overloadDrops + 1
    end
    server.inFlight[#server.inFlight + 1] = { id = id, at = now, dropped = dropped }
    return nil
  end,
}
_G.C_Timer = { After = function(_, fn) fn() end }

------------------------------------------------------------------ Module loader
local addonTable = {}
local function load(path)
  local chunk = assert(loadfile(root .. '/' .. path))
  chunk('ItemAutocomplete', addonTable)
end
load('Libs/LibModule/LibModule.lua')
for _, f in ipairs({
  'Source/Shared/UTF8/Casing.lua', 'Source/Shared/UTF8/Charsets.lua', 'Source/Shared/UTF8/Index.lua',
  'Source/Shared/EventSource.lua', 'Source/Shared/Persistence.lua',
  'Source/Shared/TaskScheduler.lua', 'Source/Utility/Functions.lua',
  'Source/Utility/FuzzyMatcher.lua', 'Source/CompletionSource.lua', 'Source/ItemDatabase.lua',
}) do load(f) end

local function getModule(name)
  local chunk = loadstring("local _, t, n = ...; t('Probe_' .. n); return require(n)")
  return chunk(nil, addonTable, name)
end
local ItemDatabase = getModule('ItemDatabase')
local CompletionSource = getModule('CompletionSource')
local EventSource = getModule('Shared.EventSource')
local Persistence = getModule('Shared.Persistence')
local TaskScheduler = getModule('Shared.TaskScheduler')
local FuzzyMatcher = getModule('Utility.FuzzyMatcher')
local utf8 = getModule('Shared.UTF8')

------------------------------------------------------------------ Fake retail item set
local syllables = { 'thun', 'der', 'fury', 'blade', 'of', 'the', 'wind', 'seek', 'er', 'ash',
                    'bring', 'devil', 'saur', 'gaunt', 'lets', 'robe', 'void', 'Ärm', 'ße', 'Ünd',
                    'шлем', 'Меч', 'ice', 'fire', 'Staff', 'Ring' }
local function randomName()
  local words = {}
  for w = 1, math.random(1, 4) do
    local word = ''
    for _ = 1, math.random(1, 3) do word = word .. syllables[math.random(#syllables)] end
    word = word:sub(1, 1):upper() .. word:sub(2)
    words[w] = word
  end
  return table.concat(words, ' ')
end

local items, localIds = {}, {}
for id = 1, 140000 do
  local r = math.random()
  if (id < 60000 and r < 0.25) or (id >= 60000 and id < 90000 and r < 0.02) or (id > 120000 and r < 0.3) then
    localIds[id] = true
    if math.random() < 0.85 then
      local name = randomName()
      if math.random() < 0.01 then name = 'Test ' .. name end
      items[id] = { name, math.random(0, 5) }
    end
  end
end
-- big gap 90000..120000 with nothing; must be bridged by the open range gap (50000)
for id = 90000, 120000 do localIds[id] = nil; items[id] = nil end

local function countExpected(db)
  local n = 0
  for id, item in pairs(items) do
    if not db:_IsDevItem(id, item[1]) then n = n + 1 end
  end
  return n
end

------------------------------------------------------------------ Scenario 1: full scan, lossy server
resetServer({ items = items, localIds = localIds, dropRate = 0.05, latency = 0.15, maxInFlight = 60 })
_G.ItemAutocompleteDB = nil
local events = EventSource.New()
local scheduler = TaskScheduler.New()
local persistence = Persistence.New('ItemAutocompleteDB')
local db = ItemDatabase.New(persistence, events, scheduler)
check(db:IsObsolete(), 'fresh database is obsolete')
local finished, finishedCount
db:UpdateItemsAsync(true, function(n) finished = true; finishedCount = n end)
local lastProgress, monotonic, ticks = 0, true, 0
while not finished and ticks < 200000 do
  serverTick(); tick(1 / 60); ticks = ticks + 1
  local p = db:GetUpdateProgress()
  if p + 1e-9 < lastProgress then monotonic = false end
  lastProgress = p
  if ticks == 600 then
    -- searching works mid-scan
    local ids = db:GetSearchData()
    check(#ids > 0, ('items searchable mid-scan (%d)'):format(#ids))
  end
end
local wanted = countExpected(db)
print(('scan: %d ticks (%.0fs simulated), %d requests, %d overload drops, %d/%d items, limit %.1f')
        :format(ticks, ticks / 60, server.requests, server.overloadDrops, db:GetItemCount(), wanted, db.requestLimit))
check(finished, 'full scan finishes')
check(monotonic, 'progress is monotonic')
check(finishedCount == db:GetItemCount(), 'finish callback receives item count')
-- with 5% random drops & 3 attempts, expect ~ 0.05^3 missing
check(db:GetItemCount() >= wanted * 0.995 and db:GetItemCount() <= wanted, 'nearly every item indexed')
local hasDev = false
for _, id in ipairs((db:GetSearchData())) do
  if items[id][1]:match('^Test ') then hasDev = true end
end
check(not hasDev, 'dev items filtered')
check(not db:IsObsolete() and not db:IsOutdated(), 'database is current after the scan')
check(db.database.scan == nil, 'scan state cleared')
local found130k = false
for id in pairs(db.database.names) do if id > 120000 then found130k = true break end end
check(found130k, 'open-ended range crosses the 30000 ID gap')

------------------------------------------------------------------ Scenario 2: patch adds items (incremental)
for id = 141000, 141100 do localIds[id] = true; items[id] = { 'Patch Item ' .. id, 4 } end
build = '70800'
for _, f in ipairs(frames) do f.shown = false; f.scripts = {} end
local events2, scheduler2 = EventSource.New(), TaskScheduler.New()
local db2 = ItemDatabase.New(Persistence.New('ItemAutocompleteDB'), events2, scheduler2)
check(not db2:IsObsolete() and db2:IsOutdated(), 'new build marks database outdated')
local before = db2:GetItemCount()
server.requests = 0
finished = false
db2:UpdateItemsAsync(false, function() finished = true end)
ticks = 0
while not finished and ticks < 200000 do serverTick(); tick(1 / 60); ticks = ticks + 1 end
check(finished, 'incremental scan finishes')
check(db2:GetItemCount() - before >= 101, ('incremental scan adds new items (+%d, %d requests)'):format(db2:GetItemCount() - before, server.requests))
check(db2:GetItemName(141050) == 'Patch Item 141050', 'patch item present')

------------------------------------------------------------------ Scenario 3: resume after relog mid-scan, combat pause
resetServer({ items = items, localIds = localIds, dropRate = 0, latency = 0.1 })
local events3, scheduler3 = EventSource.New(), TaskScheduler.New()
local db3 = ItemDatabase.New(Persistence.New('ItemAutocompleteDB'), events3, scheduler3)
db3:UpdateItemsAsync(true, function() end)
for _ = 1, 300 do serverTick(); tick(1 / 60) end
local mid = db3:GetUpdateProgress()
check(mid > 0 and mid < 1, ('progress mid scan %.2f'):format(mid))
-- combat pause
combat = true
local reqBefore = server.requests
for _ = 1, 120 do serverTick(); tick(1 / 60) end
check(server.requests == reqBefore, 'no requests sent in combat')
combat = false
-- "relog": drop scheduler (tasks die), recreate from saved variables
for _, f in ipairs(frames) do f.shown = false; f.scripts = {} end
local events4, scheduler4 = EventSource.New(), TaskScheduler.New()
local db4 = ItemDatabase.New(Persistence.New('ItemAutocompleteDB'), events4, scheduler4)
check(not db4:IsObsolete(), 'interrupted scan is resumed, not rebuilt')
check(db4:IsOutdated(), 'interrupted scan is outdated')
check(math.abs(db4:GetUpdateProgress() - mid) < 0.05, 'progress persisted')
finished = false
db4:UpdateItemsAsync(false, function() finished = true end)
ticks = 0
while not finished and ticks < 200000 do serverTick(); tick(1 / 60); ticks = ticks + 1 end
check(finished and db4:GetItemCount() == countExpected(db4), ('resumed scan completes with all items (%d)'):format(db4:GetItemCount()))

------------------------------------------------------------------ Scenario 4: search equals reference
local function referenceSearch(ids, names, pattern, limit)
  local caseInsensitive = true
  for _, cp in utf8.CodePoints(pattern) do if utf8.IsUpperCaseLetter(cp) then caseInsensitive = false end end
  local fm = FuzzyMatcher.New(pattern, caseInsensitive)
  local res = {}
  for order, id in ipairs(ids) do
    local cps = {}
    for _, cp in utf8.CodePoints(names[id]) do cps[#cps + 1] = cp end
    local s, _, score = fm:Match(cps)
    if s ~= 0 then res[#res + 1] = { id = id, score = score, len = #names[id], order = order } end
  end
  table.sort(res, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    if a.len ~= b.len then return a.len < b.len end
    return a.order < b.order
  end)
  local out = {}
  for i = 1, math.min(limit, #res) do out[i] = res[i].id end
  return out
end

local config = { entriesDisplayed = 10, entriesFilteredPerUpdate = 5000, caseInsensitive = nil }
local source = CompletionSource.New(db4.methods.GetSearchData, scheduler4, config)
local function runQuery(pattern)
  local result
  source:QueryAsync(pattern, function(iter)
    result = {}
    for id in iter do result[#result + 1] = id end
  end)
  local t = 0
  while not result and t < 100000 do tick(1 / 60); t = t + 1 end
  return result, t
end
local ids, names = db4:GetSearchData()
local mismatches = 0
local typed = { 'd', 'de', 'dev', 'devg', 'devga', 'thu', 'thunb', 'ärm', 'ÄRM', 'шл', 'шлем', 'меч', 'Меч', 'BOT', 'b o', 'zzzq', 'Staff R', 'ße' }
for _, pattern in ipairs(typed) do
  local got, frames_ = runQuery(pattern)
  local want = referenceSearch(ids, names, pattern, 10)
  local same = #got == #want
  for i = 1, #want do if got[i] ~= want[i] then same = false end end
  if not same then mismatches = mismatches + 1; print('  mismatch for', pattern, #got, #want) end
  print(('  %-8s %2d results in %d frames'):format(pattern, #got, frames_))
end
check(mismatches == 0, 'search results match reference (incl. narrowing and UTF-8)')

-- timing: full search on the database
local t0 = os.clock()
runQuery('xq')
print(('  narrow-miss query cpu %.3fs'):format(os.clock() - t0))
t0 = os.clock()
source.lastQuery = nil
runQuery('e')
local tNew = os.clock() - t0
t0 = os.clock()
referenceSearch(ids, names, 'e', 10)
print(('  single letter query: new %.3fs, reference (with decode) %.3fs over %d items'):format(tNew, os.clock() - t0, #ids))
t0 = os.clock()
source.lastQuery = nil
runQuery('thund')
print(('  "thund" fresh query: %.3fs'):format(os.clock() - t0))

-- links
local link, real = db4:GetItemLink(ids[1])
check(link:find('|Hitem:') and real, 'link from client cache')
server.cache = {}
link, real = db4:GetItemLink(ids[2])
check(link:find(('|Hitem:%d:'):format(ids[2]), 1, true) and not real, 'fallback link when uncached: ' .. link)

-- ToLowerString / Encode round trip
check(utf8.ToLowerString('ÄRM Шлем ABC') == 'ärm шлем abc', 'utf8 lower string')

------------------------------------------------------------------ Scenario 5: overload, server drops beyond 40 outstanding
for _, f in ipairs(frames) do f.shown = false; f.scripts = {} end
resetServer({ items = items, localIds = localIds, dropRate = 0.01, latency = 0.2, maxInFlight = 40 })
local events5, scheduler5 = EventSource.New(), TaskScheduler.New()
local db5 = ItemDatabase.New(Persistence.New('ItemAutocompleteDB'), events5, scheduler5)
finished = false
db5:UpdateItemsAsync(true, function() finished = true end)
ticks = 0
local limitSum, samples = 0, 0
while not finished and ticks < 400000 do
  serverTick(); tick(1 / 60); ticks = ticks + 1
  if ticks % 60 == 0 then limitSum = limitSum + db5.requestLimit; samples = samples + 1 end
end
print(('overload: %.0fs simulated, %d requests, %d overload drops, %d/%d items, mean limit %.1f')
        :format(ticks / 60, server.requests, server.overloadDrops, db5:GetItemCount(), countExpected(db5), limitSum / samples))
check(finished and db5:GetItemCount() >= countExpected(db5) * 0.995, 'overloaded server: scan completes with nearly all items')

------------------------------------------------------------------ Scenario 6: review regressions
-- (a) relog while requests are outstanding loses nothing
for _, f in ipairs(frames) do f.shown = false; f.scripts = {} end
resetServer({ items = items, localIds = localIds, dropRate = 0, latency = 0.5 })
local e6, s6 = EventSource.New(), TaskScheduler.New()
local db6 = ItemDatabase.New(Persistence.New('ItemAutocompleteDB'), e6, s6)
db6:UpdateItemsAsync(true, function() end)
for _ = 1, 20 do serverTick(); tick(1 / 60) end
check(db6.pendingRequestCount > 0, ('requests outstanding at relog (%d)'):format(db6.pendingRequestCount))
for _, f in ipairs(frames) do f.shown = false; f.scripts = {} end
server.inFlight = {}
local e7, s7 = EventSource.New(), TaskScheduler.New()
local db7 = ItemDatabase.New(Persistence.New('ItemAutocompleteDB'), e7, s7)
finished = false
db7:UpdateItemsAsync(false, function() finished = true end)
ticks = 0
while not finished and ticks < 400000 do serverTick(); tick(1 / 60); ticks = ticks + 1 end
check(finished and db7:GetItemCount() == countExpected(db7), ('relog with outstanding requests keeps every item (%d/%d)'):format(db7:GetItemCount(), countExpected(db7)))

-- (b) an item timing out on every attempt is retried by the next update
for _, f in ipairs(frames) do f.shown = false; f.scripts = {} end
items[999999] = { 'Flaky Item', 3 }; localIds[999999] = true
_G.blockedId = 999999
build = '70900'
local e8, s8 = EventSource.New(), TaskScheduler.New()
local db8 = ItemDatabase.New(Persistence.New('ItemAutocompleteDB'), e8, s8)
db8.database.highestId = 999999 - 50000 + 10 -- make the open range reach the flaky ID
finished = false
db8:UpdateItemsAsync(false, function() finished = true end)
ticks = 0
while not finished and ticks < 400000 do serverTick(); tick(1 / 60); ticks = ticks + 1 end
check(finished and db8:GetItemName(999999) == nil, 'flaky item missing after timeouts')
_G.blockedId = nil
for _, f in ipairs(frames) do f.shown = false; f.scripts = {} end
build = '71000'
local e9, s9 = EventSource.New(), TaskScheduler.New()
local db9 = ItemDatabase.New(Persistence.New('ItemAutocompleteDB'), e9, s9)
finished = false
db9:UpdateItemsAsync(false, function() finished = true end)
ticks = 0
while not finished and ticks < 400000 do serverTick(); tick(1 / 60); ticks = ticks + 1 end
check(db9:GetItemName(999999) == 'Flaky Item', 'flaky item found by the next update')

-- (c) requesting a pending item twice does not leak the pending counter
local scan = { highestId = 0, unresolved = {} }
db9.database.scan = scan
db9:_ResetRequests()
items[999998] = { 'Dup', 1 }; localIds[999998] = true
db9:_RequestItem(999998, scan)
db9:_RequestItem(999998, scan)
check(db9.pendingRequestCount == 1, 'duplicate request counted once')
db9.database.scan = nil

------------------------------------------------------------------ Scenario 7: Forever, hidden items never answered
do
  for _, f in ipairs(frames) do f.shown = false; f.scripts = {} end
  local list = {}
  for _, run in ipairs(dofile(root .. '/Tests/Fixtures/ForeverItems.lua')) do
    for id = run[1], run[2] do list[#list + 1] = { id, run[3] } end
  end
  local fItems, fLocal, hidden, revealed, silent = {}, {}, {}, 0, 0
  for _, row in ipairs(list) do
    local id = row[1]
    fLocal[id] = true
    if row[2] == 1 then
      fItems[id] = { 'Item ' .. id, 2 }
    elseif math.random() < 1 / 3 then
      fItems[id] = { 'Revealed ' .. id, 3 }; revealed = revealed + 1
    else
      hidden[#hidden + 1] = id; silent = silent + 1
    end
  end
  resetServer({ items = fItems, localIds = fLocal, dropRate = 0.01, latency = 0.15 })
  -- the server sends nothing for hidden items
  local origTick = serverTick
  serverTick = function()
    local keep = {}
    for _, r in ipairs(server.inFlight) do
      if fItems[r.id] or now - r.at < server.latency then keep[#keep + 1] = r end
    end
    server.inFlight = keep
    origTick()
  end
  _G.ItemAutocompleteDB = nil
  build = '70862'
  interface = 16001
  local e, sch = EventSource.New(), TaskScheduler.New()
  local fdb = ItemDatabase.New(Persistence.New('ItemAutocompleteDB'), e, sch)
  finished = false
  fdb:UpdateItemsAsync(true, function() finished = true end)
  ticks = 0
  local maxPending, limitTotal, limitSamples = 0, 0, 0
  while not finished and ticks < 2000000 do
    serverTick(); tick(1 / 60); ticks = ticks + 1
    if fdb.pendingRequestCount > maxPending then maxPending = fdb.pendingRequestCount end
    if ticks % 60 == 0 then limitTotal = limitTotal + fdb.requestLimit; limitSamples = limitSamples + 1 end
  end
  local want = 0
  for id, item in pairs(fItems) do if not fdb:_IsDevItem(id, item[1]) then want = want + 1 end end
  print(('forever: %d local, %d silent; %.0fs simulated, %d requests, %d/%d items, mean limit %.0f, max pending %d')
          :format(#list, silent, ticks / 60, server.requests, fdb:GetItemCount(), want, limitTotal / limitSamples, maxPending))
  check(finished and ticks / 60 < 600, 'forever first scan finishes within 10 minutes')
  check(fdb:GetItemCount() >= want * 0.999, 'forever scan finds named and revealed items')
  check(not fdb:IsOutdated(), 'forever database current right after the scan')

  -- a day later, some hidden items have dropped on the server
  local newlyRevealed = 0
  for i = 1, #hidden, 10 do fItems[hidden[i]] = { 'Later ' .. hidden[i], 4 }; newlyRevealed = newlyRevealed + 1 end
  now = now + 86400 + 60
  for _, f in ipairs(frames) do f.shown = false; f.scripts = {} end
  local e2, sch2 = EventSource.New(), TaskScheduler.New()
  local fdb2 = ItemDatabase.New(Persistence.New('ItemAutocompleteDB'), e2, sch2)
  check(fdb2:IsOutdated(), 'forever database due for a recheck after a day')
  local countBefore = fdb2:GetItemCount()
  server.requests = 0
  finished = false
  fdb2:UpdateItemsAsync(false, function() finished = true end)
  ticks = 0
  while not finished and ticks < 2000000 do serverTick(); tick(1 / 60); ticks = ticks + 1 end
  print(('forever recheck: %.0fs simulated, %d requests, +%d items (%d newly revealed)')
          :format(ticks / 60, server.requests, fdb2:GetItemCount() - countBefore, newlyRevealed))
  check(fdb2:GetItemCount() - countBefore >= newlyRevealed * 0.98 and ticks / 60 < 300, 'recheck finds newly revealed items quickly')
  check(server.requests <= silent + 1000, 'recheck only queries unavailable items')
  serverTick = origTick
end

------------------------------------------------------------------ Scenario 8: second review regressions
do
  interface = 120105
  local function freshDb()
    for _, f in ipairs(frames) do f.shown = false; f.scripts = {} end
    local e, sch = EventSource.New(), TaskScheduler.New()
    return ItemDatabase.New(Persistence.New('ItemAutocompleteDB'), e, sch)
  end
  local function runUntilDone(d)
    local done = false
    d:UpdateItemsAsync(false, function() done = true end)
    local t = 0
    while not done and t < 400000 do serverTick(); tick(1 / 60); t = t + 1 end
    return done
  end
  local small, smallLocal = {}, {}
  for id = 1, 3000 do
    if id % 3 == 0 then smallLocal[id] = true; small[id] = { 'Small ' .. id, 1 } end
  end
  smallLocal[1501] = true -- silent: exists locally, server never answers
  resetServer({ items = small, localIds = smallLocal, dropRate = 0, latency = 0.1 })
  local origTick = serverTick
  serverTick = function()
    local keep = {}
    for _, r in ipairs(server.inFlight) do if r.id ~= 1501 then keep[#keep + 1] = r end end
    server.inFlight = keep
    origTick()
  end
  _G.ItemAutocompleteDB = nil
  build = '80000'
  local d = freshDb()
  d:UpdateItemsAsync(true, function() end)
  -- (c) overlap: a pending item reached again keeps its persisted state
  local reached = false
  for _ = 1, 600 do
    serverTick(); tick(1 / 60)
    if d.pendingRequests[1501] and not reached then
      reached = true
      d:_RequestItem(1501, d.database.scan)
      check(d.database.scan.unresolved[1501] ~= nil, 'pending item reached twice stays unresolved')
      check(d.pendingRequestCount == (function() local n = 0 for _ in pairs(d.pendingRequests) do n = n + 1 end return n end)(), 'pending count consistent')
    end
  end
  -- (a) reloads don't grant fresh attempts to the silent item
  for _ = 1, 5 do
    d = freshDb()
    d:UpdateItemsAsync(false, function() end)
    for _ = 1, 400 do serverTick(); tick(1 / 60) end
  end
  d = freshDb()
  check(runUntilDone(d), 'scan completes after repeated reloads')
  local requests1501 = server.perId[1501] or 0
  check(d.database.unavailable[1501] ~= nil, 'silent item marked unavailable')
  check(requests1501 <= 3, ('silent item queried at most 3 times across reloads (%d)'):format(requests1501))

  -- (b) a patch mid-scan restarts traversal and finds items behind the cursor
  d = freshDb()
  d:UpdateItemsAsync(true, function() end)
  for _ = 1, 3 do serverTick(); tick(1 / 60) end
  local cursor = d.database.scan and d.database.scan.nextId or 0
  smallLocal[2] = true; small[2] = { 'Patched In', 2 }
  build = '80001'
  d = freshDb()
  check(runUntilDone(d), 'scan interrupted by a patch completes')
  check(cursor > 2 and d:GetItemName(2) == 'Patched In', ('item added behind the cursor (%d) is found'):format(cursor))
  serverTick = origTick
end

print(failures == 0 and 'ALL PASSED' or (failures .. ' FAILED'))
os.exit(failures == 0 and 0 or 1)
