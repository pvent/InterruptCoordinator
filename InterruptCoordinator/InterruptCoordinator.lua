local PREFIX = "IC"
local ADDON_VERSION = "1.0.3"
local HEARTBEAT_SECONDS = 20
local STALE_SECONDS = 45
local VERSION_CHECK_SECONDS = 5
local MAX_GLOBAL_COOLDOWN_DURATION = 2.5

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
local abilityCatalog = {}
for _, category in ipairs({ interruptCatalog, secondaryCatalog }) do
    for _, ability in ipairs(category) do
        ability.secondary = category == secondaryCatalog
        abilityCatalog[#abilityCatalog + 1] = ability
        for _, spellId in ipairs(ability.ids) do
            catalogById[spellId] = ability
        end
    end
end

local function synchronizeSharedCooldowns(abilities)
    local sharedElapsed = {}
    for _, ability in ipairs(abilities) do
        local catalogEntry = catalogById[ability.id]
        local group = catalogEntry and catalogEntry.sharedCooldownGroup
        if group and ability.remaining > 0 then
            local elapsed = math.max(0, ability.cooldown - ability.remaining)
            sharedElapsed[group] = math.min(sharedElapsed[group] or elapsed, elapsed)
        end
    end
    for _, ability in ipairs(abilities) do
        local catalogEntry = catalogById[ability.id]
        local group = catalogEntry and catalogEntry.sharedCooldownGroup
        local elapsed = group and sharedElapsed[group]
        if elapsed then
            ability.remaining = math.max(ability.remaining, math.max(0, ability.cooldown - elapsed))
        end
    end
end

local frame
local scrollChild
local rows = {}
local primaryText
local backupText
local statusText
local panelReady = false
local primaryIcon
local primaryHeaderText
local primaryNameText
local primaryInfoText
local layoutStatusText
local interruptHeaderText
local secondaryHeaderText
local componentPanels = {}
local componentPositionLabels = {}
local versionStatusText
local configFrame
local componentPositionFrame
local appearanceFrame
local visibilityButton
local editModeButton
local editMode = false
local componentDrag
local updateComponentDrag
local updateComponentPositionLabels
local updateBarPositionControlState
local memberIcons = {}
local secondaryIcons = {}
local settings
local reports = {}
local combatEstimates = {}
local versionReports = {}
local localAbilities = {}
local localKey
local refreshElapsed = 0
local heartbeatElapsed = 0
local publishAt
local requestStatus = false
local rosterRequestRetryAt
local rosterRequestRetries = 0
local versionCheckStartedAt
local versionCheckActive = false
local updateIconBar

local function getSettings()
    InterruptCoordinatorDB = InterruptCoordinatorDB or {}
    InterruptCoordinatorDB.layout = InterruptCoordinatorDB.layout or {}
    local layout = InterruptCoordinatorDB.layout
    layout.primarySize = math.max(40, math.min(96, tonumber(layout.primarySize) or 64))
    layout.iconSize = math.max(20, math.min(48, tonumber(layout.iconSize) or 32))
    local legacyIconsPerRow = tonumber(layout.iconsPerRow) or 6
    local legacyMaxRows = tonumber(layout.maxRows) or 3
    local legacyRowGap = tonumber(layout.rowGap) or 0
    layout.interruptsPerRow = math.max(1, math.min(10, tonumber(layout.interruptsPerRow) or legacyIconsPerRow))
    layout.interruptsMaxRows = math.max(1, math.min(10, tonumber(layout.interruptsMaxRows) or legacyMaxRows))
    layout.interruptsRowGap = math.max(0, math.min(32, tonumber(layout.interruptsRowGap) or legacyRowGap))
    layout.secondaryPerRow = math.max(1, math.min(10, tonumber(layout.secondaryPerRow) or legacyIconsPerRow))
    layout.secondaryMaxRows = math.max(1, math.min(10, tonumber(layout.secondaryMaxRows) or legacyMaxRows))
    layout.secondaryRowGap = math.max(0, math.min(32, tonumber(layout.secondaryRowGap) or legacyRowGap))
    layout.padding = math.max(0, math.min(32, tonumber(layout.padding) or 8))
    layout.primaryGap = math.max(0, math.min(48, tonumber(layout.primaryGap) or 8))
    layout.interruptGap = math.max(0, math.min(48, tonumber(layout.interruptGap) or 0))
    layout.sectionGap = math.max(0, math.min(48, tonumber(layout.sectionGap) or 6))
    layout.iconGap = math.max(0, math.min(24, tonumber(layout.iconGap) or 6))
    layout.showSecondary = layout.showSecondary ~= false
    if type(layout.secondaryBlacklist) ~= "table" then
        layout.secondaryBlacklist = {}
    end
    layout.showPrimaryHeader = layout.showPrimaryHeader == true
    layout.interruptsDetached = layout.interruptsDetached == true
    layout.showInterruptHeader = layout.showInterruptHeader ~= false
    layout.showSecondaryHeader = layout.showSecondaryHeader ~= false
    if type(layout.panelColors) ~= "table" then
        layout.panelColors = {}
    end
    local defaultColors = {
        primary = { 0.02, 0.02, 0.02, 0.82 },
        interrupts = { 0.02, 0.02, 0.02, 0.82 },
        secondary = { 0.02, 0.02, 0.02, 0.82 },
    }
    for component, defaults in pairs(defaultColors) do
        local color = layout.panelColors[component]
        if type(color) ~= "table" then
            color = {}
        end
        for channel = 1, 4 do
            color[channel] = math.max(0, math.min(1, tonumber(color[channel]) or defaults[channel]))
        end
        layout.panelColors[component] = color
    end
    for _, component in ipairs({ "primary", "interrupts", "secondary" }) do
        layout[component .. "OffsetX"] = math.max(-10000, math.min(10000, tonumber(layout[component .. "OffsetX"]) or 0))
        layout[component .. "OffsetY"] = math.max(-10000, math.min(10000, tonumber(layout[component .. "OffsetY"]) or 0))
    end
    layout.hidden = layout.hidden == true
    layout.x = math.max(-800, math.min(800, tonumber(layout.x) or 0))
    layout.y = math.max(-500, math.min(500, tonumber(layout.y) or 0))
    return layout
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

local function nameKey(name)
    return string.lower((name or ""):gsub("%s+", ""))
end

local function getRaidMemberCount()
    if GetNumRaidMembers then
        return GetNumRaidMembers()
    end
    if GetNumGroupMembers and IsInRaid and IsInRaid() then
        return GetNumGroupMembers()
    end
    return 0
end

local function getPartyMemberCount()
    if GetNumPartyMembers then
        return GetNumPartyMembers()
    end
    if GetNumGroupMembers and not (IsInRaid and IsInRaid()) then
        return math.max(0, GetNumGroupMembers() - 1)
    end
    return 0
end

local function getChannel()
    if getRaidMemberCount() > 0 then
        return "RAID"
    end
    if getPartyMemberCount() > 0 then
        return "PARTY"
    end
    return nil
end

local function sendMessage(message)
    local channel = getChannel()
    if not channel then
        return
    end

    if SendAddonMessage then
        SendAddonMessage(PREFIX, message, channel)
    elseif C_ChatInfo and C_ChatInfo.SendAddonMessage then
        C_ChatInfo.SendAddonMessage(PREFIX, message, channel)
    end
end

local function getRoster()
    local roster = {}
    local raidCount = getRaidMemberCount()
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
        for index = 1, getPartyMemberCount() do
            addUnit("party" .. index)
        end
    end
    return roster
end

local function findPetAction(spellId)
    local _, _, spellTexture = GetSpellInfo(spellId)
    if not spellTexture then
        return nil
    end

    for actionIndex = 1, 10 do
        local _, _, actionTexture = GetPetActionInfo(actionIndex)
        if actionTexture and actionTexture == spellTexture then
            return actionIndex
        end
    end
    return nil
end

local function getCooldown(spellId, isPet)
    local startTime, duration
    if isPet then
        local actionIndex = findPetAction(spellId)
        if not actionIndex then
            return nil
        end
        startTime, duration = GetPetActionCooldown(actionIndex)
    else
        startTime, duration = GetSpellCooldown(spellId)
    end

    if not startTime or not duration then
        return 0
    end

    if duration > 0 and duration <= MAX_GLOBAL_COOLDOWN_DURATION then
        return 0
    end

    local remaining = math.max(0, startTime + duration - GetTime())
    return remaining
end

local function collectLocalAbilities()
    local _, playerClass = UnitClass("player")
    local _, playerRace = UnitRace("player")
    playerRace = playerRace and string.upper(playerRace)
    local abilities = {}

    for _, entry in ipairs(abilityCatalog) do
        if entry.class == playerClass or entry.race == playerRace then
            for _, spellId in ipairs(entry.ids) do
                local known = entry.pet and findPetAction(spellId) ~= nil or (not entry.pet and IsSpellKnown(spellId))
                if known then
                    abilities[#abilities + 1] = {
                        id = spellId,
                        cooldown = entry.cooldown,
                        remaining = getCooldown(spellId, entry.pet) or 0,
                    }
                    break
                end
            end
        end
    end
    synchronizeSharedCooldowns(abilities)
    return abilities
end

local function clearEstimatesForReportedAbilities(memberKey, abilities)
    local reportedCatalogEntries = {}
    for _, ability in ipairs(abilities) do
        local catalogEntry = catalogById[ability.id]
        if catalogEntry then
            reportedCatalogEntries[catalogEntry] = true
        end
    end

    local estimates = combatEstimates[memberKey]
    if estimates then
        for spellId in pairs(estimates) do
            if reportedCatalogEntries[catalogById[spellId]] then
                estimates[spellId] = nil
            end
        end
    end
end

local function formatRemaining(seconds)
    if seconds <= 0 then
        return "CD ready"
    end
    return "CD " .. math.ceil(seconds) .. "s"
end

local function publishLocalStatus()
    localAbilities = collectLocalAbilities()
    localKey = nameKey(getFullName("player"))
    local dead = UnitIsDeadOrGhost("player")
    clearEstimatesForReportedAbilities(localKey, localAbilities)
    reports[localKey] = {
        abilities = localAbilities,
        dead = dead,
        receivedAt = GetTime(),
    }

    local parts = {}
    for _, ability in ipairs(localAbilities) do
        parts[#parts + 1] = ability.id .. ":" .. math.ceil(ability.remaining)
    end
    sendMessage("S|" .. (dead and "1" or "0") .. "|" .. table.concat(parts, ","))
end

local function requestGroupStatus()
    sendMessage("Q")
end

local function senderIsInGroup(sender)
    local senderKey = nameKey(sender)
    for _, member in ipairs(getRoster()) do
        if member.key == senderKey then
            return true
        end
    end
    return false
end

local function receiveStatus(sender, payload)
    local deadFlag, abilityList = payload:match("^S|([01])|(.*)$")
    if not deadFlag then
        return
    end

    local abilities = {}
    for item in abilityList:gmatch("[^,]+") do
        local spellText, remainingText = item:match("^(%d+):(%d+)$")
        local spellId = tonumber(spellText)
        local remaining = tonumber(remainingText)
        local catalogEntry = spellId and catalogById[spellId]
        if catalogEntry and remaining then
            abilities[#abilities + 1] = {
                id = spellId,
                cooldown = catalogEntry.cooldown,
                remaining = remaining,
            }
        end
    end
    synchronizeSharedCooldowns(abilities)

    local memberKey = nameKey(sender)
    clearEstimatesForReportedAbilities(memberKey, abilities)
    reports[memberKey] = {
        abilities = abilities,
        dead = deadFlag == "1",
        receivedAt = GetTime(),
    }
end

local function getClientInterfaceVersion()
    if not GetBuildInfo then
        return 0
    end
    local _, _, _, interface = GetBuildInfo()
    return tonumber(interface) or 0
end

local function updateVersionStatus(finalized)
    if not versionStatusText or not versionCheckStartedAt then
        return
    end

    local roster = getRoster()
    local current = 0
    local different = 0
    local noReply = 0
    local pending = 0
    for _, member in ipairs(roster) do
        local response = versionReports[member.key]
        if not member.online then
            noReply = noReply + 1
        elseif response then
            if response.version == ADDON_VERSION and response.interface == 20503 then
                current = current + 1
            else
                different = different + 1
            end
        elseif finalized then
            noReply = noReply + 1
        else
            pending = pending + 1
        end
    end

    local text = "Versions: " .. current .. " current, " .. different .. " different"
    if finalized then
        text = text .. ", " .. noReply .. " no reply"
    else
        text = text .. ", waiting on " .. pending
    end
    versionStatusText:SetText(text)
end

local function printVersionResults()
    print("Interrupt Coordinator version check (addon " .. ADDON_VERSION .. ", interface 20503):")
    for _, member in ipairs(getRoster()) do
        local response = versionReports[member.key]
        if response then
            local state = response.version == ADDON_VERSION and response.interface == 20503 and "current" or "DIFFERENT"
            print("  " .. member.name .. ": addon " .. response.version .. ", interface " .. response.interface .. " (" .. state .. ")")
        else
            print("  " .. member.name .. ": no response (addon unavailable or incompatible)")
        end
    end
end

local function checkGroupVersions()
    versionReports = {}
    versionCheckStartedAt = GetTime()
    versionCheckActive = true
    local playerName = getFullName("player")
    if playerName then
        versionReports[nameKey(playerName)] = {
            version = ADDON_VERSION,
            interface = getClientInterfaceVersion(),
        }
    end
    if versionStatusText then
        versionStatusText:SetText("Checking party/raid addon versions...")
    end
    sendMessage("VQ")
end

local function reportHasCatalogEntry(report, catalogEntry)
    if not report then
        return false
    end
    for _, ability in ipairs(report.abilities) do
        if catalogById[ability.id] == catalogEntry then
            return true
        end
    end
    return false
end

local function recordEstimatedInterrupt(sourceName, spellId)
    local catalogEntry = catalogById[spellId]
    if not catalogEntry or not sourceName then
        return false
    end
    local sourceKey = nameKey(sourceName)
    local memberKey = sourceKey
    local memberFound = false
    for _, member in ipairs(getRoster()) do
        if member.key == sourceKey then
            memberFound = true
            break
        end
        local petUnit = "pet"
        if member.unit ~= "player" then
            local partyIndex = member.unit:match("^party(%d+)$")
            local raidIndex = member.unit:match("^raid(%d+)$")
            if partyIndex then
                petUnit = "partypet" .. partyIndex
            elseif raidIndex then
                petUnit = "raidpet" .. raidIndex
            end
        end
        local petName = UnitName(petUnit)
        if petName and nameKey(petName) == sourceKey then
            memberKey = member.key
            memberFound = true
            break
        end
    end
    if not memberFound then
        return false
    end

    if reportHasCatalogEntry(reports[memberKey], catalogEntry) then
        return false
    end

    local now = GetTime()
    combatEstimates[memberKey] = combatEstimates[memberKey] or {}
    local existing = combatEstimates[memberKey][spellId]
    if existing and existing.id == spellId and now - existing.usedAt < 0.5 then
        return false
    end
    combatEstimates[memberKey][spellId] = {
        id = spellId,
        cooldown = catalogEntry.cooldown,
        usedAt = now,
    }
    if panelReady then
        updateIconBar()
    end
    return true
end

local function handleCombatLog(...)
    local eventArgs = { ... }
    if CombatLogGetCurrentEventInfo then
        eventArgs = { CombatLogGetCurrentEventInfo() }
    end
    local eventType = eventArgs[2]
    if eventType ~= "SPELL_CAST_SUCCESS" and eventType ~= "SPELL_INTERRUPT" then
        return
    end
    local sourceName = eventArgs[5]
    local spellId = tonumber(eventArgs[12])
    if spellId and recordEstimatedInterrupt(sourceName, spellId) then
        sendMessage("E|" .. sourceName .. "|" .. spellId)
    end
end

local function handleAddonMessage(sender, message)
    if message == "Q" then
        publishLocalStatus()
    elseif message:sub(1, 2) == "S|" then
        receiveStatus(sender, message)
    elseif message == "VQ" then
        sendMessage("V|" .. ADDON_VERSION .. "|" .. getClientInterfaceVersion())
    elseif message:sub(1, 2) == "V|" then
        local version, interface = message:match("^V|([^|]+)|(%d+)$")
        if version then
            versionReports[nameKey(sender)] = {
                version = version,
                interface = tonumber(interface),
            }
            updateVersionStatus(false)
        end
    elseif message:sub(1, 2) == "E|" then
        local sourceName, spellText = message:match("^E|([^|]+)|(%d+)$")
        local spellId = tonumber(spellText)
        if spellId then
            recordEstimatedInterrupt(sourceName, spellId)
        end
    end
end

local function getBestAbility(report, now, estimates)
    local best
    local sharedCooldowns = {}
    estimates = estimates or {}

    for _, ability in ipairs(report.abilities) do
        local estimate = estimates[ability.id]
        local remaining = estimate and estimate.usedAt > report.receivedAt
            and math.max(0, estimate.cooldown - (now - estimate.usedAt))
            or math.max(0, ability.remaining - (now - report.receivedAt))
        local catalogEntry = catalogById[ability.id]
        local group = catalogEntry and catalogEntry.sharedCooldownGroup
        if group and remaining > 0 then
            local elapsed = math.max(0, ability.cooldown - remaining)
            sharedCooldowns[group] = math.min(sharedCooldowns[group] or elapsed, elapsed)
        end
    end
    for spellId, estimate in pairs(estimates) do
        if estimate.usedAt > report.receivedAt then
            local catalogEntry = catalogById[spellId]
            local group = catalogEntry and catalogEntry.sharedCooldownGroup
            local remaining = math.max(0, estimate.cooldown - (now - estimate.usedAt))
            if group and remaining > 0 then
                local elapsed = math.max(0, estimate.cooldown - remaining)
                sharedCooldowns[group] = math.min(sharedCooldowns[group] or elapsed, elapsed)
            end
        end
    end

    for _, ability in ipairs(report.abilities) do
        local estimate = estimates[ability.id]
        local remaining = estimate and estimate.usedAt > report.receivedAt
            and math.max(0, estimate.cooldown - (now - estimate.usedAt))
            or math.max(0, ability.remaining - (now - report.receivedAt))
        local catalogEntry = catalogById[ability.id]
        local group = catalogEntry and catalogEntry.sharedCooldownGroup
        if group then
            local elapsed = sharedCooldowns[group]
            if elapsed then
                remaining = math.max(remaining, math.max(0, ability.cooldown - elapsed))
            end
        end
        if not best or remaining < best.remaining or (remaining == best.remaining and ability.cooldown < best.cooldown) then
            best = {
                id = ability.id,
                cooldown = ability.cooldown,
                remaining = remaining,
            }
        end
    end
    return best
end

local function createRow(index)
    local row = {
        name = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal"),
        ability = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"),
        state = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"),
    }
    row.name:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 4, -((index - 1) * 23))
    row.name:SetWidth(120)
    row.name:SetJustifyH("LEFT")
    row.ability:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 126, -((index - 1) * 23))
    row.ability:SetWidth(155)
    row.ability:SetJustifyH("LEFT")
    row.state:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 285, -((index - 1) * 23))
    row.state:SetWidth(115)
    row.state:SetJustifyH("LEFT")
    rows[index] = row
    return row
