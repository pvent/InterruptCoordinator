local ADDON_NAME = "InterruptCooldownTracker"
local ADDON_VERSION = "1.2.2"

local interruptCatalog = {
    { class = "WARRIOR", ids = { 72, 1671, 1672, 29704 }, cooldown = 12, sharedCooldownGroup = "warriorShieldBashPummel" },
    { class = "WARRIOR", ids = { 6554, 6552 }, cooldown = 10, sharedCooldownGroup = "warriorShieldBashPummel" },
    { class = "MAGE", ids = { 2139 }, cooldown = 24 },
    { class = "ROGUE", ids = { 1767, 1766 }, cooldown = 10 },
    { class = "HUNTER", ids = { 34490 }, cooldown = 20 },
    { class = "SHAMAN", ids = { 25454, 10414, 10413, 10412, 8046, 8045, 8044, 8042 }, cooldown = 6 },
    { class = "PRIEST", ids = { 15487 }, cooldown = 45 },
    { class = "WARLOCK", ids = { 19647 }, cooldown = 24, pet = true },
}

local secondaryCatalog = {
    { class = "WARRIOR", ids = { 100, 6178, 11578 }, cooldown = 15 },
    { class = "WARRIOR", ids = { 20252, 20616, 20617, 25272 }, cooldown = 30 },
    { class = "WARRIOR", ids = { 676 }, cooldown = 60 },
    { class = "WARRIOR", ids = { 12809 }, cooldown = 45 },
    { class = "WARRIOR", ids = { 5246 }, cooldown = 180 },
    { race = "TAUREN", ids = { 20549 }, cooldown = 120 },
    { class = "PALADIN", ids = { 853, 5588, 5589, 10308 }, cooldown = 60 },
    { class = "PALADIN", ids = { 20066 }, cooldown = 60 },
    { class = "HUNTER", ids = { 19503 }, cooldown = 30 },
    { class = "HUNTER", ids = { 1499, 14310, 14311 }, cooldown = 30 },
    { class = "ROGUE", ids = { 408, 8643 }, cooldown = 20 },
    { class = "ROGUE", ids = { 1776, 1777, 8629, 11285, 11286 }, cooldown = 10 },
    { class = "ROGUE", ids = { 2094 }, cooldown = 180 },
    { class = "PRIEST", ids = { 8122, 8124, 10888, 10890 }, cooldown = 30 },
    { class = "MAGE", ids = { 31661, 33041, 33042 }, cooldown = 20 },
    { class = "WARLOCK", ids = { 6789, 17925, 17926, 27223 }, cooldown = 120 },
    { class = "WARLOCK", ids = { 30283, 30413, 30414 }, cooldown = 20 },
    { class = "DRUID", ids = { 5211, 6798, 8983 }, cooldown = 60 },
    { class = "DRUID", ids = { 22570 }, cooldown = 10 },
}

local catalogById = {}
local function indexCatalog(catalog, secondary)
    for _, ability in ipairs(catalog) do
        ability.blacklistKey = tostring(ability.ids[1])
        ability.secondary = secondary
        for _, spellId in ipairs(ability.ids) do
            catalogById[spellId] = ability
        end
    end
end
indexCatalog(interruptCatalog, false)
indexCatalog(secondaryCatalog, true)

local db
local trackingEnabled
local initialized = false
local bar
local configFrame
local secondaryFiltersFrame
local showSecondaryCheckbox
local trackingCheckbox
local hideEmptyCheckbox
local combatOnlyCheckbox
local statusText
local abilityButtons = {}
local estimates = {}
local positionSliders = {}
local positionValues = {}
local filterCheckboxes = { main = {}, secondary = {} }
local refreshElapsed = 0
local combatActive = false

local iconSize = 44
local cellWidth = 64
local cellHeight = 68
local memberLabelHeight = 16

local function updateCellMetrics()
    iconSize = db.iconSize
    memberLabelHeight = db.playerFontSize + 4
    cellWidth = iconSize + (db.backgroundPadding * 2)
    cellHeight = iconSize + memberLabelHeight + (db.backgroundPadding * 2)
end

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
    return realm and realm ~= "" and name .. "-" .. realm or name
end

local function getRaidMemberCount()
    if IsInRaid and IsInRaid() and GetNumGroupMembers then
        return GetNumGroupMembers()
    end
    if GetNumRaidMembers then
        return GetNumRaidMembers()
    end
    return 0
