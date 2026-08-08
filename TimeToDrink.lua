--[[--------------------------------------------------------------------
  Time To Drink  -  Turtle WoW (vanilla 1.12) addon   v1.0
  Watches a chosen healer's mana while you are in a 5-man party
  (disabled in raids) and announces in party chat when they drop
  below a configurable threshold, repeating on an adjustable cooldown.

  Slash commands:
    /ttd            toggle the window
    /ttd status     print current settings + party state
    /ttd test       send a test line to party chat
    /ttd debug      toggle verbose messages
----------------------------------------------------------------------]]

TimeToDrink = {}
local TTD = TimeToDrink

TTD.roster         = {}
TTD.selectedHealer = nil
TTD.threshold      = 40
TTD.cooldown       = 15
TTD.lastAnnounce   = 0
TTD.wasInParty     = false
TTD.pollElapsed    = 0
TTD.debug          = false
TTD.inWorld        = false
TTD.initialized    = false
TTD.disabled       = false
TTD.locked         = false
TTD.pos            = nil

local MIN_COOLDOWN  = 10
local POLL_INTERVAL = 0.5

local function msg(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TTD:|r " .. text)
end
local function dbg(text)
    if TTD.debug then DEFAULT_CHAT_FRAME:AddMessage("|cff8888ffTTD debug:|r " .. text) end
end
local function err(text)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff4040TTD error:|r " .. tostring(text))
end

local function TTD_InFivePlayerParty()
    if GetNumRaidMembers() > 0 then return false end
    return GetNumPartyMembers() > 0
end

local function TTD_ClampThreshold(v)
    if not v then return TTD.threshold end
    if v < 1 then v = 1 end
    if v > 100 then v = 100 end
    return math.floor(v)
end

local function TTD_ClampCooldown(v)
    if not v then return TTD.cooldown end
    if v < MIN_COOLDOWN then v = MIN_COOLDOWN end
    return math.floor(v)
end

function TTD_RefreshRoster()
    TTD.roster = {}
    if not TTD_InFivePlayerParty() then return end
    local myname = UnitName("player")
    table.insert(TTD.roster, myname)
    local n = GetNumPartyMembers()
    local i = 1
    while i <= n do
        local nm = UnitName("party" .. i)
        if nm then table.insert(TTD.roster, nm) end
        i = i + 1
    end
    if TTD.selectedHealer then
        local found = false
        local j = 1
        while j <= table.getn(TTD.roster) do
            if TTD.roster[j] == TTD.selectedHealer then found = true end
            j = j + 1
        end
        if not found then TTD.selectedHealer = nil end
    end
end

local function TTD_UnitForName(name)
    if not name then return nil end
    if UnitName("player") == name then return "player" end
    local n = GetNumPartyMembers()
    local i = 1
    while i <= n do
        if UnitName("party" .. i) == name then return "party" .. i end
        i = i + 1
    end
    return nil
end

function TTD_InitHealerDropdown()
    local dd = TimeToDrinkHealerDropdown
    if not dd then return end
    UIDropDownMenu_Initialize(dd, function()
        local i = 1
        while i <= table.getn(TTD.roster) do
            local nm   = TTD.roster[i]
            local info = {}
            info.text  = nm
            info.value = nm
            info.func  = function()
                TTD.selectedHealer = nm
                local t = getglobal("TimeToDrinkHealerDropdownText")
                if t then t:SetText(nm) end
                dbg("healer set to " .. nm)
                if TTD_InFivePlayerParty() and not TTD.disabled then
                    SendChatMessage(nm .. " has been set as the healer in Time To Drink.  The party will be alerted when they drop below " .. TTD.threshold .. "% mana.", "PARTY")
                end
            end
            UIDropDownMenu_AddButton(info)
            i = i + 1
        end
    end)

    local t = getglobal("TimeToDrinkHealerDropdownText")
    if TTD.selectedHealer then
        if t then t:SetText(TTD.selectedHealer) end
    else
        if t then t:SetText("Select healer") end
    end
end

function TTD_UpdateLockVisual()
    local lock = TimeToDrinkLockButton
    if not lock then return end
    if TTD.locked then
        lock:SetNormalTexture("Interface\\Buttons\\LockButton-Locked-Up")
        lock:SetPushedTexture("Interface\\Buttons\\LockButton-Locked-Up")
    else
        lock:SetNormalTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
        lock:SetPushedTexture("Interface\\Buttons\\LockButton-Unlocked-Up")
    end
    lock:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
end

function TTD_UpdateReadout()
    local st = TimeToDrinkStatus
    if st then
        if not TTD.selectedHealer then
            st:SetText("Alerts inactive: no healer selected.")
        elseif TTD.disabled then
            st:SetText("Alerts muted (quiet mode).")
        else
            st:SetText("Alerts active.")
        end
    end
    local fs = TimeToDrinkReadout
    if not fs then return end
    if not TTD.selectedHealer then
        fs:SetText("Healer mana: (none selected)")
        fs:SetTextColor(0.7, 0.7, 0.7)
        return
    end
    local unit = TTD_UnitForName(TTD.selectedHealer)
    if not unit or not UnitExists(unit) then
        fs:SetText(TTD.selectedHealer .. ": not in party")
        fs:SetTextColor(0.7, 0.7, 0.7)
        return
    end
    if UnitPowerType(unit) ~= 0 then
        fs:SetText(TTD.selectedHealer .. " mana: n/a (shapeshifted)")
        fs:SetTextColor(0.7, 0.7, 0.7)
        return
    end
    local mm = UnitManaMax(unit)
    if not mm or mm == 0 then
        fs:SetText(TTD.selectedHealer .. " mana: --")
        fs:SetTextColor(0.7, 0.7, 0.7)
        return
    end
    local pct = math.floor((UnitMana(unit) / mm) * 100)
    fs:SetText(TTD.selectedHealer .. " mana: " .. pct .. "%")
    if pct < TTD.threshold then
        fs:SetTextColor(1.0, 0.3, 0.3)
    else
        fs:SetTextColor(0.4, 1.0, 0.4)
    end
end

local function TTD_CreateUI()
    if TimeToDrinkUI then return end

    local f = CreateFrame("Frame", "TimeToDrinkUI", UIParent)
    f:SetWidth(260)
    f:SetHeight(232)
    if TTD.pos then
        f:SetPoint(TTD.pos.point, UIParent, TTD.pos.relPoint, TTD.pos.x, TTD.pos.y)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    end
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function() if not TTD.locked then this:StartMoving() end end)
    f:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        local point, _, relPoint, x, y = this:GetPoint()
        TTD.pos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -16)
    title:SetText("Time To Drink")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

    local lock = CreateFrame("Button", "TimeToDrinkLockButton", f)
    lock:SetWidth(24); lock:SetHeight(24)
    lock:SetPoint("RIGHT", close, "LEFT", 2, 0)
    lock:SetScript("OnClick", function()
        TTD.locked = not TTD.locked
        TTD_UpdateLockVisual()
    end)
    TTD_UpdateLockVisual()

    local tl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tl:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -46)
    tl:SetText("Mana threshold (1-100%)")

    local te = CreateFrame("EditBox", "TimeToDrinkThresholdEdit", f, "InputBoxTemplate")
    te:SetWidth(50); te:SetHeight(20)
    te:SetPoint("TOPLEFT", tl, "BOTTOMLEFT", 4, -4)
    te:SetAutoFocus(false)
    te:SetMaxLetters(3)
    te:SetText("" .. TTD.threshold)
    te:SetScript("OnTextChanged", function()
        local s = this:GetText()
        local clean = string.gsub(s, "[^0-9]", "")
        if clean ~= s then this:SetText(clean) end
    end)
    local function commitThreshold()
        TTD.threshold = TTD_ClampThreshold(tonumber(this:GetText()))
        this:SetText("" .. TTD.threshold)
        this:ClearFocus()
    end
    te:SetScript("OnEnterPressed", commitThreshold)
    te:SetScript("OnEditFocusLost", commitThreshold)

    local cl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cl:SetPoint("TOPLEFT", tl, "TOPLEFT", 120, 0)
    cl:SetText("Cooldown (min 10s)")

    local ce = CreateFrame("EditBox", "TimeToDrinkCooldownEdit", f, "InputBoxTemplate")
    ce:SetWidth(50); ce:SetHeight(20)
    ce:SetPoint("TOPLEFT", cl, "BOTTOMLEFT", 4, -4)
    ce:SetAutoFocus(false)
    ce:SetMaxLetters(4)
    ce:SetText("" .. TTD.cooldown)
    ce:SetScript("OnTextChanged", function()
        local s = this:GetText()
        local clean = string.gsub(s, "[^0-9]", "")
        if clean ~= s then this:SetText(clean) end
    end)
    local function commitCooldown()
        TTD.cooldown = TTD_ClampCooldown(tonumber(this:GetText()))
        this:SetText("" .. TTD.cooldown)
        this:ClearFocus()
    end
    ce:SetScript("OnEnterPressed", commitCooldown)
    ce:SetScript("OnEditFocusLost", commitCooldown)

    local hl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hl:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -104)
    hl:SetText("Healer")

    local dd = CreateFrame("Frame", "TimeToDrinkHealerDropdown", f, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", hl, "BOTTOMLEFT", -16, -4)

    local cb = CreateFrame("CheckButton", "TimeToDrinkDisableCheck", f, "UICheckButtonTemplate")
    cb:SetWidth(22); cb:SetHeight(22)
    cb:SetPoint("TOPLEFT", f, "TOPLEFT", 22, -150)
    local cbText = getglobal("TimeToDrinkDisableCheckText")
    if cbText then cbText:SetText("Disable alerts (quiet mode)") end
    cb:SetChecked(TTD.disabled)
    cb:SetScript("OnClick", function()
        if this:GetChecked() then TTD.disabled = true else TTD.disabled = false end
        dbg("disabled = " .. tostring(TTD.disabled))
    end)

    local readout = f:CreateFontString("TimeToDrinkReadout", "OVERLAY", "GameFontNormalSmall")
    readout:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -182)
    readout:SetText("Healer mana: (none selected)")

    local status = f:CreateFontString("TimeToDrinkStatus", "OVERLAY", "GameFontDisableSmall")
    status:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
    status:SetText("Type numbers, pick a healer, press Enter.")