end

local function updatePanel()
    if not panelReady then
        return
    end

    local roster = getRoster()
    local now = GetTime()
    local candidates = {}
    local coordinatorAvailable = false

    for _, member in ipairs(roster) do
        local report = reports[member.key]
        if report and member.online and not member.dead and not report.dead and now - report.receivedAt <= STALE_SECONDS then
            local best = getBestAbility(report, now, combatEstimates[member.key])
            if best then
                candidates[#candidates + 1] = {
                    member = member,
                    ability = best,
                    ready = best.remaining <= 0,
                }
            end
        end
        if member.key == localKey then
            coordinatorAvailable = report ~= nil
        end
    end

    table.sort(candidates, function(left, right)
        if left.ready ~= right.ready then
            return left.ready
        end
        if left.ready and left.ability.cooldown ~= right.ability.cooldown then
            return left.ability.cooldown < right.ability.cooldown
        end
        if not left.ready and left.ability.remaining ~= right.ability.remaining then
            return left.ability.remaining < right.ability.remaining
        end
        return left.member.key < right.member.key
    end)

    local primary = candidates[1]
    local backup = primary and primary.ready and candidates[2] and candidates[2].ready and candidates[2] or nil
    if primary and primary.ready then
        local spellName = GetSpellInfo(primary.ability.id) or "Interrupt"
        primaryText:SetText("Primary: " .. primary.member.name .. " - " .. spellName)
    elseif primary then
        primaryText:SetText("No cooldown-ready report; next: " .. primary.member.name .. " (" .. formatRemaining(primary.ability.remaining) .. ")")
    else
        primaryText:SetText("Primary: none reported ready")
    end

    if backup then
        backupText:SetText("Backup: " .. backup.member.name .. " - " .. (GetSpellInfo(backup.ability.id) or "Interrupt"))
    else
        backupText:SetText("Backup: none reported ready")
    end

    statusText:SetText(coordinatorAvailable and "Shared cooldown reports | assignments calculated from current reports" or "Waiting for local status")

    local visibleCount = 0
    for index, member in ipairs(roster) do
        visibleCount = index
        local row = rows[index] or createRow(index)
        local report = reports[member.key]
        row.name:SetText(member.name)

        if not member.online then
            row.ability:SetText("")
            row.state:SetText("|cffaaaaaaOffline|r")
        elseif member.dead or (report and report.dead) then
            row.ability:SetText("")
            row.state:SetText("|cffff5555Dead|r")
        elseif not report then
            row.ability:SetText("")
            row.state:SetText("")
        elseif now - report.receivedAt > STALE_SECONDS then
            row.ability:SetText("")
            row.state:SetText("|cffffcc55Stale report|r")
        else
            local best = getBestAbility(report, now)
            if best then
                row.ability:SetText(GetSpellInfo(best.id) or "Interrupt")
                row.state:SetText(best.remaining <= 0 and "|cff55dd77CD ready|r" or "|cffffcc55" .. formatRemaining(best.remaining) .. "|r")
            else
                row.ability:SetText("")
                row.state:SetText("|cffffcc55No tracked ability|r")
            end
        end
    end

    for index = visibleCount + 1, #rows do
        rows[index].name:SetText("")
        rows[index].ability:SetText("")
        rows[index].state:SetText("")
    end
    scrollChild:SetHeight(math.max(1, visibleCount * 23))
