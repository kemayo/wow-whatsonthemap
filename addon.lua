local myname, ns = ...
local myfullname = GetAddOnMetadata(myname, "Title")
local db
local isClassic = WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE

function ns.Print(...) print("|cFF33FF99".. myfullname.. "|r:", ...) end

-- events
local f = CreateFrame('Frame')
f:SetScript("OnEvent", function(_, event, ...)
    ns[ns.events[event]](ns, event, ...)
end)
f:Hide()
ns.events = {}
function ns:RegisterEvent(event, method)
    self.events[event] = method or event
    f:RegisterEvent(event)
end
function ns:UnregisterEvent(...) for i=1,select("#", ...) do f:UnregisterEvent((select(i, ...))) end end

local window
local setDefaults

function ns:ADDON_LOADED(event, addon)
    if addon == myname then
        _G[myname.."DB"] = setDefaults(_G[myname.."DB"] or {}, {
            title = true, -- show title (for dragging)
            backdrop = true, -- show a backdrop on the frame
            empty = false, -- show when empty
            direction = true, -- show the direction the vignette is in
            world = true, -- show vignettes that're on the world map
            minimap = true, -- show vignettes that're on the minimap
            hidden = true, -- show vignettes that're not on either
            debug = false, -- show all the debug info in tooltips
        })
        db = _G[myname.."DB"]
        self:UnregisterEvent("ADDON_LOADED")

        window = self:CreateUI()
        window:SetPoint("CENTER")

        self:RegisterEvent("VIGNETTE_MINIMAP_UPDATED", "Refresh")
        self:RegisterEvent("VIGNETTES_UPDATED", "Refresh")
        self:RegisterEvent("PLAYER_ENTERING_WORLD", "Refresh")
    end
end
ns:RegisterEvent("ADDON_LOADED")

local function sort_vignette(a, b)
    return ns.VignetteDistanceFromPlayer(a) < ns.VignetteDistanceFromPlayer(b)
