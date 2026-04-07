--[[
  Standalone port of WeakAura "Raidwide Soulstone Checker" (wago.io/Cmo8tr2hv).
]]

local ADDON_NAME = ...

local strtrim = strtrim or function(s)
  return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local BANNER_AFTER_READY_CHECK_SEC = 30

local defaults = {
  announceRaid = false,
  whisperLocks = false,
  announceString = "No healers are currently soulstoned",
  enabled = true,
  announceCooldown = 45,
  frameLocked = false,
  autoAnnounceReadyCheck = true,
  bannerOnlyAfterReadyCheck = true,
}

local db

local SOULSTONE_AURA_IDS = {
  [95750] = true, -- Soulstone Resurrection (retail)
  [20707] = true,
  [47883] = true,
  [47884] = true,
  [152364] = true,
  [265351] = true,
}

local lastAnnounce = 0
local lastReadyCheckTime = nil

local alertFrame

local function mergeDefaults(t, d)
  for k, v in pairs(d) do
    if type(v) == "table" and type(t[k]) ~= "table" then
      t[k] = {}
      mergeDefaults(t[k], v)
    elseif t[k] == nil then
      t[k] = v
    elseif type(v) == "table" and type(t[k]) == "table" then
      mergeDefaults(t[k], v)
    end
  end
end

local function unitHasSoulstone(unit)
  if not unit or not UnitExists(unit) or not UnitIsConnected(unit) then
    return false
  end
  if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then
    return false
  end
  for i = 1, 80 do
    local d = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
    if not d then
      break
    end
    -- spellId can be a "secret" sentinel on other players' auras; using it as a table key errors.
    -- type() is not reliable for that value, so the lookup must run inside pcall.
    local ok, isSoulstone = pcall(function()
      local id = d.spellId
      if type(id) ~= "number" then
        return false
      end
      return SOULSTONE_AURA_IDS[id] == true
    end)
    if ok and isSoulstone then
      return true
    end
  end
  return false
end

local function hasWarlockAndHealerRaid()
  local warlock, healer = false, false
  for i = 1, 40 do
    local name, _, _, _, _, fileName, _, _, _, _, _, combatRole = GetRaidRosterInfo(i)
    if name then
      if fileName == "WARLOCK" then
        warlock = true
      end
      if combatRole == "HEALER" then
        healer = true
      end
    end
  end
  return warlock and healer
end