end

function TTD_ShowUI()
    TTD_CreateUI()
    TTD_RefreshRoster()
    TTD_InitHealerDropdown()
    if TimeToDrinkThresholdEdit then TimeToDrinkThresholdEdit:SetText("" .. TTD.threshold) end
    if TimeToDrinkCooldownEdit  then TimeToDrinkCooldownEdit:SetText("" .. TTD.cooldown) end
    if TimeToDrinkDisableCheck  then TimeToDrinkDisableCheck:SetChecked(TTD.disabled) end
    TTD_UpdateReadout()
    TimeToDrinkUI:Show()
end

function TTD_ToggleUI()
    TTD_CreateUI()
    if TimeToDrinkUI:IsShown() then
        TimeToDrinkUI:Hide()
    else
        TTD_ShowUI()
    end
end

local function TTD_CheckHealer()
    if not TTD.inWorld then return end
    if TTD.disabled then return end
    if not TTD_InFivePlayerParty() then return end
    if not TTD.selectedHealer then return end
    local unit = TTD_UnitForName(TTD.selectedHealer)
    if not unit or not UnitExists(unit) then return end
    if UnitIsDeadOrGhost(unit) then return end
    if UnitPowerType(unit) ~= 0 then return end
    local maxMana = UnitManaMax(unit)
    if not maxMana or maxMana == 0 then return end
    local pct = (UnitMana(unit) / maxMana) * 100
    if pct < TTD.threshold then
        if (GetTime() - TTD.lastAnnounce) >= TTD.cooldown then
            SendChatMessage("The healer has less than " .. TTD.threshold .. "% mana", "PARTY")
            TTD.lastAnnounce = GetTime()
            dbg("announced (" .. math.floor(pct) .. "% now)")
        end
    end
