local INTERRUPT_CATALOG = {
    { class = "WARRIOR", ids = { 72, 1671, 1672, 29704 }, cooldown = 12, sharedCooldownGroup = "warriorShieldBashPummel" },
    { class = "WARRIOR", ids = { 6554, 6552 }, cooldown = 10, sharedCooldownGroup = "warriorShieldBashPummel" },
    { class = "MAGE", ids = { 2139 }, cooldown = 24 },
    { class = "ROGUE", ids = { 1767, 1766 }, cooldown = 10 },
    { class = "HUNTER", ids = { 34490 }, cooldown = 20 },
    { class = "SHAMAN", ids = { 25454, 10414, 10413, 10412, 8046, 8045, 8044, 8042 }, cooldown = 6 },
    { class = "PRIEST", ids = { 15487 }, cooldown = 45 },
    { class = "WARLOCK", ids = { 19647 }, cooldown = 24, pet = true },
}

local catalogById = {}
for _, ability in ipairs(INTERRUPT_CATALOG) do
    for _, spellId in ipairs(ability.ids) do
        catalogById[spellId] = ability
    end
end

local db
local trackingEnabled
local bar
local configFrame
local trackingCheckbox
local abilityButtons = {}
local estimates = {}
local refreshElapsed = 0

local ICON_SIZE = 44
local CELL_WIDTH = 64
local CELL_HEIGHT = 68
local ICONS_PER_ROW = 6

local function nameKey(name)
    return string.lower((name or ""):gsub("%s+", ""))
end

local function shortName(name)
    return (name or ""):match("^([^-]+)") or name
end

local function getFullName(unit)
    local name, realm = UnitName(unit)
    if not name then
        return nil
    end
    if realm and realm ~= "" then
        return name .. "-" .. realm
    end
    return name
end

local function getRoster()
    local roster = {}
    local raidCount = GetNumRaidMembers and GetNumRaidMembers() or 0
    local partyCount = GetNumPartyMembers and GetNumPartyMembers() or 0

    local function addUnit(unit)
        local name = getFullName(unit)
        if not name then
            return
        end
        roster[#roster + 1] = {
            name = name,
            key = nameKey(name),
            unit = unit,
            class = select(2, UnitClass(unit)),
            online = UnitIsConnected(unit),
            dead = UnitIsDeadOrGhost(unit),
        }
    end

    if raidCount > 0 then
        for index = 1, raidCount do
            addUnit("raid" .. index)
        end
    else
        addUnit("player")
        for index = 1, partyCount do
            addUnit("party" .. index)
        end
    end
    return roster
end

local function getClassColor(class)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not color then
        return "|cffffffff", 1, 1, 1
    end
    return string.format("|cff%02x%02x%02x",
        math.floor(color.r * 255), math.floor(color.g * 255), math.floor(color.b * 255)),
        color.r, color.g, color.b
end

local function findOwnerKey(sourceName, roster)
    local sourceKey = nameKey(sourceName)
    local sourceShortKey = nameKey(shortName(sourceName))
    for _, member in ipairs(roster) do
        if member.key == sourceKey or nameKey(shortName(member.name)) == sourceShortKey then
            return member.key
        end

        local petUnit = "pet"
        local partyIndex = member.unit:match("^party(%d+)$")
        local raidIndex = member.unit:match("^raid(%d+)$")
        if partyIndex then
            petUnit = "partypet" .. partyIndex
        elseif raidIndex then
            petUnit = "raidpet" .. raidIndex
        end
        local petName = UnitName(petUnit)
        if petName and nameKey(petName) == sourceKey then
            return member.key
        end
    end
    return nil
end

local function formatRemaining(seconds)
    if seconds <= 0 then
        return "Ready"
    end
    return tostring(math.ceil(seconds)) .. "s"
end

local function recordInterrupt(sourceName, spellId)
    if not trackingEnabled then
        return
    end

    local ability = catalogById[spellId]
    if not ability or not sourceName then
        return
    end

    local memberKey = findOwnerKey(sourceName, getRoster())
    if not memberKey then
        return
    end

    local now = GetTime()
    estimates[memberKey] = estimates[memberKey] or {}
    local existing = estimates[memberKey][spellId]
    if existing and now - existing.usedAt < 0.5 then
        return
    end

    estimates[memberKey][spellId] = {
        id = spellId,
        cooldown = ability.cooldown,
        usedAt = now,
    }
end