end

local function createPanel()
    if panelReady then
        return
    end

    local backdropTemplate = BackdropTemplateMixin and "BackdropTemplate" or nil
    frame = CreateFrame("Frame", nil, UIParent, backdropTemplate)
    frame:Hide()
    frame:SetSize(475, 345)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
    else
        local background = frame:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(frame)
        background:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Background")
    end
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetClampedToScreen then
        frame:SetClampedToScreen(true)
    end

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
    title:SetText("Interrupt Coordinator")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)

    primaryText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    primaryText:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -46)
    primaryText:SetWidth(435)
    primaryText:SetJustifyH("LEFT")

    backupText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    backupText:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -67)
    backupText:SetWidth(435)
    backupText:SetJustifyH("LEFT")

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -88)
    statusText:SetWidth(435)
    statusText:SetJustifyH("LEFT")

    local headerName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerName:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -112)
    headerName:SetText("Member")
    local headerAbility = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerAbility:SetPoint("TOPLEFT", frame, "TOPLEFT", 142, -112)
    headerAbility:SetText("Interrupt")
    local headerState = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerState:SetPoint("TOPLEFT", frame, "TOPLEFT", 301, -112)
    headerState:SetText("Cooldown report")

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -132)
    scrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 16)
    scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(425, 1)
    scrollFrame:SetScrollChild(scrollChild)

    panelReady = true
    frame:Hide()
    updatePanel()
end

local positionControls = {}

local function syncPositionControls()
    for key, control in pairs(positionControls) do
        control.value:SetText(tostring(settings[key]))
        control.slider:SetValue(settings[key])
    end
end

local function beginComponentDrag(component)
    if not component then
        return
    end
    if component == "interrupts" and not settings.interruptsDetached then
        component = "primary"
    end
    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetScale()
    componentDrag = {
        component = component,
        startX = cursorX / scale,
        startY = cursorY / scale,
        initialX = settings[component .. "OffsetX"],
        initialY = settings[component .. "OffsetY"],
        initialInterruptX = settings.interruptsOffsetX,
        initialInterruptY = settings.interruptsOffsetY,
    }
end

local function enableShiftDrag(target)
    target:RegisterForDrag("LeftButton")
    target:SetScript("OnDragStart", function()
        if editMode then
            beginComponentDrag(target.layoutComponent)
        elseif IsShiftKeyDown and IsShiftKeyDown() then
            local cursorX, cursorY = GetCursorPosition()
            local scale = UIParent:GetScale()
            componentDrag = {
                bar = true,
                startX = cursorX / scale,
                startY = cursorY / scale,
                initialX = settings.x,
                initialY = settings.y,
            }
        end
    end)
    target:SetScript("OnDragStop", function()
        if componentDrag then
            updateComponentDrag()
            componentDrag = nil
        end
    end)
end

local function getClassColor(class)
    local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not color then
        return "|cffffffff", 1, 1, 1
    end
    return string.format("|cff%02x%02x%02x", math.floor(color.r * 255), math.floor(color.g * 255), math.floor(color.b * 255)), color.r, color.g, color.b
end