end

local driver = CreateFrame("Frame", "TimeToDrinkDriver", UIParent)
driver:RegisterEvent("VARIABLES_LOADED")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PARTY_MEMBERS_CHANGED")
driver:RegisterEvent("RAID_ROSTER_UPDATE")
driver:RegisterEvent("PLAYER_LOGOUT")
driver:RegisterEvent("CHAT_MSG_PARTY")
driver:RegisterEvent("CHAT_MSG_PARTY_LEADER")

driver:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        if type(TimeToDrinkDB) ~= "table" then TimeToDrinkDB = {} end
        if TimeToDrinkDB.threshold then TTD.threshold = TTD_ClampThreshold(TimeToDrinkDB.threshold) end
        if TimeToDrinkDB.cooldown  then TTD.cooldown  = TTD_ClampCooldown(TimeToDrinkDB.cooldown) end
        if TimeToDrinkDB.disabled ~= nil then TTD.disabled = TimeToDrinkDB.disabled end
        if TimeToDrinkDB.locked ~= nil then TTD.locked = TimeToDrinkDB.locked end
        if TimeToDrinkDB.pos then TTD.pos = TimeToDrinkDB.pos end

    elseif event == "PLAYER_ENTERING_WORLD" then
        TTD.inWorld = true
        if not TTD.initialized then
            TTD.wasInParty = TTD_InFivePlayerParty()
            TTD.initialized = true
        end

    elseif event == "PLAYER_LOGOUT" then
        if type(TimeToDrinkDB) ~= "table" then TimeToDrinkDB = {} end
        TimeToDrinkDB.threshold = TTD.threshold
        TimeToDrinkDB.cooldown  = TTD.cooldown
        TimeToDrinkDB.disabled  = TTD.disabled
        TimeToDrinkDB.locked    = TTD.locked
        TimeToDrinkDB.pos       = TTD.pos

    elseif event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then
        -- If anyone (any client) posts the low-mana alert, start our cooldown too,
        -- so multiple copies of the addon don't double up.
        if arg1 and string.find(arg1, "has less than", 1, true) and string.find(arg1, "mana", 1, true) then
            TTD.lastAnnounce = GetTime()
        end

    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        local inParty = TTD_InFivePlayerParty()
        local prevHealer = TTD.selectedHealer
        TTD_RefreshRoster()
        -- Designated healer left, while we were already grouped (not on a fresh join).
        if prevHealer and not TTD.selectedHealer and TTD.inWorld and not TTD.disabled
           and TTD.wasInParty and TTD_InFivePlayerParty() then
            SendChatMessage("The healer has left the party, please designate a new healer, or mute the addon.", "PARTY")
        end
        -- On joining a fresh party, require the player to pick a healer again.
        if TTD.inWorld and inParty and not TTD.wasInParty then
            TTD.selectedHealer = nil
            local ok, e = pcall(TTD_ShowUI)
            if not ok then err(e) end
        end
        if TimeToDrinkUI and TimeToDrinkUI:IsShown() then TTD_InitHealerDropdown() end
        if TimeToDrinkUI and TimeToDrinkUI:IsShown() then TTD_UpdateReadout() end
        TTD.wasInParty = inParty
    end