end

local function getPartyMemberCount()
    if IsInRaid and IsInRaid() then
        return 0
    end
    if GetNumPartyMembers then
        local count = GetNumPartyMembers()
        if count > 0 then
            return count
        end
    end
    if GetNumGroupMembers then
        return math.max(0, GetNumGroupMembers() - 1)
    end
    return 0
end

local function getRoster()
    local roster = {}
    local raidCount = getRaidMemberCount()
    local partyCount = getPartyMemberCount()

    local function addUnit(unit)
        local name = getFullName(unit)
        if name then
            roster[#roster + 1] = {
                name = name,
                key = nameKey(name),
                unit = unit,
                class = select(2, UnitClass(unit)),
                guid = UnitGUID and UnitGUID(unit),
            }
        end
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

local function classColor(class)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not color then
        return 1, 1, 1
    end
    return color.r, color.g, color.b
end

local function samePlayerName(memberName, sourceName)
    if type(memberName) ~= "string" or type(sourceName) ~= "string" then
        return false
    end
    local memberKey = nameKey(memberName)
    local sourceKey = nameKey(sourceName)
    if memberKey == sourceKey then
        return true
    end
    if not sourceName:find("-", 1, true) then
        return nameKey(shortName(memberName)) == sourceKey
    end
    return false
end

local function findMember(sourceName, roster, sourceGUID)
    local sourceShortName = nameKey(shortName(sourceName))
    if sourceGUID then
        for _, member in ipairs(roster) do
            if member.guid == sourceGUID then
                return member
            end

            local petUnit = "pet"
            local partyIndex = member.unit:match("^party(%d+)$")
            local raidIndex = member.unit:match("^raid(%d+)$")
            if partyIndex then
                petUnit = "partypet" .. partyIndex
            elseif raidIndex then
                petUnit = "raidpet" .. raidIndex
            end
            if UnitGUID and UnitGUID(petUnit) == sourceGUID then
                return member
            end
        end
    end

    for _, member in ipairs(roster) do
        if samePlayerName(member.name, sourceName) then
            return member
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
        if samePlayerName(petName, sourceName) then
            return member
        end
    end

    if sourceShortName == "" then
        return nil
    end

    local matchedMember
    for _, member in ipairs(roster) do
        local memberMatches = nameKey(shortName(member.name)) == sourceShortName
        if not memberMatches then
            local petUnit = "pet"
            local partyIndex = member.unit:match("^party(%d+)$")
            local raidIndex = member.unit:match("^raid(%d+)$")
            if partyIndex then
                petUnit = "partypet" .. partyIndex
            elseif raidIndex then
                petUnit = "raidpet" .. raidIndex
            end
            memberMatches = nameKey(UnitName(petUnit)) == sourceShortName
        end

        if memberMatches then
            if matchedMember then
                return nil
            end
            matchedMember = member
        end
    end
    return matchedMember
end

local function recordInterrupt(sourceName, spellId)
    if not trackingEnabled or not sourceName or not spellId then
        return
    end
    local ability = catalogById[spellId]
    if not ability
        or (ability.secondary and db.secondaryBlacklist[ability.blacklistKey])
        or (not ability.secondary and db.blacklist[ability.blacklistKey]) then
        return
    end
    local member = findMember(sourceName, getRoster())
    if not member then
        return
    end

    local now = GetTime()
    estimates[member.key] = estimates[member.key] or {}
    local previous = estimates[member.key][spellId]
    if previous and now - previous.usedAt < 0.5 then
        return
    end
    estimates[member.key][spellId] = {
        id = spellId,
        cooldown = ability.cooldown,
        usedAt = now,
    }
end