local function getEntries(now)
    local entries = {}
    local roster = getRoster()
    local membersByKey = {}
    for _, member in ipairs(roster) do
        membersByKey[member.key] = member
    end

    for memberKey, memberEstimates in pairs(estimates) do
        local member = membersByKey[memberKey]
        if member then
            local sharedElapsed = {}
            for spellId, estimate in pairs(memberEstimates) do
                local ability = catalogById[spellId]
                local group = ability and ability.sharedCooldownGroup
                local remaining = math.max(0, estimate.cooldown - (now - estimate.usedAt))
                if group and remaining > 0 then
                    local elapsed = math.max(0, estimate.cooldown - remaining)
                    sharedElapsed[group] = math.min(sharedElapsed[group] or elapsed, elapsed)
                end
            end

            for spellId, estimate in pairs(memberEstimates) do
                local ability = catalogById[spellId]
                if ability then
                    local remaining = math.max(0, estimate.cooldown - (now - estimate.usedAt))
                    local elapsed = ability.sharedCooldownGroup
                        and sharedElapsed[ability.sharedCooldownGroup]
                    if elapsed then
                        remaining = math.max(remaining, math.max(0, estimate.cooldown - elapsed))
                    end
                    entries[#entries + 1] = {
                        member = member,
                        id = spellId,
                        cooldown = estimate.cooldown,
                        remaining = remaining,
                    }
                end
            end
        end
    end

    table.sort(entries, function(left, right)
        local leftReady = left.remaining <= 0
        local rightReady = right.remaining <= 0
        if leftReady ~= rightReady then
            return leftReady
        end
        if left.remaining ~= right.remaining then
            return left.remaining < right.remaining
        end
        if left.member.key ~= right.member.key then
            return left.member.key < right.member.key
        end
        return left.id < right.id
    end)
    return entries
end

local function startMoving()
    if IsShiftKeyDown and IsShiftKeyDown() then
        bar:SetMovable(true)
        bar:StartMoving()
    end
end

local function stopMoving()
    bar:StopMovingOrSizing()
    local _, _, _, x, y = bar:GetPoint(1)
    db.x = x or 0
    db.y = y or 0
end