local function createAbilityButton(parent, size)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size, size)
    button:SetFrameLevel(parent:GetFrameLevel() + 2)
    button.texture = button:CreateTexture(nil, "ARTWORK")
    button.texture:SetAllPoints(button)
    button.texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    button.cooldownFrame = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    button.cooldownFrame:SetAllPoints(button)
    button.hasOmniCC = IsAddOnLoaded and IsAddOnLoaded("OmniCC") or false
    button.cooldownText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.cooldownText:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.cooldownText:SetTextColor(1, 1, 1)
    button.stateText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.stateText:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    button.stateText:SetTextColor(1, 1, 1)
    button.memberName = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.memberName:SetPoint("TOP", button, "BOTTOM", 0, -1)
    button.memberName:SetJustifyH("CENTER")
    button.entry = nil
    button:SetScript("OnEnter", function(self)
        local entry = self.entry
        if not entry then
            return
        end
        local spellName = GetSpellInfo(entry.ability.id) or "Interrupt"
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local prefix, red, green, blue = getClassColor(entry.member.class)
        GameTooltip:AddLine(prefix .. entry.member.name .. "|r", red, green, blue)
        GameTooltip:AddLine(spellName, 1, 1, 1)
        GameTooltip:AddLine(entry.stateText, 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    enableShiftDrag(button)
    return button
end

local function updateAbilityButton(button, entry, size)
    button:SetSize(size, size)
    button.entry = entry
    local _, _, texture = GetSpellInfo(entry.ability.id)
    button.texture:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
    local name = entry.member.name:match("^([^-]+)") or entry.member.name
    button.memberName:SetText(name)
    button.memberName:SetWidth(math.max(size, 64))
    local _, red, green, blue = getClassColor(entry.member.class)
    button.memberName:SetTextColor(red, green, blue)

    local unavailable = entry.state == "Offline" or entry.state == "Dead" or entry.state == "Stale" or entry.state == "Unknown"
    if button.texture.SetDesaturated then
        button.texture:SetDesaturated(unavailable or entry.ability.remaining > 0 or entry.estimated)
    end

    local showCooldown = (entry.state == "Cooldown" or entry.state == "EstimatedCooldown") and entry.ability.remaining > 0
    if showCooldown then
        local duration = math.max(entry.ability.cooldown, entry.ability.remaining)
        local start = GetTime() - (duration - entry.ability.remaining)
        if not button.cooldownStart or math.abs(button.cooldownStart - start) > 0.05 or button.cooldownDuration ~= duration then
            button.cooldownFrame:SetCooldown(start, duration)
            button.cooldownStart = start
            button.cooldownDuration = duration
        end
        button.cooldownText:SetText(button.hasOmniCC and "" or tostring(math.ceil(entry.ability.remaining)))
    elseif button.cooldownStart then
        button.cooldownFrame:SetCooldown(0, 0)
        button.cooldownStart = nil
        button.cooldownDuration = nil
        button.cooldownText:SetText("")
    else
        button.cooldownText:SetText("")
    end

    if entry.estimated then
        button.stateText:SetText("~")
    elseif entry.state == "Unknown" or entry.state == "Stale" then
        button.stateText:SetText("?")
    elseif entry.state == "Dead" then
        button.stateText:SetText("X")
    else
        button.stateText:SetText("")
    end
end

local function getIconEntries(roster, now)
    local entries = {}
    local candidates = {}

    local function addEntry(member, spellId, ability, state, estimated)
        local catalogEntry = catalogById[spellId]
        if catalogEntry and catalogEntry.secondary
            and settings.secondaryBlacklist[tostring(catalogEntry.ids[1])] then
            return
        end
        local entry = {
            key = member.key .. ":" .. spellId,
            member = member,
            ability = ability,
            state = state,
            estimated = estimated,
            category = catalogEntry and catalogEntry.secondary and "secondary" or "interrupt",
        }
        entry.stateText = state == "Ready" and "Ready"
            or state == "Cooldown" and formatRemaining(ability.remaining)
            or state == "EstimatedReady" and "Estimated ready"
            or state == "EstimatedCooldown" and ("Estimated " .. formatRemaining(ability.remaining))
            or state == "Unknown" and "Cooldown unknown; no report or cast seen"
            or state
        entries[#entries + 1] = entry
        if entry.category == "interrupt" and (state == "Ready" or state == "Cooldown" or state == "EstimatedReady" or state == "EstimatedCooldown") then
            candidates[#candidates + 1] = entry
        end
    end

    for _, member in ipairs(roster) do
        local report = reports[member.key]
        local hasFreshReport = report and now - report.receivedAt <= STALE_SECONDS
        local estimates = combatEstimates[member.key] or {}
        local reportedIds = {}
        local sharedCooldowns = {}

        local function includeSharedCooldown(spellId, remaining, estimated)
            local catalogEntry = catalogById[spellId]
            local group = catalogEntry and catalogEntry.sharedCooldownGroup
            if not group or remaining <= 0 then
                return
            end
            local elapsed = math.max(0, catalogEntry.cooldown - remaining)
            local shared = sharedCooldowns[group]
            if not shared or elapsed < shared.elapsed then
                sharedCooldowns[group] = { elapsed = elapsed, estimated = estimated }
            elseif elapsed == shared.elapsed and not estimated then
                shared.estimated = false
            end
        end

        if hasFreshReport then
            for _, reportedAbility in ipairs(report.abilities) do
                local estimate = estimates[reportedAbility.id]
                local estimated = estimate and estimate.usedAt > report.receivedAt
                local remaining = estimated
                    and math.max(0, estimate.cooldown - (now - estimate.usedAt))
                    or math.max(0, reportedAbility.remaining - (now - report.receivedAt))
                includeSharedCooldown(reportedAbility.id, remaining, estimated)
            end
        end
        for spellId, estimate in pairs(estimates) do
            if not hasFreshReport or not report or estimate.usedAt > report.receivedAt then
                includeSharedCooldown(
                    spellId,
                    math.max(0, estimate.cooldown - (now - estimate.usedAt)),
                    true
                )
            end
        end

        local function applySharedCooldown(spellId, ability, estimated)
            local catalogEntry = catalogById[spellId]
            local shared = catalogEntry and catalogEntry.sharedCooldownGroup
                and sharedCooldowns[catalogEntry.sharedCooldownGroup]
            local linkedRemaining = shared and math.max(0, ability.cooldown - shared.elapsed)
            if linkedRemaining and linkedRemaining > ability.remaining then
                ability.remaining = linkedRemaining
                estimated = estimated or shared.estimated
            end
            return estimated
        end

        if hasFreshReport then
            for _, reportedAbility in ipairs(report.abilities) do
                local estimate = estimates[reportedAbility.id]
                local estimated = estimate and estimate.usedAt > report.receivedAt
                local ability = estimated and {
                    id = estimate.id,
                    cooldown = estimate.cooldown,
                    remaining = math.max(0, estimate.cooldown - (now - estimate.usedAt)),
                } or {
                    id = reportedAbility.id,
                    cooldown = reportedAbility.cooldown,
                    remaining = math.max(0, reportedAbility.remaining - (now - report.receivedAt)),
                }
                estimated = applySharedCooldown(ability.id, ability, estimated)
                local state = not member.online and "Offline"
                    or (member.dead or report.dead) and "Dead"
                    or estimated and (ability.remaining <= 0 and "EstimatedReady" or "EstimatedCooldown")
                    or ability.remaining <= 0 and "Ready"
                    or "Cooldown"
                addEntry(member, ability.id, ability, state, estimated)
                reportedIds[reportedAbility.id] = true
            end
            for spellId, estimate in pairs(estimates) do
                if not reportedIds[spellId] then
                    local ability = {
                        id = spellId,
                        cooldown = estimate.cooldown,
                        remaining = math.max(0, estimate.cooldown - (now - estimate.usedAt)),
                    }
                    applySharedCooldown(spellId, ability, true)
                    local state = not member.online and "Offline"
                        or member.dead and "Dead"
                        or ability.remaining <= 0 and "EstimatedReady"
                        or "EstimatedCooldown"
                    addEntry(member, spellId, ability, state, true)
                end
            end
        else
            for spellId, estimate in pairs(estimates) do
                local ability = {
                    id = spellId,
                    cooldown = estimate.cooldown,
                    remaining = math.max(0, estimate.cooldown - (now - estimate.usedAt)),
                }
                applySharedCooldown(spellId, ability, true)
                local state = not member.online and "Offline"
                    or member.dead and "Dead"
                    or ability.remaining <= 0 and "EstimatedReady"
                    or "EstimatedCooldown"
                addEntry(member, spellId, ability, state, true)
            end

            if report then
                for _, reportedAbility in ipairs(report.abilities) do
                    if not estimates[reportedAbility.id] then
                        local ability = {
                            id = reportedAbility.id,
                            cooldown = reportedAbility.cooldown,
                            remaining = reportedAbility.remaining,
                        }
                        addEntry(member, ability.id, ability, "Stale", false)
                    end
                end
            end

        end

    end

    table.sort(candidates, function(left, right)
        local priorities = { Ready = 1, EstimatedReady = 2, Cooldown = 3, EstimatedCooldown = 4 }
        if priorities[left.state] ~= priorities[right.state] then
            return priorities[left.state] < priorities[right.state]
        end
        if (left.state == "Ready" or left.state == "EstimatedReady") and left.ability.cooldown ~= right.ability.cooldown then
            return left.ability.cooldown < right.ability.cooldown
        end
        if left.ability.remaining ~= right.ability.remaining then
            return left.ability.remaining < right.ability.remaining
        end
        if left.member.key ~= right.member.key then
            return left.member.key < right.member.key
        end
        return left.ability.id < right.ability.id
    end)

    table.sort(entries, function(left, right)
        local activeStates = { Ready = 1, EstimatedReady = 2, Cooldown = 3, EstimatedCooldown = 4 }
        local leftActive = activeStates[left.state] ~= nil
        local rightActive = activeStates[right.state] ~= nil
        if leftActive ~= rightActive then
            return leftActive
        end
        if leftActive and activeStates[left.state] ~= activeStates[right.state] then
            return activeStates[left.state] < activeStates[right.state]
        end
        if leftActive and left.ability.remaining ~= right.ability.remaining then
            return left.ability.remaining < right.ability.remaining
        end
        if left.member.key ~= right.member.key then
            return left.member.key < right.member.key
        end
        return left.ability.id < right.ability.id
    end)
    return entries, candidates
end

local function setComponentPanel(component, x, y, width, height, visible)
    local panel = componentPanels[component]
    if not panel then
        panel = CreateFrame("Frame", nil, frame)
        panel:SetFrameLevel(frame:GetFrameLevel() + 1)
        panel.texture = frame:CreateTexture(nil, "BACKGROUND")
        panel.texture:SetAllPoints(panel)
        panel.texture:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
        panel.editLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        panel.editLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)
        panel.editLabel:SetText(component == "primary" and "Primary" or component == "interrupts" and "Other interrupts" or "Secondary stops")
        panel.editBorder = {}
        for index = 1, 4 do
            local edge = panel:CreateTexture(nil, "OVERLAY")
            edge:SetTexture("Interface\\Buttons\\WHITE8X8")
            edge:SetVertexColor(1, 0.8, 0.1, 0.9)
            panel.editBorder[index] = edge
        end
        panel.editBorder[1]:SetPoint("TOPLEFT", panel, "TOPLEFT")
        panel.editBorder[1]:SetPoint("TOPRIGHT", panel, "TOPRIGHT")
        panel.editBorder[1]:SetHeight(2)
        panel.editBorder[2]:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT")
        panel.editBorder[2]:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT")
        panel.editBorder[2]:SetHeight(2)
        panel.editBorder[3]:SetPoint("TOPLEFT", panel, "TOPLEFT")
        panel.editBorder[3]:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT")
        panel.editBorder[3]:SetWidth(2)
        panel.editBorder[4]:SetPoint("TOPRIGHT", panel, "TOPRIGHT")
        panel.editBorder[4]:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT")
        panel.editBorder[4]:SetWidth(2)
        panel:RegisterForDrag("LeftButton")
        panel:SetMovable(true)
        panel:SetScript("OnDragStart", function(self)
            if not editMode then
                return
            end
            beginComponentDrag(component)
        end)
        panel:SetScript("OnDragStop", function()
            if componentDrag then
                updateComponentDrag()
                componentDrag = nil
            end
        end)
        componentPanels[component] = panel
    end

    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
    panel:SetSize(math.max(1, width), math.max(1, height))
    panel.texture:SetVertexColor(unpack(settings.panelColors[component]))
    panel:EnableMouse(editMode)
    if editMode then
        panel.editLabel:Show()
        for _, edge in ipairs(panel.editBorder) do
            edge:Show()
        end
    else
        panel.editLabel:Hide()
        for _, edge in ipairs(panel.editBorder) do
            edge:Hide()
        end
    end
    if visible then
        panel.texture:Show()
        panel:Show()
    else
        panel.texture:Hide()
        panel:Hide()
    end
end

updateComponentDrag = function()
    if not componentDrag then
        return
    end

    local cursorX, cursorY = GetCursorPosition()
    local scale = UIParent:GetScale()
    local deltaX = cursorX / scale - componentDrag.startX
    local deltaY = cursorY / scale - componentDrag.startY
    if componentDrag.bar then
        settings.x = math.max(-800, math.min(800, math.floor(componentDrag.initialX + deltaX + 0.5)))
        settings.y = math.max(-500, math.min(500, math.floor(componentDrag.initialY + deltaY + 0.5)))
        InterruptCoordinatorDB.layout.x = settings.x
        InterruptCoordinatorDB.layout.y = settings.y
        settings.point = "CENTER"
        syncPositionControls()
        updateIconBar()
        return
    end

    local component = componentDrag.component
    local xOffset = math.max(-10000, math.min(10000, math.floor(componentDrag.initialX + deltaX + 0.5)))
    local yOffset = math.max(-10000, math.min(10000, math.floor(componentDrag.initialY + deltaY + 0.5)))
    settings[component .. "OffsetX"] = xOffset
    settings[component .. "OffsetY"] = yOffset
    InterruptCoordinatorDB.layout[component .. "OffsetX"] = xOffset
    InterruptCoordinatorDB.layout[component .. "OffsetY"] = yOffset

    if component == "primary" and not settings.interruptsDetached then
        settings.interruptsOffsetX = math.max(-10000, math.min(10000, math.floor(componentDrag.initialInterruptX + deltaX + 0.5)))
        settings.interruptsOffsetY = math.max(-10000, math.min(10000, math.floor(componentDrag.initialInterruptY + deltaY + 0.5)))
        InterruptCoordinatorDB.layout.interruptsOffsetX = settings.interruptsOffsetX
        InterruptCoordinatorDB.layout.interruptsOffsetY = settings.interruptsOffsetY
    end

    if updateComponentPositionLabels then
        updateComponentPositionLabels()
    end
    if updateBarPositionControlState then
        updateBarPositionControlState()
    end
    updateIconBar()
end

local function layoutIconCategory(entries, buttons, visibleCount, header, label, component, showHeader, cursor, baseTop, originX, centerX, offsetX, offsetY, iconSize, cellWidth, iconsPerRow, rowGap, rowHeight)
    if visibleCount == 0 then
        header:Hide()
        for index = 1, #buttons do
            buttons[index]:Hide()
        end
        return cursor
    end

    if showHeader then
        header:SetText(label)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", frame, "TOPLEFT", originX + offsetX, -(baseTop + cursor - offsetY))
        header:Show()
        cursor = cursor + 16
    else
        header:Hide()
    end

    local rowCountTotal = math.ceil(visibleCount / iconsPerRow)
    for index = 1, visibleCount do
        local button = buttons[index]
        if not button then
            button = createAbilityButton(frame, iconSize)
            buttons[index] = button
        end
        button.layoutComponent = component
        local row = math.floor((index - 1) / iconsPerRow)
        local column = (index - 1) % iconsPerRow
        local rowCount = math.min(iconsPerRow, visibleCount - row * iconsPerRow)
        local currentRowWidth = rowCount * cellWidth + (rowCount - 1) * settings.iconGap
        local left = centerX + offsetX - currentRowWidth / 2
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", frame, "TOPLEFT", left + column * (cellWidth + settings.iconGap) + (cellWidth - iconSize) / 2, -(baseTop + cursor - offsetY + row * rowHeight))
        updateAbilityButton(button, entries[index], iconSize)
        button.memberName:Show()
        button:Show()
    end
    for index = visibleCount + 1, #buttons do
        buttons[index]:Hide()
    end

    return cursor + rowCountTotal * rowHeight - rowGap + settings.sectionGap
end

updateIconBar = function()
    if not panelReady then
        return
    end

    local roster = getRoster()
    local entries, candidates = getIconEntries(roster, GetTime())
    local primary = candidates[1]
    local interruptEntries = {}
    local secondaryEntries = {}
    for _, entry in ipairs(entries) do
        if not primary or entry.key ~= primary.key then
            if entry.category == "secondary" then
                if settings.showSecondary then
                    secondaryEntries[#secondaryEntries + 1] = entry
                end
            else
                interruptEntries[#interruptEntries + 1] = entry
            end
        end
    end

    if primary then
        local prefix = getClassColor(primary.member.class)
        primaryNameText:SetText(prefix .. primary.member.name .. "|r")
        local primaryDetail = GetSpellInfo(primary.ability.id) or "Interrupt"
        if primary.state == "Cooldown" then
            primaryDetail = primaryDetail .. "  " .. formatRemaining(primary.ability.remaining)
        elseif primary.state == "EstimatedCooldown" then
            primaryDetail = primaryDetail .. "  ~" .. formatRemaining(primary.ability.remaining)
        elseif primary.state == "EstimatedReady" then
            primaryDetail = primaryDetail .. "  ~ready"
        end
        primaryInfoText:SetText(primaryDetail)
        updateAbilityButton(primaryIcon, primary, settings.primarySize)
        primaryIcon.memberName:Hide()
    else
        primaryNameText:SetText("|cffffcc55No primary reported|r")
        primaryInfoText:SetText("Waiting for interrupt reports")
        primaryIcon.texture:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        primaryIcon.texture:SetDesaturated(true)
        primaryIcon.cooldownFrame:SetCooldown(0, 0)
        primaryIcon.cooldownStart = nil
        primaryIcon.cooldownDuration = nil
        primaryIcon.stateText:SetText("")
        primaryIcon.entry = nil
    end

    local visibleInterrupts = math.min(#interruptEntries, settings.interruptsPerRow * settings.interruptsMaxRows)
    local visibleSecondary = math.min(#secondaryEntries, settings.secondaryPerRow * settings.secondaryMaxRows)
    local iconSize = settings.iconSize
    local padding = settings.padding
    local cellWidth = math.max(iconSize, 64)
    local interruptRowHeight = iconSize + 18 + settings.interruptsRowGap
    local secondaryRowHeight = iconSize + 18 + settings.secondaryRowGap
    local primaryHeaderHeight = settings.showPrimaryHeader and 16 or 0
    local function getRowWidth(count, iconsPerRow)
        local columns = math.min(count, iconsPerRow)
        return columns > 0 and columns * cellWidth + (columns - 1) * settings.iconGap or 0
    end
    local rowWidth = math.max(
        getRowWidth(visibleInterrupts, settings.interruptsPerRow),
        getRowWidth(visibleSecondary, settings.secondaryPerRow)
    )
    local baseWidth = math.max(120, settings.primarySize, rowWidth) + padding * 2
    local overflow = (#interruptEntries - visibleInterrupts) + (#secondaryEntries - visibleSecondary)
    local showFooter = overflow > 0
    local primaryEnd = padding + primaryHeaderHeight + 34 + settings.primarySize + settings.primaryGap
    local interruptHeaderHeight = visibleInterrupts > 0 and settings.showInterruptHeader and 16 or 0
    local interruptRows = math.ceil(visibleInterrupts / settings.interruptsPerRow)
    local interruptHeight = visibleInterrupts > 0 and interruptHeaderHeight + interruptRows * interruptRowHeight - settings.interruptsRowGap or 0
    local secondaryHeaderHeight = visibleSecondary > 0 and settings.showSecondaryHeader and 16 or 0
    local secondaryRows = math.ceil(visibleSecondary / settings.secondaryPerRow)
    local secondaryHeight = visibleSecondary > 0 and secondaryHeaderHeight + secondaryRows * secondaryRowHeight - settings.secondaryRowGap or 0
    local panelGap = settings.sectionGap + padding * 2
    local interruptStart = primaryEnd + (visibleInterrupts > 0 and settings.interruptGap or 0)
        + (settings.interruptsDetached and visibleInterrupts > 0 and panelGap or 0)
    local secondaryStart
    if visibleInterrupts > 0 then
        secondaryStart = interruptStart + interruptHeight + panelGap
    else
        secondaryStart = primaryEnd + panelGap
    end
    local centerX = UIParent:GetWidth() / 2 + settings.x
    local stackHeight = primaryEnd + padding
    if visibleInterrupts > 0 then
        stackHeight = stackHeight + settings.interruptGap
            + (settings.interruptsDetached and panelGap or 0) + interruptHeight
    end
    if visibleSecondary > 0 then
        stackHeight = stackHeight + panelGap + secondaryHeight
    end
    if showFooter then
        stackHeight = stackHeight + 20
    end
    local baseTop = (UIParent:GetHeight() - stackHeight) / 2 - settings.y
    local primaryTop = baseTop - settings.primaryOffsetY + padding
    layoutIconCategory(
        interruptEntries, memberIcons, visibleInterrupts, interruptHeaderText, "Other interrupts", "interrupts",
        settings.showInterruptHeader, interruptStart, baseTop, centerX - baseWidth / 2 + padding, centerX,
        settings.interruptsOffsetX, settings.interruptsOffsetY, iconSize, cellWidth,
        settings.interruptsPerRow, settings.interruptsRowGap, interruptRowHeight
    )
    layoutIconCategory(
        secondaryEntries, secondaryIcons, visibleSecondary, secondaryHeaderText, "Secondary stops", "secondary",
        settings.showSecondaryHeader, secondaryStart, baseTop, centerX - baseWidth / 2 + padding, centerX,
        settings.secondaryOffsetX, settings.secondaryOffsetY, iconSize, cellWidth,
        settings.secondaryPerRow, settings.secondaryRowGap, secondaryRowHeight
    )

    setComponentPanel(
        "primary",
        centerX - baseWidth / 2 + settings.primaryOffsetX,
        baseTop - settings.primaryOffsetY,
        baseWidth,
        primaryEnd + padding,
        true
    )
    local primaryPanelLeft = centerX - baseWidth / 2 + settings.primaryOffsetX
    local primaryPanelTop = baseTop - settings.primaryOffsetY
    setComponentPanel(
        "interrupts",
        centerX - baseWidth / 2 + settings.interruptsOffsetX,
        baseTop + interruptStart - settings.interruptsOffsetY - padding,
        baseWidth,
        interruptHeight + padding * 2,
        settings.interruptsDetached and visibleInterrupts > 0
    )
    setComponentPanel(
        "secondary",
        centerX - baseWidth / 2 + settings.secondaryOffsetX,
        baseTop + secondaryStart - settings.secondaryOffsetY - padding,
        baseWidth,
        secondaryHeight + padding * 2,
        visibleSecondary > 0
    )
    if not settings.interruptsDetached and visibleInterrupts > 0 then
        local primaryLeft = centerX - baseWidth / 2 + settings.primaryOffsetX
        local primaryTop = baseTop - settings.primaryOffsetY
        local interruptLeft = centerX - baseWidth / 2 + settings.interruptsOffsetX
        local interruptTop = baseTop + interruptStart - settings.interruptsOffsetY - padding
        local left = math.min(primaryLeft, interruptLeft)
        local top = math.min(primaryTop, interruptTop)
        local right = math.max(primaryLeft + baseWidth, interruptLeft + baseWidth)
        local bottom = math.max(primaryTop + primaryEnd + padding, interruptTop + interruptHeight + padding * 2)
        componentPanels.primary:ClearAllPoints()
        componentPanels.primary:SetPoint("TOPLEFT", frame, "TOPLEFT", left, -top)
        componentPanels.primary:SetSize(right - left, bottom - top)
        primaryPanelLeft = left
        primaryPanelTop = top
    end

    local primaryContentLeft = centerX + settings.primaryOffsetX - primaryPanelLeft
    local primaryContentTop = primaryTop - primaryPanelTop
    if settings.showPrimaryHeader then
        primaryHeaderText:SetText("Primary interrupt")
        primaryHeaderText:ClearAllPoints()
        primaryHeaderText:SetPoint("TOPLEFT", componentPanels.primary, "TOPLEFT", primaryContentLeft - baseWidth / 2 + padding, -primaryContentTop)
        primaryHeaderText:Show()
    else
        primaryHeaderText:Hide()
    end
    primaryNameText:ClearAllPoints()
    primaryNameText:SetPoint("TOP", componentPanels.primary, "TOPLEFT", primaryContentLeft, -primaryContentTop - primaryHeaderHeight)
    primaryNameText:SetWidth(baseWidth - padding * 2)
    primaryInfoText:ClearAllPoints()
    primaryInfoText:SetPoint("TOP", componentPanels.primary, "TOPLEFT", primaryContentLeft, -primaryContentTop - primaryHeaderHeight - 16)
    primaryInfoText:SetWidth(baseWidth - padding * 2)
    primaryIcon:ClearAllPoints()
    primaryIcon:SetPoint("TOP", componentPanels.primary, "TOPLEFT", primaryContentLeft, -primaryContentTop - primaryHeaderHeight - 34)
    primaryIcon:SetSize(settings.primarySize, settings.primarySize)
    primaryIcon.layoutComponent = "primary"
    primaryIcon:SetFrameLevel(frame:GetFrameLevel() + 2)
    primaryIcon:Show()

    if showFooter then
        layoutStatusText:SetText("+" .. overflow .. " more")
        layoutStatusText:Show()
        layoutStatusText:ClearAllPoints()
        local overflowTop = math.max(
            primaryEnd - settings.primaryOffsetY,
            visibleInterrupts > 0 and interruptStart + interruptHeight - settings.interruptsOffsetY or 0,
            visibleSecondary > 0 and secondaryStart + secondaryHeight - settings.secondaryOffsetY or 0
        )
        layoutStatusText:SetPoint("TOP", frame, "TOP", centerX, -(baseTop + overflowTop + padding))
    else
        layoutStatusText:SetText("")
        layoutStatusText:Hide()
    end
end

local function updateConfigLabels()
    if not configFrame then
        return
    end
    for _, row in pairs(configFrame.optionRows) do
        local unit = (row.key == "interruptsPerRow" or row.key == "interruptsMaxRows"
            or row.key == "secondaryPerRow" or row.key == "secondaryMaxRows") and "" or " px"
        row.value:SetText(tostring(settings[row.key]) .. unit)
    end
end

local function addConfigOption(key, label, y, minimum, maximum, step)
    local row = {}
    row.key = key
    row.label = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.label:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 18, y)
    row.label:SetText(label)

    row.value = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.value:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -56, y)
    row.value:SetWidth(48)
    row.value:SetJustifyH("CENTER")

    local function adjust(direction)
        settings[key] = math.max(minimum, math.min(maximum, settings[key] + direction * step))
        InterruptCoordinatorDB.layout[key] = settings[key]
        updateConfigLabels()
        updateIconBar()
    end

    local decrease = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    decrease:SetSize(24, 22)
    decrease:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -108, y + 4)
    decrease:SetText("-")
    decrease:SetScript("OnClick", function() adjust(-1) end)

    local increase = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    increase:SetSize(24, 22)
    increase:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -20, y + 4)
    increase:SetText("+")
    increase:SetScript("OnClick", function() adjust(1) end)

    configFrame.optionRows[#configFrame.optionRows + 1] = row
end

local function setBarVisible(visible)
    if not panelReady then
        return
    end
    settings.hidden = not visible
    InterruptCoordinatorDB.layout.hidden = settings.hidden
    if visible then
        frame:Show()
    else
        frame:Hide()
    end
    if visibilityButton then
        visibilityButton:SetText(visible and "Hide interrupt bar" or "Show interrupt bar")
    end
end

local componentColorSwatches = {}

updateBarPositionControlState = function()
    local freeform = false
    for _, component in ipairs({ "primary", "interrupts", "secondary" }) do
        if settings[component .. "OffsetX"] ~= 0 or settings[component .. "OffsetY"] ~= 0 then
            freeform = true
            break
        end
    end
    for _, key in ipairs({ "x", "y" }) do
        local control = positionControls[key]
        if control then
            if freeform then
                control.slider:Disable()
                control.slider:SetAlpha(0.45)
                control.value:SetText("Custom")
            else
                control.slider:Enable()
                control.slider:SetAlpha(1)
                control.value:SetText(tostring(settings[key]))
            end
        end
    end
end

local function setEditMode(enabled)
    editMode = enabled
    if editMode then
        setBarVisible(true)
    end
    if editModeButton then
        editModeButton:SetText(editMode and "Finish layout editing" or "Edit layout (drag panels)")
    end
    updateIconBar()
end

updateComponentPositionLabels = function()
    for component, label in pairs(componentPositionLabels) do
        label:SetText(component.label .. "  X: " .. settings[component.key .. "OffsetX"] .. "  Y: " .. settings[component.key .. "OffsetY"])
    end
end

local function updateComponentColorSwatches()
    for component, texture in pairs(componentColorSwatches) do
        texture:SetVertexColor(unpack(settings.panelColors[component]))
    end
end

local function openPanelColorPicker(component)
    if not ColorPickerFrame then
        print("Interrupt Coordinator: this client does not provide a color picker.")
        return
    end
    local color = settings.panelColors[component]
    local function updateColor(restore)
        local red, green, blue
        if restore then
            red, green, blue = restore[1], restore[2], restore[3]
        else
            red, green, blue = ColorPickerFrame:GetColorRGB()
        end
        color[1], color[2], color[3] = red, green, blue
        InterruptCoordinatorDB.layout.panelColors[component] = color
        updateComponentColorSwatches()
        updateIconBar()
    end
    ColorPickerFrame.hasOpacity = false
    ColorPickerFrame.func = updateColor
    ColorPickerFrame.cancelFunc = updateColor
    ColorPickerFrame.previousValues = { color[1], color[2], color[3] }
    ColorPickerFrame:SetColorRGB(color[1], color[2], color[3])
    ColorPickerFrame:Show()
end

local function createComponentPositionFrame()
    if componentPositionFrame then
        return
    end

    componentPositionFrame = CreateFrame("Frame", "InterruptCoordinatorComponentPositionFrame", configFrame)
    componentPositionFrame:SetSize(420, 590)
    componentPositionFrame:SetPoint("TOPLEFT", configFrame, "TOPRIGHT", 8, 0)
    componentPositionFrame:SetFrameStrata("DIALOG")
    componentPositionFrame:SetFrameLevel(configFrame:GetFrameLevel() + 5)
    componentPositionFrame:SetMovable(true)
    componentPositionFrame:EnableMouse(true)
    if componentPositionFrame.SetClampedToScreen then
        componentPositionFrame:SetClampedToScreen(true)
    end

    local background = componentPositionFrame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(componentPositionFrame)
    background:SetTexture("Interface\\Buttons\\WHITE8X8")
    background:SetVertexColor(0.025, 0.025, 0.025, 1)

    local title = componentPositionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", componentPositionFrame, "TOPLEFT", 16, -14)
    title:SetText("Layout editor")
    local close = CreateFrame("Button", nil, componentPositionFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", componentPositionFrame, "TOPRIGHT", -4, -4)

    local dragHandle = CreateFrame("Frame", nil, componentPositionFrame)
    dragHandle:SetPoint("TOPLEFT", componentPositionFrame, "TOPLEFT", 0, 0)
    dragHandle:SetPoint("TOPRIGHT", componentPositionFrame, "TOPRIGHT", -34, 0)
    dragHandle:SetHeight(38)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function() componentPositionFrame:StartMoving() end)
    dragHandle:SetScript("OnDragStop", function() componentPositionFrame:StopMovingOrSizing() end)

    editModeButton = CreateFrame("Button", nil, componentPositionFrame, "UIPanelButtonTemplate")
    editModeButton:SetSize(190, 24)
    editModeButton:SetPoint("TOPLEFT", componentPositionFrame, "TOPLEFT", 16, -46)
    editModeButton:SetScript("OnClick", function()
        setEditMode(not editMode)
    end)

    local dragHelp = componentPositionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dragHelp:SetPoint("TOPLEFT", componentPositionFrame, "TOPLEFT", 218, -50)
    dragHelp:SetWidth(184)
    dragHelp:SetJustifyH("LEFT")
    dragHelp:SetText("Drag the highlighted panel to reposition it.")

    local detachedToggle = CreateFrame("CheckButton", nil, componentPositionFrame, "UICheckButtonTemplate")
    detachedToggle:SetPoint("TOPLEFT", componentPositionFrame, "TOPLEFT", 12, -76)
    detachedToggle:SetSize(24, 24)
    detachedToggle:SetChecked(settings.interruptsDetached)
    detachedToggle:SetScript("OnClick", function(self)
        local primaryTop = componentPanels.primary and componentPanels.primary:GetTop()
        settings.interruptsDetached = self:GetChecked() and true or false
        InterruptCoordinatorDB.layout.interruptsDetached = settings.interruptsDetached
        if not settings.interruptsDetached then
            settings.interruptsOffsetX = settings.primaryOffsetX
            settings.interruptsOffsetY = settings.primaryOffsetY
            InterruptCoordinatorDB.layout.interruptsOffsetX = settings.interruptsOffsetX
            InterruptCoordinatorDB.layout.interruptsOffsetY = settings.interruptsOffsetY
        end
        updateComponentPositionLabels()
        updateBarPositionControlState()
        updateIconBar()
        if primaryTop and componentPanels.primary then
            local updatedPrimaryTop = componentPanels.primary:GetTop()
            local topDelta = updatedPrimaryTop and updatedPrimaryTop - primaryTop
            if topDelta and topDelta ~= 0 then
                settings.y = math.max(-500, math.min(500, settings.y - topDelta))
                InterruptCoordinatorDB.layout.y = settings.y
                settings.point = "CENTER"
                syncPositionControls()
                updateIconBar()
            end
        end
    end)
    local detachedLabel = componentPositionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detachedLabel:SetPoint("LEFT", detachedToggle, "RIGHT", 2, 0)
    detachedLabel:SetText("Detach Other interrupts from primary panel")

    local components = {
        { key = "primary", label = "Primary" },
        { key = "interrupts", label = "Other interrupts" },
        { key = "secondary", label = "Secondary stops" },
    }
    local headerSettings = {
        { key = "showPrimaryHeader", label = "Primary header" },
        { key = "showInterruptHeader", label = "Other interrupts header" },
        { key = "showSecondaryHeader", label = "Secondary stops header" },
    }
    for index, setting in ipairs(headerSettings) do
        local settingKey = setting.key
        local settingLabel = setting.label
        local checkbox = CreateFrame("CheckButton", nil, componentPositionFrame, "UICheckButtonTemplate")
        checkbox:SetPoint("TOPLEFT", componentPositionFrame, "TOPLEFT", 12, -102 - (index - 1) * 26)
        checkbox:SetSize(24, 24)
        checkbox:SetChecked(settings[settingKey])
        checkbox:SetScript("OnClick", function(self)
            settings[settingKey] = self:GetChecked() and true or false
            InterruptCoordinatorDB.layout[settingKey] = settings[settingKey]
            updateIconBar()
        end)
        local label = componentPositionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
        label:SetText(settingLabel)
    end

    for index, component in ipairs(components) do
        local componentKey = component.key
        local y = -188 - (index - 1) * 54
        local label = componentPositionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", componentPositionFrame, "TOPLEFT", 18, y)
        componentPositionLabels[component] = label

        local reset = CreateFrame("Button", nil, componentPositionFrame, "UIPanelButtonTemplate")
        reset:SetSize(58, 22)
        reset:SetPoint("TOPLEFT", componentPositionFrame, "TOPLEFT", 18, y - 20)
        reset:SetText("Reset")
        reset:SetScript("OnClick", function()
            local resetX = 0
            local resetY = 0
            if componentKey == "interrupts" and not settings.interruptsDetached then
                resetX = settings.primaryOffsetX
                resetY = settings.primaryOffsetY
            end
            settings[componentKey .. "OffsetX"] = resetX
            settings[componentKey .. "OffsetY"] = resetY
            InterruptCoordinatorDB.layout[componentKey .. "OffsetX"] = resetX
            InterruptCoordinatorDB.layout[componentKey .. "OffsetY"] = resetY
            if componentKey == "primary" and not settings.interruptsDetached then
                settings.interruptsOffsetX = resetX
                settings.interruptsOffsetY = resetY
                InterruptCoordinatorDB.layout.interruptsOffsetX = resetX
                InterruptCoordinatorDB.layout.interruptsOffsetY = resetY
            end
            updateComponentPositionLabels()
            updateBarPositionControlState()
            updateIconBar()
        end)

        for _, axis in ipairs({ "X", "Y" }) do
            local axisName = axis
            for _, direction in ipairs({ -1, 1 }) do
                local step = direction * 10
                local button = CreateFrame("Button", nil, componentPositionFrame, "UIPanelButtonTemplate")
                local axisX = axis == "X" and 224 or 318
                button:SetSize(38, 22)
                button:SetPoint("TOPLEFT", componentPositionFrame, "TOPLEFT", axisX + (direction == 1 and 42 or 0), y - 20)
                button:SetText(axisName .. (step < 0 and "-" or "+"))
                button:SetScript("OnClick", function()
                    local key = componentKey .. "Offset" .. axisName
                    settings[key] = math.max(-10000, math.min(10000, settings[key] + step))
                    InterruptCoordinatorDB.layout[key] = settings[key]
                    updateComponentPositionLabels()
                    updateBarPositionControlState()
                    updateIconBar()
                end)
            end
        end
    end

    for index, component in ipairs({ "primary", "interrupts", "secondary" }) do
        local componentName = component
        local y = -350 - (index - 1) * 40
        local label = componentPositionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", componentPositionFrame, "TOPLEFT", 18, y)
        label:SetText(componentName == "primary" and "Primary backdrop" or componentName == "interrupts" and "Other interrupts (detached)" or "Secondary stops backdrop")

        local colorButton = CreateFrame("Button", nil, componentPositionFrame, "UIPanelButtonTemplate")
        colorButton:SetSize(72, 22)
        colorButton:SetPoint("TOPLEFT", componentPositionFrame, "TOPLEFT", 224, y + 4)
        colorButton:SetText("Color")
        local swatch = colorButton:CreateTexture(nil, "ARTWORK")
        swatch:SetPoint("TOPLEFT", colorButton, "TOPLEFT", 4, -4)
        swatch:SetPoint("BOTTOMRIGHT", colorButton, "BOTTOMRIGHT", -4, 4)
        componentColorSwatches[componentName] = swatch
        colorButton:SetScript("OnClick", function()
            openPanelColorPicker(componentName)
        end)

        local opacityLabel = componentPositionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        opacityLabel:SetPoint("TOPLEFT", componentPositionFrame, "TOPLEFT", 306, y)
        opacityLabel:SetText("Opacity")
        local alphaSlider = CreateFrame("Slider", nil, componentPositionFrame, "OptionsSliderTemplate")
        alphaSlider:SetPoint("TOPLEFT", componentPositionFrame, "TOPLEFT", 306, y - 14)
        alphaSlider:SetSize(82, 18)
        if alphaSlider.SetOrientation then
            alphaSlider:SetOrientation("HORIZONTAL")
        end
        alphaSlider:SetMinMaxValues(0, 1)
        alphaSlider:SetValueStep(0.05)
        alphaSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        alphaSlider:SetValue(settings.panelColors[componentName][4])
        local alphaValue = componentPositionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        alphaValue:SetPoint("TOPLEFT", componentPositionFrame, "TOPLEFT", 392, y - 14)
        alphaValue:SetWidth(24)
        alphaValue:SetJustifyH("RIGHT")
        alphaValue:SetText(tostring(math.floor(settings.panelColors[componentName][4] * 100 + 0.5)) .. "%")
        alphaSlider:SetScript("OnValueChanged", function(_, value)
            value = math.floor(value * 20 + 0.5) / 20
            settings.panelColors[componentName][4] = value
            InterruptCoordinatorDB.layout.panelColors[componentName][4] = value
            alphaValue:SetText(tostring(math.floor(value * 100 + 0.5)) .. "%")
            updateIconBar()
        end)
    end

    local function addBarPositionSlider(key, label, y, minimum, maximum)
        local sliderLabel = componentPositionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        sliderLabel:SetPoint("TOPLEFT", componentPositionFrame, "TOPLEFT", 18, y)
        sliderLabel:SetText(label)
        local valueText = componentPositionFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        valueText:SetPoint("TOPRIGHT", componentPositionFrame, "TOPRIGHT", -20, y)
        valueText:SetWidth(52)
        valueText:SetJustifyH("RIGHT")
        valueText:SetText(tostring(settings[key]))

        local slider = CreateFrame("Slider", nil, componentPositionFrame, "OptionsSliderTemplate")
        slider:SetPoint("TOPLEFT", componentPositionFrame, "TOPLEFT", 22, y - 12)
        slider:SetSize(376, 18)
        if slider.SetOrientation then
            slider:SetOrientation("HORIZONTAL")
        end
        slider:SetMinMaxValues(minimum, maximum)
        slider:SetValueStep(10)
        slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        local track = slider:CreateTexture(nil, "BACKGROUND")
        track:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")
        track:SetPoint("CENTER", slider, "CENTER", 0, 0)
        track:SetSize(360, 8)
        slider:SetValue(settings[key])
        positionControls[key] = { slider = slider, value = valueText }
        slider:SetScript("OnValueChanged", function(_, value)
            value = math.floor(value / 10 + 0.5) * 10
            value = math.max(minimum, math.min(maximum, value))
            settings[key] = value
            InterruptCoordinatorDB.layout[key] = value
            valueText:SetText(tostring(value))
            settings.point = "CENTER"
            updateIconBar()
        end)
    end

    addBarPositionSlider("x", "Bar horizontal position (X)", -472, -800, 800)
    addBarPositionSlider("y", "Bar vertical position (Y)", -512, -500, 500)

    local resetAllPositionsButton = CreateFrame("Button", nil, componentPositionFrame, "UIPanelButtonTemplate")
    resetAllPositionsButton:SetSize(190, 24)
    resetAllPositionsButton:SetPoint("TOPLEFT", componentPositionFrame, "TOPLEFT", 18, -546)
    resetAllPositionsButton:SetText("Reset all positioning")
    resetAllPositionsButton:SetScript("OnClick", function()
        settings.x, settings.y = 0, 0
        settings.point = "CENTER"
        settings.interruptsDetached = false
        for _, componentName in ipairs({ "primary", "interrupts", "secondary" }) do
            settings[componentName .. "OffsetX"] = 0
            settings[componentName .. "OffsetY"] = 0
            InterruptCoordinatorDB.layout[componentName .. "OffsetX"] = 0
            InterruptCoordinatorDB.layout[componentName .. "OffsetY"] = 0
        end
        InterruptCoordinatorDB.layout.x = 0
        InterruptCoordinatorDB.layout.y = 0
        InterruptCoordinatorDB.layout.interruptsDetached = false
        detachedToggle:SetChecked(false)
        syncPositionControls()
        updateComponentPositionLabels()
        updateBarPositionControlState()
        updateIconBar()
    end)

    UISpecialFrames = UISpecialFrames or {}
    local registeredForEscape = false
    for _, frameName in ipairs(UISpecialFrames) do
        if frameName == "InterruptCoordinatorComponentPositionFrame" then
            registeredForEscape = true
            break
        end
    end
    if not registeredForEscape then
        table.insert(UISpecialFrames, "InterruptCoordinatorComponentPositionFrame")
    end
    updateComponentPositionLabels()
    updateComponentColorSwatches()
    updateBarPositionControlState()
    editModeButton:SetText(editMode and "Finish layout editing" or "Edit layout (drag panels)")
    componentPositionFrame:Hide()
end

local function createConfigFrame()
    if configFrame then
        return
    end
    configFrame = CreateFrame("Frame", "InterruptCoordinatorConfigFrame", UIParent)
    configFrame:SetSize(320, 700)
    configFrame:SetPoint("CENTER")
    configFrame:SetFrameStrata("DIALOG")
    configFrame:SetMovable(true)
    configFrame:EnableMouse(true)
    if configFrame.SetClampedToScreen then
        configFrame:SetClampedToScreen(true)
    end
    local background = configFrame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints(configFrame)
    background:SetTexture("Interface\\Buttons\\WHITE8X8")
    background:SetVertexColor(0.025, 0.025, 0.025, 1)
    configFrame.optionRows = {}

    local dragHandle = CreateFrame("Frame", nil, configFrame)
    dragHandle:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 0, 0)
    dragHandle:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -34, 0)
    dragHandle:SetHeight(38)
    dragHandle:EnableMouse(true)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:SetScript("OnDragStart", function() configFrame:StartMoving() end)
    dragHandle:SetScript("OnDragStop", function() configFrame:StopMovingOrSizing() end)

    local title = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 16, -14)
    title:SetText("Interrupt Coordinator")
    local close = CreateFrame("Button", nil, configFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -4, -4)

    addConfigOption("primarySize", "Primary icon", -50, 40, 96, 8)
    addConfigOption("iconSize", "Group icons", -89, 20, 48, 4)
    addConfigOption("interruptsPerRow", "Other icons per row", -128, 1, 10, 1)
    addConfigOption("interruptsMaxRows", "Other maximum rows", -167, 1, 10, 1)
    addConfigOption("interruptsRowGap", "Other row spacing", -206, 0, 32, 2)
    addConfigOption("secondaryPerRow", "Secondary icons per row", -245, 1, 10, 1)
    addConfigOption("secondaryMaxRows", "Secondary maximum rows", -284, 1, 10, 1)
    addConfigOption("secondaryRowGap", "Secondary row spacing", -323, 0, 32, 2)
    addConfigOption("padding", "Background padding", -362, 0, 32, 2)
    local secondaryToggle = CreateFrame("CheckButton", nil, configFrame, "UICheckButtonTemplate")
    secondaryToggle:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 14, -392)
    secondaryToggle:SetSize(24, 24)
    secondaryToggle:SetChecked(settings.showSecondary)
    secondaryToggle:SetScript("OnClick", function(self)
        settings.showSecondary = self:GetChecked() and true or false
        InterruptCoordinatorDB.layout.showSecondary = settings.showSecondary
        updateIconBar()
    end)
    local secondaryToggleLabel = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    secondaryToggleLabel:SetPoint("LEFT", secondaryToggle, "RIGHT", 2, 0)
    secondaryToggleLabel:SetText("Show secondary stops")
    local blacklistButton = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    blacklistButton:SetSize(112, 22)
    blacklistButton:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -18, -393)
    blacklistButton:SetText("Blacklist...")
    local secondaryBlacklistFrame = CreateFrame("Frame", nil, UIParent)
    secondaryBlacklistFrame:SetSize(320, 430)
    secondaryBlacklistFrame:SetPoint("TOPLEFT", configFrame, "TOPRIGHT", 8, 0)
    secondaryBlacklistFrame:SetFrameStrata("DIALOG")
    secondaryBlacklistFrame:SetFrameLevel(configFrame:GetFrameLevel() + 15)
    secondaryBlacklistFrame:EnableMouse(true)
    secondaryBlacklistFrame:SetMovable(true)
    if secondaryBlacklistFrame.SetClampedToScreen then
        secondaryBlacklistFrame:SetClampedToScreen(true)
    end
    local blacklistBackground = secondaryBlacklistFrame:CreateTexture(nil, "BACKGROUND")
    blacklistBackground:SetAllPoints(secondaryBlacklistFrame)
    blacklistBackground:SetTexture("Interface\\Buttons\\WHITE8X8")
    blacklistBackground:SetVertexColor(0.025, 0.025, 0.025, 1)
    local blacklistTitle = secondaryBlacklistFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    blacklistTitle:SetPoint("TOPLEFT", secondaryBlacklistFrame, "TOPLEFT", 16, -14)
    blacklistTitle:SetText("Secondary stops blacklist")
    local blacklistDragHandle = CreateFrame("Frame", nil, secondaryBlacklistFrame)
    blacklistDragHandle:SetPoint("TOPLEFT", secondaryBlacklistFrame, "TOPLEFT", 0, 0)
    blacklistDragHandle:SetPoint("TOPRIGHT", secondaryBlacklistFrame, "TOPRIGHT", -34, 0)
    blacklistDragHandle:SetHeight(38)
    blacklistDragHandle:EnableMouse(true)
    blacklistDragHandle:RegisterForDrag("LeftButton")
    blacklistDragHandle:SetScript("OnDragStart", function() secondaryBlacklistFrame:StartMoving() end)
    blacklistDragHandle:SetScript("OnDragStop", function() secondaryBlacklistFrame:StopMovingOrSizing() end)
    local blacklistClose = CreateFrame("Button", nil, secondaryBlacklistFrame, "UIPanelCloseButton")
    blacklistClose:SetPoint("TOPRIGHT", secondaryBlacklistFrame, "TOPRIGHT", -4, -4)
    local blacklistHelp = secondaryBlacklistFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    blacklistHelp:SetPoint("TOPLEFT", secondaryBlacklistFrame, "TOPLEFT", 16, -42)
    blacklistHelp:SetWidth(264)
    blacklistHelp:SetJustifyH("LEFT")
    blacklistHelp:SetText("Check abilities to hide them from Secondary stops.")
    local blacklistCheckboxes = {}
    local function setAllSecondaryBlacklisted(hidden)
        for _, ability in ipairs(secondaryCatalog) do
            local key = tostring(ability.ids[1])
            settings.secondaryBlacklist[key] = hidden and true or nil
            InterruptCoordinatorDB.layout.secondaryBlacklist[key] = hidden and true or nil
            if blacklistCheckboxes[key] then
                blacklistCheckboxes[key]:SetChecked(hidden)
            end
        end
        updateIconBar()
    end
    local showAllBlacklistButton = CreateFrame("Button", nil, secondaryBlacklistFrame, "UIPanelButtonTemplate")
    showAllBlacklistButton:SetSize(92, 22)
    showAllBlacklistButton:SetPoint("TOPLEFT", secondaryBlacklistFrame, "TOPLEFT", 16, -62)
    showAllBlacklistButton:SetText("Show all")
    showAllBlacklistButton:SetScript("OnClick", function()
        setAllSecondaryBlacklisted(false)
    end)
    local hideAllBlacklistButton = CreateFrame("Button", nil, secondaryBlacklistFrame, "UIPanelButtonTemplate")
    hideAllBlacklistButton:SetSize(92, 22)
    hideAllBlacklistButton:SetPoint("LEFT", showAllBlacklistButton, "RIGHT", 8, 0)
    hideAllBlacklistButton:SetText("Hide all")
    hideAllBlacklistButton:SetScript("OnClick", function()
        setAllSecondaryBlacklisted(true)
    end)

    local blacklistScroll = CreateFrame("ScrollFrame", nil, secondaryBlacklistFrame, "UIPanelScrollFrameTemplate")
    blacklistScroll:SetPoint("TOPLEFT", secondaryBlacklistFrame, "TOPLEFT", 16, -94)
    blacklistScroll:SetPoint("BOTTOMRIGHT", secondaryBlacklistFrame, "BOTTOMRIGHT", -34, 14)
    local blacklistChild = CreateFrame("Frame", nil, blacklistScroll)
    blacklistChild:SetSize(246, #secondaryCatalog * 28)
    blacklistScroll:SetScrollChild(blacklistChild)
    for index, ability in ipairs(secondaryCatalog) do
        local blacklistKey = tostring(ability.ids[1])
        local abilityName, _, abilityTexture = GetSpellInfo(ability.ids[1])
        abilityName = abilityName or ("Ability " .. blacklistKey)
        local checkbox = CreateFrame("CheckButton", nil, blacklistChild, "UICheckButtonTemplate")
        checkbox:SetPoint("TOPLEFT", blacklistChild, "TOPLEFT", 0, -(index - 1) * 28)
        checkbox:SetSize(24, 24)
        checkbox:SetChecked(settings.secondaryBlacklist[blacklistKey] == true)
        blacklistCheckboxes[blacklistKey] = checkbox
        checkbox:SetScript("OnClick", function(self)
            local hidden = self:GetChecked() and true or false
            settings.secondaryBlacklist[blacklistKey] = hidden and true or nil
            InterruptCoordinatorDB.layout.secondaryBlacklist[blacklistKey] = hidden and true or nil
            updateIconBar()
        end)
        local abilityIcon = blacklistChild:CreateTexture(nil, "ARTWORK")
        abilityIcon:SetSize(22, 22)
        abilityIcon:SetPoint("LEFT", checkbox, "RIGHT", 2, 0)
        abilityIcon:SetTexture(abilityTexture or "Interface\\Icons\\INV_Misc_QuestionMark")
        local abilityLabel = blacklistChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        abilityLabel:SetPoint("LEFT", abilityIcon, "RIGHT", 6, 0)
        abilityLabel:SetText(abilityName)
    end
    secondaryBlacklistFrame:Hide()
    blacklistButton:SetScript("OnClick", function()
        if secondaryBlacklistFrame:IsShown() then
            secondaryBlacklistFrame:Hide()
        else
            componentPositionFrame:Hide()
            secondaryBlacklistFrame:Show()
        end
        blacklistButton:SetText(secondaryBlacklistFrame:IsShown() and "Close blacklist" or "Blacklist...")
    end)
    secondaryBlacklistFrame:SetScript("OnHide", function()
        blacklistButton:SetText("Blacklist...")
    end)
    addConfigOption("primaryGap", "Primary-to-groups spacing", -432, 0, 48, 4)
    addConfigOption("sectionGap", "Section spacing", -471, 0, 48, 4)
    addConfigOption("iconGap", "Icon spacing", -510, 0, 24, 2)
    addConfigOption("interruptGap", "Other interrupts spacing", -549, 0, 48, 4)
    local versionButton = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    versionButton:SetSize(160, 24)
    versionButton:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -18, -622)
    versionButton:SetText("Check group versions")
    versionButton:SetScript("OnClick", checkGroupVersions)
    versionStatusText = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionStatusText:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 18, -654)
    versionStatusText:SetWidth(284)
    versionStatusText:SetHeight(28)
    versionStatusText:SetJustifyH("LEFT")
    versionStatusText:SetText("Group version check has not been run.")

    visibilityButton = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    visibilityButton:SetSize(136, 24)
    visibilityButton:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 18, -590)
    visibilityButton:SetScript("OnClick", function()
        setBarVisible(not frame:IsShown())
    end)
    visibilityButton:SetText(settings.hidden and "Show interrupt bar" or "Hide interrupt bar")

    createComponentPositionFrame()
    local componentPositionButton = CreateFrame("Button", nil, configFrame, "UIPanelButtonTemplate")
    componentPositionButton:SetSize(136, 24)
    componentPositionButton:SetPoint("TOPLEFT", visibilityButton, "TOPRIGHT", 8, 0)
    componentPositionButton:SetText("Layout editor")
    componentPositionButton:SetScript("OnClick", function()
        if componentPositionFrame:IsShown() then
            componentPositionFrame:Hide()
        else
            secondaryBlacklistFrame:Hide()
            componentPositionFrame:Show()
        end
        componentPositionButton:SetText(componentPositionFrame:IsShown() and "Hide layout editor" or "Layout editor")
    end)
    componentPositionFrame:SetScript("OnHide", function()
        componentPositionButton:SetText("Layout editor")
    end)
    blacklistButton:SetSize(136, 24)
    blacklistButton:ClearAllPoints()
    blacklistButton:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 18, -622)

    UISpecialFrames = UISpecialFrames or {}
    local registeredForEscape = false
    for _, frameName in ipairs(UISpecialFrames) do
        if frameName == "InterruptCoordinatorConfigFrame" then
            registeredForEscape = true
            break
        end
    end
    if not registeredForEscape then
        table.insert(UISpecialFrames, "InterruptCoordinatorConfigFrame")
    end
    updateConfigLabels()
    configFrame:Hide()