local function processCombatLog(args)
    local eventType = args[2]
    if eventType ~= "SPELL_CAST_SUCCESS" and eventType ~= "SPELL_INTERRUPT" then
        return false
    end

    local modernEvent = type(args[3]) == "boolean"
    local sourceNameIndex = modernEvent and 5 or 4
    local spellIdIndex = modernEvent and 12 or 11
    local roster = getRoster()
    local sourceGUIDIndex = modernEvent and 4 or 3
    local member = findMember(args[sourceNameIndex], roster, args[sourceGUIDIndex])

    if not member then
        for index = 3, #args do
            if type(args[index]) == "string" then
                member = findMember(args[index], roster, args[sourceGUIDIndex])
                if member then
                    break
                end
            end
        end
    end
    if not member then
        return false
    end

    local spellId = tonumber(args[spellIdIndex])
    if not catalogById[spellId] then
        local firstSpellArgument = modernEvent and 12 or 11
        for index = firstSpellArgument, #args do
            local candidate = tonumber(args[index])
            if catalogById[candidate] then
                spellId = candidate
                break
            end
        end
    end
    if not catalogById[spellId] then
        return false
    end

    recordInterrupt(member.name, spellId)
    return true
end

local function collectEntries(now)
    local entries = {}
    local members = {}
    for _, member in ipairs(getRoster()) do
        members[member.key] = member
    end

    for memberKey, memberEstimates in pairs(estimates) do
        local member = members[memberKey]
        if member then
            local sharedElapsed = {}
            for spellId, estimate in pairs(memberEstimates) do
                local ability = catalogById[spellId]
                local remaining = math.max(0, estimate.cooldown - (now - estimate.usedAt))
                local group = ability and ability.sharedCooldownGroup
                if group and remaining > 0 then
                    local elapsed = estimate.cooldown - remaining
                    sharedElapsed[group] = math.min(sharedElapsed[group] or elapsed, elapsed)
                end
            end
            for spellId, estimate in pairs(memberEstimates) do
                local ability = catalogById[spellId]
                local isBlacklisted = ability and (
                    ability.secondary and db.secondaryBlacklist[ability.blacklistKey]
                    or not ability.secondary and db.blacklist[ability.blacklistKey]
                )
                local secondaryHidden = ability and ability.secondary and not db.showSecondaryStops
                if ability and not isBlacklisted and not secondaryHidden then
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
                        secondary = ability.secondary,
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

local function savePosition()
    local left = bar:GetLeft()
    local bottom = bar:GetBottom()
    if left and bottom then
        local uiLeft, uiBottom = UIParent:GetLeft(), UIParent:GetBottom()
        local scale = bar:GetEffectiveScale()
        local uiScale = UIParent:GetEffectiveScale()
        -- Convert absolute position into center offset coordinates relative to UIParent center
        local centerX = left + (bar:GetWidth() / 2)
        local centerY = bottom + (bar:GetHeight() / 2)
        local uiCenterX = uiLeft + (UIParent:GetWidth() / 2)
        local uiCenterY = uiBottom + (UIParent:GetHeight() / 2)
        
        db.x = (centerX - uiCenterX) * (scale / uiScale)
        db.y = (centerY - uiCenterY) * (scale / uiScale)
    end
    for key, positionValue in pairs(positionValues) do
        positionValue:SetText(tostring(math.floor((db[key] or 0) + 0.5)))
        if positionSliders[key] then
            positionSliders[key]:SetValue(db[key])
        end
    end
end