end)
driver:Show()

driver:SetScript("OnUpdate", function()
    TTD.pollElapsed = TTD.pollElapsed + arg1
    if TTD.pollElapsed < POLL_INTERVAL then return end
    TTD.pollElapsed = 0
    if TimeToDrinkUI and TimeToDrinkUI:IsShown() then TTD_UpdateReadout() end
    TTD_CheckHealer()
end)

SLASH_TIMETODRINK1 = "/ttd"
SLASH_TIMETODRINK2 = "/timetodrink"
SlashCmdList["TIMETODRINK"] = function(arg)
    local cmd = string.lower(arg or "")

    if cmd == "status" then
        msg("disabled=" .. tostring(TTD.disabled) .. "  threshold=" .. TTD.threshold .. "%  cooldown=" .. TTD.cooldown .. "s  healer=" ..
            (TTD.selectedHealer or "none") .. "  inParty=" .. tostring(TTD_InFivePlayerParty()) ..
            "  raid=" .. tostring(GetNumRaidMembers() > 0))
        return
    end

    if cmd == "test" then
        if TTD_InFivePlayerParty() then
            SendChatMessage("Time To Drink test - if you see this, chat works.", "PARTY")
            msg("sent test line to party chat.")
        else
            msg("not in a 5-man party, so nothing was sent to party chat.")
        end
        return
    end

    if cmd == "debug" then
        TTD.debug = not TTD.debug
        msg("debug " .. (TTD.debug and "ON" or "OFF"))
        return
    end

    local ok, e = pcall(TTD_ToggleUI)
    if not ok then err(e) end
end

msg("loaded v1.7. /ttd to open, /ttd status, /ttd test. (5-man parties only)")