end

local function createIconBar()
    if panelReady then
        return
    end
    settings = getSettings()
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(180, 150)
    frame:SetFrameStrata("MEDIUM")
    frame:SetAllPoints(UIParent)
    frame:EnableMouse(false)
    frame:SetScript("OnUpdate", function()
        if componentDrag then
            updateComponentDrag()
        end
    end)

    primaryHeaderText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    primaryHeaderText:SetTextColor(0.8, 0.8, 0.8)
    primaryNameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    primaryNameText:SetPoint("TOP", frame, "TOP", 0, -8)
    primaryNameText:SetJustifyH("CENTER")
    primaryInfoText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    primaryInfoText:SetPoint("TOP", frame, "TOP", 0, -26)
    primaryInfoText:SetJustifyH("CENTER")
    interruptHeaderText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    interruptHeaderText:SetTextColor(0.8, 0.8, 0.8)
    interruptHeaderText:SetJustifyH("LEFT")
    secondaryHeaderText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    secondaryHeaderText:SetTextColor(0.8, 0.8, 0.8)
    secondaryHeaderText:SetJustifyH("LEFT")
    primaryIcon = createAbilityButton(frame, settings.primarySize)
    primaryIcon.memberName:Hide()
    layoutStatusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    layoutStatusText:SetJustifyH("CENTER")

    createConfigFrame()
    panelReady = true
    updateIconBar()
    if settings.hidden then
        frame:Hide()
    else
        frame:Show()
    end