end
function ns:Refresh()
    local vignetteids = C_VignetteInfo.GetVignettes()
    table.sort(vignetteids, sort_vignette)

    window.linePool:ReleaseAll()
    -- print("VIGNETTES_UPDATED", #vignetteids)

    if db.title then
        window.title:Show()
    else
        window.title:Hide()
    end

    local count = 0
    local lastLine
    local height = db.title and (window.title:GetHeight() + 6) or 6
    for i=1, #vignetteids do
        local instanceid = vignetteids[i]
        -- print(i, vignetteInfo.name)
        local vignetteInfo = C_VignetteInfo.GetVignetteInfo(instanceid)
        if self:ShouldShowVignette(vignetteInfo) then
            local line = self:AddLine(instanceid, vignetteInfo)
            if count == 0 and not db.title then
                line:SetPoint("TOPLEFT", window.title)
                line:SetPoint("TOPRIGHT", window.title)
            else
                local anchor = count == 0 and window.title or lastLine
                line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT")
                line:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT")
            end
            -- print('line was shown', vignetteInfo)
            height = height + line:GetHeight()
            lastLine = line
            count = count + 1
        end
    end

    if count == 0 then
        if not db.empty then
            return window:Hide()
        end
        if not db.title then
            local line = window.linePool:Acquire()
            line:SetPoint("TOPLEFT", window.title)
            line:SetPoint("TOPRIGHT", window.title)
            line.icon:SetAtlas("xmarksthespot")
            line.title:SetText(NONE)
            line:Show()
            height = height + line:GetHeight()
        end
    end

    if db.backdrop then
        window:SetBackdropColor(0, 0, 0, .5)
        window:SetBackdropBorderColor(0, 0, 0, .5)
    else
        window:SetBackdropColor(0, 0, 0, 0)
        window:SetBackdropBorderColor(0, 0, 0, 0)
    end

    window:SetHeight(height)
    window:Show()
end

function ns:AddLine(instanceid, vignetteInfo)
    local line = window.linePool:Acquire()
    line.vignetteGUID = instanceid

    if vignetteInfo then
        line.icon:SetAtlas(vignetteInfo.atlasName)
        line.title:SetText(vignetteInfo.name)
        if not (vignetteInfo.onMinimap or vignetteInfo.onWorldMap) then
            line.icon:SetDesaturated(true)
            line.icon:SetAlpha(0.5)
        end
    else
        line.icon:SetAtlas("poi-nzothvision") -- "islands-questdisable"?
        line.icon:SetVertexColor(0.9, 0.3, 1, 1)
        line.title:SetText(UNKNOWN)
    end
    if db.direction then
        local _, angle = ns.VignetteDistanceFromPlayer(instanceid)
        line.direction:SetWidth(30)
        line.direction:SetText(ns.AngleToCompassDirection(angle, true))
    else
        line.direction:SetWidth(0)
    end

    line:Show()
    return line
end

function ns:ShouldShowVignette(vignetteInfo)
    if not vignetteInfo then
        return db.hidden
    end
    if not vignetteInfo.onMinimap then
        if vignetteInfo.onWorldMap then
            return db.world
        end
        return db.hidden
    end
    return db.minimap
end

local function VignettePosition(vignetteGUID)
    local uiMapID = C_Map.GetBestMapForUnit('player')
    if not uiMapID then return end
    local position = C_VignetteInfo.GetVignettePosition(vignetteGUID, uiMapID)
    if position then
        return uiMapID, position, position:GetXY()
    end
end

function ns.VignetteDistanceFromPlayer(vignetteGUID)
    local uiMapID, position = VignettePosition(vignetteGUID)
    if not (uiMapID and position) then return 0, 0 end
    local player = C_Map.GetPlayerMapPosition(uiMapID, 'player')
    if not player then return 0, 0 end
    local width, height = C_Map.GetMapWorldSize(uiMapID)
    position:Subtract(player)

    local angle = (math.pi - Vector2D_CalculateAngleBetween(position.x, position.y, 0, 1))
    return position:GetLength() * width, angle
end

do
    local function round(x) return x + 0.5 - (x + 0.5) % 1 end
    local directions_long = {"North", "Northeast", "East", "Southeast", "South", "Southwest", "West", "Northwest"}
    local directions_short = {"N", "NE", "E", "SE", "S", "SW", "W", "NW"}
    function ns.AngleToCompassDirection(radians, short)
        -- algorithm is: find out how many increments we've gone around the
        -- circle, rounded to the nearest one, modulo the number of increments so
        -- we don't go over the top at 2pi
        local directions = short and directions_short or directions_long
        local increment = (2*math.pi) / #directions
        local direction = (round(radians / increment) % #directions) + 1
        return directions[direction]
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

    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnMouseUp", function(w, button)
        if button == "RightButton" then
            return ns:ShowConfigMenu(w)
        end
    end)
    frame:SetScript("OnUpdate", function(_, since)
        if not db.direction then return end
        frame.time = (frame.time or 0) + since
        if frame.time <= 3 then return end
        for line in frame.linePool:EnumerateActive() do
            if line.vignetteGUID then
                local _, angle = ns.VignetteDistanceFromPlayer(line.vignetteGUID)
                line.direction:SetWidth(30)
                line.direction:SetText(ns.AngleToCompassDirection(angle, true))
            end
        end
        frame.time = 0
    end)

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
    frame.title = title
    title:SetJustifyH("MIDDLE")
    title:SetJustifyV("MIDDLE")
    title:SetPoint("TOPLEFT", 0, -4)
    title:SetPoint("TOPRIGHT", 0, -4)
    title:SetText(myfullname)

    local function LineTooltip(line)
        if not line.vignetteGUID then return end
        local anchor = (line:GetCenter() < (UIParent:GetWidth() / 2)) and "ANCHOR_RIGHT" or "ANCHOR_LEFT"
        GameTooltip:SetOwner(line, anchor, 0, -60)
        local vignetteInfo = C_VignetteInfo.GetVignetteInfo(line.vignetteGUID)
        local _, _, x, y = VignettePosition(line.vignetteGUID)
        local distance, angle = ns.VignetteDistanceFromPlayer(line.vignetteGUID)
        local location = (x and y) and ("%d, %d"):format(x * 100, y * 100) or UNKNOWN
        if vignetteInfo then
            GameTooltip:AddDoubleLine(vignetteInfo.name or UNKNOWN, location, 1, 1, 1)
        else
            GameTooltip:AddDoubleLine("No data from API", location, 1, 0, 0)
        end
        if distance then
            GameTooltip:AddDoubleLine(" ", ("%d yards away, %s"):format(distance, ns.AngleToCompassDirection(angle)))
        end
        if db.debug then
            if vignetteInfo then
                for k,v in pairs(vignetteInfo) do
                    if k ~= 'name' then
                        GameTooltip:AddDoubleLine(k, type(v) == "boolean" and (v and "true" or "false") or v)
                    end
                end
            else
                GameTooltip:AddDoubleLine('vignetteGUID', line.vignetteGUID)
            end
        end
        GameTooltip_AddInstructionLine(GameTooltip, "Control-click to add a map pin")
        GameTooltip_AddInstructionLine(GameTooltip, "Shift-click to share to chat")
        GameTooltip:Show()
    end
    local function Line_OnClick(line, button)
        if button == "RightButton" then
            return ns:ShowConfigMenu(line)
        end
        if button ~= "LeftButton" then return end
        if not line.vignetteGUID then return end
        local vignetteInfo = C_VignetteInfo.GetVignetteInfo(line.vignetteGUID)
        local uiMapID, _, x, y = VignettePosition(line.vignetteGUID)
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
            line.title = line:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            line.title:SetPoint("LEFT", line.icon, "RIGHT", 4, 0)
            line.title:SetPoint("RIGHT")
            line.title:SetJustifyH("LEFT")
            line.title:SetMaxLines(2)
            line.direction = line:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
            line.direction:SetPoint("RIGHT")
            line.title:SetPoint("RIGHT", line.direction, "LEFT")
            line:SetScript("OnEnter", LineTooltip)
            line:SetScript("OnLeave", GameTooltip_Hide)
            line:SetScript("OnMouseUp", Line_OnClick)
            line:EnableMouse(true)
        end
        line.vignetteGUID = nil
        line.icon:SetDesaturated(false)
        line.icon:SetAlpha(1)
        line.icon:SetVertexColor(1, 1, 1, 1)
        line.direction:SetWidth(30)
        line.direction:SetText("")
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
        PrintConfigLine('backdrop', "Show a backdrop in the frame")
        PrintConfigLine('direction', "Show the direction of the item")
        PrintConfigLine('empty', "Show while empty")
        PrintConfigLine('world', "Show world map items")
        PrintConfigLine('minimap', "Show minimap items")
        PrintConfigLine('hidden', "Show hidden map items")
        PrintConfigLine('debug', "Show debug information")
        ns.Print("To toggle: /whatsonthemap [type]")
    end
end

do
    local menuFrame, menuData
    local isChecked = function(button) return db[button.value] end
    local toggle = function(button, arg1, arg2, checked)
        db[button.value] = not checked
        ns:Refresh()
    end
    function ns:ShowConfigMenu(frame)
        if not menuFrame then
            menuFrame = CreateFrame("Frame", myname.."MenuFrame", UIParent, "UIDropDownMenuTemplate")
            menuData = {
                { text=myfullname, isTitle=true, },
                { text="Show a title in the frame", value="title", checked=isChecked, func=toggle, isNotRadio=true, },
                { text="Show a backdrop in the frame", value="backdrop", checked=isChecked, func=toggle, isNotRadio=true, },
                { text="Show the direction of the item", value="direction", checked=isChecked, func=toggle, isNotRadio=true, },
                { text="Show while empty", value="empty", checked=isChecked, func=toggle, isNotRadio=true, },
                { text="Show debug information", value="debug", checked=isChecked, func=toggle, isNotRadio=true, },
                { text="Show map items...", hasArrow=true, notCheckable=true, menuList={
                    { text="From the world map", value="world", checked=isChecked, func=toggle, isNotRadio=true, },
                    { text="From the minimap", value="minimap", checked=isChecked, func=toggle, isNotRadio=true, },
                    { text="Hidden", value="hidden", checked=isChecked, func=toggle, isNotRadio=true, },
                }, },
            }
        end
        EasyMenu(menuData, menuFrame, "cursor", 0, 0, "MENU")
    end
end

function setDefaults(options, defaults)
    setmetatable(options, { __index = function(t, k)
        if type(defaults[k]) == "table" then
            t[k] = setDefaults({}, defaults[k])
            return t[k]
        end
        return defaults[k]
    end, })
    -- and add defaults to existing tables
    for k, v in pairs(options) do
        if defaults[k] and type(v) == "table" then
            setDefaults(v, defaults[k])
        end
    end
    return options
end