local function makeButton()
    local button = CreateFrame("Button", nil, bar)
    button:SetSize(iconSize, iconSize)
    button.texture = button:CreateTexture(nil, "ARTWORK")
    button.texture:SetAllPoints(button)
    button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldown:SetAllPoints(button)
    button.countdown = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.countdown:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.countdown:SetTextColor(1, 1, 1)
    button.memberText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.memberText:SetPoint("TOP", button, "BOTTOM", 0, -2)
    button.memberText:SetWidth(cellWidth)
    button.memberText:SetJustifyH("CENTER")
    button:SetScript("OnEnter", function(self)
        if not self.entry then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local red, green, blue = classColor(self.entry.member.class)
        GameTooltip:AddLine(self.entry.member.name, red, green, blue)
        GameTooltip:AddLine(GetSpellInfo(self.entry.id) or "Interrupt", 1, 1, 1)
        if self.entry.secondary then
            GameTooltip:AddLine("Secondary stop", 0.8, 0.8, 0.8)
        end
        GameTooltip:AddLine("Estimated cooldown: " .. math.ceil(self.entry.remaining) .. "s", 0.9, 0.9, 0.9)
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
    if not trackingEnabled or (db.combatOnly and not combatActive) then
        bar:Hide()
        return
    end

    local entries = collectEntries(GetTime())
    local perRow = db.perRow
    local maxRows = db.maxRows
    local capacity = perRow * maxRows
    local visibleCount = math.min(#entries, capacity)
    if visibleCount == 0 and db.hideWhenEmpty then
        bar:Hide()
        return
    end
    local rowCount = math.max(1, math.ceil(visibleCount / perRow))
    local columnCount = math.max(1, math.min(visibleCount, perRow))
    local showStatus = visibleCount == 0 or #entries > visibleCount
    local statusHeight = showStatus and select(2, statusText:GetFont()) or 0
    local barHeight = visibleCount == 0
        and statusHeight + (db.backgroundPadding * 2)
        or rowCount * cellHeight + (showStatus and (statusHeight + db.backgroundPadding) or 0)
    if visibleCount == 0 then
        statusText:SetText("Waiting for casts")
        local statusWidth = statusText:GetStringWidth() + (db.backgroundPadding * 2)
        bar:SetSize(statusWidth, barHeight)
    else
        bar:SetSize(columnCount * cellWidth, barHeight)
    end
    statusText:ClearAllPoints()
    statusText:SetPoint("BOTTOM", bar, "BOTTOM", 0, db.backgroundPadding)

    if visibleCount == 0 then
        statusText:Show()
    else
        statusText:SetText(#entries > visibleCount and ("+" .. (#entries - visibleCount) .. " more") or "")
        if showStatus then
            statusText:Show()
        else
            statusText:Hide()
        end
    end

    for index = 1, visibleCount do
        local entry = entries[index]
        local button = abilityButtons[index] or makeButton()
        abilityButtons[index] = button
        button.entry = entry
        button:SetSize(iconSize, iconSize)
        button.memberText:SetWidth(cellWidth)
        button:ClearAllPoints()
        local row = math.floor((index - 1) / perRow)
        local column = (index - 1) % perRow
        button:SetPoint("TOPLEFT", bar, "TOPLEFT",
            column * cellWidth + db.backgroundPadding, -row * cellHeight - db.backgroundPadding)

        local _, _, texture = GetSpellInfo(entry.id)
        button.texture:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        if button.texture.SetDesaturated then
            button.texture:SetDesaturated(false)
        end
        button.memberText:SetText(entry.member.name:match("^([^-]+)") or entry.member.name)
        local fontPath, _, fontFlags = GameFontNormalSmall:GetFont()
        button.memberText:SetFont(fontPath, db.playerFontSize, fontFlags)
        local red, green, blue = classColor(entry.member.class)
        button.memberText:SetTextColor(red, green, blue)
        if entry.remaining > 0 then
            local start = GetTime() - (entry.cooldown - entry.remaining)
            if not button.cooldownStart or math.abs(button.cooldownStart - start) > 0.1 then
                button.cooldown:SetCooldown(start, entry.cooldown)
                button.cooldownStart = start
            end
            button.countdown:SetText(tostring(math.ceil(entry.remaining)))
        else
            if button.cooldownStart then
                button.cooldown:SetCooldown(0, 0)
                button.cooldownStart = nil
            end
            button.countdown:SetText("")
        end
        button:Show()
    end
    for index = visibleCount + 1, #abilityButtons do
        abilityButtons[index]:Hide()
    end
    bar:Show()
end

local function setTracking(enabled)
    trackingEnabled = enabled and true or false
    db.trackingEnabled = trackingEnabled
    if trackingCheckbox then
        trackingCheckbox:SetChecked(trackingEnabled)
    end
    updateBar()
end

local function makeStepControl(parent, titleText, key, minimum, maximum, step, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, y)
    label:SetText(titleText)
    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -54, y)
    value:SetWidth(32)
    value:SetJustifyH("CENTER")
    local function refresh()
        value:SetText(tostring(db[key]))
    end
    local function change(delta)
        db[key] = math.max(minimum, math.min(maximum, db[key] + delta * step))
        if key == "iconSize" or key == "backgroundPadding" or key == "playerFontSize" then
            updateCellMetrics()
        end
        refresh()
        updateBar()
    end
    local minus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    minus:SetSize(24, 22)
    minus:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -94, y + 4)
    minus:SetText("-")
    minus:SetScript("OnClick", function() change(-1) end)
    local plus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    plus:SetSize(24, 22)
    plus:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, y + 4)
    plus:SetText("+")
    plus:SetScript("OnClick", function() change(1) end)
    refresh()