end

updatePanel = updateIconBar
createPanel = createIconBar

SLASH_INTERRUPTCOORDINATOR1 = "/ic"
SlashCmdList.INTERRUPTCOORDINATOR = function(command)
    local normalized = string.lower(command or "")
    if normalized == "help" then
        print("Interrupt Coordinator: /ic toggles settings, /ic config also toggles settings, /ic bar toggles the interrupt bar, /ic edit toggles layout edit mode, /ic show|hide controls the bar, /ic report refreshes reports, /ic versions checks group versions.")
        return
    end
    if not panelReady then
        print("Interrupt Coordinator: panel did not initialize at login; check the Lua error message.")
        return
    end
    if normalized == "" or normalized == "config" then
        if configFrame:IsShown() then
            configFrame:Hide()
        else
            configFrame:Show()
        end
    elseif normalized == "bar" or normalized == "toggle" or normalized == "show" then
        local visible = normalized == "show" or not frame:IsShown()
        setBarVisible(visible)
        if visible then
            publishLocalStatus()
            requestGroupStatus()
        end
    elseif normalized == "edit" then
        setEditMode(not editMode)
    elseif normalized == "versions" then
        checkGroupVersions()
    elseif normalized == "report" then
        publishLocalStatus()
        requestGroupStatus()
        updatePanel()
    elseif normalized == "hide" then
        setBarVisible(false)
    else
        print("Interrupt Coordinator: unknown command. Use /ic help for commands.")
    end
