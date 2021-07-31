local myname, ns = ...
local myfullname = GetAddOnMetadata(myname, "Title")
local db
local isClassic = WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE

function ns.Print(...) print("|cFF33FF99".. myfullname.. "|r:", ...) end

-- events
local f = CreateFrame("Frame")
f:SetScript("OnEvent", function(self, event, ...) if ns[event] then return ns[event](ns, event, ...) end end)
function ns:RegisterEvent(...) for i=1,select("#", ...) do f:RegisterEvent((select(i, ...))) end end
function ns:UnregisterEvent(...) for i=1,select("#", ...) do f:UnregisterEvent((select(i, ...))) end end

local window

function ns:ADDON_LOADED(event, addon)
    if addon == myname then
        _G[myname.."DB"] = setmetatable(_G[myname.."DB"] or {}, {
            __index = {
                title = true, -- show title (for dragging)
                empty = false, -- show when empty
                hidden = true, -- show vignettes that won't be on the minimap
                debug = false, -- show all the debug info in tooltips
            },
        })
        db = _G[myname.."DB"]
        self:UnregisterEvent("ADDON_LOADED")

        window = self:CreateUI()
        window:SetPoint("CENTER")

        self:RegisterEvent("VIGNETTE_MINIMAP_UPDATED", "VIGNETTES_UPDATED")
    end
end
ns:RegisterEvent("ADDON_LOADED")

-- function ns:PLAYER_ENTERING_WORLD()
--     self:VIGNETTES_UPDATED()
-- end