end

local function makeLayoutStepControl(titleText, key, minimum, maximum, step, y, helpText)
    makeStepControl(configFrame, titleText, key, minimum, maximum, step, y)
    local help = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    help:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 18, y - 18)
    help:SetText(helpText)
end

local function makePositionControl(parent, titleText, key, y)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, y)
    label:SetText(titleText)
    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -54, y)
    value:SetWidth(42)
    value:SetJustifyH("CENTER")
    positionValues[key] = value
    local function refresh()
        value:SetText(tostring(math.floor((db[key] or 0) + 0.5)))
    end
    local function apply(newValue)
        db[key] = math.max(-1000, math.min(1000, newValue))
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
        refresh()
        if positionSliders[key] and positionSliders[key]:GetValue() ~= db[key] then
            positionSliders[key]:SetValue(db[key])
        end
    end
    local function change(delta)
        apply(db[key] + delta)
    end
    local minus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    minus:SetSize(24, 22)
    minus:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -94, y + 4)
    minus:SetText("-")
    minus:SetScript("OnClick", function() change(-1) end)
    local plus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    plus:SetSize(24, 22)
    plus:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -18, y + 4)
    plus:SetText("+")
    plus:SetScript("OnClick", function() change(1) end)

    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetOrientation("HORIZONTAL")
    slider:SetWidth(190)
    slider:SetHeight(16)
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y - 18)
    slider:SetMinMaxValues(-1000, 1000)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end
    slider:SetValue(db[key])
    slider:SetScript("OnValueChanged", function(_, newValue)
        apply(math.floor(newValue + 0.5))
    end)
    positionSliders[key] = slider
    refresh()
end

local function setAllBlacklisted(catalog, blacklist, category, hidden)
    for _, ability in ipairs(catalog) do
        blacklist[ability.blacklistKey] = hidden and true or nil
    end
    for key, checkbox in pairs(filterCheckboxes[category]) do
        checkbox:SetChecked(blacklist[key] == true)
    end
    updateBar()
end

local function createFilterColumn(parent, category, titleText, catalog, blacklist, x, width)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -48)
    title:SetText(titleText)

    local function makeBulkButton(label, offset, hidden)
        local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetSize(92, 22)
        button:SetPoint("TOPLEFT", parent, "TOPLEFT", x + offset, -70)
        button:SetText(label)
        button:SetScript("OnClick", function()
            setAllBlacklisted(catalog, blacklist, category, hidden)
        end)
    end
    makeBulkButton("Show all", 0, false)
    makeBulkButton("Hide all", 98, true)

    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -100)
    scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", x + width - 26, 16)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width - 30, #catalog * 27)
    scroll:SetScrollChild(child)

    filterCheckboxes[category] = {}
    for index, ability in ipairs(catalog) do
        local spellId = ability.ids[1]
        local spellName, _, texture = GetSpellInfo(spellId)
        spellName = spellName or ("Spell " .. spellId)

        local checkbox = CreateFrame("CheckButton", nil, child, "UICheckButtonTemplate")
        checkbox:SetPoint("TOPLEFT", child, "TOPLEFT", 0, -(index - 1) * 27)
        checkbox:SetSize(22, 22)
        checkbox:SetChecked(blacklist[ability.blacklistKey] == true)
        filterCheckboxes[category][ability.blacklistKey] = checkbox
        checkbox:SetScript("OnClick", function(self)
            blacklist[ability.blacklistKey] = self:GetChecked() and true or nil
            updateBar()
        end)

        local icon = child:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
        icon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
        local label = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", icon, "RIGHT", 5, 0)
        label:SetText(spellName)
    end
end