end

local events = CreateFrame("Frame")
local function registerEvent(eventName)
    local registered = pcall(events.RegisterEvent, events, eventName)
    if not registered then
        print("Interrupt Coordinator: unsupported event " .. eventName)
    end
end

registerEvent("PLAYER_LOGIN")
registerEvent("PLAYER_ENTERING_WORLD")
registerEvent("PARTY_MEMBERS_CHANGED")
registerEvent("RAID_ROSTER_UPDATE")
registerEvent("GROUP_ROSTER_UPDATE")
registerEvent("CHAT_MSG_ADDON")
registerEvent("COMBAT_LOG_EVENT_UNFILTERED")
registerEvent("SPELL_UPDATE_COOLDOWN")
registerEvent("SPELLS_CHANGED")
registerEvent("UNIT_PET")
registerEvent("PET_BAR_UPDATE")
registerEvent("PLAYER_DEAD")
registerEvent("PLAYER_ALIVE")
registerEvent("PLAYER_UNGHOST")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, message, _, sender = ...
        if prefix == PREFIX and sender and senderIsInGroup(sender) then
            handleAddonMessage(sender, message)
        end
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        handleCombatLog(...)
        return
    end

    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        if RegisterAddonMessagePrefix then
            RegisterAddonMessagePrefix(PREFIX)
        elseif C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        end
        local initialized, initializationError = pcall(createPanel)
        if initialized then
            publishLocalStatus()
            requestGroupStatus()
        else
            print("Interrupt Coordinator: panel initialization failed: " .. tostring(initializationError))
        end
    elseif event == "UNIT_PET" then
        local unit = ...
        if unit == "player" then
            publishAt = GetTime() + 0.25
        end
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" or event == "GROUP_ROSTER_UPDATE" then
        requestStatus = true
        rosterRequestRetries = 0
        rosterRequestRetryAt = GetTime() + 0.75
        publishAt = GetTime() + 0.5
        if panelReady then
            updateIconBar()
        end
    elseif event == "SPELL_UPDATE_COOLDOWN" or event == "SPELLS_CHANGED" or event == "PET_BAR_UPDATE" or event == "PLAYER_DEAD" or event == "PLAYER_ALIVE" or event == "PLAYER_UNGHOST" then
        publishAt = GetTime() + 0.25
    else
        requestStatus = true
        publishAt = GetTime() + 0.5
    end
end)

events:SetScript("OnUpdate", function(_, elapsed)
    refreshElapsed = refreshElapsed + elapsed
    heartbeatElapsed = heartbeatElapsed + elapsed
    if publishAt and GetTime() >= publishAt then
        publishAt = nil
        publishLocalStatus()
    end
    if requestStatus then
        requestStatus = false
        requestGroupStatus()
    end
    if rosterRequestRetryAt and GetTime() >= rosterRequestRetryAt then
        requestGroupStatus()
        rosterRequestRetries = rosterRequestRetries + 1
        if rosterRequestRetries < 2 then
            rosterRequestRetryAt = GetTime() + 1
        else
            rosterRequestRetryAt = nil
        end
    end
    if heartbeatElapsed >= HEARTBEAT_SECONDS then
        heartbeatElapsed = 0
        publishLocalStatus()
    end
    if versionCheckActive and GetTime() - versionCheckStartedAt >= VERSION_CHECK_SECONDS then
        versionCheckActive = false
        updateVersionStatus(true)
        printVersionResults()
    end
    if refreshElapsed >= 0.25 then
        refreshElapsed = 0
        if panelReady and frame:IsShown() then
            updatePanel()
        end
    end
end)