local function createAbilityButton()
    local button = CreateFrame("Button", nil, bar)
    button:SetSize(ICON_SIZE, ICON_SIZE)
    button.texture = button:CreateTexture(nil, "ARTWORK")
    button.texture:SetAllPoints(button)
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button)
    button.cooldownText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.cooldownText:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.cooldownText:SetTextColor(1, 1, 1)
    button.nameText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.nameText:SetPoint("TOP", button, "BOTTOM", 0, -2)
    button.nameText:SetWidth(CELL_WIDTH)
    button.nameText:SetJustifyH("CENTER")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", startMoving)
    button:SetScript("OnDragStop", stopMoving)
    button:SetScript("OnEnter", function(self)
        if not self.entry then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local _, red, green, blue = getClassColor(self.entry.member.class)
        GameTooltip:AddLine(self.entry.member.name, red, green, blue)
        GameTooltip:AddLine(GetSpellInfo(self.entry.id) or "Interrupt", 1, 1, 1)
        GameTooltip:AddLine("Cooldown estimate: " .. formatRemaining(self.entry.remaining), 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return button
end

local function updateBar()
    if not bar then
        return
    end
    if not trackingEnabled then
        bar:Hide()
        return
    end

    local entries = getEntries(GetTime())
    if #entries == 0 then
        bar:Hide()
        return
    end

    local rowCount = math.ceil(#entries / ICONS_PER_ROW)
    local columnCount = math.min(#entries, ICONS_PER_ROW)
    bar:SetSize(columnCount * CELL_WIDTH, rowCount * CELL_HEIGHT)
    for index, entry in ipairs(entries) do
        local button = abilityButtons[index] or createAbilityButton()
        abilityButtons[index] = button
        button.entry = entry
        button:ClearAllPoints()
        local row = math.floor((index - 1) / ICONS_PER_ROW)
        local column = (index - 1) % ICONS_PER_ROW
        button:SetPoint("TOPLEFT", bar, "TOPLEFT", column * CELL_WIDTH + (CELL_WIDTH - ICON_SIZE) / 2, -row * CELL_HEIGHT)

        local _, _, texture = GetSpellInfo(entry.id)
        button.texture:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        if button.texture.SetDesaturated then
            button.texture:SetDesaturated(false)
        end
        local playerName = entry.member.name:match("^([^-]+)") or entry.member.name
        button.nameText:SetText(playerName)
        local _, red, green, blue = getClassColor(entry.member.class)
        button.nameText:SetTextColor(red, green, blue)

        if entry.remaining > 0 then
            local elapsed = math.max(0, entry.cooldown - entry.remaining)
            local start = GetTime() - elapsed
            if not button.cooldownStart
                or math.abs(button.cooldownStart - start) > 0.05
                or button.cooldownDuration ~= entry.cooldown then
                button.cooldown:SetCooldown(start, entry.cooldown)
                button.cooldownStart = start
                button.cooldownDuration = entry.cooldown
            end
            button.cooldownText:SetText(tostring(math.ceil(entry.remaining)))
        else
            if button.cooldownStart then
                button.cooldown:SetCooldown(0, 0)
                button.cooldownStart = nil
                button.cooldownDuration = nil
            end
            button.cooldownText:SetText("")
        end
        button:Show()
    end
    for index = #entries + 1, #abilityButtons do
        abilityButtons[index]:Hide()
    end
    bar:Show()
end

local function setTrackingEnabled(enabled)
    trackingEnabled = enabled and true or false
    db.trackingEnabled = trackingEnabled
    if trackingCheckbox then
        trackingCheckbox:SetChecked(trackingEnabled)
    end
    updateBar()
end

local function createConfigFrame()
    configFrame = CreateFrame("Frame", "InterruptCooldownTrackerConfigFrame", UIParent)
    configFrame:SetSize(250, 105)
    configFrame:SetPoint("CENTER")
    configFrame:SetFrameStrata("DIALOG")
    configFrame:SetMovable(true)
    configFrame:EnableMouse(true)
    configFrame:RegisterForDrag("LeftButton")
    configFrame:SetScript("OnDragStart", configFrame.StartMoving)
    configFrame:SetScript("OnDragStop", configFrame.StopMovingOrSizing)
    configFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", configFrame, "TOP", 0, -18)
    title:SetText("Interrupt Cooldown Tracker")

    trackingCheckbox = CreateFrame("CheckButton", nil, configFrame, "UICheckButtonTemplate")
    trackingCheckbox:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 24, -42)
    trackingCheckbox:SetSize(24, 24)
    trackingCheckbox:SetChecked(trackingEnabled)
    trackingCheckbox:SetScript("OnClick", function(self)
        setTrackingEnabled(self:GetChecked())
    end)

    local label = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", trackingCheckbox, "RIGHT", 6, 0)
    label:SetText("Enable interrupt tracking")

    configFrame:Hide()
end

local function initialize()
    db = InterruptCooldownTrackerDB or {}
    InterruptCooldownTrackerDB = db
    trackingEnabled = db.trackingEnabled ~= false

    bar = CreateFrame("Frame", "InterruptCooldownTrackerBar", UIParent)
    bar:SetSize(CELL_WIDTH, CELL_HEIGHT)
    bar:SetPoint("CENTER", UIParent, "CENTER", tonumber(db.x) or 0, tonumber(db.y) or 0)
    bar:SetMovable(true)
    bar:EnableMouse(false)
    bar:SetClampedToScreen(true)

    createConfigFrame()
    updateBar()
end

SLASH_INTERRUPTCOOLDOWNTRACKER1 = "/ict"
SlashCmdList.INTERRUPTCOOLDOWNTRACKER = function(command)
    local normalized = string.lower(command or "")
    if not bar then
        return
    end
    if normalized == "tracking" or normalized == "toggle" then
        setTrackingEnabled(not trackingEnabled)
    elseif normalized == "show" then
        setTrackingEnabled(true)
    elseif normalized == "hide" then
        setTrackingEnabled(false)
    else
        if configFrame:IsShown() then
            configFrame:Hide()
        else
            configFrame:Show()
        end
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
events:RegisterEvent("PARTY_MEMBERS_CHANGED")
events:RegisterEvent("RAID_ROSTER_UPDATE")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        local initialized, initializationError = pcall(initialize)
        if not initialized then
            print("Interrupt Cooldown Tracker: initialization failed: " .. tostring(initializationError))
        end
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local eventArgs = { ... }
        if CombatLogGetCurrentEventInfo then
            eventArgs = { CombatLogGetCurrentEventInfo() }
        end
        local eventType = eventArgs[2]
        if trackingEnabled and (eventType == "SPELL_CAST_SUCCESS" or eventType == "SPELL_INTERRUPT") then
            recordInterrupt(eventArgs[5], tonumber(eventArgs[12]))
        end
    end
    updateBar()
end)

events:SetScript("OnUpdate", function(_, elapsed)
    if not trackingEnabled or not bar or not bar:IsShown() then
        return
    end
    refreshElapsed = refreshElapsed + elapsed
    if refreshElapsed >= 0.25 then
        refreshElapsed = 0
        updateBar()
    end
end)