local function createSecondaryFiltersFrame()
    local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
    secondaryFiltersFrame = CreateFrame("Frame", "InterruptCooldownTrackerSecondaryFiltersFrame", UIParent, backdropTemplate)
    secondaryFiltersFrame:SetSize(560, 540)
    secondaryFiltersFrame:SetPoint("TOPLEFT", configFrame, "TOPRIGHT", 8, 0)
    secondaryFiltersFrame:SetFrameStrata("DIALOG")
    secondaryFiltersFrame:SetMovable(true)
    secondaryFiltersFrame:EnableMouse(true)
    if secondaryFiltersFrame.SetClampedToScreen then
        secondaryFiltersFrame:SetClampedToScreen(true)
    end
    if secondaryFiltersFrame.SetBackdrop then
        secondaryFiltersFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
    else
        local background = secondaryFiltersFrame:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(secondaryFiltersFrame)
        background:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    end
    secondaryFiltersFrame:RegisterForDrag("LeftButton")
    secondaryFiltersFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    secondaryFiltersFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local title = secondaryFiltersFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", secondaryFiltersFrame, "TOPLEFT", 16, -14)
    title:SetText("Cooldown filters")
    local close = CreateFrame("Button", nil, secondaryFiltersFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", secondaryFiltersFrame, "TOPRIGHT", -5, -5)

    createFilterColumn(secondaryFiltersFrame, "main", "Interrupts", interruptCatalog, db.blacklist, 18, 250)
    createFilterColumn(secondaryFiltersFrame, "secondary", "Secondary stops", secondaryCatalog, db.secondaryBlacklist, 286, 250)
    secondaryFiltersFrame:Hide()
end

local function createConfig()
    local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
    configFrame = CreateFrame("Frame", "InterruptCooldownTrackerConfigFrame", UIParent, backdropTemplate)
    configFrame:SetSize(350, 555)
    configFrame:SetPoint("CENTER")
    configFrame:SetFrameStrata("DIALOG")
    configFrame:SetMovable(true)
    configFrame:EnableMouse(true)
    if configFrame.SetBackdrop then
        configFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
    else
        local background = configFrame:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(configFrame)
        background:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    end
    configFrame:RegisterForDrag("LeftButton")
    configFrame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    configFrame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    if UISpecialFrames then
        table.insert(UISpecialFrames, "InterruptCooldownTrackerConfigFrame")
        table.insert(UISpecialFrames, "InterruptCooldownTrackerSecondaryFiltersFrame")
    end
    configFrame:SetScript("OnHide", function()
        if secondaryFiltersFrame then
            secondaryFiltersFrame:Hide()
        end
    end)

    local title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 16, -14)
    title:SetText("Interrupt Cooldown Tracker")
    local close = CreateFrame("Button", nil, configFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -5, -5)

    trackingCheckbox = CreateFrame("CheckButton", nil, configFrame, "UICheckButtonTemplate")
    trackingCheckbox:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 14, -44)
    trackingCheckbox:SetSize(24, 24)
    trackingCheckbox:SetChecked(trackingEnabled)
    trackingCheckbox:SetScript("OnClick", function(self) setTracking(self:GetChecked()) end)
    local trackingLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    trackingLabel:SetPoint("LEFT", trackingCheckbox, "RIGHT", 4, 0)
    trackingLabel:SetText("Enable combat-log tracking")

    makeStepControl(configFrame, "Interrupt icons per row", "perRow", 1, 10, 1, -82)
    makeStepControl(configFrame, "Maximum rows", "maxRows", 1, 10, 1, -118)
    makeLayoutStepControl("Icon size", "iconSize", 24, 64, 2, -154,
        "Icon width and height in pixels.")
    makeLayoutStepControl("Cell padding per side", "backgroundPadding", 0, 20, 1, -190,
        "8 px adds 16 px to each cell's width and height.")
    makeLayoutStepControl("Player name font size", "playerFontSize", 8, 18, 1, -226,
        "Adjusts the name text beneath each icon.")
    makePositionControl(configFrame, "Horizontal position", "x", -276)
    makePositionControl(configFrame, "Vertical position", "y", -342)
    local dragHelp = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dragHelp:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 18, -402)
    dragHelp:SetText("Hold Shift and drag the bar to move it.")

    showSecondaryCheckbox = CreateFrame("CheckButton", nil, configFrame, "UICheckButtonTemplate")
    showSecondaryCheckbox:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 14, -424)
    showSecondaryCheckbox:SetSize(24, 24)
    showSecondaryCheckbox:SetChecked(db.showSecondaryStops)
    showSecondaryCheckbox:SetScript("OnClick", function(self)
        db.showSecondaryStops = self:GetChecked() and true or false
        updateBar()
    end)
    local secondaryLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    secondaryLabel:SetPoint("LEFT", showSecondaryCheckbox, "RIGHT", 4, 0)
    secondaryLabel:SetText("Track secondary stops")
    hideEmptyCheckbox = CreateFrame("CheckButton", nil, configFrame, "UICheckButtonTemplate")
    hideEmptyCheckbox:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 14, -452)
    hideEmptyCheckbox:SetSize(24, 24)
    hideEmptyCheckbox:SetChecked(db.hideWhenEmpty)
    hideEmptyCheckbox:SetScript("OnClick", function(self)
        db.hideWhenEmpty = self:GetChecked() and true or false
        updateBar()
    end)
    local hideEmptyLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hideEmptyLabel:SetPoint("LEFT", hideEmptyCheckbox, "RIGHT", 4, 0)
    hideEmptyLabel:SetText("Hide tracker when empty")

    combatOnlyCheckbox = CreateFrame("CheckButton", nil, configFrame, "UICheckButtonTemplate")
    combatOnlyCheckbox:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 14, -480)
    combatOnlyCheckbox:SetSize(24, 24)
    combatOnlyCheckbox:SetChecked(db.combatOnly)
    combatOnlyCheckbox:SetScript("OnClick", function(self)
        db.combatOnly = self:GetChecked() and true or false
        updateBar()
    end)
    local combatOnlyLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    combatOnlyLabel:SetPoint("LEFT", combatOnlyCheckbox, "RIGHT", 4, 0)
    combatOnlyLabel:SetText("Show tracker only in combat")

    local filtersButton = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    filtersButton:SetSize(130, 24)
    filtersButton:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 18, -510)
    filtersButton:SetText("Interrupt filters...")
    filtersButton:SetScript("OnClick", function()
        if secondaryFiltersFrame:IsShown() then
            secondaryFiltersFrame:Hide()
        else
            secondaryFiltersFrame:Show()
        end
    end)

    createSecondaryFiltersFrame()
    configFrame:Hide()