local function hasWarlockAndHealerParty()
  local units = { "player" }
  for i = 1, GetNumSubgroupMembers() or 0 do
    units[#units + 1] = "party" .. i
  end
  local warlock, healer = false, false
  for _, unit in ipairs(units) do
    if UnitExists(unit) then
      local _, classFile = UnitClass(unit)
      if classFile == "WARLOCK" then
        warlock = true
      end
      if UnitGroupRolesAssigned(unit) == "HEALER" then
        healer = true
      end
    end
  end
  return warlock and healer
end

local function hasWarlockAndHealer()
  if IsInRaid() then
    return hasWarlockAndHealerRaid()
  end
  if IsInGroup() then
    return hasWarlockAndHealerParty()
  end
  return false
end

local function forEachHealerUnit(callback)
  if IsInRaid() then
    for i = 1, 40 do
      local name, _, _, _, _, _, _, _, _, _, _, combatRole = GetRaidRosterInfo(i)
      if name and combatRole == "HEALER" then
        local unit = "raid" .. i
        if UnitExists(unit) then
          callback(unit, name)
        end
      end
    end
    return
  end
  if IsInGroup() then
    local list = { "player" }
    for i = 1, GetNumSubgroupMembers() or 0 do
      list[#list + 1] = "party" .. i
    end
    for _, unit in ipairs(list) do
      if UnitExists(unit) and UnitGroupRolesAssigned(unit) == "HEALER" then
        callback(unit, UnitName(unit))
      end
    end
  end
end

local function anyHealerSoulstoned()
  local ok = false
  forEachHealerUnit(function(unit)
    if unitHasSoulstone(unit) then
      ok = true
    end
  end)
  return ok
end

-- Ally buff details are restricted in combat (secret spellId, etc.), so scans often look
-- like "no soulstone" and cause false positives. Same during boss encounters.
-- See https://warcraft.wiki.gg/wiki/API_change_summaries (aura / API restrictions).
local function shouldSuppressSoulstoneScan()
  if UnitAffectingCombat("player") then
    return true
  end
  if IsEncounterInProgress and IsEncounterInProgress() then
    return true
  end
  return false
end

local function isMissingSoulstoneCondition()
  if not hasWarlockAndHealer() then
    return false
  end
  if shouldSuppressSoulstoneScan() then
    return false
  end
  return not anyHealerSoulstoned()
end

local function shouldShowMissingSoulstoneBanner()
  if not isMissingSoulstoneCondition() then
    return false
  end
  if db.bannerOnlyAfterReadyCheck then
    if not lastReadyCheckTime then
      return false
    end
    if (GetTime() - lastReadyCheckTime) > BANNER_AFTER_READY_CHECK_SEC then
      return false
    end
  end
  return true
end

local function collectWarlocksAndHealers()
  local warlocks, healers = {}, {}
  if IsInRaid() then
    for i = 1, 40 do
      local name, _, _, _, _, fileName, _, _, _, _, _, combatRole = GetRaidRosterInfo(i)
      if name then
        if fileName == "WARLOCK" then
          warlocks[#warlocks + 1] = name
        end
        if combatRole == "HEALER" then
          healers[#healers + 1] = name
        end
      end
    end
  else
    local list = { "player" }
    for i = 1, GetNumSubgroupMembers() or 0 do
      list[#list + 1] = "party" .. i
    end
    for _, unit in ipairs(list) do
      if UnitExists(unit) then
        local n = UnitName(unit)
        local _, classFile = UnitClass(unit)
        if classFile == "WARLOCK" then
          warlocks[#warlocks + 1] = n
        end
        if UnitGroupRolesAssigned(unit) == "HEALER" then
          healers[#healers + 1] = n
        end
      end
    end
  end
  return warlocks, healers
end

local function sendGroupMessage(text)
  if not text or text == "" then
    return
  end
  if IsInRaid() then
    SendChatMessage(text, "RAID")
  elseif IsInGroup() then
    SendChatMessage(text, "PARTY")
  else
    print("|cff88ccffSoulstone Reminder:|r " .. text)
  end
end

local function performAnnounce()
  local warlocks, healers = collectWarlocksAndHealers()
  if db.announceRaid then
    sendGroupMessage(db.announceString)
  end
  if db.whisperLocks and #warlocks > 0 then
    local healerString = table.concat(healers, ", ")
    local msg =
      "No healers are currently soulstoned. Please soulstone one of the following: " .. healerString
    for _, warlock in ipairs(warlocks) do
      SendChatMessage(msg, "WHISPER", nil, warlock)
    end
  end
end

--- @param opts table|nil `{ silentCooldown = bool, silentNoChannels = bool }` for automation paths
function SoulstoneReminder_SendAnnounce(opts)
  opts = opts or {}
  if not db.announceRaid and not db.whisperLocks then
    if not opts.silentNoChannels then
      print("|cff88ccffSoulstone Reminder:|r Turn on |cffaaaaaa/ssr raid on|r or |cffaaaaaa/ssr whisper on|r first.")
    end
    return
  end
  local now = GetTime()
  local cd = db.announceCooldown or 45
  if now - lastAnnounce < cd then
    if not opts.silentCooldown then
      print("|cff88ccffSoulstone Reminder:|r Wait a few seconds before announcing again.")
    end
    return
  end
  lastAnnounce = now
  performAnnounce()
end

local function announceOnReadyCheckIfNeeded()
  if not db.autoAnnounceReadyCheck then
    return
  end
  if shouldSuppressSoulstoneScan() then
    return
  end
  if not db.announceRaid and not db.whisperLocks then
    return
  end
  if not hasWarlockAndHealer() or anyHealerSoulstoned() then
    return
  end
  SoulstoneReminder_SendAnnounce({ silentCooldown = true, silentNoChannels = true })
end

local function saveFramePosition(self)
  if not db or db.frameLocked then
    return
  end
  local point, relativeTo, relPoint, x, y = self:GetPoint(1)
  if not point or type(x) ~= "number" or type(y) ~= "number" then
    return
  end
  if relativeTo ~= UIParent then
    return
  end
  db.framePoint = point
  db.frameRelPoint = relPoint
  db.frameX = x
  db.frameY = y
end

local function applySavedFramePosition(f)
  f:ClearAllPoints()
  if db and db.framePoint and type(db.frameX) == "number" and type(db.frameY) == "number" then
    f:SetPoint(db.framePoint, UIParent, db.frameRelPoint or db.framePoint, db.frameX, db.frameY)
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -120)
  end
end

local function updateFrameHint(f)
  f = f or alertFrame
  if not f or not f.hint then
    return
  end
  if db.frameLocked then
    f.hint:SetText("Click: notify  •  |cffffcc66Locked|r — /ssr unlock to move")
  else
    f.hint:SetText("Drag to move  •  Click: notify  •  /ssr lock")
  end
end

local function applyFrameLockState(f)
  f = f or alertFrame
  if not f then
    return
  end
  if db.frameLocked then
    f:SetMovable(false)
    f:RegisterForDrag()
    f:SetScript("OnDragStart", nil)
    f:SetScript("OnDragStop", nil)
  else
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      saveFramePosition(self)
    end)
  end
  updateFrameHint(f)
end

local function ensureFrame()
  if alertFrame then
    return alertFrame
  end
  local f = CreateFrame("Button", "SoulstoneReminderAlert", UIParent, "BackdropTemplate")
  f:SetSize(340, 56)
  applySavedFramePosition(f)
  f:SetFrameStrata("HIGH")
  f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  f:SetBackdropColor(0.15, 0.05, 0.05, 0.92)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    saveFramePosition(self)
  end)
  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  fs:SetPoint("CENTER", 0, 6)
  fs:SetTextColor(1, 0.45, 0.45)
  fs:SetText("No Soulstone placed on raid healer!")
  f.title = fs
  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("BOTTOM", 0, 8)
  hint:SetTextColor(0.7, 0.7, 0.7)
  hint:SetText("")
  f.hint = hint
  f:SetScript("OnClick", function()
    SoulstoneReminder_SendAnnounce()
  end)
  f:RegisterForClicks("LeftButtonUp")
  f:Hide()
  alertFrame = f
  applyFrameLockState(f)
  return f
end

local function updateDisplay()
  if not db.enabled then
    if alertFrame then
      alertFrame:Hide()
    end
    return
  end
  local missing = shouldShowMissingSoulstoneBanner()
  local f = ensureFrame()
  updateFrameHint(f)
  if missing then
    f:Show()
  else
    f:Hide()
  end
end

local tickFrame = CreateFrame("Frame")
tickFrame:RegisterEvent("ADDON_LOADED")
tickFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
tickFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
tickFrame:RegisterEvent("READY_CHECK")
tickFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
tickFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
tickFrame:RegisterEvent("ENCOUNTER_START")
tickFrame:RegisterEvent("ENCOUNTER_END")

tickFrame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    SoulstoneReminderDB = SoulstoneReminderDB or {}
    db = SoulstoneReminderDB
    mergeDefaults(db, defaults)
    C_Timer.NewTicker(1.0, updateDisplay)
    return
  end
  if event == "READY_CHECK" then
    lastReadyCheckTime = GetTime()
    announceOnReadyCheckIfNeeded()
    updateDisplay()
    return
  end
  updateDisplay()
end)

SLASH_SOULSTONEREMINDER1 = "/ssr"
SlashCmdList.SOULSTONEREMINDER = function(msg)
  msg = strlower(strtrim(msg or ""))
  local a, b = msg:match("^(%S+)%s*(.*)$")
  a = a or "help"
  if a == "help" or a == "?" then
    print("|cff88ccffSoulstone Reminder|r — commands:")
    print("  |cffaaaaaa/ssr on|r | |cffaaaaaa/ssr off|r — show or hide reminders")
    print("  |cffaaaaaa/ssr raid on|r | off — send your string to raid when you |cffaaaaaassr send|r or click the banner")
    print("  |cffaaaaaa/ssr whisper on|r | off — whisper warlocks (healer list)")
    print("  |cffaaaaaa/ssr send|r — announce now (respects cooldown)")
    print("  |cffaaaaaa/ssr msg <text>|r — set raid message")
    print("  |cffaaaaaa/ssr cooldown <sec>|r — min seconds between sends (default 45)")
    print("  |cffaaaaaa/ssr lock|r | |cffaaaaaa/ssr unlock|r — freeze or allow moving the banner")
    print("  |cffaaaaaa/ssr resetpos|r — reset banner position (drag saves to saved variables)")
    print("  |cffaaaaaa/ssr readycheck on|r | off — auto announce when a ready check starts (if stone missing)")
    print("  |cffaaaaaa/ssr rcbanner on|r | off — only show banner " .. BANNER_AFTER_READY_CHECK_SEC .. "s after a ready check (default on)")
    print("  |cff888888Banner and readycheck announce stay off in combat and boss encounters|r (ally aura API is unreliable).")
    return
  end
  if a == "lock" then
    db.frameLocked = true
    applyFrameLockState(alertFrame)
    print("Banner |cffffcc66locked|r (cannot drag). |cffaaaaaa/ssr unlock|r to move.")
    return
  end
  if a == "unlock" then
    db.frameLocked = false
    applyFrameLockState(alertFrame)
    print("Banner |cff00ff00unlocked|r — you can drag it.")
    return
  end
  if a == "resetpos" then
    db.framePoint = nil
    db.frameRelPoint = nil
    db.frameX = nil
    db.frameY = nil
    if alertFrame then
      applySavedFramePosition(alertFrame)
    end
    print("Banner position reset to default.")
    return
  end
  if a == "readycheck" then
    local on = strlower(strtrim(b or ""))
    db.autoAnnounceReadyCheck = (on == "on" or on == "1" or on == "true")
    print("Auto announce on ready check:", db.autoAnnounceReadyCheck and "ON" or "OFF")
    return
  end
  if a == "rcbanner" then
    local on = strlower(strtrim(b or ""))
    db.bannerOnlyAfterReadyCheck = (on == "on" or on == "1" or on == "true")
    print(
      "Banner only for "
        .. BANNER_AFTER_READY_CHECK_SEC
        .. "s after ready check:",
      db.bannerOnlyAfterReadyCheck and "ON" or "OFF"
    )
    updateDisplay()
    return
  end
  if a == "on" then
    db.enabled = true
    print("Soulstone Reminder |cff00ff00enabled|r.")
    updateDisplay()
    return
  end
  if a == "off" then
    db.enabled = false
    print("Soulstone Reminder |cffff4444disabled|r.")
    updateDisplay()
    return
  end
  if a == "raid" then
    local on = strlower(strtrim(b or ""))
    db.announceRaid = (on == "on" or on == "1" or on == "true")
    print("Raid announce on click/send:", db.announceRaid and "ON" or "OFF")
    return
  end
  if a == "whisper" or a == "whisperlocks" then
    local on = strlower(strtrim(b or ""))
    db.whisperLocks = (on == "on" or on == "1" or on == "true")
    print("Whisper warlocks on click/send:", db.whisperLocks and "ON" or "OFF")
    return
  end
  if a == "send" or a == "announce" then
    SoulstoneReminder_SendAnnounce()
    return
  end
  if a == "msg" or a == "message" then
    b = strtrim(b or "")
    if b == "" then
      print("Current raid string:", db.announceString)
      return
    end
    db.announceString = b
    print("Raid string updated.")
    return
  end
  if a == "cooldown" then
    local n = tonumber(b)
    if not n or n < 10 or n > 600 then
      print("Usage: /ssr cooldown <seconds>  (10–600)")
      return
    end
    db.announceCooldown = n
    print("Announce cooldown:", n, "s")
    return
  end
  print("Unknown. Try |cff88ccff/ssr help|r")
end