function ns:Refresh()
    local vignetteids = C_VignetteInfo.GetVignettes()

    window.linePool:ReleaseAll()
    -- print("VIGNETTES_UPDATED", #vignetteids)

    if db.title then
        window.title:Show()
    else
        window.title:Hide()
    end

    local count = 0
    local lastLine
    local height = db.title and (window.title:GetHeight() + 6) or 0
    for i=1, #vignetteids do
        local instanceid = vignetteids[i]
        -- print(i, vignetteInfo.name)

        local line = window.linePool:Acquire()
        if count == 0 and not db.title then
            line:SetPoint("TOPLEFT", window.title)
            line:SetPoint("TOPRIGHT", window.title)
        else
            local anchor = count == 0 and window.title or lastLine
            line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT")
            line:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT")
        end

        line.vignetteGUID = instanceid
        local vignetteInfo = C_VignetteInfo.GetVignetteInfo(instanceid)
        if vignetteInfo then
            if db.hidden or (vignetteInfo.onWorldMap or vignetteInfo.onMinimap) then
                line.icon:SetAtlas(vignetteInfo.atlasName)
                line.title:SetText(vignetteInfo.name)
                if not (vignetteInfo.onMinimap or vignetteInfo.onWorldMap) then
                    line.icon:SetDesaturated(true)
                end
                line:Show()
            end
        elseif db.hidden then
            line.icon:SetAtlas("islands-questdisable")
            line.title:SetText(UNKNOWN)
            line:Show()
        else
            window.linePool:Release(line)
        end

        if line:IsShown() then
            -- print('line was shown', vignetteInfo)
            height = height + line:GetHeight()
            lastLine = line
            count = count + 1
        end
    end

    if not db.empty and count == 0 then
        return window:Hide()
    end

    window:SetHeight(height)
    window:Show()
end

ns.VIGNETTES_UPDATED = ns.Refresh

function ns:VIGNETTE_MINIMAP_UPDATED(event, instanceid, onMinimap, ...)
    self:Refresh()
end

local function VignettePosition(vignetteGUID)
    local uiMapID = C_Map.GetBestMapForUnit('player')
    if not uiMapID then return end
    local position = C_VignetteInfo.GetVignettePosition(vignetteGUID, uiMapID)
    if position then
        return uiMapID, position:GetXY()
    end
end

function ns:CreateUI()
    local frame = CreateFrame("Frame", "WhatsOnTheMapFrame", UIParent, "BackdropTemplate")
    frame:SetSize(240, 60)
    frame:SetBackdrop({
        edgeFile = [[Interface\Buttons\WHITE8X8]],
        bgFile = [[Interface\Buttons\WHITE8X8]],
        edgeSize = 1,
    })
    frame:SetBackdropColor(0, 0, 0, .5)
    frame:SetBackdropBorderColor(0, 0, 0, .5)

    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
    frame.title = title
    title:SetJustifyH("MIDDLE")
    title:SetJustifyV("MIDDLE")
    title:SetPoint("TOPLEFT", 0, -4)
    title:SetPoint("TOPRIGHT", 0, -4)
    title:SetText(myfullname)

    local function LineTooltip(line)
        local anchor = (line:GetCenter() < (UIParent:GetWidth() / 2)) and "ANCHOR_RIGHT" or "ANCHOR_LEFT"
        GameTooltip:SetOwner(line, anchor, 0, -60)
        local vignetteInfo = C_VignetteInfo.GetVignetteInfo(line.vignetteGUID)
        local _, x, y = VignettePosition(line.vignetteGUID)
        local location = (x and y) and ("%d, %d"):format(x * 100, y * 100) or UNKNOWN
        if vignetteInfo then
            GameTooltip:AddDoubleLine(vignetteInfo.name or UNKNOWN, location, 1, 1, 1)
            if db.debug then
                for k,v in pairs(vignetteInfo) do
                    if k ~= 'name' then
                        GameTooltip:AddDoubleLine(k, type(v) == "boolean" and (v and "true" or "false") or v)
                    end
                end
            end
        else
            GameTooltip:AddDoubleLine("No data from API", location, 1, 0, 0)
            if db.debug then
                GameTooltip:AddDoubleLine('vignetteGUID', line.vignetteGUID)
            end
        end
        GameTooltip_AddInstructionLine(GameTooltip, "Control-click to add a map pin")
        GameTooltip_AddInstructionLine(GameTooltip, "Shift-click to share to chat")
        GameTooltip:Show()
    end
    local function Line_OnClick(line, button)
        if button ~= "LeftButton" then return end
        local vignetteInfo = C_VignetteInfo.GetVignetteInfo(line.vignetteGUID)
        local uiMapID, x, y = VignettePosition(line.vignetteGUID)
        if IsShiftKeyDown() then
            local message = ("%s|cffffff00|Hworldmap:%d:%d:%d|h[%s]|h|r"):format(
                vignetteInfo and (vignetteInfo.name .. " ") or "",
                uiMapID,
                x * 10000,
                y * 10000,
                -- WoW seems to filter out anything which isn't the standard MAP_PIN_HYPERLINK
                MAP_PIN_HYPERLINK
            )
            PlaySound(SOUNDKIT.UI_MAP_WAYPOINT_CHAT_SHARE)
            -- if you have an open editbox, just paste to it
            if not ChatEdit_InsertLink(message) then
                -- open the chat to whatever it was on and add the text
                ChatFrame_OpenChat(message)
            end
        elseif IsControlKeyDown() then
            if uiMapID and x and y and C_Map.CanSetUserWaypointOnMap(uiMapID) then
                local uiMapPoint = UiMapPoint.CreateFromCoordinates(uiMapID, x, y)
                C_Map.SetUserWaypoint(uiMapPoint)
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            end
        end
    end

    frame.linePool = CreateFramePool("Frame", frame, nil, function(pool, line)
        if not line.icon then
            line:SetHeight(26)
            line.icon = line:CreateTexture()
            line.icon:SetSize(24, 24)
            line.icon:SetPoint("LEFT", 4, 0)
            line.title = line:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            line.title:SetPoint("LEFT", line.icon, "RIGHT", 4, 0)
            line.title:SetPoint("RIGHT")
            line.title:SetJustifyH("LEFT")
            line.title:SetMaxLines(2)
            line:SetScript("OnEnter", LineTooltip)
            line:SetScript("OnLeave", GameTooltip_Hide)
            line:SetScript("OnMouseUp", Line_OnClick)
            line:EnableMouse(true)
        end
        line.icon:SetDesaturated(false)
        FramePool_HideAndClearAnchors(pool, line)
    end)

    return frame
end

-- Quick config:

local function PrintConfigLine(key, description)
    ns.Print(key, '-', description, '-', db[key] and YES or NO)
end

_G["SLASH_".. myname:upper().."1"] = "/whatsonthemap"
_G["SLASH_".. myname:upper().."2"] = "/wotm"
SlashCmdList[myname:upper()] = function(msg)
    msg = msg:trim()
    if db[msg] ~= nil then
        db[msg] = not db[msg]
        ns.Print(msg, '=', db[msg] and YES or NO)
        ns:Refresh()
    end
    if msg == "" then
        ns.Print("What's On The Map?")
        PrintConfigLine('title', "Show a title in the frame")
        PrintConfigLine('empty', "Show while empty")
        PrintConfigLine('hidden', "Show hidden map items")
        PrintConfigLine('debug', "Show debug information")
        ns.Print("To toggle: /whatsonthemap [type]")
    end
end