end

local function openConfig()
    if not configFrame then
        return false
    end
    if configFrame:IsShown() then
        configFrame:Hide()
    else
        configFrame:Show()
    end
    return true
end

local function initialize()
    if initialized then
        updateBar()
        return
    end
    db = InterruptCooldownTrackerDB or {}
    InterruptCooldownTrackerDB = db
    if db.version ~= ADDON_VERSION then
        db.trackingEnabled = true
        db.version = ADDON_VERSION
    end
    db.trackingEnabled = db.trackingEnabled ~= false
    db.perRow = math.max(1, math.min(10, tonumber(db.perRow) or 6))
    db.maxRows = math.max(1, math.min(10, tonumber(db.maxRows) or 3))
    db.iconSize = math.max(24, math.min(64, tonumber(db.iconSize) or 44))
    db.backgroundPadding = math.max(0, math.min(20, tonumber(db.backgroundPadding) or 8))
    db.playerFontSize = math.max(8, math.min(18, tonumber(db.playerFontSize) or 10))
    db.x = math.max(-1000, math.min(1000, tonumber(db.x) or 0))
    db.y = math.max(-1000, math.min(1000, tonumber(db.y) or 0))
    db.blacklist = type(db.blacklist) == "table" and db.blacklist or {}
    db.secondaryBlacklist = type(db.secondaryBlacklist) == "table" and db.secondaryBlacklist or {}
    db.showSecondaryStops = db.showSecondaryStops ~= false
    db.hideWhenEmpty = db.hideWhenEmpty == true
    db.combatOnly = db.combatOnly == true
    updateCellMetrics()
    trackingEnabled = db.trackingEnabled
    combatActive = UnitAffectingCombat and UnitAffectingCombat("player") or false

    bar = CreateFrame("Frame", "InterruptCooldownTrackerBar", UIParent)
    bar:SetSize(cellWidth, cellHeight + 20)
    bar:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)
    bar:SetFrameStrata("MEDIUM")
    bar:SetMovable(true)
    bar:EnableMouse(true)
    if bar.SetClampedToScreen then
        bar:SetClampedToScreen(true)
    end

    -- Custom Mouse Delta Drag Handler to resolve frame-jumping on release
    bar:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and (not IsShiftKeyDown or IsShiftKeyDown()) then
            local scale = self:GetEffectiveScale()
            local cursorX, cursorY = GetCursorPosition()
            
            self.startX = cursorX / scale - self:GetLeft()
            self.startY = cursorY / scale - self:GetBottom()
            
            self:SetScript("OnUpdate", function(f)
                local cX, cY = GetCursorPosition()
                local s = f:GetEffectiveScale()
                
                f:ClearAllPoints()
                f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (cX / s) - f.startX, (cY / s) - f.startY)
            end)
        end
    end)

    bar:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            self:SetScript("OnUpdate", nil)
            
            local left = self:GetLeft()
            local bottom = self:GetBottom()
            if left and bottom then
                self:ClearAllPoints()
                self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", math.floor(left + 0.5), math.floor(bottom + 0.5))
                savePosition()
            end
        end
    end)

    local background = bar:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(bar)
    background:SetTexture("Interface\\Buttons\\WHITE8X8")
    background:SetVertexColor(0.02, 0.02, 0.02, 0.82)
    statusText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    statusText:SetWidth(400)
    statusText:SetJustifyH("CENTER")

    createConfig()
    initialized = true
    updateBar()
end

local function toggleConfig(command)
    local normalized = string.lower(command or "")
    if not initialized and normalized == "" then
        local success, err = pcall(initialize)
        if not success then
            print("Interrupt Cooldown Tracker: " .. tostring(err))
            return
        end
    end
    if not initialized then
        print("Interrupt Cooldown Tracker is not initialized. Check whether the addon is enabled and reload the UI.")
        return
    end
    if normalized == "show" then
        setTracking(true)
    elseif normalized == "hide" then
        setTracking(false)
    elseif normalized == "tracking" or normalized == "toggle" then
        setTracking(not trackingEnabled)
    elseif normalized == "reset" then
        db.x, db.y = 0, 0
        bar:ClearAllPoints()
        bar:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        savePosition()
        updateBar()
    elseif not openConfig() then
        print("Interrupt Cooldown Tracker config is not ready. Reload the UI and check Lua errors.")
    end
end

SLASH_INTERRUPTCOOLDOWNTRACKER1 = "/ict"
SLASH_INTERRUPTCOOLDOWNTRACKER2 = "/ictracker"
SLASH_INTERRUPTCOOLDOWNTRACKER3 = "/interrupttracker"
SLASH_INTERRUPTCOOLDOWNTRACKER4 = "/interruptcooldowntracker"
SlashCmdList.INTERRUPTCOOLDOWNTRACKER = toggleConfig

local eventFrame = CreateFrame("Frame")
local function registerEvent(eventName)
    local ok = pcall(eventFrame.RegisterEvent, eventFrame, eventName)
    return ok
end

registerEvent("ADDON_LOADED")
registerEvent("PLAYER_LOGIN")
registerEvent("COMBAT_LOG_EVENT_UNFILTERED")
registerEvent("PLAYER_REGEN_DISABLED")
registerEvent("PLAYER_REGEN_ENABLED")
registerEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == ADDON_NAME then
            local ok, err = pcall(initialize)
            if not ok then
                print("Interrupt Cooldown Tracker initialization failed: " .. tostring(err))
            end
        end
    elseif event == "PLAYER_LOGIN" then
        local ok, err = pcall(initialize)
        if not ok then
            print("Interrupt Cooldown Tracker initialization failed: " .. tostring(err))
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        combatActive = true
        updateBar()
    elseif event == "PLAYER_REGEN_ENABLED" then
        combatActive = false
        updateBar()
    elseif event == "PLAYER_ENTERING_WORLD" then
        combatActive = UnitAffectingCombat and UnitAffectingCombat("player") or false
        updateBar()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local args = { ... }
        if CombatLogGetCurrentEventInfo then
            args = { CombatLogGetCurrentEventInfo() }
        end
        if trackingEnabled then
            processCombatLog(args)
        end
        updateBar()
    end
end)

eventFrame:SetScript("OnUpdate", function(_, elapsed)
    if not initialized or not trackingEnabled then
        return
    end
    refreshElapsed = refreshElapsed + elapsed
    if refreshElapsed >= 0.25 then
        refreshElapsed = 0
        updateBar()
    end
end)

local loaded, loadError = pcall(initialize)
if not loaded then
    print("Interrupt Cooldown Tracker initialization failed: " .. tostring(loadError))
else
    print("Interrupt Cooldown Tracker loaded. Use /ict or /interruptcooldowntracker for settings.")
end