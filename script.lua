
-- ═══════════════════════════════════════════════════════════════════════════
-- LURAPH v14 MACRO SHIMS
-- These make the script run correctly BOTH raw (untouched) and after LuaProt
-- obfuscation. The whole point: keep client FPS good after obfuscation by
-- wrapping the hot per-frame loops with LPH_NO_VIRTUALIZE so they don't get
-- virtualized (virtualized render loops are what tank client FPS).
-- Every LPH_ macro below is shimmed to a no-op / pass-through so running the
-- raw (unobfuscated) script never errors on an undefined macro.
-- ═══════════════════════════════════════════════════════════════════════════
if not LPH_OBFUSCATED then
    -- value macros
    LPH_OBFUSCATED = false
    LPH_LINE = 0
    -- callable / string macros -> pass-through
    LPH_ENCSTR   = function(v) return v end
    LPH_STRENC   = function(v) return v end
    LPH_ENCNUM   = function(v) return v end
    LPH_NUMENC   = function(v) return v end
    LPH_ENCBUF   = function(v) return v end
    LPH_BUFENC   = function(v) return v end
    LPH_CRASH    = function() end
    -- v14 wrapper macros: take a function, return it unchanged when running raw
    LPH_JIT           = function(f) return f end
    LPH_JIT_MAX       = function(f) return f end
    LPH_NO_VIRTUALIZE = function(f) return f end
    LPH_NO_UPVALUES   = function(f) return f end
    LPH_ENCFUNC       = function(f) return f end   -- (fn, encKey, decKey) raw: ignore keys
end

-- Runtime decryption key for LPH_ENCFUNC. The encryption key is the 64-char hex
-- CONSTANT passed to LPH_ENCFUNC; the decryption key must be a NON-CONSTANT
-- runtime value that evaluates to the same string. We build it at runtime (from
-- table.concat) so the obfuscator can't fold it back into a constant. The name
-- must NOT use the reserved LPH_/LP_ prefix.
local riotsDecKey = table.concat({
    "a3f5c901", "2e7b46d8", "419caf62", "038d5e71",
    "bc90784a", "f1d2635e", "8a04c7be", "95201f3d",
})

-- ═══════════════════════════════════════════════════════════════════════════
-- ANTI-CHEAT NEUTRALIZATION — EXACT port of take.lua's approach, run FIRST.
-- take.lua does all of this at the very top, BEFORE building any UI, and waits
-- out the loading screen. Doing it here (before the menu loads) is what stops the
-- ~5s detection-crash. Every step is pcall-guarded so a missing API can't crash.
-- ═══════════════════════════════════════════════════════════════════════════
do
    local LocalPlayer = game:GetService("Players").LocalPlayer
    local eli_inext = function(t, i)
        i = i + 1
        local v = t[i]
        if v ~= nil then return i, v end
    end
    local eli_ipairs = function(t) return eli_inext, t, 0 end

    if hookfunction and newcclosure and getcallingscript then
        pcall(function()
            local Old1 = nil; Old1 = hookfunction(setmetatable, newcclosure(function(Table, MetaTable)
                if type(MetaTable) == "table" and rawget(MetaTable, "__mode") == "kv" then
                    local Caller = getcallingscript()
                    if Caller and Caller.Name == "MiscellaneousController" then
                        return Old1(Table, { })
                    end
                end
                return Old1(Table, MetaTable)
            end))
        end)

        pcall(function()
            local Ol2 = nil; Ol2 = hookfunction(rawlen, newcclosure(function(Table)
                if type(Table) == "table" then
                    local Caller = getcallingscript()
                    if Caller and Caller.Name == "MiscellaneousController" then
                        return 3
                    end
                end
                return Ol2(Table)
            end))
        end)
    end

    task.wait(6)   -- take.lua waits here so the game's controllers fully init before the next hook

    pcall(function()
        if not (hookfunction and newcclosure and getrenv) then return end
        local oldtable; oldtable = hookfunction(getrenv().setmetatable, newcclosure(function(Table, Metatable)
            if Metatable and typeof(Metatable) == "table" and rawget(Metatable, "__mode") == "kv" then
                local trace = debug.traceback()
                if trace:find("MiscellaneousController") then
                    return oldtable({1, 2, 3}, {})
                end
            end
            return oldtable(Table, Metatable)
        end))
    end)

    coroutine.wrap(function()
        pcall(function()
            local acWords = {"anticheat", "ac", "detection", "ban", "kick", "security", "moderation"}
            local function disableScript(obj) obj.Disabled = true end
            local function checkScript(obj)
                if obj:IsA("LocalScript") or obj:IsA("ModuleScript") then
                    local n = string.lower(obj.Name)
                    for _, ac in eli_ipairs(acWords) do
                        if string.find(n, ac, 1, true) then
                            pcall(disableScript, obj)
                            break
                        end
                    end
                end
            end
            local function blockScript(obj) pcall(checkScript, obj) end

            pcall(function() game.DescendantAdded:Connect(blockScript) end)
            pcall(function()
                local descendants = game:GetDescendants()
                for index = 1, #descendants do
                    blockScript(descendants[index])
                    if index % 4000 == 0 then task.wait() end
                end
            end)
        end)

        pcall(function()
            local networkClient = game:GetService("NetworkClient")
            if networkClient then
                networkClient.ChildAdded:Connect(function(child)
                    pcall(function()
                        local ok, n = pcall(function() return child.Name:lower() end)
                        if ok and n then
                            if n:find("anticheat") or n:find("detection") then
                                pcall(function() child:Destroy() end)
                            end
                        end
                    end)
                end)
            end
        end)
    end)()

    pcall(function()
        local fake = Instance.new("RemoteEvent")
        fake.Name = "ClientAlert"
        fake.Parent = LocalPlayer
    end)

    task.spawn(function()
        pcall(function()
            if type(getgc) ~= "function" then return end
            local rf = game:GetService("ReplicatedFirst")
            local ls3 = rf:WaitForChild("LocalScript3", 10)

            local gc = getgc(false)
            for index = 1, #gc do
                local f = gc[index]
                if type(f) == "function" and (type(islclosure) ~= "function" or islclosure(f)) then
                    local ok, e = pcall(getfenv, f)
                    if ok and type(e) == "table" then
                        local ok2, scr = pcall(function() return rawget(e, "script") end)
                        if ok2 and scr and typeof(scr) == "Instance" then
                            local ok3, scrStr = pcall(tostring, scr)
                            if ok3 and (scr == ls3 or (type(scrStr) == "string" and scrStr:find("LoadingScreen"))) then
                                local ok4, cs = pcall(debug.getconstants, f)
                                if ok4 and type(cs) == "table" then
                                    for _, k in eli_ipairs(cs) do
                                        if type(k) == "string" and (k:find("TakeTheL") or k:find("ban") or k:find("kick")) then
                                            pcall(function() hookfunction(f, function() end) end)
                                            break
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                if index % 1500 == 0 then task.wait() end
            end
        end)
    end)

    local antidetect = true
    local detecteds = {
        ["localscript3"] = true,
        ["miscellaneouscontroller"] = true
    }
    local callerVerdicts = setmetatable({}, { __mode = "k" })
    local original
    pcall(function()
        if not (hookmetamethod and newcclosure and getcallingscript) then return end
        original = hookmetamethod(game, "__index", newcclosure(function(self, key)
            if antidetect and (key == "Name" or key == "Text") then
                local caller = getcallingscript()
                if caller then
                    local blocked = callerVerdicts[caller]
                    if blocked == nil then
                        local ok, result = pcall(function()
                            return detecteds[string.lower(original(caller, "Name"))] == true
                        end)
                        blocked = ok and result or false
                        callerVerdicts[caller] = blocked
                    end
                    if blocked then return "" end
                end
            end
            return original(self, key)
        end))
    end)
    getgenv().elisium_set_antidetect = function(v) antidetect = v and true or false end

    -- take.lua waits out the loading screen before continuing (bounded so we never
    -- hang forever if the LoadingScreen never appears/leaves).
    pcall(function()
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if pg then
            local tries = 0
            while pg:FindFirstChild("LoadingScreen") and tries < 600 do
                task.wait(); tries += 1
            end
        end
    end)
end
-- ═══════════════════════════════════════════════════════════════════════════

local inputService   = game:GetService("UserInputService")
local runService     = game:GetService("RunService")
local tweenService   = game:GetService("TweenService")
local players        = game:GetService("Players")
local localPlayer    = players.LocalPlayer
local mouse          = localPlayer:GetMouse()

local menu           = game:GetObjects("rbxassetid://12702460854")[1]

if syn and syn.protect_gui then
    syn.protect_gui(menu)
elseif PROTECTGUI then
    PROTECTGUI(menu)
elseif protect_gui then
    protect_gui(menu)
elseif protectgui then
    protectgui(menu)
elseif gethui then
    menu.Parent = gethui()
end
menu.bg.Position     = UDim2.new(0.5,-menu.bg.Size.X.Offset/2,0.5,-menu.bg.Size.Y.Offset/2)
menu.Parent          = game:GetService("CoreGui")
menu.bg.pre.Text = 'riots<font color="#ff2a2a">.wtf</font>'
local library = {cheatname = "";ext = "";gamename = "";colorpicking = false;tabbuttons = {};tabs = {};options = {};flags = {};scrolling = false;notifyText = Drawing.new("Text");playing = false;multiZindex = 200;toInvis = {};libColor = Color3.fromRGB(255, 42, 42);disabledcolor = Color3.fromRGB(120, 0, 0);blacklisted = {Enum.KeyCode.W,Enum.KeyCode.A,Enum.KeyCode.S,Enum.KeyCode.D,Enum.UserInputType.MouseMovement};currentAimTarget = nil;currentAimTargetAt = nil;getPlayerWeapon = nil;_openModeMenu = nil;startNameScan = nil}

function draggable(a)local b=inputService;local c;local d;local e;local f;local function g(h)if not library.colorpicking then local i=h.Position-e;a.Position=UDim2.new(f.X.Scale,f.X.Offset+i.X,f.Y.Scale,f.Y.Offset+i.Y)end end;a.InputBegan:Connect(function(h)if h.UserInputType==Enum.UserInputType.MouseButton1 or h.UserInputType==Enum.UserInputType.Touch then c=true;e=h.Position;f=a.Position;h.Changed:Connect(function()if h.UserInputState==Enum.UserInputState.End then c=false end end)end end)a.InputChanged:Connect(function(h)if h.UserInputType==Enum.UserInputType.MouseMovement or h.UserInputType==Enum.UserInputType.Touch then d=h end end)b.InputChanged:Connect(function(h)if h==d and c then g(h)end end)end
draggable(menu.bg)

local menuScale = menu.bg:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
menuScale.Parent = menu.bg
-- one-time, non-per-frame function; encrypted via v14 LPH_ENCFUNC so encryption
-- cost never touches a render loop. LPH_ENCFUNC(fn, encKey, decKey): encKey is a
-- 64-char hex CONSTANT, decKey is the runtime VARIABLE riotsDecKey (same value).
local playMenuIntro = LPH_ENCFUNC(function()
    pcall(function()
        menuScale.Scale = 0.9
        tweenService:Create(menuScale, TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Scale = 1}):Play()
    end)
end, "a3f5c9012e7b46d8419caf62038d5e71bc90784af1d2635e8a04c7be95201f3d", riotsDecKey)

menu.Enabled = false

local tabholder = menu.bg.bg.bg.bg.main.group
local tabviewer = menu.bg.bg.bg.bg.tabbuttons

local function enlargeColumns(newTab) end

inputService.InputEnded:Connect(function(key)
    if key.KeyCode == Enum.KeyCode.RightShift then
        menu.Enabled = not menu.Enabled
        library.scrolling = false
        library.colorpicking = false
        for i,v in next, library.toInvis do
            v.Visible = false
        end
        if menu.Enabled then playMenuIntro() end
    end
end)

local keyNames = {
    [Enum.KeyCode.LeftAlt] = 'LALT';
    [Enum.KeyCode.RightAlt] = 'RALT';
    [Enum.KeyCode.LeftControl] = 'LCTRL';
    [Enum.KeyCode.RightControl] = 'RCTRL';
    [Enum.KeyCode.LeftShift] = 'LSHIFT';
    [Enum.KeyCode.RightShift] = 'RSHIFT';
    [Enum.KeyCode.Underscore] = '_';
    [Enum.KeyCode.Minus] = '-';
    [Enum.KeyCode.Plus] = '+';
    [Enum.KeyCode.Period] = '.';
    [Enum.KeyCode.Slash] = '/';
    [Enum.KeyCode.BackSlash] = '\\';
    [Enum.KeyCode.Question] = '?';
    [Enum.UserInputType.MouseButton1] = 'MB1';
    [Enum.UserInputType.MouseButton2] = 'MB2';
    [Enum.UserInputType.MouseButton3] = 'MB3';
}

library.notifyText.Font = 2
library.notifyText.Size = 13
library.notifyText.Outline = true
library.notifyText.Color = Color3.new(1,1,1)
library.notifyText.Position = Vector2.new(10,60)

function library:Tween(...)
    tweenService:Create(...):Play()
end

library.accentObjects = {}
function library:registerAccent(obj, prop)
    prop = prop or "BackgroundColor3"
    table.insert(library.accentObjects, { obj = obj, prop = prop })
    pcall(function() obj[prop] = library.libColor end)
end
function library:recolor(color)
    library.libColor = color
    for _, e in ipairs(library.accentObjects) do
        if e.apply then
            pcall(e.apply, color)
        elseif e.obj and e.obj.Parent then
            pcall(function() e.obj[e.prop] = color end)
        end
    end
end


library.colorFrames = library.colorFrames or {}
function library:registerColorFrame(frame)
    table.insert(library.colorFrames, frame)
end
function library:openColorFrame(frame)
    for _, f in ipairs(library.colorFrames) do
        if f ~= frame then pcall(function() f.Visible = false end) end
    end
    frame.Visible = true
end
function library:closeAllColorFrames()
    for _, f in ipairs(library.colorFrames) do
        pcall(function() f.Visible = false end)
    end
end

-- ── ONE shared drag dispatcher for ALL colorpickers ──────────────────────────
-- Previously each picker attached its own inputService.InputChanged (fires on
-- every mouse-move) + InputEnded. With ~50 pickers that meant ~50 mouse-move
-- handlers running every frame = the load/gameplay freeze. Now there is a single
-- pair of global listeners; each picker just sets library._activeColorDrag to
-- its own apply function while its slider is held.
library._activeColorDrag = nil
if not library._colorDragBound then
    library._colorDragBound = true
    inputService.InputChanged:Connect(function(inp)
        if inp.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local d = library._activeColorDrag
        if d then d() end
    end)
    inputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 and library._activeColorDrag then
            library._activeColorDrag = nil
            library.colorpicking = false
        end
    end)
end

-- ── shared colorpicker popup factory ─────────────────────────────────────────
-- Design matches the menu's groupbox aesthetic:
--   bg rgb(20,20,20), 2px rgb(30,30,30) border, Code font 13px, accent top strip.
-- Drag logic uses a global InputChanged listener so the cursor can leave the
-- element while still tracking — fixes the "stuck" / "jittery" drag bug.
-- HSV is back-solved from incoming Color3 so indicators always match the swatch.
-- Only one picker open at a time via library:openColorFrame.
function library:buildColorPicker(args, triggerBtn, swatch)
    local hud = library.hudGui

    -- layout constants — mirror menu padding
    local PAD     = 8
    local SV_SIZE = 148   -- slightly larger for better precision
    local HUE_W   = 12
    local HEX_H   = 18
    local TITLE_H = 16
    local GAP     = 4     -- gap between SV box and hue strip
    local CP_W    = PAD + SV_SIZE + GAP + HUE_W + PAD
    local CP_H    = PAD + TITLE_H + PAD + SV_SIZE + GAP + HEX_H + PAD

    -- ── outer panel ──────────────────────────────────────────────────────────
    local colorFrame = Instance.new("Frame")
    colorFrame.Name = "colorFrame"
    colorFrame.Parent = hud
    colorFrame.Visible = false
    colorFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    colorFrame.BorderColor3 = Color3.fromRGB(30, 30, 30)
    colorFrame.BorderSizePixel = 2
    colorFrame.Size = UDim2.fromOffset(CP_W, CP_H)
    colorFrame.ZIndex = 300
    colorFrame.Active = true
    library:registerColorFrame(colorFrame)
    draggable(colorFrame)

    -- accent top strip (1 px, tracks libColor)
    local cfStrip = Instance.new("Frame")
    cfStrip.BorderSizePixel = 0
    cfStrip.BackgroundColor3 = library.libColor
    cfStrip.Size = UDim2.new(1, 0, 0, 1)
    cfStrip.ZIndex = 302
    cfStrip.Parent = colorFrame
    library:registerAccent(cfStrip)

    -- title row: label left, small [×] close button right
    local cfTitle = Instance.new("TextLabel")
    cfTitle.BackgroundTransparency = 1
    cfTitle.Position = UDim2.fromOffset(PAD, PAD)
    cfTitle.Size = UDim2.fromOffset(CP_W - PAD*2 - 18, TITLE_H)
    cfTitle.Font = Enum.Font.Code
    cfTitle.Text = args.text or args.flag
    cfTitle.TextColor3 = Color3.fromRGB(200, 200, 200)
    cfTitle.TextSize = 13
    cfTitle.TextXAlignment = Enum.TextXAlignment.Left
    cfTitle.TextStrokeTransparency = 0
    cfTitle.ZIndex = 301
    cfTitle.Parent = colorFrame

    local closeBtn = Instance.new("TextButton")
    closeBtn.BackgroundTransparency = 1
    closeBtn.Position = UDim2.new(1, -PAD - 14, 0, PAD)
    closeBtn.Size = UDim2.fromOffset(14, TITLE_H)
    closeBtn.Font = Enum.Font.Code
    closeBtn.Text = "×"
    closeBtn.TextSize = 14
    closeBtn.TextColor3 = Color3.fromRGB(150, 150, 150)
    closeBtn.TextStrokeTransparency = 0
    closeBtn.ZIndex = 302
    closeBtn.Parent = colorFrame

    -- 1px divider below title
    local divider = Instance.new("Frame")
    divider.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    divider.BorderSizePixel = 0
    divider.Position = UDim2.fromOffset(0, PAD + TITLE_H + 2)
    divider.Size = UDim2.new(1, 0, 0, 1)
    divider.ZIndex = 301
    divider.Parent = colorFrame

    local CONTENT_Y = PAD + TITLE_H + PAD  -- y where SV box starts

    -- ── SV (saturation/value) square ─────────────────────────────────────────
    local svBg = Instance.new("Frame")
    svBg.BackgroundColor3 = Color3.fromRGB(255, 0, 0)  -- tinted by hue in code
    svBg.BorderSizePixel = 0
    svBg.Position = UDim2.fromOffset(PAD, CONTENT_Y)
    svBg.Size = UDim2.fromOffset(SV_SIZE, SV_SIZE)
    svBg.ZIndex = 301
    svBg.ClipsDescendants = true
    svBg.Parent = colorFrame

    -- correct SV gradient image: white-to-hue on X, opaque-to-black on Y
    local svImg = Instance.new("ImageLabel")
    svImg.Name = "svImg"
    svImg.BackgroundTransparency = 1
    svImg.Size = UDim2.new(1, 0, 1, 0)
    svImg.ZIndex = 302
    svImg.Active = true
    svImg.Image = "rbxassetid://4155801252"   -- correct Sat/Val square
    svImg.Parent = svBg

    -- cursor: crosshair-style — a tiny white square with black 1px outline
    local svCursor = Instance.new("Frame")
    svCursor.Name = "svCursor"
    svCursor.AnchorPoint = Vector2.new(0.5, 0.5)
    svCursor.BackgroundColor3 = Color3.new(1, 1, 1)
    svCursor.BorderColor3 = Color3.new(0, 0, 0)
    svCursor.BorderSizePixel = 1
    svCursor.Size = UDim2.fromOffset(6, 6)
    svCursor.ZIndex = 305
    svCursor.Parent = svBg

    -- ── hue strip (vertical, right of SV) ────────────────────────────────────
    local hueBg = Instance.new("Frame")
    hueBg.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    hueBg.BorderSizePixel = 0
    hueBg.Position = UDim2.fromOffset(PAD + SV_SIZE + GAP, CONTENT_Y)
    hueBg.Size = UDim2.fromOffset(HUE_W, SV_SIZE)
    hueBg.ZIndex = 301
    hueBg.ClipsDescendants = true
    hueBg.Parent = colorFrame

    local hueImg = Instance.new("ImageLabel")
    hueImg.Name = "hueImg"
    hueImg.BackgroundTransparency = 1
    hueImg.Size = UDim2.new(1, 0, 1, 0)
    hueImg.ZIndex = 302
    hueImg.Active = true
    hueImg.Image = "rbxassetid://2615692420"  -- vertical hue rainbow
    hueImg.Parent = hueBg

    -- hue cursor: a white 2px-tall bar spanning full width
    local hueCursor = Instance.new("Frame")
    hueCursor.Name = "hueCursor"
    hueCursor.AnchorPoint = Vector2.new(0, 0.5)
    hueCursor.BackgroundColor3 = Color3.new(1, 1, 1)
    hueCursor.BorderColor3 = Color3.new(0, 0, 0)
    hueCursor.BorderSizePixel = 1
    hueCursor.Size = UDim2.new(1, 0, 0, 3)
    hueCursor.ZIndex = 305
    hueCursor.Parent = hueBg

    -- ── bottom row: preview swatch + hex input ───────────────────────────────
    local ROW_Y = CONTENT_Y + SV_SIZE + GAP

    local preview = Instance.new("Frame")
    preview.BackgroundColor3 = Color3.new(1, 0, 0)
    preview.BorderColor3 = Color3.fromRGB(35, 35, 35)
    preview.BorderSizePixel = 1
    preview.Position = UDim2.fromOffset(PAD, ROW_Y)
    preview.Size = UDim2.fromOffset(HEX_H, HEX_H)
    preview.ZIndex = 301
    preview.Parent = colorFrame

    -- hex input box — allows typing a hex color directly
    local hexBg = Instance.new("Frame")
    hexBg.BackgroundColor3 = Color3.fromRGB(14, 14, 14)
    hexBg.BorderColor3 = Color3.fromRGB(35, 35, 35)
    hexBg.BorderSizePixel = 1
    hexBg.Position = UDim2.fromOffset(PAD + HEX_H + GAP, ROW_Y)
    hexBg.Size = UDim2.fromOffset(CP_W - PAD*2 - HEX_H - GAP, HEX_H)
    hexBg.ZIndex = 301
    hexBg.Parent = colorFrame

    local hexBox = Instance.new("TextBox")
    hexBox.BackgroundTransparency = 1
    hexBox.Size = UDim2.new(1, -8, 1, 0)
    hexBox.Position = UDim2.fromOffset(4, 0)
    hexBox.Font = Enum.Font.Code
    hexBox.Text = "FF2A2A"
    hexBox.TextColor3 = Color3.fromRGB(210, 210, 210)
    hexBox.PlaceholderText = "hex..."
    hexBox.PlaceholderColor3 = Color3.fromRGB(90, 90, 90)
    hexBox.TextSize = 12
    hexBox.ClearTextOnFocus = false
    hexBox.TextXAlignment = Enum.TextXAlignment.Left
    hexBox.TextStrokeTransparency = 0
    hexBox.ZIndex = 302
    hexBox.Parent = hexBg

    -- ── HSV state + logic ─────────────────────────────────────────────────────
    local hueP, satP, valP = 0, 1, 0  -- hue[0-1], sat[0-1], val represented as 1-valP

    local function updateIndicators()
        -- SV cursor positioned at (sat, 1-val) in the square
        svCursor.Position = UDim2.new(satP, 0, valP, 0)
        -- hue cursor positioned at hue fraction
        hueCursor.Position = UDim2.new(0, 0, hueP, 0)
        -- tint the SV background to the pure hue
        svBg.BackgroundColor3 = Color3.fromHSV(hueP, 1, 1)
    end

    local suppressHex = false
    local function updateValue(value, _fakevalue)
        if typeof(value) ~= "Color3" then value = Color3.new(1, 1, 1) end
        local h, s, v = value:ToHSV()
        hueP = math.clamp(h, 0, 1)
        satP = math.clamp(s, 0, 1)
        valP = math.clamp(1 - v, 0, 1)
        library.flags[args.flag] = value
        preview.BackgroundColor3 = value
        updateIndicators()
        suppressHex = true
        hexBox.Text = value:ToHex():upper()
        suppressHex = false
        if args.__front then args.__front.BackgroundColor3 = value end
        if args.callback then args.callback(value) end
    end

    local function recompute()
        local c = Color3.fromHSV(hueP, satP, 1 - valP)
        library.flags[args.flag] = c
        preview.BackgroundColor3 = c
        updateIndicators()
        suppressHex = true
        hexBox.Text = c:ToHex():upper()
        suppressHex = false
        if args.__front then args.__front.BackgroundColor3 = c end
        if args.callback then args.callback(c) end
    end

    -- ── dragging — routed through the single shared dispatcher so the cursor
    --    can leave the element while still tracking (no per-picker listeners)
    local function applyHueDrag()
        local m = inputService:GetMouseLocation()
        local ap = hueImg.AbsolutePosition
        local as = hueImg.AbsoluteSize
        hueP = math.clamp((m.Y - ap.Y) / math.max(as.Y, 1), 0, 1)
        recompute()
    end

    local function applySVDrag()
        local m = inputService:GetMouseLocation()
        local ap = svImg.AbsolutePosition
        local as = svImg.AbsoluteSize
        satP = math.clamp((m.X - ap.X) / math.max(as.X, 1), 0, 1)
        valP = math.clamp((m.Y - ap.Y) / math.max(as.Y, 1), 0, 1)
        recompute()
    end

    -- press starts a drag by pointing the SHARED dispatcher at this picker's
    -- apply fn; the single global InputChanged/InputEnded pair (defined once
    -- above) drives it. No per-picker global listeners = no freeze.
    hueImg.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            library.colorpicking = true
            library._activeColorDrag = applyHueDrag
            applyHueDrag()
        end
    end)
    svImg.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            library.colorpicking = true
            library._activeColorDrag = applySVDrag
            applySVDrag()
        end
    end)

    -- hex input: commit on FocusLost or Enter
    local function applyHex(text)
        if suppressHex then return end
        text = text:gsub("[^%x]", ""):sub(1, 6)
        if #text == 6 then
            local ok, c = pcall(Color3.fromHex, text)
            if ok and typeof(c) == "Color3" then updateValue(c) end
        end
    end
    hexBox.FocusLost:Connect(function() applyHex(hexBox.Text) end)
    hexBox:GetPropertyChangedSignal("Text"):Connect(function()
        if #hexBox.Text == 6 then applyHex(hexBox.Text) end
    end)

    -- ── open / close ──────────────────────────────────────────────────────────
    local function openAt()
        local ap = triggerBtn.AbsolutePosition
        local as = triggerBtn.AbsoluteSize
        local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
        local px = ap.X + as.X + 6
        local py = ap.Y
        if px + CP_W > vp.X - 4 then px = ap.X - CP_W - 6 end
        if py + CP_H > vp.Y - 4 then py = vp.Y - CP_H - 4 end
        colorFrame.Position = UDim2.fromOffset(math.max(4, px), math.max(4, py))
        library:openColorFrame(colorFrame)
    end

    triggerBtn.MouseButton1Click:Connect(function()
        if colorFrame.Visible then colorFrame.Visible = false
        else openAt() end
        if swatch then swatch.BorderColor3 = Color3.fromRGB(30, 30, 30) end
    end)
    closeBtn.MouseButton1Click:Connect(function() colorFrame.Visible = false end)

    if swatch then
        triggerBtn.MouseEnter:Connect(function() swatch.BorderColor3 = library.libColor end)
        triggerBtn.MouseLeave:Connect(function() swatch.BorderColor3 = Color3.fromRGB(30, 30, 30) end)
    end

    return colorFrame, updateValue
end

local hudGui = Instance.new("ScreenGui")
library.hudGui = hudGui
hudGui.Name = "riotsHUD"
hudGui.ResetOnSpawn = false
hudGui.IgnoreGuiInset = true
hudGui.DisplayOrder = 999999
hudGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() hudGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)

-- ═══════════════════════════════════════════════════════════════════════════
-- SHARED DAMAGE EVENT SYSTEM (exact take.lua hook)
-- take.lua hooks fighter_controller.LocalFighter.ReplicateFromServer (an INSTANCE
-- method on the LocalFighter object) — NOT the module's function. The old test.lua
-- code hooked the module itself, which never fired. Fixed here: one hook, one
-- dispatcher, and every hit feature (chams/sounds/effects/damage numbers/notify)
-- subscribes via library:onDamage(fn).
library._damageSubs = {}
function library:onDamage(fn) library._damageSubs[#library._damageSubs + 1] = fn end
function library:fireDamage(hitChar, hitRoot, damage, isHeadshot)
    for _, fn in ipairs(library._damageSubs) do
        pcall(fn, hitChar, hitRoot, damage, isHeadshot)
    end
end
-- hitmarker sound subscribers (fired by the ClientViewModel.PlayHitmarkerSound hook)
library._hitmarkerSubs = {}
function library:onHitmarker(fn) library._hitmarkerSubs[#library._hitmarkerSubs + 1] = fn end

task.spawn(function()
    -- damage hook — resolve LocalFighter exactly like take.lua
    pcall(function()
        local PS = localPlayer:WaitForChild("PlayerScripts", 20)
        local Controllers = PS and PS:WaitForChild("Controllers", 20)
        local fcMod = Controllers and Controllers:WaitForChild("FighterController", 20)
        if not fcMod then return end
        local fighter_controller = require(fcMod)
        -- LocalFighter may not exist immediately; wait for it
        local lf = fighter_controller.LocalFighter
        local tries = 0
        while not lf and tries < 200 do task.wait(0.1); lf = fighter_controller.LocalFighter; tries += 1 end
        if not (lf and lf.ReplicateFromServer) then return end
        local replicate_from_server = lf.ReplicateFromServer
        lf.ReplicateFromServer = function(controller, _type, ...)
            if _type == "DamageNumberEffect" then
                local hit_root, hit_damage, is_headshot = ...
                if hit_root and hit_damage then
                    local hit_char = hit_root.Parent
                    if hit_char and hit_char:FindFirstChildOfClass("Humanoid") then
                        -- fallback path: only fire if billboard detection is unavailable
                        if not library._billboardHitActive then
                            library:fireDamage(hit_char, hit_root, hit_damage, is_headshot)
                        end
                    end
                end
            end
            return replicate_from_server(controller, _type, ...)
        end
    end)
    -- hitmarker sound hook — correct module path from take.lua
    pcall(function()
        local PS = localPlayer:WaitForChild("PlayerScripts", 20)
        local vmMod = PS
            and PS:WaitForChild("Modules", 20)
            and PS.Modules:WaitForChild("ClientReplicatedClasses", 20)
            and PS.Modules.ClientReplicatedClasses:WaitForChild("ClientFighter", 20)
            and PS.Modules.ClientReplicatedClasses.ClientFighter:WaitForChild("ClientItem", 20)
            and PS.Modules.ClientReplicatedClasses.ClientFighter.ClientItem:WaitForChild("ClientViewModel", 20)
        if not vmMod then return end
        local client_viewmodel = require(vmMod)
        if not client_viewmodel.PlayHitmarkerSound then return end
        local play_hitmarker_sound = client_viewmodel.PlayHitmarkerSound
        client_viewmodel.PlayHitmarkerSound = function(controller, critical, pitch)
            local suppress = false
            for _, fn in ipairs(library._hitmarkerSubs) do
                local ok, s = pcall(fn, controller, critical, pitch)
                if ok and s then suppress = true end
            end
            if suppress then return end
            return play_hitmarker_sound(controller, critical, pitch)
        end
    end)
end)

-- ── BillboardGui-based hit detection (ported from take1.lua) ─────────────────
-- The game spawns a BillboardGui with a damage-number TextLabel every time you
-- land a hit. Detecting these is far more reliable than the ReplicateFromServer
-- hook (works even when the module hook fails to resolve). We fire both the
-- shared damage event AND a dedicated billboard event (for hit effects/sounds
-- that want the exact world adornee).
library._hitBillboardSubs = {}
function library:onHitBillboard(fn) library._hitBillboardSubs[#library._hitBillboardSubs + 1] = fn end
do
    local damageBillboardInfoCache = setmetatable({}, {__mode = "k"})
    function library.getDamageBillboardInfo(obj)
        local cached = damageBillboardInfoCache[obj]
        if cached ~= nil then return cached or nil end
        if not obj:IsA("BillboardGui") then damageBillboardInfoCache[obj] = false; return nil end
        if obj.Name == "FortniteDamageNumber" then damageBillboardInfoCache[obj] = false; return nil end
        local lbl = obj:FindFirstChildWhichIsA("TextLabel", true)
        if not lbl then damageBillboardInfoCache[obj] = false; return nil end
        local dmg = tonumber((tostring(lbl.Text):gsub("[^%d%.%-]", "")))
        if not (dmg and dmg > 0) then damageBillboardInfoCache[obj] = false; return nil end
        local adornee = obj.Adornee or (obj.Parent and obj.Parent:IsA("BasePart") and obj.Parent)
        if not adornee then damageBillboardInfoCache[obj] = false; return nil end
        local info = { lbl = lbl, dmg = dmg, adornee = adornee }
        damageBillboardInfoCache[obj] = info
        return info
    end

    Workspace.DescendantAdded:Connect(function(obj)
        if #library._hitBillboardSubs == 0 and #library._damageSubs == 0 then return end
        if not obj:IsA("BillboardGui") then return end
        local info = library.getDamageBillboardInfo(obj)
        if not info then return end
        -- billboard detection is confirmed working; tell the ReplicateFromServer
        -- fallback to stand down so damage events don't double-fire
        library._billboardHitActive = true
        task.defer(function()
            if not obj or not obj.Parent then return end
            -- fire dedicated billboard subs (hit effects/sounds) with the adornee
            for _, fn in ipairs(library._hitBillboardSubs) do
                pcall(fn, info)
            end
            -- also feed the shared damage event so chams/damage-numbers/notify work
            local adornee = info.adornee
            local part = adornee
            if adornee:IsA("Attachment") then part = adornee.Parent end
            local char = nil
            if part then
                local ok, res = pcall(function() return part:FindFirstAncestorOfClass("Model") end)
                if ok then char = res end
            end
            local hitRoot = (part and part:IsA("BasePart")) and part or (char and char:FindFirstChild("HumanoidRootPart"))
            if char then
                local nameL = string.lower(part and part.Name or "")
                local isHead = nameL:find("head") ~= nil
                library:fireDamage(char, hitRoot or part, info.dmg, isHead)
            end
        end)
    end)
end

local function accentStrip(parent, order)

    local strip = Instance.new("Frame")
    strip.Name = "accent"
    strip.BorderSizePixel = 0
    strip.BackgroundColor3 = library.libColor
    strip.Size = UDim2.new(1, 0, 0, 1)
    strip.Position = UDim2.new(0, 0, 0, 0)
    strip.ZIndex = (order or 1) + 1
    strip.Parent = parent
    library:registerAccent(strip)
    return strip
end

_G.riotsHUD = _G.riotsHUD or { Watermark = false, KeybindList = true }
local watermark = Instance.new("Frame")
watermark.Name = "watermark"
watermark.AnchorPoint = Vector2.new(0, 0)
watermark.Position = UDim2.new(0, 12, 0, 12)
watermark.Size = UDim2.new(0, 220, 0, 22)
watermark.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
watermark.BorderColor3 = Color3.fromRGB(0, 0, 0)
watermark.BorderSizePixel = 1
watermark.Visible = true
watermark.Parent = hudGui
accentStrip(watermark, 2)

local wmText = Instance.new("TextLabel")
wmText.BackgroundTransparency = 1
wmText.Position = UDim2.new(0, 8, 0, 0)
wmText.Size = UDim2.new(1, -16, 1, 0)
wmText.Font = Enum.Font.Code
wmText.TextSize = 13
wmText.TextColor3 = Color3.fromRGB(240, 240, 240)
wmText.TextXAlignment = Enum.TextXAlignment.Left
wmText.TextStrokeTransparency = 0
wmText.RichText = true
wmText.ZIndex = 3
wmText.Text = "riots.wtf"
wmText.Parent = watermark
draggable(watermark)

do
    local fpsAccum, fpsFrames, fps = 0, 0, 0
    runService.RenderStepped:Connect(function(dt)
        fpsAccum += dt; fpsFrames += 1
        if fpsAccum >= 0.5 then
            fps = math.floor(fpsFrames / fpsAccum + 0.5)
            fpsAccum, fpsFrames = 0, 0
        end
        watermark.Visible = _G.riotsHUD.Watermark ~= false
        if watermark.Visible then
            local ping = 0
            pcall(function()
                ping = math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() + 0.5)
            end)
            wmText.Text = string.format(
                'riots<font color="#ff2a2a">.wtf</font>  |  %dfps  |  %dms', fps, ping)

            watermark.Size = UDim2.new(0, math.max(160, wmText.TextBounds.X + 20), 0, 22)
        end
    end)
end

-- ─── custom text watermark (animated, per-letter) ─────────────────────────────
library.textWatermarkCfg = library.textWatermarkCfg or {
    enabled = false,
    text    = "riots.wtf",
    anim    = "wave",          -- "static" | "wave" | "rainbow" | "wave+rainbow"
    color   = Color3.fromRGB(255, 42, 42),
}
;(function()
    local twCfg = library.textWatermarkCfg
    local LETTER_W = 11
    local twFrame = Instance.new("Frame")
    twFrame.Name = "textwatermark"
    twFrame.AnchorPoint = Vector2.new(0.5, 0)
    twFrame.Position = UDim2.new(0.5, 0, 0, 40)
    twFrame.Size = UDim2.fromOffset(220, 24)
    twFrame.BackgroundTransparency = 1
    twFrame.BorderSizePixel = 0
    twFrame.Visible = false
    twFrame.Parent = hudGui
    draggable(twFrame)

    local labels = {}
    local builtText = nil

    local function rebuild(str)
        for _, l in ipairs(labels) do l:Destroy() end
        table.clear(labels)
        for i = 1, #str do
            local lbl = Instance.new("TextLabel")
            lbl.BackgroundTransparency = 1
            lbl.BorderSizePixel = 0
            lbl.Size = UDim2.fromOffset(LETTER_W, 22)
            lbl.Position = UDim2.fromOffset((i-1)*LETTER_W, 1)
            lbl.Font = Enum.Font.Code
            lbl.TextSize = 15
            lbl.TextStrokeTransparency = 0
            lbl.Text = str:sub(i, i)
            lbl.RichText = false
            lbl.ZIndex = 3
            lbl.Parent = twFrame
            labels[i] = lbl
        end
        builtText = str
        twFrame.Size = UDim2.fromOffset(math.max(1, #str) * LETTER_W, 24)
    end

    local function hsv(h)
        return Color3.fromHSV(h % 1, 0.85, 1)
    end

    local _t = 0
    runService.RenderStepped:Connect(function(dt)
        _t = _t + dt
        local on = (twCfg.enabled == true) and not menu.Enabled
        twFrame.Visible = on
        if not on then return end

        local str = twCfg.text
        if str == nil or str == "" then str = " " end
        if str ~= builtText then rebuild(str) end

        local n = #labels
        for i = 1, n do
            local lbl = labels[i]
            local yOff = 0
            local col = twCfg.color

            if twCfg.anim == "wave" then
                yOff = math.sin(_t * 3 - (i-1) * 0.45) * 3
            elseif twCfg.anim == "rainbow" then
                col = hsv(_t * 0.25 + (i-1) / math.max(1, n))
            elseif twCfg.anim == "wave+rainbow" then
                yOff = math.sin(_t * 3 - (i-1) * 0.45) * 3
                col = hsv(_t * 0.25 + (i-1) / math.max(1, n))
            end
            -- "static" leaves yOff=0 and col=twCfg.color

            lbl.Position = UDim2.fromOffset((i-1)*LETTER_W, 1 - yOff)
            lbl.TextColor3 = col
        end
    end)
end)()

local notifyHolder = Instance.new("Frame")
notifyHolder.Name = "notifications"
notifyHolder.AnchorPoint = Vector2.new(1, 1)
notifyHolder.Position = UDim2.new(1, -12, 1, -12)
notifyHolder.Size = UDim2.new(0, 260, 1, -24)
notifyHolder.BackgroundTransparency = 1
notifyHolder.Parent = hudGui

local notifyLayout = Instance.new("UIListLayout")
notifyLayout.SortOrder = Enum.SortOrder.LayoutOrder
notifyLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
notifyLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
notifyLayout.Padding = UDim.new(0, 6)
notifyLayout.Parent = notifyHolder

function library:notify(text, duration)
    duration = duration or 3
    local card = Instance.new("Frame")
    card.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    card.BorderColor3 = Color3.fromRGB(0, 0, 0)
    card.BorderSizePixel = 1
    card.Size = UDim2.new(1, 0, 0, 26)
    card.BackgroundTransparency = 1
    card.Parent = notifyHolder

    local bar = Instance.new("Frame")
    bar.BorderSizePixel = 0
    bar.BackgroundColor3 = library.libColor
    bar.Size = UDim2.new(0, 2, 1, 0)
    bar.Parent = card
    library:registerAccent(bar)

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.Position = UDim2.new(0, 8, 0, 0)
    label.Size = UDim2.new(1, -12, 1, 0)
    label.Font = Enum.Font.Code
    label.TextSize = 13
    label.TextColor3 = Color3.fromRGB(240, 240, 240)
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.TextStrokeTransparency = 0.6
    label.Text = tostring(text)
    label.Parent = card

    local prog = Instance.new("Frame")
    prog.BorderSizePixel = 0
    prog.BackgroundColor3 = library.libColor
    prog.AnchorPoint = Vector2.new(0, 1)
    prog.Position = UDim2.new(0, 0, 1, 0)
    prog.Size = UDim2.new(1, 0, 0, 1)
    prog.Parent = card
    library:registerAccent(prog)

    card.BackgroundTransparency = 1
    library:Tween(card, TweenInfo.new(0.2), { BackgroundTransparency = 0 })
    library:Tween(prog, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 1) })

    task.spawn(function()
        task.wait(duration)
        pcall(function()
            library:Tween(card, TweenInfo.new(0.25), { BackgroundTransparency = 1 })
            library:Tween(label, TweenInfo.new(0.25), { TextTransparency = 1, TextStrokeTransparency = 1 })
        end)
        task.wait(0.3)
        card:Destroy()
    end)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HIT NOTIFICATION STACK (ported behavior from take1.lua) — dedicated animated
-- boxes stacked top-left, with selectable in-animation. Distinct from the
-- generic library:notify toast (bottom-right).
-- ═══════════════════════════════════════════════════════════════════════════
library.hitNotifCfg = library.hitNotifCfg or {
    color = Color3.fromRGB(235, 235, 235),
    textSize = 14,
    maxVisible = 8,
    duration = 3,
    stackGap = 6,
    inAnimation = "fade bounce",
}
library.hitNotifAnimStyles = { "fade", "slide left", "slide right", "slide down", "bounce", "fade bounce", "scale" }
do
    local hn = library.hitNotifCfg
    local root = Instance.new("Frame")
    root.Name = "hitNotifications"
    root.BackgroundTransparency = 1
    root.Position = UDim2.fromOffset(12, 12)
    root.Size = UDim2.new(0, 320, 1, -24)
    root.Visible = false
    root.Parent = hudGui

    local entries = {}

    local function easeOutBack(t)
        local c1, c3 = 1.70158, 2.70158
        return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
    end
    local function easeOutCubic(t) return 1 - (1 - t) ^ 3 end

    -- returns alpha(0-1), offsetX, offsetY, scale for the in animation
    local function sampleIn(style, t)
        t = math.clamp(t, 0, 1)
        if style == "fade" then
            return easeOutCubic(t), 0, 0, 1
        elseif style == "slide left" then
            return easeOutCubic(t), (1 - easeOutCubic(t)) * -40, 0, 1
        elseif style == "slide right" then
            return easeOutCubic(t), (1 - easeOutCubic(t)) * 40, 0, 1
        elseif style == "slide down" then
            return easeOutCubic(t), 0, (1 - easeOutCubic(t)) * -20, 1
        elseif style == "bounce" then
            return 1, 0, 0, easeOutBack(t)
        elseif style == "scale" then
            return easeOutCubic(t), 0, 0, 0.6 + 0.4 * easeOutCubic(t)
        else -- "fade bounce"
            return easeOutCubic(t), 0, 0, easeOutBack(t)
        end
    end

    function library:hitNotify(text, duration, animStyle, color)
        duration = duration or hn.duration or 3
        animStyle = animStyle or hn.inAnimation or "fade bounce"
        color = color or hn.color

        root.Visible = true
        local box = Instance.new("Frame")
        box.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
        box.BorderColor3 = Color3.fromRGB(0, 0, 0)
        box.BorderSizePixel = 1
        box.BackgroundTransparency = 1
        box.Size = UDim2.new(0, 300, 0, 24)
        box.Parent = root

        local strip = Instance.new("Frame")
        strip.BorderSizePixel = 0
        strip.BackgroundColor3 = library.libColor
        strip.Size = UDim2.new(0, 2, 1, 0)
        strip.Parent = box
        library:registerAccent(strip)

        local lbl = Instance.new("TextLabel")
        lbl.BackgroundTransparency = 1
        lbl.Position = UDim2.new(0, 8, 0, 0)
        lbl.Size = UDim2.new(1, -12, 1, 0)
        lbl.Font = Enum.Font.Code
        lbl.TextSize = hn.textSize or 14
        lbl.TextColor3 = color
        lbl.TextTransparency = 1
        lbl.TextStrokeTransparency = 1
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextTruncate = Enum.TextTruncate.AtEnd
        lbl.Text = tostring(text)
        lbl.Parent = box

        local entry = {
            box = box, lbl = lbl, strip = strip,
            start = tick(), phaseStart = tick(), phase = "in",
            duration = duration, style = animStyle,
            targetY = 0, displayY = 0, baseX = 0,
        }
        table.insert(entries, 1, entry)

        while #entries > math.clamp(hn.maxVisible or 8, 1, 25) do
            local e = entries[#entries]
            pcall(function() e.box:Destroy() end)
            table.remove(entries, #entries)
        end
    end

    runService.RenderStepped:Connect(function(dt)
        if #entries == 0 then root.Visible = false; return end
        root.Visible = not (menu and menu.Enabled)
        local now = tick()
        local gap = hn.stackGap or 6
        local inDur, outDur = 0.5, 0.35

        -- layout target Ys
        local y = 0
        for _, e in ipairs(entries) do
            e.targetY = y
            e.displayY = e.displayY + (e.targetY - e.displayY) * (1 - math.exp(-dt * 14))
            y = y + 24 + gap
        end

        local i = 1
        while i <= #entries do
            local e = entries[i]
            local age = now - e.start
            if e.phase == "in" then
                local t = (now - e.phaseStart) / inDur
                if t >= 1 then e.phase = "hold"; t = 1 end
                local a, ox, oy, sc = sampleIn(e.style, t)
                e.box.BackgroundTransparency = 1 - a
                e.lbl.TextTransparency = 1 - a
                e.lbl.TextStrokeTransparency = 0.4 + 0.6 * (1 - a)
                e.box.Position = UDim2.fromOffset(math.floor(e.baseX + ox), math.floor(e.displayY + oy))
                local w = math.floor(300 * sc)
                e.box.Size = UDim2.new(0, w, 0, math.floor(24 * sc))
            elseif e.phase == "hold" then
                e.box.BackgroundTransparency = 0
                e.lbl.TextTransparency = 0
                e.lbl.TextStrokeTransparency = 0.4
                e.box.Position = UDim2.fromOffset(e.baseX, math.floor(e.displayY))
                e.box.Size = UDim2.new(0, 300, 0, 24)
                if age >= e.duration - outDur then e.phase = "out"; e.phaseStart = now end
            elseif e.phase == "out" then
                local t = math.clamp((now - e.phaseStart) / outDur, 0, 1)
                local a = 1 - easeOutCubic(t)
                e.box.BackgroundTransparency = 1 - a
                e.lbl.TextTransparency = 1 - a
                e.lbl.TextStrokeTransparency = 0.4 + 0.6 * (1 - a)
                e.box.Position = UDim2.fromOffset(math.floor(e.baseX - (1 - a) * 20), math.floor(e.displayY))
                if t >= 1 then
                    pcall(function() e.box:Destroy() end)
                    table.remove(entries, i)
                    i = i - 1
                end
            end
            i = i + 1
        end
    end)
end

local keybindFrame = Instance.new("Frame")
keybindFrame.Name = "keybinds"
keybindFrame.AnchorPoint = Vector2.new(0, 0.5)
keybindFrame.Position = UDim2.new(0, 12, 0.5, 0)
keybindFrame.Size = UDim2.new(0, 170, 0, 22)
keybindFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
keybindFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
keybindFrame.BorderSizePixel = 1
keybindFrame.Visible = false
keybindFrame.Parent = hudGui
accentStrip(keybindFrame, 2)
draggable(keybindFrame)

local kbTitle = Instance.new("TextLabel")
kbTitle.BackgroundTransparency = 1
kbTitle.Position = UDim2.new(0, 8, 0, 2)
kbTitle.Size = UDim2.new(1, -16, 0, 16)
kbTitle.Font = Enum.Font.Code
kbTitle.TextSize = 13
kbTitle.TextColor3 = Color3.fromRGB(240, 240, 240)
kbTitle.TextXAlignment = Enum.TextXAlignment.Left
kbTitle.TextStrokeTransparency = 0
kbTitle.Text = "keybinds"
kbTitle.ZIndex = 3
kbTitle.Parent = keybindFrame

local kbList = Instance.new("Frame")
kbList.BackgroundTransparency = 1
kbList.Position = UDim2.new(0, 0, 0, 20)
kbList.Size = UDim2.new(1, 0, 1, -20)
kbList.Parent = keybindFrame

local kbLayout = Instance.new("UIListLayout")
kbLayout.SortOrder = Enum.SortOrder.Name
kbLayout.Parent = kbList

local function keyLabel(val)
    if typeof(val) == "EnumItem" then return val.Name end
    return tostring(val)
end

do
    local rows = {}
    runService.RenderStepped:Connect(function()
        if not _G.riotsHUD.KeybindList or library.flags["ShowKeybinds"] ~= true then
            keybindFrame.Visible = false
            return
        end

        local active = {}
        for flag, opt in pairs(library.options) do
            if opt.type == "keybind" then
                local v = library.flags[flag]
                if v ~= nil and v ~= Enum.KeyCode.Unknown then
                    local name = (opt.oldargs and (opt.oldargs.text or opt.oldargs.flag)) or flag
                    active[#active+1] = { name = tostring(name):gsub("_key$",""), key = keyLabel(v) }
                end
            end
        end
        table.sort(active, function(a, b) return a.name < b.name end)

        for i, entry in ipairs(active) do
            local row = rows[i]
            if not row then
                row = Instance.new("TextLabel")
                row.BackgroundTransparency = 1
                row.Size = UDim2.new(1, -12, 0, 15)
                row.Position = UDim2.new(0, 8, 0, 0)
                row.Font = Enum.Font.Code
                row.TextSize = 12
                row.TextColor3 = Color3.fromRGB(200, 200, 200)
                row.TextXAlignment = Enum.TextXAlignment.Left
                row.TextStrokeTransparency = 0.5
                row.Parent = kbList
                rows[i] = row
            end
            row.Name = string.format("%03d", i)
            row.Visible = true
            row.RichText = true
            row.Text = string.format('%s  <font color="#ff2a2a">[%s]</font>', entry.name, entry.key)
        end
        for i = #active + 1, #rows do rows[i].Visible = false end

        keybindFrame.Visible = #active > 0
        keybindFrame.Size = UDim2.new(0, 170, 0, 22 + #active * 15)
    end)
end

-- default OFF; the "target hud" toggle is the single source of truth
_G.riotsHUD.TargetHud = false
do
    local W = 196
    -- ===== card =====
    local targetFrame = Instance.new("Frame")
    targetFrame.Name = "targethud"
    targetFrame.AnchorPoint = Vector2.new(1, 0.5)
    targetFrame.Position = UDim2.new(1, -14, 0.5, 0)
    targetFrame.Size = UDim2.new(0, W, 0, 76)
    targetFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
    targetFrame.BorderColor3 = Color3.fromRGB(0, 0, 0)
    targetFrame.BorderSizePixel = 1
    targetFrame.Visible = false
    targetFrame.Parent = hudGui
    accentStrip(targetFrame, 2)
    draggable(targetFrame)

    -- ===== avatar =====
    local avatarHolder = Instance.new("Frame")
    avatarHolder.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
    avatarHolder.BorderColor3 = Color3.fromRGB(35, 35, 35)
    avatarHolder.BorderSizePixel = 1
    avatarHolder.Position = UDim2.new(0, 9, 0, 10)
    avatarHolder.Size = UDim2.new(0, 40, 0, 40)
    avatarHolder.ZIndex = 3
    avatarHolder.Parent = targetFrame

    local avatar = Instance.new("ImageLabel")
    avatar.BackgroundTransparency = 1
    avatar.BorderSizePixel = 0
    avatar.Position = UDim2.new(0, 1, 0, 1)
    avatar.Size = UDim2.new(1, -2, 1, -2)
    avatar.ScaleType = Enum.ScaleType.Fit
    avatar.ZIndex = 4
    avatar.Parent = avatarHolder

    -- ===== name / username =====
    local dispLabel = Instance.new("TextLabel")
    dispLabel.BackgroundTransparency = 1
    dispLabel.Position = UDim2.new(0, 57, 0, 10)
    dispLabel.Size = UDim2.new(1, -65, 0, 15)
    dispLabel.Font = Enum.Font.Code
    dispLabel.TextSize = 13
    dispLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
    dispLabel.TextXAlignment = Enum.TextXAlignment.Left
    dispLabel.TextTruncate = Enum.TextTruncate.AtEnd
    dispLabel.TextStrokeTransparency = 0
    dispLabel.ZIndex = 4
    dispLabel.Text = "target"
    dispLabel.Parent = targetFrame

    local userLabel = Instance.new("TextLabel")
    userLabel.BackgroundTransparency = 1
    userLabel.Position = UDim2.new(0, 57, 0, 25)
    userLabel.Size = UDim2.new(1, -65, 0, 12)
    userLabel.Font = Enum.Font.Code
    userLabel.TextSize = 11
    userLabel.TextColor3 = Color3.fromRGB(130, 130, 130)
    userLabel.TextXAlignment = Enum.TextXAlignment.Left
    userLabel.TextTruncate = Enum.TextTruncate.AtEnd
    userLabel.TextStrokeTransparency = 0.4
    userLabel.RichText = true
    userLabel.ZIndex = 4
    userLabel.Parent = targetFrame

    -- distance + weapon on one line under the name
    local metaLabel = Instance.new("TextLabel")
    metaLabel.BackgroundTransparency = 1
    metaLabel.Position = UDim2.new(0, 57, 0, 38)
    metaLabel.Size = UDim2.new(1, -65, 0, 12)
    metaLabel.Font = Enum.Font.Code
    metaLabel.TextSize = 11
    metaLabel.TextColor3 = Color3.fromRGB(170, 170, 170)
    metaLabel.TextXAlignment = Enum.TextXAlignment.Left
    metaLabel.TextTruncate = Enum.TextTruncate.AtEnd
    metaLabel.TextStrokeTransparency = 0.4
    metaLabel.RichText = true
    metaLabel.ZIndex = 4
    metaLabel.Parent = targetFrame

    -- ===== health bar =====
    local hpBarBg = Instance.new("Frame")
    hpBarBg.BackgroundColor3 = Color3.fromRGB(9, 9, 9)
    hpBarBg.BorderColor3 = Color3.fromRGB(0, 0, 0)
    hpBarBg.BorderSizePixel = 1
    hpBarBg.Position = UDim2.new(0, 9, 1, -14)
    hpBarBg.Size = UDim2.new(1, -18, 0, 9)
    hpBarBg.ZIndex = 3
    hpBarBg.Parent = targetFrame

    local hpBarFill = Instance.new("Frame")
    hpBarFill.BackgroundColor3 = Color3.fromRGB(70, 220, 90)
    hpBarFill.BorderSizePixel = 0
    hpBarFill.Size = UDim2.new(1, 0, 1, 0)
    hpBarFill.ZIndex = 4
    hpBarFill.Parent = hpBarBg

    -- hp text centered over the bar
    local hpText = Instance.new("TextLabel")
    hpText.BackgroundTransparency = 1
    hpText.Position = UDim2.new(0, 0, 0, 0)
    hpText.Size = UDim2.new(1, 0, 1, 0)
    hpText.Font = Enum.Font.Code
    hpText.TextSize = 10
    hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
    hpText.TextXAlignment = Enum.TextXAlignment.Center
    hpText.TextStrokeTransparency = 0
    hpText.ZIndex = 5
    hpText.Text = ""
    hpText.Parent = hpBarBg


    local thumbCache = {}
    local function headshot(userId)
        if thumbCache[userId] then return thumbCache[userId] end
        local url = "rbxthumb://type=AvatarHeadShot&id="..userId.."&w=150&h=150"
        thumbCache[userId] = url
        return url
    end

    local shownHpPct = 1  -- smoothed bar
    runService.RenderStepped:Connect(function(dt)
        if not _G.riotsHUD.TargetHud then targetFrame.Visible = false; return end
        local model = library.currentAimTarget
        local fresh = library.currentAimTargetAt and (tick() - library.currentAimTargetAt < 0.5)
        local locked = model and model.Parent and fresh
        if not locked then targetFrame.Visible = false; return end

        local hum = model:FindFirstChildOfClass("Humanoid")
        local hrp = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
        if not hum or hum.Health <= 0 or not hrp then
            targetFrame.Visible = false
            return
        end
        targetFrame.Visible = true

        local plr = players:GetPlayerFromCharacter(model)
        local disp, user, uid = model.Name, model.Name, nil
        if plr then disp = plr.DisplayName; user = plr.Name; uid = plr.UserId end

        if uid then avatar.Image = headshot(uid) else avatar.Image = "" end
        dispLabel.Text = disp
        userLabel.Text = '<font color="#6f6f6f">@</font>'..user

        -- health
        local hp = math.floor(hum.Health + 0.5)
        local maxhp = math.floor(hum.MaxHealth + 0.5)
        local pct = maxhp > 0 and math.clamp(hp / maxhp, 0, 1) or 0
        shownHpPct = shownHpPct + (pct - shownHpPct) * math.clamp(dt * 12, 0, 1)
        local col = Color3.fromHSV(math.clamp(pct, 0, 1) * 0.33, 0.8, 0.95)
        hpBarFill.Size = UDim2.new(shownHpPct, 0, 1, 0)
        hpBarFill.BackgroundColor3 = col
        hpText.Text = string.format('%d / %d', hp, maxhp)

        -- distance + weapon combined on one line
        local myChar = localPlayer.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        local distStr = "-"
        if myRoot then
            distStr = string.format('%dm', math.floor((myRoot.Position - hrp.Position).Magnitude + 0.5))
        end
        local weap = plr and library.getPlayerWeapon and library.getPlayerWeapon(plr) or nil
        if not weap or weap == "None" then weap = "-" end
        metaLabel.Text = string.format(
            '<font color="#6f6f6f">%s</font>  <font color="#3a3a3a">|</font>  <font color="#b4b4b4">%s</font>',
            distStr, weap)
    end)
end

library.dependencies = library.dependencies or {}
local function resizeGroupbox(groupbox)
    if not groupbox or not groupbox.Parent then return end

    local grouper
    for _, c in ipairs(groupbox:GetChildren()) do
        if c:IsA("Frame") and c:FindFirstChildOfClass("UIListLayout") then
            grouper = c
            break
        end
    end
    if not grouper then return end
    local total = 11
    for _, c in ipairs(grouper:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIPadding") and c.Visible then
            total = total + c.Size.Y.Offset
        end
    end
    groupbox.Size = UDim2.new(groupbox.Size.X.Scale, groupbox.Size.X.Offset, 0, total)
end

runService.RenderStepped:Connect(function()
    if not menu.Enabled then return end
    local deps = library.dependencies
    if not deps then return end
    local toResize = {}
    for _, dep in ipairs(deps) do
        local on = (library.flags[dep.flag] == dep.want)
        for _, f in ipairs(dep.frames) do
            if f and f.Parent and f.Visible ~= on then
                f.Visible = on
                toResize[dep.groupbox] = true
            end
        end
    end
    for gb in pairs(toResize) do
        resizeGroupbox(gb)
    end
end)

_G.riotsMenuFX = _G.riotsMenuFX or { Blur = false, Snow = false, ClickThrough = false }

do
    local Lighting = game:GetService("Lighting")

    local menuBlur = Instance.new("BlurEffect")
    menuBlur.Name = "riotsMenuBlur"
    menuBlur.Size = 0
    menuBlur.Enabled = true
    menuBlur.Parent = Lighting

    pcall(function() menu.DisplayOrder = 5000 end)
    local snowScreen = Instance.new("ScreenGui")
    snowScreen.Name = "riotsSnowScreen"
    snowScreen.ResetOnSpawn = false
    snowScreen.IgnoreGuiInset = true
    snowScreen.DisplayOrder = 4000
    snowScreen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function() snowScreen.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)

    local snowGui = Instance.new("Frame")
    snowGui.Name = "riotsSnow"
    snowGui.BackgroundTransparency = 1
    snowGui.BorderSizePixel = 0
    snowGui.Size = UDim2.new(1, 0, 1, 0)
    snowGui.ZIndex = 1
    snowGui.Visible = false
    snowGui.Parent = snowScreen

    local flakes = {}
    local FLAKE_COUNT = 60
    local function makeFlakes()
        local vs = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1920, 1080)
        for i = 1, FLAKE_COUNT do
            local f = Instance.new("Frame")
            f.BorderSizePixel = 0
            f.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
            f.BackgroundTransparency = math.random(20, 70) / 100
            local sz = math.random(2, 5)
            f.Size = UDim2.new(0, sz, 0, sz)
            f.Position = UDim2.new(math.random(), 0, math.random(), 0)
            f.ZIndex = 2
            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(1, 0)
            corner.Parent = f
            f.Parent = snowGui
            flakes[i] = {
                gui = f,
                speed = math.random(20, 60) / 100,
                drift = math.random(-15, 15) / 100,
            }
        end
    end
    -- snow + blur removed: flakes are only built lazily if snow is ever enabled
    -- (there is no UI toggle anymore, so this stays off and costs nothing).
    local flakesBuilt = false

    runService.RenderStepped:Connect(function(dt)
        local open = menu.Enabled == true

        local wantBlur = open and _G.riotsMenuFX.Blur
        if menuBlur.Size > 0.01 or wantBlur then
            local target = wantBlur and 18 or 0
            menuBlur.Size = menuBlur.Size + (target - menuBlur.Size) * math.clamp(dt * 10, 0, 1)
        end

        local wantSnow = open and _G.riotsMenuFX.Snow
        if wantSnow and not flakesBuilt then flakesBuilt = true; makeFlakes() end
        snowGui.Visible = wantSnow
        if wantSnow then
            for _, fl in ipairs(flakes) do
                local p = fl.gui.Position
                local ny = p.Y.Scale + fl.speed * dt
                local nx = p.X.Scale + fl.drift * dt
                if ny > 1.02 then ny = -0.02; nx = math.random() end
                if nx < -0.02 then nx = 1.02 elseif nx > 1.02 then nx = -0.02 end
                fl.gui.Position = UDim2.new(nx, 0, ny, 0)
            end
        end
    end)

    library.setClickThrough = function(v)
        _G.riotsMenuFX.ClickThrough = v
        pcall(function()

            menu.bg.Active = not v
            for _, d in ipairs(menu:GetDescendants()) do
                if d:IsA("GuiButton") then
                    d.Modal = false
                end
            end
        end)
    end
end

function library:addTab(name)
    local newTab = tabholder.tab:Clone()
    local newButton = tabviewer.button:Clone()

    table.insert(library.tabs,newTab)
    newTab.Parent = tabholder
    newTab.Visible = false

    pcall(function()
        newTab.Size = UDim2.new(1, 0, 1, 0)
        newTab.Position = UDim2.new(0, 0, 0, 0)
        if newTab:IsA("Frame") or newTab:IsA("ScrollingFrame") then
            newTab.BackgroundTransparency = 1
        end
    end)

    local function setupColumn(col, side)
        if not col then return end
        pcall(function()
            col.BackgroundTransparency = 1
            col.Size = UDim2.new(0.5, -12, 1, -8)
            col.Position = side == "left" and UDim2.new(0, 8, 0, 4) or UDim2.new(0.5, 4, 0, 4)
            if col:IsA("ScrollingFrame") then
                col.ScrollBarThickness = 4
                col.ScrollingEnabled = true
                col.ScrollingDirection = Enum.ScrollingDirection.Y
                col.CanvasSize = UDim2.new(0, 0, 0, 0)
                col.AutomaticCanvasSize = Enum.AutomaticSize.Y
                col.ClipsDescendants = true
                col.Active = true
            end

            local layout = col:FindFirstChildOfClass("UIListLayout")
            if not layout then
                layout = Instance.new("UIListLayout")
                layout.Parent = col
            end
            layout.FillDirection = Enum.FillDirection.Vertical
            layout.SortOrder = Enum.SortOrder.LayoutOrder
            layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
            layout.Padding = UDim.new(0, 10)
            local pad = col:FindFirstChildOfClass("UIPadding")
            if not pad then
                pad = Instance.new("UIPadding")
                pad.Parent = col
            end
            pad.PaddingTop = UDim.new(0, 6)
            pad.PaddingBottom = UDim.new(0, 40)
        end)
    end

    local leftCol   = newTab:FindFirstChild("left")
    local centerCol = newTab:FindFirstChild("center")
    local rightCol  = newTab:FindFirstChild("right")
    setupColumn(leftCol, "left")
    setupColumn(rightCol, "right")
    if centerCol then pcall(function() centerCol.Visible = false end) end

    table.insert(library.tabbuttons,newButton)
    newButton.Parent = tabviewer
    newButton.Modal = true
    newButton.Visible = true
    newButton.text.Text = name
    pcall(function()
        if newButton:FindFirstChild("element") then
            library:registerAccent(newButton.element)
        end
    end)
    newButton.MouseButton1Click:Connect(function()
        for i,v in next, library.tabs do
            v.Visible = v == newTab
        end
        for i,v in next, library.toInvis do
            v.Visible = false
        end
        for i,v in next, library.tabbuttons do
            local state = v == newButton
            if state then
                v.element.Visible = true
                library:Tween(v.element, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 0.000})
                v.text.TextColor3 = Color3.fromRGB(244, 244, 244)
            else
                library:Tween(v.element, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {BackgroundTransparency = 1.000})
                v.text.TextColor3 = Color3.fromRGB(144, 144, 144)
            end
        end
    end)

    local tab = {}
    local groupCount = 0
    local jigCount = 0
    local topStuff = 2000

    function tab:createGroup(pos,groupname)
        local groupbox = Instance.new("Frame")
        local grouper = Instance.new("Frame")
        local UIListLayout = Instance.new("UIListLayout")
        local UIPadding = Instance.new("UIPadding")
        local element = Instance.new("Frame")
        local title = Instance.new("TextLabel")
        local backframe = Instance.new("Frame")

        groupCount -= 1

        groupbox.Parent = newTab[pos]
        groupbox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        groupbox.BorderColor3 = Color3.fromRGB(30, 30, 30)
        groupbox.BorderSizePixel = 2
        groupbox.Size = UDim2.new(1, 0, 0, 8)
        groupbox.ZIndex = groupCount

        grouper.Parent = groupbox
        grouper.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        grouper.BorderColor3 = Color3.fromRGB(0, 0, 0)
        grouper.Size = UDim2.new(1, 0, 1, 0)

        UIListLayout.Parent = grouper
        UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder

        UIPadding.Parent = grouper
        UIPadding.PaddingBottom = UDim.new(0, 4)
        UIPadding.PaddingTop = UDim.new(0, 7)

        element.Name = "element"
        element.Parent = groupbox
        element.BackgroundColor3 = library.libColor
        element.BorderSizePixel = 0
        element.Size = UDim2.new(1, 0, 0, 1)
        library:registerAccent(element)

        title.Parent = groupbox
        title.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        title.BackgroundTransparency = 1.000
        title.BorderSizePixel = 0
        title.Position = UDim2.new(0, 17, 0, 0)
        title.ZIndex = 2
        title.Font = Enum.Font.Code
        title.Text = groupname or ""
        title.TextColor3 = Color3.fromRGB(255, 255, 255)
        title.TextSize = 13.000
        title.TextStrokeTransparency = 0.000
        title.TextXAlignment = Enum.TextXAlignment.Left

        backframe.Parent = groupbox
        backframe.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        backframe.BorderSizePixel = 0
        backframe.Position = UDim2.new(0, 10, 0, -2)
        backframe.Size = UDim2.new(0, 13 + title.TextBounds.X, 0, 3)

        local group = {}
        function group:addToggle(args)
            if not args.flag and args.text then args.flag = args.text end
            if not args.flag then return end
            groupbox.Size += UDim2.new(0, 0, 0, 20)

            local toggleframe = Instance.new("Frame")
            local tobble = Instance.new("Frame")
            local mid = Instance.new("Frame")
            local front = Instance.new("Frame")
            local text = Instance.new("TextLabel")
            local button = Instance.new("TextButton")

            jigCount -= 1
            library.multiZindex -= 1

            toggleframe.Name = "toggleframe"
            toggleframe.Parent = grouper
            toggleframe.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            toggleframe.BackgroundTransparency = 1.000
            toggleframe.BorderSizePixel = 0
            toggleframe.Size = UDim2.new(1, 0, 0, 20)
            toggleframe.ZIndex = library.multiZindex

            tobble.Name = "tobble"
            tobble.Parent = toggleframe
            tobble.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            tobble.BorderColor3 = Color3.fromRGB(0, 0, 0)
            tobble.BorderSizePixel = 3
                        tobble.Position = UDim2.new(0.0299999993, 0, 0.272000015, 0)

            tobble.Size = UDim2.new(0, 10, 0, 10)

            mid.Name = "mid"
            mid.Parent = tobble
            mid.BackgroundColor3 = library.libColor
            mid.BorderColor3 = Color3.fromRGB(30,30,30)
            mid.BorderSizePixel = 2
            mid.Size = UDim2.new(0, 10, 0, 10)

            front.Name = "front"
            front.Parent = mid
            front.BackgroundColor3 = Color3.fromRGB(15,15,15)
            front.BorderColor3 = Color3.fromRGB(0, 0, 0)
            front.Size = UDim2.new(0, 10, 0, 10)

            text.Name = "text"
            text.Parent = toggleframe
            text.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
            text.BackgroundTransparency = 1.000
            text.Position = UDim2.new(0, 30, 0, 0)
            text.Size = UDim2.new(1, -34, 1, 2)
            text.Font = Enum.Font.Code
            text.Text = args.text or args.flag
            text.TextColor3 = Color3.fromRGB(155, 155, 155)
            text.TextSize = 13.000
            text.TextStrokeTransparency = 0.000
            text.TextXAlignment = Enum.TextXAlignment.Left

            button.Name = "button"
            button.Parent = toggleframe
            button.BackgroundColor3 = Color3.fromRGB(255, 255, 255)

            button.BackgroundTransparency = 1.000
            button.BorderSizePixel = 0
            button.Size = UDim2.new(0, 101, 1, 0)
            button.Font = Enum.Font.SourceSans
            button.Text = ""
            button.TextColor3 = Color3.fromRGB(0, 0, 0)
            button.TextSize = 14.000

            if args.disabled then
                button.Visible = false
                text.TextColor3 = library.disabledcolor
                text.Text = args.text
            return end

            local state = false
            local function applyVisual()
                front.BackgroundColor3 = state and library.libColor or Color3.fromRGB(15,15,15)
                text.TextColor3 = state and Color3.fromRGB(244, 244, 244) or Color3.fromRGB(144, 144, 144)
            end
            function toggle(newState)
                state = newState
                library.flags[args.flag] = state
                applyVisual()
                if args.callback then
                    args.callback(state)
                end
            end

            local function flip()
                state = not state
                front.Name = state and "accent" or "back"
                library.flags[args.flag] = state
                mid.BorderColor3 = Color3.fromRGB(30,30,30)
                applyVisual()
                if args.callback then
                    args.callback(state)
                end
            end
            button.MouseButton1Click:Connect(flip)
            button.MouseEnter:connect(function()
                mid.BorderColor3 = library.libColor
			end)
            button.MouseLeave:connect(function()
                mid.BorderColor3 = Color3.fromRGB(30,30,30)
			end)

            library.flags[args.flag] = false
            library.options[args.flag] = {type = "toggle",changeState = toggle,skipflag = args.skipflag,oldargs = args}
            -- honor an initial value = true so default-on toggles actually enable
            if args.value == true then
                toggle(true)
            end
            local toggle = {}

            function toggle:addHotkey(hkArgs)
                hkArgs = hkArgs or {}
                local hkFlag = hkArgs.flag or (args.flag .. "_key")
                local hkModeFlag = hkFlag .. "_mode"
                local waiting = false
                local hkBtn = Instance.new("TextButton")
                hkBtn.Name = "hotkey"
                hkBtn.Parent = toggleframe
                hkBtn.BackgroundTransparency = 1
                hkBtn.BorderSizePixel = 0
                hkBtn.Position = UDim2.new(1, -46, 0, 0)
                hkBtn.Size = UDim2.new(0, 44, 1, 0)
                hkBtn.Font = Enum.Font.Code
                hkBtn.Text = "[ - ]"
                hkBtn.TextColor3 = Color3.fromRGB(150,150,150)
                hkBtn.TextSize = 12
                hkBtn.TextStrokeTransparency = 0
                hkBtn.TextXAlignment = Enum.TextXAlignment.Right
                hkBtn.ZIndex = library.multiZindex + 1

                library.flags[hkFlag] = hkArgs.key or Enum.KeyCode.Unknown
                library.flags[hkModeFlag] = hkArgs.mode or "Toggle"
                library.options[hkFlag] = {type = "keybind", skipflag = hkArgs.skipflag,
                    mode = "Toggle",
                    modeFlag = hkModeFlag,
                    setMode = function(m)
                        if m ~= "Toggle" and m ~= "Hold" and m ~= "Always" then m = "Toggle" end
                        library.flags[hkModeFlag] = m
                        library.options[hkFlag].mode = m
                    end,
                    changeState = function(val)
                        library.flags[hkFlag] = val
                        local modeText = library.flags[hkModeFlag] and (" " .. library.flags[hkModeFlag]) or ""
                        hkBtn.Text = "[" .. (keyNames[val] or (typeof(val)=="EnumItem" and val.Name) or "-") .. "]"
                    end, oldargs = hkArgs}
                library.options[hkFlag].changeState(library.flags[hkFlag])

                local function updateHotkeyDisplay()
                    local keyText = keyNames[library.flags[hkFlag]] or (typeof(library.flags[hkFlag])=="EnumItem" and library.flags[hkFlag].Name) or "-"
                    hkBtn.Text = "[" .. keyText .. "]"
                end

                local function createModeMenu()
                    if library._openModeMenu then
                        pcall(function() library._openModeMenu:Destroy() end)
                        library._openModeMenu = nil
                    end

                    local ROW_H  = 18
                    local WIDTH  = 72
                    local modes  = {"Toggle", "Hold"}
                    local totalH = #modes * ROW_H

                    local screenPos = hkBtn.AbsolutePosition

                    local contextMenu = Instance.new("ScreenGui")
                    contextMenu.Name = "hotkeyModeContext"
                    contextMenu.ResetOnSpawn = false
                    contextMenu.DisplayOrder = 2147483647
                    contextMenu.IgnoreGuiInset = true
                    contextMenu.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
                    pcall(function() contextMenu.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
                    library._openModeMenu = contextMenu

                    local function closeMenu()
                        pcall(function() contextMenu:Destroy() end)
                        if library._openModeMenu == contextMenu then library._openModeMenu = nil end
                    end

                    -- clicking anywhere else closes it
                    local backing = Instance.new("TextButton")
                    backing.BackgroundTransparency = 1
                    backing.Text = ""
                    backing.AutoButtonColor = false
                    backing.Size = UDim2.new(1, 0, 1, 0)
                    backing.ZIndex = 19999
                    backing.Parent = contextMenu
                    backing.MouseButton1Click:Connect(closeMenu)
                    backing.MouseButton2Click:Connect(closeMenu)

                    -- dark card with black border + accent top strip (matches the menu)
                    local card = Instance.new("Frame")
                    card.Name = "modeMenu"
                    card.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
                    card.BorderColor3 = Color3.fromRGB(0, 0, 0)
                    card.BorderSizePixel = 1
                    card.Size = UDim2.fromOffset(WIDTH, totalH + 1)
                    local vp = (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize) or Vector2.new(1920,1080)
                    local btnSize = hkBtn.AbsoluteSize
                    -- place directly UNDER the hotkey button, right-aligned to it (button text is right-aligned)
                    local px = math.floor(screenPos.X + btnSize.X - WIDTH)
                    local py = math.floor(screenPos.Y + btnSize.Y + 2)
                    -- if it would clip the bottom, flip it to sit above the button instead
                    if py + totalH > vp.Y - 4 then py = math.floor(screenPos.Y - totalH - 2) end
                    px = math.clamp(px, 4, vp.X - WIDTH - 4)
                    py = math.clamp(py, 4, vp.Y - totalH - 4)
                    card.Position = UDim2.fromOffset(px, py)
                    card.ZIndex = 20000
                    card.Parent = contextMenu

                    local strip = Instance.new("Frame")
                    strip.BorderSizePixel = 0
                    strip.BackgroundColor3 = library.libColor
                    strip.Size = UDim2.new(1, 0, 0, 1)
                    strip.ZIndex = 20002
                    strip.Parent = card
                    library:registerAccent(strip)

                    for i, mode in ipairs(modes) do
                        local selected = (library.flags[hkModeFlag] == mode)

                        local btn = Instance.new("TextButton")
                        btn.AutoButtonColor = false
                        btn.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
                        btn.BackgroundTransparency = selected and 0 or 1
                        btn.BorderSizePixel = 0
                        btn.Position = UDim2.new(0, 0, 0, 1 + (i-1)*ROW_H)
                        btn.Size = UDim2.new(1, 0, 0, ROW_H)
                        btn.Font = Enum.Font.Code
                        btn.Text = "  " .. mode
                        btn.TextColor3 = selected and library.libColor or Color3.fromRGB(150, 150, 150)
                        btn.TextSize = 12
                        btn.TextStrokeTransparency = 0
                        btn.TextXAlignment = Enum.TextXAlignment.Left
                        btn.ZIndex = 20001
                        btn.Parent = card

                        btn.MouseEnter:Connect(function()
                            if library.flags[hkModeFlag] ~= mode then
                                btn.BackgroundTransparency = 0.6
                                btn.TextColor3 = Color3.fromRGB(230, 230, 230)
                            end
                        end)
                        btn.MouseLeave:Connect(function()
                            if library.flags[hkModeFlag] ~= mode then
                                btn.BackgroundTransparency = 1
                                btn.TextColor3 = Color3.fromRGB(150, 150, 150)
                            end
                        end)
                        btn.MouseButton1Click:Connect(function()
                            library.flags[hkModeFlag] = mode
                            library.options[hkFlag].mode = mode
                            updateHotkeyDisplay()
                            closeMenu()
                        end)
                    end
                end

                -- Left click: set key
                hkBtn.MouseButton1Click:Connect(function()
                    waiting = true
                    hkBtn.Text = "[...]"
                    hkBtn.TextColor3 = library.libColor
                end)

                -- Right click: show mode menu
                hkBtn.MouseButton2Click:Connect(function()
                    createModeMenu()
                end)

                inputService.InputBegan:Connect(function(key, gpe)
                    local k = key.KeyCode == Enum.KeyCode.Unknown and key.UserInputType or key.KeyCode
                    if waiting then
                        if not table.find(library.blacklisted, k) then
                            waiting = false
                            library.options[hkFlag].changeState(k)
                            updateHotkeyDisplay()
                            hkBtn.TextColor3 = Color3.fromRGB(150,150,150)
                        end
                        return
                    end
                    if gpe then return end
                    local mode = library.flags[hkModeFlag] or "Toggle"
                    if k == library.flags[hkFlag] and not library.colorpicking then
                        if mode == "Toggle" then
                            flip()
                        elseif mode == "Hold" or mode == "Always" then
                            -- Force ON when key is pressed down (only if not already on)
                            if not library.flags[args.flag] then
                                flip()
                            end
                        end
                    end
                end)

                inputService.InputEnded:Connect(function(key, gameProcessed)
                    local k = key.KeyCode == Enum.KeyCode.Unknown and key.UserInputType or key.KeyCode
                    local mode = library.flags[hkModeFlag] or "Toggle"
                    if (mode == "Hold" or mode == "Always") and k == library.flags[hkFlag] then
                        -- Force OFF when key is released (only if currently on)
                        if library.flags[args.flag] then
                            flip()
                        end
                    end
                end)

                return toggle
            end
            function toggle:addKeybind(args)
                if not args.flag then return end
                local next = false

                local keybind = Instance.new("Frame")
                local button = Instance.new("TextButton")

                keybind.Parent = toggleframe
                keybind.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                keybind.BackgroundTransparency = 1.000
                keybind.BorderColor3 = Color3.fromRGB(0, 0, 0)
                keybind.BorderSizePixel = 0
                keybind.Position = UDim2.new(0.720000029, 4, 0.272000015, 0)
                keybind.Size = UDim2.new(0, 51, 0, 10)

                button.Parent = keybind
                button.BackgroundColor3 = library.libColor
                button.BackgroundTransparency = 1.000
                button.BorderSizePixel = 0
                button.Position = UDim2.new(-0.270902753, 0, 0, 0)
                button.Size = UDim2.new(1.27090275, 0, 1, 0)
                button.Font = Enum.Font.Code
                button.Text = ""
                button.TextColor3 = Color3.fromRGB(155, 155, 155)
                button.TextSize = 13.000
                button.TextStrokeTransparency = 0.000
                button.TextXAlignment = Enum.TextXAlignment.Right

                function updateValue(val)
                    if library.colorpicking then return end
                    library.flags[args.flag] = val
                    button.Text = keyNames[val] or val.Name
                end
                inputService.InputBegan:Connect(function(key)
                    local key = key.KeyCode == Enum.KeyCode.Unknown and key.UserInputType or key.KeyCode
                    if next then
                        if not table.find(library.blacklisted,key) then
                            next = false
                            library.flags[args.flag] = key
                            button.Text = keyNames[key] or key.Name
                            button.TextColor3 = Color3.fromRGB(155, 155, 155)
                        end
                    end
                    if not next and key == library.flags[args.flag] and args.callback then
                        args.callback()
                    end
                end)

                button.MouseButton1Click:Connect(function()
                    if library.colorpicking then return end
                    library.flags[args.flag] = Enum.KeyCode.Unknown
                    button.Text = "--"
                    button.TextColor3 = library.libColor
                    next = true
                end)

                library.flags[args.flag] = Enum.KeyCode.Unknown
                library.options[args.flag] = {type = "keybind",changeState = updateValue,skipflag = args.skipflag,oldargs = args}

                updateValue(args.key or Enum.KeyCode.Unknown)
                return toggle
            end
            function toggle:addColorpicker(args)
                if not args.flag and args.text then args.flag = args.text end
                if not args.flag then return end

                library.multiZindex -= 1
                jigCount -= 1
                topStuff -= 1

                -- ── swatch button (tiny color square on the toggle row) ──────────────
                local colorpicker = Instance.new("Frame")
                colorpicker.Parent = toggleframe
                colorpicker.BackgroundColor3 = Color3.fromRGB(255,255,255)
                colorpicker.BorderColor3 = Color3.fromRGB(0,0,0)
                colorpicker.BorderSizePixel = 3
                colorpicker.Position = args.second
                    and UDim2.new(0.720000029,4,0.272000015,0)
                    or  UDim2.new(0.860000014,4,0.272000015,0)
                colorpicker.Size = UDim2.new(0,20,0,10)

                local mid = Instance.new("Frame")
                mid.Name = "mid"
                mid.Parent = colorpicker
                mid.BackgroundColor3 = library.libColor
                mid.BorderColor3 = Color3.fromRGB(30,30,30)
                mid.BorderSizePixel = 2
                mid.Size = UDim2.new(1,0,1,0)

                local front = Instance.new("Frame")
                front.Name = "front"
                front.Parent = mid
                front.BackgroundColor3 = Color3.fromRGB(15,15,15)
                front.BorderColor3 = Color3.fromRGB(0,0,0)
                front.Size = UDim2.new(1,0,1,0)

                local button2 = Instance.new("TextButton")
                button2.Name = "button2"
                button2.Parent = front
                button2.BackgroundTransparency = 1
                button2.Size = UDim2.new(1,0,1,0)
                button2.Text = ""
                button2.Font = Enum.Font.SourceSans
                button2.TextColor3 = Color3.fromRGB(0,0,0)
                button2.TextSize = 14

                args.__front = front
                local colorFrame, updateValue = library:buildColorPicker(args, button2, mid)
                table.insert(library.toInvis, colorFrame)
                library.flags[args.flag] = Color3.new(1,1,1)
                library.options[args.flag] = {type="colorpicker", changeState=updateValue, skipflag=args.skipflag, oldargs=args}

                updateValue(args.color or Color3.new(1,1,1))
                return toggle
            end
            return toggle
        end
        function group:addButton(args)
            if not args.callback or not args.text then return end
            groupbox.Size += UDim2.new(0, 0, 0, 22)

            local buttonframe = Instance.new("Frame")
            local bg = Instance.new("Frame")
            local main = Instance.new("Frame")
            local button = Instance.new("TextButton")
            local gradient = Instance.new("UIGradient")

            buttonframe.Name = "buttonframe"
            buttonframe.Parent = grouper
            buttonframe.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            buttonframe.BackgroundTransparency = 1.000
            buttonframe.BorderSizePixel = 0
            buttonframe.Size = UDim2.new(1, 0, 0, 21)

            bg.Name = "bg"
            bg.Parent = buttonframe
            bg.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
            bg.BorderColor3 = Color3.fromRGB(0, 0, 0)
            bg.BorderSizePixel = 2
            bg.Position = UDim2.new(0.02, 0, 0, 0)
            bg.Size = UDim2.new(0.96, 0, 0, 15)

            main.Name = "main"
            main.Parent = bg
            main.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
            main.BorderColor3 = Color3.fromRGB(60, 60, 60)
            main.Size = UDim2.new(1, 0, 1, 0)

            button.Name = "button"
            button.Parent = main
            button.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
            button.BackgroundTransparency = 1.000
            button.BorderSizePixel = 0
            button.Size = UDim2.new(1, 0, 1, 0)
            button.Font = Enum.Font.Code
            button.Text = args.text or args.flag
            button.TextColor3 = Color3.fromRGB(255, 255, 255)
            button.TextSize = 13.000
            button.TextStrokeTransparency = 0.000

            gradient.Color = ColorSequence.new{ColorSequenceKeypoint.new(0.00, Color3.fromRGB(105, 105, 105)), ColorSequenceKeypoint.new(1.00, Color3.fromRGB(121, 121, 121))}
            gradient.Rotation = 90
            gradient.Name = "gradient"
            gradient.Parent = main

            button.MouseButton1Click:Connect(function()
                if not library.colorpicking then
                    args.callback()
                end
            end)
            button.MouseEnter:connect(function()
                main.BorderColor3 = library.libColor
			end)
			button.MouseLeave:connect(function()
                main.BorderColor3 = Color3.fromRGB(60, 60, 60)
			end)
        end
        function group:addSlider(args,sub)
            if not args.flag or not args.max then return end
            sub = sub or args.suffix or ""
            groupbox.Size += UDim2.new(0, 0, 0, 30)

            local slider = Instance.new("Frame")
            local bg = Instance.new("Frame")
            local main = Instance.new("Frame")
            local fill = Instance.new("Frame")
            local button = Instance.new("TextButton")
            local valuetext = Instance.new("TextLabel")
            local UIGradient = Instance.new("UIGradient")
            local text = Instance.new("TextLabel")

            slider.Name = "slider"
            slider.Parent = grouper
            slider.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            slider.BackgroundTransparency = 1.000
            slider.BorderSizePixel = 0
            slider.Size = UDim2.new(1, 0, 0, 30)

            bg.Name = "bg"
            bg.Parent = slider
            bg.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
            bg.BorderColor3 = Color3.fromRGB(0, 0, 0)
            bg.BorderSizePixel = 2
            bg.Position = UDim2.new(0.02, 0, 0, 16)
            bg.Size = UDim2.new(0.96, 0, 0, 10)

            main.Name = "main"
            main.Parent = bg
            main.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
            main.BorderColor3 = Color3.fromRGB(50, 50, 50)
            main.Size = UDim2.new(1, 0, 1, 0)

            fill.Name = "fill"
            fill.Parent = main
            fill.BackgroundColor3 = library.libColor
            fill.BackgroundTransparency = 0.200
            fill.BorderColor3 = Color3.fromRGB(60, 60, 60)
            fill.BorderSizePixel = 0
            fill.Size = UDim2.new(0.617238641, 13, 1, 0)

            button.Name = "button"
            button.Parent = main
            button.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            button.BackgroundTransparency = 1.000
            button.Size = UDim2.new(1, 0, 1, 0)
            button.Font = Enum.Font.SourceSans
            button.Text = ""
            button.TextColor3 = Color3.fromRGB(0, 0, 0)
            button.TextSize = 14.000

            valuetext.Parent = main
            valuetext.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            valuetext.BackgroundTransparency = 1.000
            valuetext.Position = UDim2.new(0.5, 0, 0.5, 0)
            valuetext.Font = Enum.Font.Code
            valuetext.Text = "0.9172/10"
            valuetext.TextColor3 = Color3.fromRGB(255, 255, 255)
            valuetext.TextSize = 14.000
            valuetext.TextStrokeTransparency = 0.000

            UIGradient.Color = ColorSequence.new{ColorSequenceKeypoint.new(0.00, Color3.fromRGB(105, 105, 105)), ColorSequenceKeypoint.new(1.00, Color3.fromRGB(121, 121, 121))}
            UIGradient.Rotation = 90
            UIGradient.Parent = main

            text.Name = "text"
            text.Parent = slider
            text.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            text.BackgroundTransparency = 1.000
            text.Position = UDim2.new(0.0299999993, -1, 0, 7)
            text.ZIndex = 2
            text.Font = Enum.Font.Code
            text.Text = args.text or args.flag
            text.TextColor3 = Color3.fromRGB(244, 244, 244)
            text.TextSize = 13.000
            text.TextStrokeTransparency = 0.000
            text.TextXAlignment = Enum.TextXAlignment.Left

            local entered = false
			local scrolling = false
			local amount = 0

            local function updateValue(value)
                if library.colorpicking then return end
				if value ~= 0 then
					fill:TweenSize(UDim2.new(value/args.max,0,1,0),Enum.EasingDirection.In,Enum.EasingStyle.Sine,0.01)
				else
					fill:TweenSize(UDim2.new(0,1,1,0),Enum.EasingDirection.In,Enum.EasingStyle.Sine,0.01)
                end
                valuetext.Text = value..sub
                library.flags[args.flag] = value
                if args.callback then
                    args.callback(value)
                end
			end
			-- RenderStepped-driven slider: no blocking loops at all
			local dragging = false
			runService.RenderStepped:Connect(function()
				if not entered then return end
				if library.colorpicking or not newTab.Visible then return end
				if inputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) and menu.Enabled then
					library.scrolling = true
					scrolling = true
					dragging = true
					valuetext.TextColor3 = Color3.fromRGB(255, 255, 255)
					local raw = args.min + ((mouse.X - button.AbsolutePosition.X) / math.max(button.AbsoluteSize.X, 1)) * (args.max - args.min)
					updateValue(math.clamp(math.floor(raw), args.min or 0, args.max))
				else
					if dragging then
						dragging = false
						scrolling = false
						library.scrolling = false
						if not entered then
							valuetext.TextColor3 = Color3.fromRGB(255, 255, 255)
						end
					end
					if not menu.Enabled then
						entered = false
					end
				end
			end)
			button.MouseEnter:connect(function()
                if library.colorpicking then return end
				if scrolling or entered then return end
                entered = true
                main.BorderColor3 = library.libColor
			end)
			button.MouseLeave:connect(function()
                entered = false
                main.BorderColor3 = Color3.fromRGB(60, 60, 60)
			end)
            if args.value then
                updateValue(args.value)
            end
            library.flags[args.flag] = 0
            library.options[args.flag] = {type = "slider",changeState = updateValue,skipflag = args.skipflag,oldargs = args}
            updateValue(args.value or 0)
        end
        function group:addTextbox(args)
            if not args.flag then return end
            groupbox.Size += UDim2.new(0, 0, 0, 35)

            local textbox = Instance.new("Frame")
            local bg = Instance.new("Frame")
            local main = Instance.new("ScrollingFrame")
            local box = Instance.new("TextBox")
            local gradient = Instance.new("UIGradient")
            local text = Instance.new("TextLabel")

            box:GetPropertyChangedSignal('Text'):Connect(function(val)
                if library.colorpicking then return end
                library.flags[args.flag] = box.Text
                args.value = box.Text
                if args.callback then
                    args.callback()
                end
            end)
            textbox.Name = "textbox"
            textbox.Parent = grouper
            textbox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            textbox.BackgroundTransparency = 1.000
            textbox.BorderSizePixel = 0
            textbox.Size = UDim2.new(1, 0, 0, 35)
            textbox.ZIndex = 10

            bg.Name = "bg"
            bg.Parent = textbox
            bg.BackgroundColor3 = Color3.fromRGB(15,15,15)
            bg.BorderColor3 = Color3.fromRGB(0, 0, 0)
            bg.BorderSizePixel = 2
            bg.Position = UDim2.new(0.02, 0, 0, 16)
            bg.Size = UDim2.new(0.96, 0, 0, 15)

            main.Name = "main"
            main.Parent = bg
            main.Active = true
            main.BackgroundColor3 = Color3.fromRGB(15,15,15)
            main.BorderColor3 = Color3.fromRGB(30, 30, 30)
            main.Size = UDim2.new(1, 0, 1, 0)
            main.CanvasSize = UDim2.new(0, 0, 0, 0)
            main.ScrollBarThickness = 0

            box.Name = "box"
            box.Parent = main
            box.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            box.BackgroundTransparency = 1.000
            box.Selectable = false
            box.Size = UDim2.new(1, 0, 1, 0)
            box.Font = Enum.Font.Code
            box.Text = args.value or ""
            box.TextColor3 = Color3.fromRGB(255, 255, 255)
            box.TextSize = 13.000
            box.TextStrokeTransparency = 0.000
            box.TextXAlignment = Enum.TextXAlignment.Left

            gradient.Color = ColorSequence.new{ColorSequenceKeypoint.new(0.00, Color3.fromRGB(105, 105, 105)), ColorSequenceKeypoint.new(1.00, Color3.fromRGB(121, 121, 121))}
            gradient.Rotation = 90
            gradient.Name = "gradient"
            gradient.Parent = main

            text.Name = "text"
            text.Parent = textbox
            text.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            text.BackgroundTransparency = 1.000
            text.Position = UDim2.new(0.0299999993, -1, 0, 7)
            text.ZIndex = 2
            text.Font = Enum.Font.Code
            text.Text = args.text or args.flag
            text.TextColor3 = Color3.fromRGB(244, 244, 244)
            text.TextSize = 13.000
            text.TextStrokeTransparency = 0.000
            text.TextXAlignment = Enum.TextXAlignment.Left

            library.flags[args.flag] = args.value or ""
            library.options[args.flag] = {type = "textbox",changeState = function(text) box.Text = text end,skipflag = args.skipflag,oldargs = args}
        end
        function group:addDivider(args)
            groupbox.Size += UDim2.new(0, 0, 0, 10)

            local div = Instance.new("Frame")
            local bg = Instance.new("Frame")
            local main = Instance.new("Frame")

            div.Name = "div"
            div.Parent = grouper
            div.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            div.BackgroundTransparency = 1.000
            div.BorderSizePixel = 0
            div.Position = UDim2.new(0, 0, 0.743662, 0)
            div.Size = UDim2.new(0, 202, 0, 10)

            bg.Name = "bg"
            bg.Parent = div
            bg.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
            bg.BorderColor3 = Color3.fromRGB(0, 0, 0)
            bg.BorderSizePixel = 2
            bg.Position = UDim2.new(0.02, 0, 0, 4)
            bg.Size = UDim2.new(0, 191, 0, 1)

            main.Name = "main"
            main.Parent = bg
            main.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
            main.BorderColor3 = Color3.fromRGB(60, 60, 60)
            main.Size = UDim2.new(0, 191, 0, 1)
        end
        function group:addList(args)
            if not args.flag or not args.values then return end
            groupbox.Size += UDim2.new(0, 0, 0, 35)

            library.multiZindex -= 1

            local list = Instance.new("Frame")
            local bg = Instance.new("Frame")
            local main = Instance.new("ScrollingFrame")
            local button = Instance.new("TextButton")
            local dumbtriangle = Instance.new("ImageLabel")
            local valuetext = Instance.new("TextLabel")
            local gradient = Instance.new("UIGradient")
            local text = Instance.new("TextLabel")

            local frame = Instance.new("Frame")
            local holder = Instance.new("ScrollingFrame")
            local UIListLayout = Instance.new("UIListLayout")

            local MAX_VISIBLE = 5
            local OPTION_HEIGHT = 20

            list.Name = "list"
            list.Parent = grouper
            list.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            list.BackgroundTransparency = 1.000
            list.BorderSizePixel = 0
            list.Size = UDim2.new(1, 0, 0, 35)
            list.ZIndex = library.multiZindex

            bg.Name = "bg"
            bg.Parent = list
            bg.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
            bg.BorderColor3 = Color3.fromRGB(0, 0, 0)
            bg.BorderSizePixel = 2
            bg.Position = UDim2.new(0.02, 0, 0, 16)
            bg.Size = UDim2.new(0.96, 0, 0, 15)

            main.Name = "main"
            main.Parent = bg
            main.Active = true
            main.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
            main.BorderColor3 = Color3.fromRGB(60, 60, 60)
            main.Size = UDim2.new(1, 0, 1, 0)
            main.CanvasSize = UDim2.new(0, 0, 0, 0)
            main.ScrollBarThickness = 0

            button.Name = "button"
            button.Parent = main
            button.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            button.BackgroundTransparency = 1.000
            button.Size = UDim2.new(1, 0, 1, 0)
            button.Font = Enum.Font.SourceSans
            button.Text = ""
            button.TextColor3 = Color3.fromRGB(0, 0, 0)
            button.TextSize = 14.000

            dumbtriangle.Name = "dumbtriangle"
            dumbtriangle.Parent = main
            dumbtriangle.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            dumbtriangle.BackgroundTransparency = 1.000
            dumbtriangle.BorderColor3 = Color3.fromRGB(0, 0, 0)
            dumbtriangle.BorderSizePixel = 0
            dumbtriangle.Position = UDim2.new(1, -11, 0.5, -3)
            dumbtriangle.Size = UDim2.new(0, 7, 0, 6)
            dumbtriangle.ZIndex = 3
            dumbtriangle.Image = "rbxassetid://8532000591"

            valuetext.Name = "valuetext"
            valuetext.Parent = main
            valuetext.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            valuetext.BackgroundTransparency = 1.000
            valuetext.Position = UDim2.new(0.00200000009, 2, 0, 7)
            valuetext.ZIndex = 2
            valuetext.Font = Enum.Font.Code
            valuetext.Text = ""
            valuetext.TextColor3 = Color3.fromRGB(244, 244, 244)
            valuetext.TextSize = 13.000
            valuetext.TextStrokeTransparency = 0.000
            valuetext.TextXAlignment = Enum.TextXAlignment.Left

            gradient.Color = ColorSequence.new{ColorSequenceKeypoint.new(0.00, Color3.fromRGB(105, 105, 105)), ColorSequenceKeypoint.new(1.00, Color3.fromRGB(121, 121, 121))}
            gradient.Rotation = 90
            gradient.Name = "gradient"
            gradient.Parent = main

            text.Name = "text"
            text.Parent = list
            text.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            text.BackgroundTransparency = 1.000
            text.Position = UDim2.new(0.0299999993, -1, 0, 7)
            text.ZIndex = 2
            text.Font = Enum.Font.Code
            text.Text = args.text or args.flag
            text.TextColor3 = Color3.fromRGB(244, 244, 244)
            text.TextSize = 13.000
            text.TextStrokeTransparency = 0.000
            text.TextXAlignment = Enum.TextXAlignment.Left

            frame.Name = "frame"
            frame.Parent = list
            frame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
            frame.BorderColor3 = Color3.fromRGB(0, 0, 0)
            frame.BorderSizePixel = 2
            frame.Position = UDim2.new(0.0299999993, -1, 0.605000019, 15)
            frame.Size = UDim2.new(0, 203, 0, 0)
            frame.Visible = false
            frame.ZIndex = library.multiZindex

            holder.Name = "holder"
            holder.Parent = frame
            holder.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
            holder.BorderColor3 = Color3.fromRGB(0, 0, 0)
            holder.BorderSizePixel = 0
            holder.Size = UDim2.new(1, 0, 1, 0)
            holder.Active = true
            holder.CanvasSize = UDim2.new(0, 0, 0, 0)
            holder.ScrollBarThickness = 3
            holder.ScrollBarImageColor3 = Color3.fromRGB(90, 90, 90)
            holder.ScrollingDirection = Enum.ScrollingDirection.Y
            holder.ZIndex = library.multiZindex

            UIListLayout.Parent = holder
            UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder

			local function updateValue(value)
                if value == nil then valuetext.Text = "nil" return end
				if args.multiselect then
                    if type(value) == "string" then
                        if not table.find(library.options[args.flag].values,value) then return end
                        if table.find(library.flags[args.flag],value) then
                            for i,v in pairs(library.flags[args.flag]) do
                                if v == value then
                                    table.remove(library.flags[args.flag],i)
                                end
                            end
                        else
                            table.insert(library.flags[args.flag],value)
                        end
                    else
                        library.flags[args.flag] = value
                    end
					local buttonText = ""
					for i,v in pairs(library.flags[args.flag]) do
						local jig = i ~= #library.flags[args.flag] and "," or ""
						buttonText = buttonText..v..jig
					end
                    if buttonText == "" then buttonText = "..." end
					for i,v in next, holder:GetChildren() do
						if v.ClassName ~= "Frame" then continue end
						v.off.TextColor3 = Color3.fromRGB(150,150,150)
						for _i,_v in next, library.flags[args.flag] do
							if v.Name == _v then
								v.off.TextColor3 = library.libColor
							end
						end
					end
					valuetext.Text = buttonText
					if args.callback then
						args.callback(library.flags[args.flag])
					end
				else
                    if not table.find(library.options[args.flag].values,value) then value = library.options[args.flag].values[1] end
                    library.flags[args.flag] = value
					for i,v in next, holder:GetChildren() do
						if v.ClassName ~= "Frame" then continue end
						v.off.TextColor3 = Color3.fromRGB(150,150,150)
                        if v.Name == library.flags[args.flag] then
                            v.off.TextColor3 = library.libColor
                        end
					end
					frame.Visible = false
                    if library.flags[args.flag] then
                        valuetext.Text = library.flags[args.flag]
                        if args.callback then
                            args.callback(library.flags[args.flag])
                        end
                    end
				end
			end

            function refresh(tbl)
                for i,v in next, holder:GetChildren() do
                    if v.ClassName == "Frame" then
                        v:Destroy()
                    end
					frame.Size = UDim2.new(0, 203, 0, 0)
                end
                for i,v in pairs(tbl) do

                    if i <= MAX_VISIBLE then
                        frame.Size += UDim2.new(0, 0, 0, OPTION_HEIGHT)
                    end

                    local option = Instance.new("Frame")
                    local button_2 = Instance.new("TextButton")
                    local text_2 = Instance.new("TextLabel")

                    option.Name = v
                    option.Parent = holder
                    option.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                    option.BackgroundTransparency = 1.000
                    option.Size = UDim2.new(1, 0, 0, 20)

                    button_2.Name = "button"
                    button_2.Parent = option
                    button_2.AutoButtonColor = false
                    button_2.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
                    button_2.BackgroundTransparency = 1.000
                    button_2.BorderSizePixel = 0
                    button_2.Size = UDim2.new(1, 0, 1, 0)
                    button_2.Font = Enum.Font.SourceSans
                    button_2.Text = ""
                    button_2.TextColor3 = Color3.fromRGB(0, 0, 0)
                    button_2.TextSize = 14.000

                    text_2.Name = "off"
                    text_2.Parent = option
                    text_2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                    text_2.BackgroundTransparency = 1.000
                    text_2.Position = UDim2.new(0, 6, 0, 0)
                    text_2.Size = UDim2.new(1, -10, 1, 0)
                    text_2.Font = Enum.Font.Code
                    text_2.Text = v
                    text_2.TextColor3 = args.multiselect and Color3.fromRGB(150,150,150) or Color3.fromRGB(255,255,255)
                    text_2.TextSize = 13.000
                    text_2.TextStrokeTransparency = 0.000
                    text_2.TextXAlignment = Enum.TextXAlignment.Left

                    option.ZIndex = library.multiZindex
                    button_2.ZIndex = library.multiZindex
                    text_2.ZIndex = library.multiZindex + 1

                    button_2.MouseEnter:Connect(function() button_2.BackgroundTransparency = 0.65 end)
                    button_2.MouseLeave:Connect(function() button_2.BackgroundTransparency = 1.000 end)
                    button_2.MouseButton1Click:Connect(function()
                        updateValue(v)
                    end)
                end

                holder.CanvasSize = UDim2.new(0, 0, 0, #tbl * OPTION_HEIGHT)
                library.options[args.flag].values = tbl
                updateValue(table.find(library.options[args.flag].values,library.flags[args.flag]) and library.flags[args.flag] or library.options[args.flag].values[1])
            end

            button.MouseButton1Click:Connect(function()
                if not library.colorpicking then
                    frame.Visible = not frame.Visible
                end
            end)
            button.MouseEnter:connect(function()
                main.BorderColor3 = library.libColor
			end)
			button.MouseLeave:connect(function()
                main.BorderColor3 = Color3.fromRGB(60, 60, 60)
			end)

            table.insert(library.toInvis,frame)
            library.flags[args.flag] = args.multiselect and {} or ""
            library.options[args.flag] = {type = "list",changeState = updateValue,values = args.values,refresh = refresh,skipflag = args.skipflag,oldargs = args}

            refresh(args.values)
            updateValue(args.value or not args.multiselect and args.values[1] or "abcdefghijklmnopqrstuwvxyz")
        end

        function group:addSkinGrid(args)
            if not args.flag then return end
            local GRID_HEIGHT = args.height or 190
            local COLUMNS     = args.columns or 3
            local CELL_PAD    = 6

            -- header (title + search) ends at y=46, grid uses GRID_HEIGHT-12, plus bottom margin
            local BLOCK = 46 + (GRID_HEIGHT - 12) + 6
            groupbox.Size += UDim2.new(0, 0, 0, BLOCK)
            library.multiZindex -= 1

            local wrap    = Instance.new("Frame")

            local sbg     = Instance.new("Frame")
            local search  = Instance.new("TextBox")
            local slabel  = Instance.new("TextLabel")
            local sicon   = Instance.new("ImageLabel")

            local gridBg  = Instance.new("Frame")
            local grid    = Instance.new("ScrollingFrame")
            local gLayout = Instance.new("UIGridLayout")
            local gPad    = Instance.new("UIPadding")

            wrap.Name = "skingrid"
            wrap.Parent = grouper
            wrap.BackgroundTransparency = 1
            wrap.BorderSizePixel = 0
            wrap.Size = UDim2.new(1, 0, 0, BLOCK)
            wrap.ZIndex = library.multiZindex

            slabel.Name = "text"
            slabel.Parent = wrap
            slabel.BackgroundTransparency = 1
            slabel.Position = UDim2.new(0.03, -1, 0, 4)
            slabel.Size = UDim2.new(0.94, 0, 0, 14)
            slabel.ZIndex = library.multiZindex + 1
            slabel.Font = Enum.Font.Code
            slabel.Text = args.text or "cosmetic"
            slabel.TextColor3 = Color3.fromRGB(244, 244, 244)
            slabel.TextSize = 13.000
            slabel.TextStrokeTransparency = 0.000
            slabel.TextXAlignment = Enum.TextXAlignment.Left

            sbg.Name = "sbg"
            sbg.Parent = wrap
            sbg.BackgroundColor3 = Color3.fromRGB(15,15,15)
            sbg.BorderColor3 = Color3.fromRGB(0, 0, 0)
            sbg.BorderSizePixel = 2
            sbg.Position = UDim2.new(0.02, 0, 0, 21)
            sbg.Size = UDim2.new(0.96, 0, 0, 20)
            sbg.ZIndex = library.multiZindex + 1

            sicon.Name = "sicon"
            sicon.Parent = sbg
            sicon.BackgroundTransparency = 1
            sicon.AnchorPoint = Vector2.new(1, 0.5)
            sicon.Position = UDim2.new(1, -6, 0.5, 0)
            sicon.Size = UDim2.new(0, 11, 0, 11)
            sicon.Image = "rbxassetid://3926305904"
            sicon.ImageRectOffset = Vector2.new(964, 324)
            sicon.ImageRectSize = Vector2.new(36, 36)
            sicon.ImageColor3 = Color3.fromRGB(120,120,120)
            sicon.ZIndex = library.multiZindex + 2

            search.Name = "search"
            search.Parent = sbg
            search.BackgroundTransparency = 1
            search.Position = UDim2.new(0, 6, 0, 0)
            search.Size = UDim2.new(1, -24, 1, 0)
            search.Font = Enum.Font.Code
            search.Text = ""
            search.PlaceholderText = "search..."
            search.PlaceholderColor3 = Color3.fromRGB(110,110,110)
            search.ClearTextOnFocus = false
            search.TextColor3 = Color3.fromRGB(235,235,235)
            search.TextSize = 13.000
            search.TextStrokeTransparency = 0.000
            search.TextXAlignment = Enum.TextXAlignment.Left
            search.ZIndex = library.multiZindex + 2

            gridBg.Name = "gridBg"
            gridBg.Parent = wrap
            gridBg.BackgroundColor3 = Color3.fromRGB(15,15,15)
            gridBg.BorderColor3 = Color3.fromRGB(0,0,0)
            gridBg.BorderSizePixel = 2
            gridBg.Position = UDim2.new(0.02, 0, 0, 46)
            gridBg.Size = UDim2.new(0.96, 0, 0, GRID_HEIGHT - 12)
            gridBg.ZIndex = library.multiZindex + 1

            grid.Name = "grid"
            grid.Parent = gridBg
            grid.Active = true
            grid.BackgroundTransparency = 1
            grid.BorderSizePixel = 0
            grid.Size = UDim2.new(1, 0, 1, 0)
            grid.CanvasSize = UDim2.new(0, 0, 0, 0)
            grid.ScrollBarThickness = 3
            grid.ScrollBarImageColor3 = Color3.fromRGB(90,90,90)
            grid.ScrollingDirection = Enum.ScrollingDirection.Y
            grid.ZIndex = library.multiZindex + 1

            gPad.Parent = grid
            gPad.PaddingTop = UDim.new(0, CELL_PAD)
            gPad.PaddingLeft = UDim.new(0, CELL_PAD)

            gLayout.Parent = grid
            gLayout.SortOrder = Enum.SortOrder.LayoutOrder
            gLayout.CellPadding = UDim2.new(0, CELL_PAD, 0, CELL_PAD)

            local cellW = 60
            local lastW, lastCell = -1, -1
            local function recomputeCellSize()
                local w = grid.AbsoluteSize.X
                if w <= 0 then w = 203 end
                if math.abs(w - lastW) < 4 then return end
                lastW = w
                local avail = w - CELL_PAD * (COLUMNS + 1)
                local newCell = math.max(40, math.floor(avail / COLUMNS))
                if newCell == lastCell then return end
                lastCell = newCell
                cellW = newCell
                gLayout.CellSize = UDim2.new(0, cellW, 0, cellW + 18)
            end
            recomputeCellSize()
            grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(recomputeCellSize)

            local selected = nil
            local tiles = {}
            local currentList = {}

            local function imageFor(name)
                if args.imageFor then
                    local ok, img = pcall(args.imageFor, name)
                    if ok and img then return img end
                end
                return ""
            end

            local pool = {}
            local MAX_TILES = 150
            local imgToken = 0

            local function highlight()
                for _, t in ipairs(pool) do
                    if t.frame.Visible then
                        local isSel = (t.name == selected)
                        t.sel.Visible = isSel
                        t.nm.TextColor3 = isSel and library.libColor or Color3.fromRGB(210,210,210)
                    end
                end
            end

            local function makeTile()
                local tile = Instance.new("Frame")
                local sel  = Instance.new("Frame")
                local img  = Instance.new("ImageLabel")
                local nm   = Instance.new("TextLabel")
                local btn  = Instance.new("TextButton")

                tile.Parent = grid
                -- no box / no outline: just the image + name
                tile.BackgroundTransparency = 1
                tile.BorderSizePixel = 0
                tile.ClipsDescendants = true
                tile.ZIndex = library.multiZindex + 2

                -- selection indicator: subtle accent border only when selected
                sel.Name = "sel"
                sel.Parent = tile
                sel.BackgroundTransparency = 1
                sel.Size = UDim2.new(1, 0, 1, -16)
                sel.BorderColor3 = library.libColor
                sel.BorderSizePixel = 2
                sel.Visible = false
                sel.ZIndex = library.multiZindex + 4

                img.Name = "img"
                img.Parent = tile
                img.BackgroundTransparency = 1
                img.BorderSizePixel = 0
                img.Position = UDim2.new(0, 0, 0, 0)
                img.Size = UDim2.new(1, 0, 1, -16)
                img.ScaleType = Enum.ScaleType.Fit
                img.ZIndex = library.multiZindex + 3

                nm.Name = "nm"
                nm.Parent = tile
                nm.BackgroundTransparency = 1
                nm.AnchorPoint = Vector2.new(0, 1)
                nm.Position = UDim2.new(0, 0, 1, 0)
                nm.Size = UDim2.new(1, 0, 0, 14)
                nm.Font = Enum.Font.Code
                nm.TextColor3 = Color3.fromRGB(210,210,210)
                nm.TextSize = 11
                nm.TextTruncate = Enum.TextTruncate.AtEnd
                nm.TextXAlignment = Enum.TextXAlignment.Center
                nm.TextStrokeTransparency = 0.5
                nm.ZIndex = library.multiZindex + 4

                btn.Name = "btn"
                btn.Parent = tile
                btn.BackgroundTransparency = 1
                btn.Size = UDim2.new(1, 0, 1, 0)
                btn.Text = ""
                btn.ZIndex = library.multiZindex + 5

                local t = { frame = tile, sel = sel, img = img, nm = nm, btn = btn, name = nil, image = nil }

                -- hover just brightens the name (no box to outline anymore)
                btn.MouseEnter:Connect(function() if t.name and selected ~= t.name then t.nm.TextColor3 = Color3.fromRGB(255,255,255) end end)
                btn.MouseLeave:Connect(function() if t.name and selected ~= t.name then t.nm.TextColor3 = Color3.fromRGB(210,210,210) end end)
                btn.MouseButton1Click:Connect(function()
                    if not t.name then return end
                    selected = t.name
                    library.flags[args.flag] = t.name
                    highlight()
                    if args.callback then args.callback(t.name) end
                end)

                pool[#pool + 1] = t
                return t
            end

            local function buildTiles(list)
                imgToken += 1
                local myToken = imgToken
                local shown = math.min(#list, MAX_TILES)
                local pending = {}
                for i = 1, shown do
                    local name = list[i]
                    local t = pool[i] or makeTile()
                    t.name = name
                    t.frame.Name = name
                    t.frame.Visible = true
                    t.frame.LayoutOrder = i
                    t.sel.Visible = (name == selected)
                    t.nm.TextColor3 = (name == selected) and library.libColor or Color3.fromRGB(210,210,210)
                    t.nm.Text = (name:gsub("_", " "))
                    tiles[name] = t

                    local newImg = imageFor(name)
                    if t.image ~= newImg then
                        t.image = newImg
                        t.img.Image = ""
                        pending[#pending + 1] = { tile = t, img = newImg }
                    end
                end

                for i = shown + 1, #pool do
                    pool[i].frame.Visible = false
                    pool[i].name = nil
                end
                local rows = math.ceil(shown / COLUMNS)
                local cellH = cellW + 18
                grid.CanvasSize = UDim2.new(0, 0, 0, CELL_PAD + rows * (cellH + CELL_PAD))

                if #pending > 0 then
                    task.spawn(function()
                        for i, p in ipairs(pending) do
                            if myToken ~= imgToken then return end
                            if p.tile.image == p.img then
                                p.tile.img.Image = p.img
                            end
                            if i % 12 == 0 then task.wait() end
                        end
                    end)
                end
            end

            local function applyFilter()
                tiles = {}
                local q = search.Text:lower()
                if q == "" then buildTiles(currentList) return end
                local filtered = {}
                for _, name in ipairs(currentList) do
                    if name:lower():find(q, 1, true) then
                        filtered[#filtered+1] = name
                    end
                end
                buildTiles(filtered)
            end

            table.insert(library.accentObjects, {
                obj = grid, prop = "__skingrid",
                apply = function(color)
                    for _, t in ipairs(pool) do t.sel.BorderColor3 = color end
                    highlight()
                end,
            })

            local searchToken = 0
            search:GetPropertyChangedSignal("Text"):Connect(function()
                searchToken += 1
                local myToken = searchToken
                task.delay(0.12, function()
                    if myToken == searchToken then applyFilter() end
                end)
            end)

            local function refresh(tbl)
                currentList = tbl or {}
                if selected and not table.find(currentList, selected) then selected = nil end
                applyFilter()
            end

            library.flags[args.flag] = ""
            library.options[args.flag] = {
                type = "skingrid",
                values = args.values or {},
                refresh = refresh,
                changeState = function(name)
                    selected = name
                    library.flags[args.flag] = name
                    highlight()
                    if args.callback then args.callback(name) end
                end,
                getSelected = function() return selected end,
                skipflag = args.skipflag,
                oldargs = args,
            }

            refresh(args.values or {})
            return { refresh = refresh }
        end
        function group:addConfigbox(args)
            if not args.flag or not args.values then return end
            groupbox.Size += UDim2.new(0, 0, 0, 138)
            library.multiZindex -= 1

            local list2 = Instance.new("Frame")
            local frame = Instance.new("Frame")
            local main = Instance.new("Frame")
            local holder = Instance.new("ScrollingFrame")
            local UIListLayout = Instance.new("UIListLayout")
            local dwn = Instance.new("ImageLabel")
            local up = Instance.new("ImageLabel")

            list2.Name = "list2"
            list2.Parent = grouper
            list2.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            list2.BackgroundTransparency = 1.000
            list2.BorderSizePixel = 0
            list2.Position = UDim2.new(0, 0, 0.108108111, 0)
            list2.Size = UDim2.new(1, 0, 0, 138)

            frame.Name = "frame"
            frame.Parent = list2
            frame.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
            frame.BorderColor3 = Color3.fromRGB(0, 0, 0)
            frame.BorderSizePixel = 2
            frame.Position = UDim2.new(0.02, -1, 0.0439999998, 0)
            frame.Size = UDim2.new(0, 205, 0, 128)

            main.Name = "main"
            main.Parent = frame
            main.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
            main.BorderColor3 = Color3.fromRGB(30,30,30)
            main.Size = UDim2.new(1, 0, 1, 0)

            holder.Name = "holder"
            holder.Parent = main
            holder.Active = true
            holder.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            holder.BackgroundTransparency = 1.000
            holder.BorderSizePixel = 0
            holder.Position = UDim2.new(0, 0, 0.00571428565, 0)
            holder.Size = UDim2.new(1, 0, 1, 0)
            holder.BottomImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
            holder.CanvasSize = UDim2.new(0, 0, 0, 0)
            holder.ScrollBarThickness = 0
            holder.TopImage = "rbxasset://textures/ui/Scroll/scroll-middle.png"
            holder.AutomaticCanvasSize = Enum.AutomaticSize.Y
            holder.ScrollingEnabled = true
            holder.ScrollBarImageTransparency = 0

            UIListLayout.Parent = holder

            dwn.Name = "dwn"
            dwn.Parent = frame
            dwn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            dwn.BackgroundTransparency = 1.000
            dwn.BorderColor3 = Color3.fromRGB(0, 0, 0)
            dwn.BorderSizePixel = 0
            dwn.Position = UDim2.new(0.930000007, 4, 1, -9)
            dwn.Size = UDim2.new(0, 7, 0, 6)
            dwn.ZIndex = 3
            dwn.Image = "rbxassetid://8548723563"
            dwn.Visible = false

            up.Name = "up"
            up.Parent = frame
            up.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            up.BackgroundTransparency = 1.000
            up.BorderColor3 = Color3.fromRGB(0, 0, 0)
            up.BorderSizePixel = 0
            up.Position = UDim2.new(0, 3, 0, 3)
            up.Size = UDim2.new(0, 7, 0, 6)
            up.ZIndex = 3
            up.Image = "rbxassetid://8548757311"
            up.Visible = false

            local function updateValue(value)
                if value == nil then return end
                if not table.find(library.options[args.flag].values,value) then value = library.options[args.flag].values[1] end
                library.flags[args.flag] = value

                for i,v in next, holder:GetChildren() do
                    if v.ClassName ~= "Frame" then continue end
                    if v.text.Text == library.flags[args.flag] then
                        v.text.TextColor3 = library.libColor
                    else
                        v.text.TextColor3 = Color3.fromRGB(255,255,255)
                    end
                end
                if library.flags[args.flag] then
                    if args.callback then
                        args.callback(library.flags[args.flag])
                    end
                end
                holder.Visible = true
            end
            holder:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
                up.Visible = (holder.CanvasPosition.Y > 1)
                dwn.Visible = (holder.CanvasPosition.Y + 1 < (holder.AbsoluteCanvasSize.Y - holder.AbsoluteSize.Y))
            end)

            function refresh(tbl)
                for i,v in next, holder:GetChildren() do
                    if v.ClassName == "Frame" then
                        v:Destroy()
                    end
                end
                for i,v in pairs(tbl) do
                    local item = Instance.new("Frame")
                    local button = Instance.new("TextButton")
                    local text = Instance.new("TextLabel")

                    item.Name = v
                    item.Parent = holder
                    item.Active = true
                    item.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                    item.BackgroundTransparency = 1.000
                    item.BorderColor3 = Color3.fromRGB(0, 0, 0)
                    item.BorderSizePixel = 0
                    item.Size = UDim2.new(1, 0, 0, 18)

                    button.Parent = item
                    button.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
                    button.BackgroundTransparency = 1
                    button.BorderColor3 = Color3.fromRGB(0, 0, 0)
                    button.BorderSizePixel = 0
                    button.Size = UDim2.new(1, 0, 1, 0)
                    button.Text = ""
                    button.TextTransparency = 1.000

                    text.Name = 'text'
                    text.Parent = item
                    text.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                    text.BackgroundTransparency = 1.000
                    text.Size = UDim2.new(1, 0, 0, 18)
                    text.Font = Enum.Font.Code
                    text.Text = v
                    text.TextColor3 = Color3.fromRGB(255, 255, 255)
                    text.TextSize = 14.000
                    text.TextStrokeTransparency = 0.000

                    button.MouseButton1Click:Connect(function()
                        updateValue(v)
                    end)
                end

                holder.Visible = true
                library.options[args.flag].values = tbl
                updateValue(table.find(library.options[args.flag].values,library.flags[args.flag]) and library.flags[args.flag] or library.options[args.flag].values[1])
            end

            library.flags[args.flag] = ""
            library.options[args.flag] = {type = "cfg",changeState = updateValue,values = args.values,refresh = refresh,skipflag = args.skipflag,oldargs = args}

            refresh(args.values)
            updateValue(args.value or not args.multiselect and args.values[1] or "abcdefghijklmnopqrstuwvxyz")
        end
        function group:addColorpicker(args)
            if not args.flag then return end
            groupbox.Size += UDim2.new(0, 0, 0, 20)

            library.multiZindex -= 1
            jigCount -= 1
            topStuff -= 1

            -- ── row container ────────────────────────────────────────────────────
            local colorpicker = Instance.new("Frame")
            colorpicker.Name = "colorpicker"
            colorpicker.Parent = grouper
            colorpicker.BackgroundTransparency = 1
            colorpicker.BorderSizePixel = 0
            colorpicker.Size = UDim2.new(1, 0, 0, 20)
            colorpicker.ZIndex = topStuff

            local text = Instance.new("TextLabel")
            text.Name = "text"
            text.Parent = colorpicker
            text.BackgroundTransparency = 1
            text.Position = UDim2.new(0.02, -1, 0, 10)
            text.Font = Enum.Font.Code
            text.Text = args.text or args.flag
            text.TextColor3 = Color3.fromRGB(244, 244, 244)
            text.TextSize = 13
            text.TextStrokeTransparency = 0
            text.TextXAlignment = Enum.TextXAlignment.Left

            -- swatch box (same style as toggle:addColorpicker)
            local colorpicker_2 = Instance.new("Frame")
            colorpicker_2.Name = "colorpicker"
            colorpicker_2.Parent = colorpicker
            colorpicker_2.BackgroundColor3 = Color3.fromRGB(255,255,255)
            colorpicker_2.BorderColor3 = Color3.fromRGB(0,0,0)
            colorpicker_2.BorderSizePixel = 3
            colorpicker_2.Position = UDim2.new(0.860000014, 4, 0.272000015, 0)
            colorpicker_2.Size = UDim2.new(0, 20, 0, 10)

            local mid = Instance.new("Frame")
            mid.Name = "mid"
            mid.Parent = colorpicker_2
            mid.BackgroundColor3 = library.libColor
            mid.BorderColor3 = Color3.fromRGB(30,30,30)
            mid.BorderSizePixel = 2
            mid.Size = UDim2.new(1, 0, 1, 0)

            local front = Instance.new("Frame")
            front.Name = "front"
            front.Parent = mid
            front.BackgroundColor3 = Color3.fromRGB(15,15,15)
            front.BorderColor3 = Color3.fromRGB(0,0,0)
            front.Size = UDim2.new(1, 0, 1, 0)

            local button = Instance.new("TextButton")
            button.Name = "button"
            button.Parent = colorpicker
            button.BackgroundTransparency = 1
            button.BorderSizePixel = 0
            button.Size = UDim2.new(1, 0, 1, 0)
            button.Font = Enum.Font.SourceSans
            button.Text = ""
            button.ZIndex = args.ontop and topStuff or jigCount
            button.TextColor3 = Color3.fromRGB(0,0,0)
            button.TextSize = 14

            -- ── popup panel via shared factory ───────────────────────────────────
            args.__front = front
            local colorFrame, updateValue = library:buildColorPicker(args, button, mid)

            table.insert(library.toInvis, colorFrame)
            library.flags[args.flag] = Color3.new(1,1,1)
            library.options[args.flag] = {type="colorpicker", changeState=updateValue, skipflag=args.skipflag, oldargs=args}

            updateValue(args.color or Color3.new(1,1,1))
        end
        function group:addKeybind(args)
            if not args.flag then return end
            groupbox.Size += UDim2.new(0, 0, 0, 20)
            local next = false

            local keybind = Instance.new("Frame")
            local text = Instance.new("TextLabel")
            local button = Instance.new("TextButton")

            keybind.Parent = grouper
            keybind.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            keybind.BackgroundTransparency = 1.000
            keybind.BorderSizePixel = 0
            keybind.Size = UDim2.new(1, 0, 0, 20)

            text.Parent = keybind
            text.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
            text.BackgroundTransparency = 1.000
            text.Position = UDim2.new(0.02, -1, 0, 10)
            text.Font = Enum.Font.Code
            text.Text = args.text or args.flag
            text.TextColor3 = Color3.fromRGB(244, 244, 244)
            text.TextSize = 13.000
            text.TextStrokeTransparency = 0.000
            text.TextXAlignment = Enum.TextXAlignment.Left

            button.Parent = keybind
            button.BackgroundColor3 = library.libColor
            button.BackgroundTransparency = 1.000
            button.BorderSizePixel = 0
            button.Position = UDim2.new(7.09711117e-08, 0, 0, 0)
            button.Size = UDim2.new(0.02, 0, 1, 0)
            button.Font = Enum.Font.Code
            button.Text = "--"
            button.TextColor3 = Color3.fromRGB(155, 155, 155)
            button.TextSize = 13.000
            button.TextStrokeTransparency = 0.000
            button.TextXAlignment = Enum.TextXAlignment.Right

            function updateValue(val)
                if library.colorpicking then return end
                library.flags[args.flag] = val
                button.Text = keyNames[val] or val.Name
            end
            inputService.InputBegan:Connect(function(key)
                local key = key.KeyCode == Enum.KeyCode.Unknown and key.UserInputType or key.KeyCode
                if next then
                    if not table.find(library.blacklisted,key) then
                        next = false
                        library.flags[args.flag] = key
                        button.Text = keyNames[key] or key.Name
                        button.TextColor3 = Color3.fromRGB(155, 155, 155)
                    end
                end
                if not next and key == library.flags[args.flag] and args.callback then
                    args.callback()
                end
            end)

            button.MouseButton1Click:Connect(function()
                if library.colorpicking then return end
                library.flags[args.flag] = Enum.KeyCode.Unknown
                button.Text = "..."
                button.TextColor3 = Color3.new(0.2,0.2,0.2)
                next = true
            end)

            library.flags[args.flag] = Enum.KeyCode.Unknown
            library.options[args.flag] = {type = "keybind",changeState = updateValue,skipflag = args.skipflag,oldargs = args}

            updateValue(args.key or Enum.KeyCode.Unknown)
        end

        library.dependencies = library.dependencies or {}

        local function grouperElements()
            local t = {}
            for _, c in ipairs(grouper:GetChildren()) do
                if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
                    table.insert(t, c)
                end
            end
            return t
        end

        group._elemBaseline = #grouperElements()

        function group:markStart()
            group._elemBaseline = #grouperElements()
            return group
        end

        function group:dependsOn(flag, wantValue)
            if wantValue == nil then wantValue = true end
            local all = grouperElements()
            local bound = {}
            for i = (group._elemBaseline or 0) + 1, #all do
                table.insert(bound, all[i])
            end
            group._elemBaseline = #all
            if #bound == 0 then return group end

            local dep = {
                flag = flag,
                want = wantValue,
                frames = bound,
                groupbox = groupbox,
            }
            table.insert(library.dependencies, dep)
            return group
        end

        return group, groupbox
    end

    function tab:createTabbox(pos, boxname)
        local tabbox = { buttons = {}, groups = {} }

        local barGroup, barBox = tab:createGroup(pos, "")

        local barGrouper
        for _, c in ipairs(barBox:GetChildren()) do
            if c:IsA("Frame") and c:FindFirstChildOfClass("UIListLayout") then barGrouper = c break end
        end

        if barGrouper then
            local lay = barGrouper:FindFirstChildOfClass("UIListLayout")
            if lay then
                lay.FillDirection = Enum.FillDirection.Horizontal
                lay.HorizontalAlignment = Enum.HorizontalAlignment.Left
                lay.VerticalAlignment = Enum.VerticalAlignment.Center
            end

            local pad = barGrouper:FindFirstChildOfClass("UIPadding")
            if pad then
                pad.PaddingTop = UDim.new(0, 2)
                pad.PaddingBottom = UDim.new(0, 2)
            end
        end
        barBox.Size = UDim2.new(barBox.Size.X.Scale, barBox.Size.X.Offset, 0, 28)

        for _, c in ipairs(barBox:GetChildren()) do
            if c.Name == "element" then c.Visible = false
            elseif c:IsA("Frame") and not c:FindFirstChildOfClass("UIListLayout") then

                if c.Size.Y.Offset <= 4 then c.Visible = false end
            elseif c:IsA("TextLabel") then c.Visible = false end
        end
        barBox.BorderSizePixel = 0
        barBox.BackgroundTransparency = 1

        local function refreshButtonSizes()
            local n = #tabbox.buttons
            if n == 0 then return end
            for _, b in ipairs(tabbox.buttons) do
                b.Size = UDim2.new(1 / n, -2, 1, 0)
            end
        end

        function tabbox:addTab(name)

            local group, groupbox = tab:createGroup(pos, name)
            groupbox.Visible = false

            local btn = Instance.new("TextButton")
            btn.Name = "subbtn_"..name
            btn.Parent = barGrouper or barBox
            btn.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
            btn.BorderColor3 = Color3.fromRGB(0, 0, 0)
            btn.BorderSizePixel = 1
            btn.AutoButtonColor = false
            btn.Size = UDim2.new(0.5, -2, 1, 0)
            btn.ZIndex = 5
            btn.Font = Enum.Font.Code
            btn.Text = name
            btn.TextColor3 = Color3.fromRGB(144, 144, 144)
            btn.TextSize = 13
            btn.TextStrokeTransparency = 0
            btn.Modal = true

            table.insert(tabbox.buttons, btn)
            table.insert(tabbox.groups, groupbox)
            refreshButtonSizes()

            local function show()
                for i, gb in ipairs(tabbox.groups) do
                    gb.Visible = false
                    tabbox.buttons[i].TextColor3 = Color3.fromRGB(144, 144, 144)
                    tabbox.buttons[i].BackgroundColor3 = Color3.fromRGB(15, 15, 15)
                end
                groupbox.Visible = true
                btn.TextColor3 = library.libColor
                btn.BackgroundColor3 = Color3.fromRGB(26, 26, 26)
            end

            btn.MouseEnter:Connect(function()
                if not groupbox.Visible then btn.TextColor3 = Color3.fromRGB(200, 200, 200) end
            end)
            btn.MouseLeave:Connect(function()
                if not groupbox.Visible then btn.TextColor3 = Color3.fromRGB(144, 144, 144) end
            end)
            btn.MouseButton1Click:Connect(show)

            if #tabbox.groups == 1 then show() end
            return group
        end

        return tabbox
    end

    return tab
end

function contains(list, x)
	for _, v in pairs(list) do
		if v == x then return true end
	end
	return false
end

local CONFIG_DIR = "riots"
pcall(function()
    if makefolder and (not isfolder or not isfolder(CONFIG_DIR)) then makefolder(CONFIG_DIR) end
end)

function library:createConfig()
    local name = library.flags["config_name"]
    if contains(library.options["selected_config"].values, name) then return library:notify(name..".cfg already exists!") end
    if name == "" then return library:notify("Put a name goofy") end
    local jig = {}
    for i,v in next, library.flags do
        local opt = library.options[i]
        if not opt or opt.skipflag then continue end
        if typeof(v) == "Color3" then
            jig[i] = {v.R,v.G,v.B}
        elseif typeof(v) == "EnumItem" then
            jig[i] = {string.split(tostring(v),".")[2],string.split(tostring(v),".")[3]}
        else
            jig[i] = v
        end
        -- keybinds also persist their Toggle/Hold mode
        if opt.type == "keybind" and opt.modeFlag then
            jig[opt.modeFlag] = library.flags[opt.modeFlag] or "Toggle"
        end
    end
    writefile(CONFIG_DIR.."/"..name..".cfg",game:GetService("HttpService"):JSONEncode(jig))
    library:notify("Succesfully created config "..name..".cfg!")
    library:refreshConfigs()
end

function library:saveConfig()
    local name = library.flags["selected_config"]
    local jig = {}
    for i,v in next, library.flags do
        local opt = library.options[i]
        if not opt or opt.skipflag then continue end
        if typeof(v) == "Color3" then
            jig[i] = {v.R,v.G,v.B}
        elseif typeof(v) == "EnumItem" then
            jig[i] = {string.split(tostring(v),".")[2],string.split(tostring(v),".")[3]}
        else
            jig[i] = v
        end
        -- keybinds also persist their Toggle/Hold mode
        if opt.type == "keybind" and opt.modeFlag then
            jig[opt.modeFlag] = library.flags[opt.modeFlag] or "Toggle"
        end
    end
    writefile(CONFIG_DIR.."/"..name..".cfg",game:GetService("HttpService"):JSONEncode(jig))
    library:notify("Succesfully updated config "..name..".cfg!")
    library:refreshConfigs()
end

function library:loadConfig()
    local name = library.flags["selected_config"]
    if not isfile(CONFIG_DIR.."/"..name..".cfg") then
        library:notify("Config file not found!")
        return
    end
    local config = game:GetService("HttpService"):JSONDecode(readfile(CONFIG_DIR.."/"..name..".cfg"))
    -- Apply one option's value from the loaded config (or its default if absent)
    local function applyOption(i, v)
        if config[i] then
            if v.type == "colorpicker" then
                v.changeState(Color3.new(config[i][1],config[i][2],config[i][3]))
            elseif v.type == "keybind" then
                v.changeState(Enum[config[i][1]][config[i][2]])
                if v.setMode and v.modeFlag and config[v.modeFlag] then
                    v.setMode(config[v.modeFlag])
                end
            else
                if config[i] ~= library.flags[i] then
                    v.changeState(config[i])
                end
            end
        else
            local a = v.oldargs or {}
            if v.type == "toggle" then
                v.changeState(a.value == true)
            elseif v.type == "slider" then
                v.changeState(a.value or 0)
            elseif v.type == "textbox" or v.type == "list" or v.type == "cfg" then
                v.changeState(a.value or a.text or "")
            elseif v.type == "colorpicker" then
                v.changeState(a.color or Color3.new(1,1,1))
            elseif v.type == "keybind" then
                v.changeState(a.key or Enum.KeyCode.Unknown)
                if v.setMode then v.setMode(a.mode or "Toggle") end
            end
        end
    end

    -- Spread the work across frames so heavy callbacks (ESP/lighting/skins/name
    -- scan) don't all fire on one frame and freeze the game.
    task.spawn(function()
        local processed = 0
        for i, v in next, library.options do
            pcall(applyOption, i, v)
            processed += 1
            if processed % 8 == 0 then
                task.wait()  -- yield to let the frame breathe
            end
        end
        library:notify("Succesfully loaded config "..name..".cfg!")
    end)
end

function library:refreshConfigs()
    local tbl = {}
    local ok, files = pcall(listfiles, CONFIG_DIR)
    if ok and files then
        for _, v in next, files do
            -- listfiles returns FULL paths (e.g. "riots/name.cfg" or "riots\name.cfg").
            -- strip the directory + extension so the dropdown holds CLEAN names, and so
            -- save/load rebuild the path correctly instead of "riots/riots/x.cfg.cfg".
            local fname = tostring(v):gsub("[/\\]+$", "")
            fname = fname:match("[^/\\]+$") or fname          -- drop the folder prefix
            if fname:sub(-4):lower() == ".cfg" then
                local clean = fname:sub(1, #fname - 4)         -- drop the .cfg extension
                table.insert(tbl, clean)
            end
        end
    end
    if library.options["selected_config"] and library.options["selected_config"].refresh then
        library.options["selected_config"].refresh(tbl)
    end
end

function library:deleteConfig()
    if isfile(CONFIG_DIR.."/"..library.flags["selected_config"]..".cfg") then
        delfile(CONFIG_DIR.."/"..library.flags["selected_config"]..".cfg")
        library:refreshConfigs()
    end
end

local AUTOLOAD_FILE = CONFIG_DIR.."/autoload.txt"
function library:setAutoload(name)
    if not name or name == "" then return end
    pcall(function() writefile(AUTOLOAD_FILE, name) end)
    library.autoloadName = name
    library:notify("Autoload set to "..name)
end
function library:clearAutoload()
    pcall(function() if isfile(AUTOLOAD_FILE) then delfile(AUTOLOAD_FILE) end end)
    library.autoloadName = nil
    library:notify("Autoload cleared")
end
function library:getAutoload()
    local ok, data = pcall(function()
        if isfile(AUTOLOAD_FILE) then return readfile(AUTOLOAD_FILE) end
    end)
    if ok and data and data ~= "" then return data end
    return nil
end
function library:runAutoload()
    local name = library:getAutoload()
    if not name then return end
    if not isfile(CONFIG_DIR.."/"..name..".cfg") then return end
    library.flags["selected_config"] = name
    pcall(function()
        if library.options["selected_config"] and library.options["selected_config"].changeState then
            library.options["selected_config"].changeState(name)
        end
    end)
    library:loadConfig()
end

local THEME_FILE = CONFIG_DIR.."/theme.json"
local function color3ToTable(c) return { math.floor(c.R*255+0.5), math.floor(c.G*255+0.5), math.floor(c.B*255+0.5) } end
local function tableToColor3(t) return Color3.fromRGB(t[1] or 255, t[2] or 42, t[3] or 42) end

function library:getTheme()
    return { accent = color3ToTable(library.libColor) }
end
function library:applyTheme(theme)
    if type(theme) ~= "table" then return end
    if theme.accent then
        local c = tableToColor3(theme.accent)
        library:recolor(c)
        if library.options["MenuAccent"] and library.options["MenuAccent"].changeState then
            pcall(library.options["MenuAccent"].changeState, c)
        end
    end
end
function library:exportTheme()
    local json = game:GetService("HttpService"):JSONEncode(library:getTheme())
    local set = setclipboard or toclipboard or (syn and syn.write_clipboard)
    if set then pcall(set, json); library:notify("Theme copied to clipboard") else library:notify("No clipboard function") end
    return json
end
function library:importTheme(str)
    str = str or ""
    if str == "" then return library:notify("Paste a theme string first") end
    local ok, theme = pcall(function() return game:GetService("HttpService"):JSONDecode(str) end)
    if not ok or type(theme) ~= "table" then return library:notify("Invalid theme string") end
    library:applyTheme(theme)
    library:notify("Theme imported")
end
function library:saveTheme()
    pcall(function() writefile(THEME_FILE, game:GetService("HttpService"):JSONEncode(library:getTheme())) end)
    library:notify("Theme saved")
end
function library:loadTheme()
    local ok, data = pcall(function() if isfile(THEME_FILE) then return readfile(THEME_FILE) end end)
    if not ok or not data then return end
    local ok2, theme = pcall(function() return game:GetService("HttpService"):JSONDecode(data) end)
    if ok2 and type(theme) == "table" then library:applyTheme(theme) end
end

-- ── theme presets ────────────────────────────────────────────────────────────
-- Each preset defines an accent (drives library:recolor) plus a `colors` map of
-- colorpicker flag -> Color3. Applying a preset actually pushes those colours
-- through each picker's changeState so the swatches + ESP config update live.
local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end
library.themePresets = {
    ["classic"] = {
        accent = rgb(255, 42, 42),
        colors = {
            box_outline_color = rgb(255,42,42), box_outline_color2 = rgb(0,0,0),
            esp_name_c1 = rgb(255,255,255), esp_name_c2 = rgb(255,42,42),
            esp_dist_c1 = rgb(200,200,200), esp_dist_c2 = rgb(255,42,42),
            esp_tool_c1 = rgb(200,200,200), esp_tool_c2 = rgb(255,42,42),
            esp_skel_c1 = rgb(255,42,42), esp_skel_c2 = rgb(120,0,0),
            esp_tracer_c1 = rgb(255,42,42), esp_tracer_c2 = rgb(120,0,0),
            esp_chams_c1 = rgb(255,42,42), esp_chams_c2 = rgb(0,0,0),
            esp_glowchams_c1 = rgb(255,42,42),
            CrosshairC1 = rgb(255,42,42), CrosshairC2 = rgb(255,120,120),
        },
    },
    ["nebula"] = {
        accent = rgb(138, 79, 255),
        colors = {
            box_outline_color = rgb(138,79,255), box_outline_color2 = rgb(20,10,40),
            esp_name_c1 = rgb(220,200,255), esp_name_c2 = rgb(138,79,255),
            esp_dist_c1 = rgb(180,160,220), esp_dist_c2 = rgb(90,60,180),
            esp_tool_c1 = rgb(180,160,220), esp_tool_c2 = rgb(90,60,180),
            esp_skel_c1 = rgb(138,79,255), esp_skel_c2 = rgb(60,20,120),
            esp_tracer_c1 = rgb(138,79,255), esp_tracer_c2 = rgb(60,20,120),
            esp_chams_c1 = rgb(138,79,255), esp_chams_c2 = rgb(20,10,40),
            esp_glowchams_c1 = rgb(160,110,255),
            CrosshairC1 = rgb(138,79,255), CrosshairC2 = rgb(200,170,255),
        },
    },
    ["sunrise"] = {
        accent = rgb(255, 138, 60),
        colors = {
            box_outline_color = rgb(255,138,60), box_outline_color2 = rgb(60,20,0),
            esp_name_c1 = rgb(255,235,200), esp_name_c2 = rgb(255,138,60),
            esp_dist_c1 = rgb(255,200,150), esp_dist_c2 = rgb(255,90,40),
            esp_tool_c1 = rgb(255,200,150), esp_tool_c2 = rgb(255,90,40),
            esp_skel_c1 = rgb(255,138,60), esp_skel_c2 = rgb(200,60,20),
            esp_tracer_c1 = rgb(255,180,60), esp_tracer_c2 = rgb(255,90,40),
            esp_chams_c1 = rgb(255,138,60), esp_chams_c2 = rgb(60,20,0),
            esp_glowchams_c1 = rgb(255,170,90),
            CrosshairC1 = rgb(255,138,60), CrosshairC2 = rgb(255,210,140),
        },
    },
    ["galaxy"] = {
        accent = rgb(70, 130, 255),
        colors = {
            box_outline_color = rgb(70,130,255), box_outline_color2 = rgb(10,10,30),
            esp_name_c1 = rgb(200,220,255), esp_name_c2 = rgb(70,130,255),
            esp_dist_c1 = rgb(150,180,240), esp_dist_c2 = rgb(40,80,200),
            esp_tool_c1 = rgb(150,180,240), esp_tool_c2 = rgb(40,80,200),
            esp_skel_c1 = rgb(70,130,255), esp_skel_c2 = rgb(20,40,120),
            esp_tracer_c1 = rgb(120,80,255), esp_tracer_c2 = rgb(40,80,200),
            esp_chams_c1 = rgb(70,130,255), esp_chams_c2 = rgb(10,10,30),
            esp_glowchams_c1 = rgb(120,160,255),
            CrosshairC1 = rgb(70,130,255), CrosshairC2 = rgb(180,200,255),
        },
    },
    ["gold"] = {
        accent = rgb(255, 200, 60),
        colors = {
            box_outline_color = rgb(255,200,60), box_outline_color2 = rgb(40,30,0),
            esp_name_c1 = rgb(255,245,210), esp_name_c2 = rgb(255,200,60),
            esp_dist_c1 = rgb(240,220,150), esp_dist_c2 = rgb(200,150,30),
            esp_tool_c1 = rgb(240,220,150), esp_tool_c2 = rgb(200,150,30),
            esp_skel_c1 = rgb(255,200,60), esp_skel_c2 = rgb(160,110,20),
            esp_tracer_c1 = rgb(255,215,90), esp_tracer_c2 = rgb(200,150,30),
            esp_chams_c1 = rgb(255,200,60), esp_chams_c2 = rgb(40,30,0),
            esp_glowchams_c1 = rgb(255,220,120),
            CrosshairC1 = rgb(255,200,60), CrosshairC2 = rgb(255,235,170),
        },
    },
}

function library:applyThemePreset(name)
    local preset = library.themePresets[name]
    if not preset then return end
    -- accent cascades across the whole UI
    library:recolor(preset.accent)
    -- keep the accent swatches in sync
    for _, f in ipairs({"MenuAccent", "ThemeAccent"}) do
        local opt = library.options[f]
        if opt and opt.changeState then pcall(opt.changeState, preset.accent) end
    end
    -- push each colour through its picker so swatches + live config update
    for flag, color in pairs(preset.colors) do
        local opt = library.options[flag]
        if opt and opt.changeState then pcall(opt.changeState, color) end
    end
    library.currentTheme = name
    library:notify("Applied theme: "..name)
end

local Workspace         = game:GetService("Workspace")
local RunService        = runService
local Camera            = Workspace.CurrentCamera
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = Workspace.CurrentCamera
end)

local function getAspectStretch()
    return 1
end

local function applyAspectToViewport(screenVec, cam)
    local stretch = getAspectStretch()
    if stretch == 1 then return screenVec end
    cam = cam or Workspace.CurrentCamera
    if not cam then return screenVec end
    local centerY = cam.ViewportSize.Y * 0.5
    return Vector3.new(screenVec.X, centerY + (screenVec.Y - centerY) * stretch, screenVec.Z)
end

local function worldToScreen(worldPos, cam)
    cam = cam or Workspace.CurrentCamera
    if not cam or not worldPos then return nil, false end
    local v, onScreen = cam:WorldToViewportPoint(worldPos)
    if not onScreen or v.Z <= 0 then return v, false end
    return applyAspectToViewport(v, cam), true
end

local function screenAnchor(xNorm, yNorm, cam)
    cam = cam or Workspace.CurrentCamera
    if not cam then return Vector2.zero end
    local vs = cam.ViewportSize
    local stretch = getAspectStretch()
    local centerY = vs.Y * 0.5
    local y = centerY + (vs.Y * yNorm - centerY) * stretch
    return Vector2.new(vs.X * xNorm, y)
end

local function screenCenter(cam) return screenAnchor(0.5, 0.5, cam) end

local combatTab    = library:addTab("main")
local visualsTab   = library:addTab("visuals")
local skinsTab     = library:addTab("character")
local playersTab   = library:addTab("players")
local miscTab      = library:addTab("misc")
local settingsTab  = library:addTab("settings")
-- world tab was merged into visuals; alias keeps existing group calls working.
local worldTab     = visualsTab

local FOV_ORDER = 696969

local fovScreenGui = Instance.new("ScreenGui")
fovScreenGui.Name           = "riotsFOV"
fovScreenGui.DisplayOrder   = FOV_ORDER
fovScreenGui.ResetOnSpawn   = false
fovScreenGui.IgnoreGuiInset = true
fovScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function()
    fovScreenGui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
end)

local function buildfov(name, cfg)
    local container = Instance.new("Frame")
    container.Name = name
    container.BackgroundTransparency = 1
    container.BorderSizePixel = 0
    container.Visible = false
    container.Parent = fovScreenGui

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(1, 0, 1, 0)
    fill.BackgroundColor3 = Color3.new(1, 1, 1)
    fill.BackgroundTransparency = cfg.FilledTransparency
    fill.BorderSizePixel = 0
    fill.Visible = false
    fill.ZIndex = 1
    fill.Parent = container

    local fillCorner = Instance.new("UICorner")
    fillCorner.CornerRadius = UDim.new(1, 0)
    fillCorner.Parent = fill

    local fillgrad = Instance.new("UIGradient")
    fillgrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, cfg.FilledColor1),
        ColorSequenceKeypoint.new(1, cfg.FilledColor2),
    })
    fillgrad.Rotation = cfg.FilledRotation
    fillgrad.Parent = fill

    local outline = Instance.new("Frame")
    outline.Size = UDim2.new(1, 0, 1, 0)
    outline.BackgroundTransparency = 1
    outline.BorderSizePixel = 0
    outline.ZIndex = 2
    outline.Parent = container

    local outlineCorner = Instance.new("UICorner")
    outlineCorner.CornerRadius = UDim.new(1, 0)
    outlineCorner.Parent = outline

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.new(1, 1, 1)
    stroke.Thickness = cfg.OutlineThickness
    stroke.Transparency = cfg.OutlineTransparency
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = outline

    local strokegrad = Instance.new("UIGradient")
    strokegrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, cfg.OutlineColor1),
        ColorSequenceKeypoint.new(1, cfg.OutlineColor2),
    })
    strokegrad.Rotation = cfg.OutlineRotation
    strokegrad.Parent = stroke

    return { container = container, fill = fill, fillgrad = fillgrad, stroke = stroke, strokegrad = strokegrad }
end

local silentFOVCfg = {
    OutlineColor1 = Color3.fromRGB(255,255,255), OutlineColor2 = Color3.fromRGB(255,255,255),
    OutlineRotation = 0, OutlineThickness = 1.5, OutlineTransparency = 0,
    FilledEnabled = false, FilledColor1 = Color3.fromRGB(255,255,255), FilledColor2 = Color3.fromRGB(0,0,0),
    FilledRotation = 0, FilledTransparency = 0.7, FilledAnimated = false, FilledSpeed = 1,
    SpinOn = false, SpinSpd = 1, Rainbow = false,
}
local sFOV = buildfov("SilentFOV", silentFOVCfg)
local silentFOVContainer, silentFOVFill = sFOV.container, sFOV.fill
local silentFOVFillGrad, silentFOVStroke, silentFOVStrokeGrad = sFOV.fillgrad, sFOV.stroke, sFOV.strokegrad

local function silentlinegrad()
    silentFOVStrokeGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, silentFOVCfg.OutlineColor1),
        ColorSequenceKeypoint.new(1, silentFOVCfg.OutlineColor2),
    })
end
local function updsilentgrad()
    silentFOVFillGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, silentFOVCfg.FilledColor1),
        ColorSequenceKeypoint.new(1, silentFOVCfg.FilledColor2),
    })
end

local aimbotFOVCfg = {
    OutlineColor1 = Color3.fromRGB(255,255,255), OutlineColor2 = Color3.fromRGB(255,255,255),
    OutlineRotation = 0, OutlineThickness = 1.5, OutlineTransparency = 0,
    FilledEnabled = false, FilledColor1 = Color3.fromRGB(255,255,255), FilledColor2 = Color3.fromRGB(0,0,0),
    FilledRotation = 0, FilledTransparency = 0.7, FilledAnimated = false, FilledSpeed = 1,
    SpinOn = false, SpinSpd = 1, Rainbow = false,
}
local aFOV = buildfov("AimbotFOV", aimbotFOVCfg)
local aimbotFOVContainer, aimbotFOVFill = aFOV.container, aFOV.fill
local aimbotFOVFillGrad, aimbotFOVStroke, aimbotFOVStrokeGrad = aFOV.fillgrad, aFOV.stroke, aFOV.strokegrad

local function updaimbotoutlinegrad()
    aimbotFOVStrokeGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, aimbotFOVCfg.OutlineColor1),
        ColorSequenceKeypoint.new(1, aimbotFOVCfg.OutlineColor2),
    })
end
local function updaimbotfillgrad()
    aimbotFOVFillGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, aimbotFOVCfg.FilledColor1),
        ColorSequenceKeypoint.new(1, aimbotFOVCfg.FilledColor2),
    })
end

local silentAim = { enabled=false, hitPart="Head", fovRadius=100, followMuzzle=false, hitChance=100 }
local aimbot    = {
    enabled=false, masterEnabled=false, showFov=false,
    targetPart="Head", fovRadius=500,
    smoothingEnabled=true, smoothness=12,
    predictionEnabled=false, predX=0, predY=0,
    missChance=0, sticky=false,
    followMuzzle=false, lockedTarget=nil, smoothCF=nil,
    aimType="Cam",  -- "Cam" for camera, "Mouse" for mouse position
    -- target filters ("checks")
    checkWall=false,   -- require line of sight (visible)
    checkTeam=false,   -- ignore teammates
    checkDead=false,   -- ignore dead / knocked
    checkMelee=false,  -- don't lock while I have a melee equipped
}
local antikatana = false

local function muzzlepos()
    local vm = Workspace:FindFirstChild("ViewModels")
    if not vm then return nil end
    local fp = vm:FindFirstChild("FirstPerson")
    if not fp then return nil end
    local pn = localPlayer.Name
    for _, model in pairs(fp:GetChildren()) do
        if model:IsA("Model") and model.Name:find("^"..pn) then
            local iv = model:FindFirstChild("ItemVisual")
            if iv then
                local b = iv:FindFirstChild("Body")
                if b then
                    local bp = b:FindFirstChild("BodyPrimary")
                    if bp then
                        local muzzle = bp:FindFirstChild("_muzzle")
                        if muzzle and muzzle:IsA("Attachment") then
                            return muzzle.WorldPosition
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function screenpos2(worldPos)
    if not worldPos then return nil end
    local sp, ok = worldToScreen(worldPos, Camera)
    if not ok then return nil end
    return Vector2.new(sp.X, sp.Y)
end

local function silentfovcenter()
    if silentAim.followMuzzle then
        local s = screenpos2(muzzlepos())
        if s then return s end
    end
    return screenCenter(Camera)
end
local function aimbotfovcenter()
    if aimbot.followMuzzle then
        local s = screenpos2(muzzlepos())
        if s then return s end
    end
    return screenCenter(Camera)
end

local fovRainbowHue = 0

RunService.RenderStepped:Connect(function(dt)
  pcall(function()
    fovRainbowHue = (fovRainbowHue + dt * 0.2) % 1
    local rainbow = Color3.fromHSV(fovRainbowHue, 1, 1)

    if silentFOVContainer.Visible then
        local r = silentAim.fovRadius
        local c = silentfovcenter()
        silentFOVContainer.Position = UDim2.fromOffset(c.X - r, c.Y - r)
        silentFOVContainer.Size = UDim2.fromOffset(r * 2, r * 2)
        silentFOVFill.Visible = silentFOVCfg.FilledEnabled
        if silentFOVCfg.SpinOn then
            silentFOVStrokeGrad.Rotation = (silentFOVStrokeGrad.Rotation + silentFOVCfg.SpinSpd) % 360
        end
        if silentFOVCfg.FilledAnimated then
            silentFOVFillGrad.Rotation = (silentFOVFillGrad.Rotation + silentFOVCfg.FilledSpeed) % 360
        end
    end

    if aimbotFOVContainer.Visible then
        local r = aimbot.fovRadius
        local c = aimbotfovcenter()
        aimbotFOVContainer.Position = UDim2.fromOffset(c.X - r, c.Y - r)
        aimbotFOVContainer.Size = UDim2.fromOffset(r * 2, r * 2)
        aimbotFOVFill.Visible = aimbotFOVCfg.FilledEnabled
        if aimbotFOVCfg.SpinOn then
            aimbotFOVStrokeGrad.Rotation = (aimbotFOVStrokeGrad.Rotation + aimbotFOVCfg.SpinSpd) % 360
        end
        if aimbotFOVCfg.FilledAnimated then
            aimbotFOVFillGrad.Rotation = (aimbotFOVFillGrad.Rotation + aimbotFOVCfg.FilledSpeed) % 360
        end
    end
  end)
end)

local HPlist = {
    "Head","HumanoidRootPart","Torso","UpperTorso","LowerTorso",
    "Left Arm","LeftHand","LeftLowerArm","LeftUpperArm",
    "Right Arm","RightHand","RightLowerArm","RightUpperArm",
    "Left Leg","LeftFoot","LeftLowerLeg","LeftUpperLeg",
    "Right Leg","RightFoot","RightLowerLeg","RightUpperLeg",
    "Neck","Back","Front","Closest","Random"
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local restricteditems = {
    "Flamethrower","Fists","Battle Axe","Chainsaw","Katana","Knife",
    "Riot Shield","Scythe","Maul","Trowel","Grenade","Flashbang",
    "Jump Pad","Molotov","Satchel","Smoke Grenade","War Horn",
    "Medkit","Subspace Tripmine","Warpstone"
}

local function weaponstricted(weaponName)
    if not weaponName then return false end
    for _, w in ipairs(restricteditems) do
        if weaponName == w then return true end
    end
    return false
end

local function curweap2()
    local vm = Workspace:FindFirstChild("ViewModels")
    if not vm then return nil end
    local fp = vm:FindFirstChild("FirstPerson")
    if not fp then return nil end
    for _, child in ipairs(fp:GetChildren()) do
        local parts = {}
        for p in child.Name:gmatch("[^-]+") do
            table.insert(parts, p:match("^%s*(.-)%s*$"))
        end
        if #parts >= 2 then return parts[2] end
    end
    return nil
end

local function getUnstretchedCameraCFrame(cam)
    cam = cam or Workspace.CurrentCamera
    if not cam then return nil end
    local cf = cam.CFrame
    if getAspectStretch() == 1 then return cf end
    local pos = cf.Position
    local look = cf.LookVector
    local right = cf.RightVector
    local up = right:Cross(look).Unit
    return CFrame.fromMatrix(pos, right, up, -look)
end

local katanausers = {}
local katanaHooked = false
local function detectkatana()
    task.spawn(function()
        local lp = localPlayer
        pcall(function() lp:WaitForChild("PlayerScripts", 15) end)
        local ps = lp:FindFirstChild("PlayerScripts")
        if not ps then return end
        local attempts = 0
        while attempts < 10 and not katanaHooked do
            attempts += 1

            local katana
            pcall(function()
                local modules = ps:FindFirstChild("Modules")
                local items = modules and modules:FindFirstChild("Items")
                local m = items and items:FindFirstChild("Katana")
                if m and m:IsA("ModuleScript") then
                    katana = require(m)
                end
            end)
            if katana and type(katana) == "table" and katana.StartAiming then
                katanaHooked = true
                local old = katana.StartAiming
                katana.StartAiming = function(self, force)
                    local fighter = self.ClientFighter
                    local player  = fighter and fighter.Player
                    if player then
                        katanausers[player] = true
                        local dur = (self.Info and self.Info.DeflectDuration) or 0.6
                        task.delay(dur, function() katanausers[player] = nil end)
                    end
                    return old(self, force)
                end
                break
            end
            task.wait(1)
        end
    end)
end
detectkatana()

local function katanadeflect(player) return katanausers[player] == true end

local Utility, EnumLibrary
task.spawn(function()
    pcall(function()
        local modules = ReplicatedStorage:WaitForChild("Modules", 20)
        local u = modules and modules:WaitForChild("Utility", 20)
        Utility = u and require(u)
    end)
    pcall(function()
        local modules = ReplicatedStorage:WaitForChild("Modules", 20)
        local e = modules and modules:WaitForChild("EnumLibrary", 20)
        EnumLibrary = e and require(e)
    end)
end)

local backshoot = { enabled=false, connection=nil, target=nil, origCFrame=nil }
local curtarget = nil
local lastHitTime = 0
local backshootCheckConn = nil

local function closestplayerbs()
    local best, bestD = nil, math.huge
    local sc = screenCenter(Camera)
    for _, player in ipairs(players:GetPlayers()) do
        if player ~= localPlayer and player.Character then
            local root = player.Character:FindFirstChild("HumanoidRootPart")
            if root then
                local pos, on = worldToScreen(root.Position, Camera)
                if on then
                    local d = (sc - Vector2.new(pos.X, pos.Y)).Magnitude
                    if d < bestD then best = player.Character; bestD = d end
                end
            end
        end
    end
    return best
end
local function backshoot2()
    if backshoot.connection then backshoot.connection:Disconnect() end
    backshoot.connection = RunService.Heartbeat:Connect(function()
        local mc = localPlayer.Character
        if not mc or not mc:FindFirstChild("HumanoidRootPart") then return end
        if not backshoot.target then return end
        local tr = backshoot.target:FindFirstChild("HumanoidRootPart")
        if not tr then return end
        local behind = tr.Position + (-tr.CFrame.LookVector*5)
        mc.HumanoidRootPart.CFrame = CFrame.new(behind, tr.Position)
    end)
end
local function stopbs()
    if backshoot.connection then backshoot.connection:Disconnect(); backshoot.connection = nil end
end
local function startBackshootMonitor()
    if backshootCheckConn then return end
    backshootCheckConn = RunService.Heartbeat:Connect(function()
        if not backshoot.target then
            if backshootCheckConn then backshootCheckConn:Disconnect(); backshootCheckConn = nil end
            return
        end
        local hum = backshoot.target:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 then
            local mc = localPlayer.Character
            if mc and mc:FindFirstChild("HumanoidRootPart") and backshoot.origCFrame then
                mc.HumanoidRootPart.CFrame = backshoot.origCFrame
            end
            backshoot.target = nil; stopbs()
            if backshootCheckConn then backshootCheckConn:Disconnect(); backshootCheckConn = nil end
        end
    end)
end
localPlayer.CharacterRemoving:Connect(function()
    stopbs(); backshoot.target = nil; backshoot.origCFrame = nil
    if backshootCheckConn then backshootCheckConn:Disconnect(); backshootCheckConn = nil end
end)

local function hitpartfromname(target, partName)
    local fc = function(n) return target:FindFirstChild(n) end
    if     partName == "Head"             then return fc("Head")
    elseif partName == "HumanoidRootPart" then return fc("HumanoidRootPart")
    elseif partName == "Torso"            then return fc("Torso") or fc("UpperTorso")
    elseif partName == "UpperTorso"       then return fc("UpperTorso")
    elseif partName == "LowerTorso"       then return fc("LowerTorso")
    elseif partName == "Left Arm"         then return fc("Left Arm") or fc("LeftUpperArm")
    elseif partName == "LeftHand"         then return fc("LeftHand") or fc("Left Arm")
    elseif partName == "Right Arm"        then return fc("Right Arm") or fc("RightUpperArm")
    elseif partName == "RightHand"        then return fc("RightHand") or fc("Right Arm")
    elseif partName == "Left Leg"         then return fc("Left Leg") or fc("LeftUpperLeg")
    elseif partName == "Right Leg"        then return fc("Right Leg") or fc("RightUpperLeg")
    elseif partName == "Neck"             then return fc("Neck")
    elseif partName == "Back"             then return fc("Back") or fc("HumanoidRootPart")
    elseif partName == "Front"            then return fc("Front") or fc("HumanoidRootPart")
    elseif partName == "Closest" then
        local camPos  = Camera.CFrame.Position
        local camLook = Camera.CFrame.LookVector
        local best, bestD = nil, math.huge
        for _, part in pairs(target:GetChildren()) do
            if part:IsA("BasePart") then
                local d = 1 - camLook:Dot((part.Position-camPos).Unit)
                if d < bestD then bestD=d; best=part end
            end
        end
        return best or fc("HumanoidRootPart")
    elseif partName == "Random" then
        local list = {}
        for _, part in pairs(target:GetChildren()) do
            if part:IsA("BasePart") then table.insert(list, part) end
        end
        if #list > 0 then return list[math.random(1, #list)] end
    end
    return target:FindFirstChild("HumanoidRootPart")
end

local function shouldHitTarget()
    if silentAim.hitChance >= 100 then return true end
    if silentAim.hitChance <= 0   then return false end
    return math.random(1, 100) <= silentAim.hitChance
end

local function closestinfov(radius, center)
    local closest, closestDist = nil, math.huge
    local cam = Camera
    for _, player in ipairs(players:GetPlayers()) do
        if player ~= localPlayer then
            local char = player.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 and not char:FindFirstChildOfClass("ForceField") then
                    local root = char:FindFirstChild("HumanoidRootPart")
                    if root then
                        local pos, onScreen = worldToScreen(root.Position, cam)
                        if onScreen then
                            local dx = pos.X - center.X
                            local dy = pos.Y - center.Y
                            local dist = math.sqrt(dx*dx + dy*dy)
                            if dist <= radius and dist < closestDist then
                                closest = char
                                closestDist = dist
                            end
                        end
                    end
                end
            end
        end
    end
    -- NPC targets (shooting range / range entities)
    local range = Workspace:FindFirstChild("ShootingRangeEntities")
    if range then
        for _, model in ipairs(range:GetDescendants()) do
            if model:IsA("Model") then
                local hum = model:FindFirstChildOfClass("Humanoid")
                local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
                if hum and hum.Health > 0 and root then
                    local pos, onScreen = worldToScreen(root.Position, cam)
                    if onScreen then
                        local dx = pos.X - center.X
                        local dy = pos.Y - center.Y
                        local dist = math.sqrt(dx*dx + dy*dy)
                        if dist <= radius and dist < closestDist then
                            closest = model
                            closestDist = dist
                        end
                    end
                end
            end
        end
    end
    return closest
end

local function closestplayerinfov(radius)
    local c = closestinfov(radius, silentfovcenter())
    curtarget = c
    if silentAim.enabled then library.currentAimTarget = c; library.currentAimTargetAt = tick() end
    return c
end

local localFighter = nil
local camController = nil
local lastFireTime = 0
local fireCooldown = 0.05

local function firesilent()
    if not silentAim.enabled then return end
    local cw = curweap2()
    if cw and weaponstricted(cw) then return end
    local now = tick()
    if now - lastFireTime < fireCooldown then return end
    if not shouldHitTarget() then return end
    local closest = closestplayerinfov(silentAim.fovRadius)
    if not closest then return end
    local tp = players:GetPlayerFromCharacter(closest)
    if antikatana and tp and katanadeflect(tp) then return end
    local part = hitpartfromname(closest, silentAim.hitPart)
    if not part then return end
    local myChar = localPlayer.Character
    local root   = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local equipped = localFighter and localFighter.EquippedItem
    if not equipped then return end
    local objId = equipped:Get("ObjectID")
    if not objId then return end
    if not Utility or not EnumLibrary then return end
    lastFireTime  = now
    getgenv().InstanceCombatLastShotAt = tick()
    local shootPos  = root.Position
    local targetPos = part.Position
    local data = {
        [utf8.char(1)] = {
            [utf8.char(0)] = Utility:EncodeCFrame(CFrame.new(shootPos, targetPos)),
            [utf8.char(1)] = Utility:EncodeCFrame(CFrame.new(shootPos, targetPos)),
            [utf8.char(2)] = part,
            [utf8.char(3)] = Utility:EncodeCFrame(CFrame.new(0.43, 0.25, 0.42)),
        },
    }
    pcall(function()
        ReplicatedStorage.Remotes.Replication.Fighter.UseItem:FireServer(
            objId,
            EnumLibrary:ToEnum("StartShooting"),
            data,
            nil
        )
    end)
end

RunService.Heartbeat:Connect(function()
    if silentAim.enabled and not menu.Enabled then
        if inputService:GetFocusedTextBox() then return end
        if inputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            pcall(firesilent)
        end
    end
end)

inputService.InputBegan:Connect(function(input, gpe)
    if gpe or menu.Enabled then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        getgenv().InstanceCombatLastShotAt = tick()
    end
end)

task.spawn(function()
    repeat task.wait(0.1) until game:IsLoaded()
    repeat task.wait(0.1) until localPlayer.Parent
    repeat task.wait(0.1) until localPlayer:FindFirstChild("PlayerScripts")
    task.wait(0.8)
    pcall(function()
        local ctrl = localPlayer.PlayerScripts:WaitForChild("Controllers", 10)
        local cm   = ctrl:FindFirstChild("CameraController")
        if cm and cm:IsA("ModuleScript") then camController = require(cm) end
        local fm   = ctrl:FindFirstChild("FighterController")
        if fm and fm:IsA("ModuleScript") then
            local fc = require(fm)
            localFighter = fc.LocalFighter
        end
    end)
end)

local function clearAimbotLock()
    aimbot.lockedTarget = nil
    aimbot.smoothCF = nil
    if aimbot.enabled then library.currentAimTarget = nil end
end

local function getAimbotScreenPoint()
    if aimbot.followMuzzle then return aimbotfovcenter() end
    
    if aimbot.aimType == "Mouse" then
        local loc = inputService:GetMouseLocation()
        return Vector2.new(loc.X, loc.Y)
    else  -- "Cam" mode - center of screen
        return screenCenter(Camera)
    end
end

-- ===== aimbot target "checks" (filters) =====
local aimbotMeleeSet = {
    ["Fists"]=true, ["Battle Axe"]=true, ["Chainsaw"]=true, ["Katana"]=true,
    ["Knife"]=true, ["Scythe"]=true, ["Maul"]=true, ["Trowel"]=true, ["Riot Shield"]=true,
}
-- true if the local player currently has a melee equipped
local function aimbotSelfHasMelee()
    local w = curweap2()
    if not w then return false end
    return aimbotMeleeSet[w] == true
end
-- teammate check (self-contained; aimbot can't see the ESP-scoped one)
local function aimbotIsTeammate(char)
    local plr = players:GetPlayerFromCharacter(char)
    if not plr or plr == localPlayer then return false end
    local myTeam = localPlayer:GetAttribute("TeamID")
    local theirTeam = plr:GetAttribute("TeamID")
    if myTeam ~= nil and theirTeam ~= nil then return myTeam == theirTeam end
    if localPlayer.Team and plr.Team then return localPlayer.Team == plr.Team end
    return false
end
-- dead / knocked check
local function aimbotIsDown(char, hum)
    if hum and hum.Health <= 0 then return true end
    local be = char:FindFirstChild("BodyEffects")
    if be then
        local ko = be:FindFirstChild("K.O") or be:FindFirstChild("KO")
        if ko and ko.Value then return true end
    end
    return false
end
-- line of sight (wall) check: raycast from camera to the target part
local function aimbotVisible(part, char)
    local cam = Workspace.CurrentCamera
    if not cam or not part then return true end
    local origin = cam.CFrame.Position
    local dir = part.Position - origin
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = { char }
    if localPlayer.Character then table.insert(ignore, localPlayer.Character) end
    params.FilterDescendantsInstances = ignore
    params.IgnoreWater = true
    local result = Workspace:Raycast(origin, dir, params)
    -- nothing in the way (or whatever we hit belongs to the target) = visible
    if not result then return true end
    local hitModel = result.Instance and result.Instance:FindFirstAncestorOfClass("Model")
    return hitModel == char
end

local function closesttocursor()
    -- melee check: if enabled and I'm holding a melee, don't lock at all
    if aimbot.checkMelee and aimbotSelfHasMelee() then return nil end

    local best, bestDist = nil, aimbot.fovRadius
    local mp = getAimbotScreenPoint()
    if not mp then return nil end
    local cam = Workspace.CurrentCamera or Camera

    local function consider(model)
        if not model then return end
        local part = model:FindFirstChild(aimbot.targetPart)
            or model:FindFirstChild("HumanoidRootPart")
            or model:FindFirstChild("Head")
        if not part or not part:IsA("BasePart") or not part:IsDescendantOf(Workspace) then return end
        local hum = model:FindFirstChildOfClass("Humanoid")
        -- dead/knocked filter (always skip 0hp; checkDead also skips knocked)
        if hum and hum.Health <= 0 then return end
        if aimbot.checkDead and aimbotIsDown(model, hum) then return end
        -- team filter
        if aimbot.checkTeam and aimbotIsTeammate(model) then return end
        -- wall / visibility filter
        if aimbot.checkWall and not aimbotVisible(part, model) then return end
        local scr, on = worldToScreen(part.Position, cam)
        if not on then return end
        local dx = scr.X - mp.X
        local dy = scr.Y - mp.Y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < bestDist then bestDist = dist; best = part end
    end

    for _, p in ipairs(players:GetPlayers()) do
        if p ~= localPlayer and p.Character then consider(p.Character) end
    end
    local range = Workspace:FindFirstChild("ShootingRangeEntities")
    if range then
        for _, model in ipairs(range:GetDescendants()) do
            if model:IsA("Model") and model:FindFirstChildOfClass("Humanoid") then
                consider(model)
            end
        end
    end
    return best
end

local function getAimbotLerpAlpha(dt)
    if not aimbot.smoothingEnabled then return 1 end
    -- smoothness slider 1..30. Non-linear curve so the low end is VERY smooth
    -- (heavy lag = lots of smoothing) and the high end snaps near-instantly.
    -- Frame-rate independent (60fps reference).
    local s = math.clamp(tonumber(aimbot.smoothness) or 12, 1, 30)
    local norm = (s - 1) / 29           -- 0 at s=1, 1 at s=30
    -- per-60fps-frame rate constant: 0.05 (very smooth glide) -> ~5 (near-instant)
    local speed = 0.05 + (norm ^ 2) * 5
    -- (dt*60) keeps it framerate-independent; at 60fps alpha ~= 1 - e^-speed
    return math.clamp(1 - math.exp(-speed * dt * 60), 0, 1)
end

-- throttle target scan to every N frames to avoid FPS drops
local _aimbotScanFrame = 0
local _aimbotScanInterval = 3  -- re-scan every 3 frames
local _lastLockedModel = nil   -- track model changes for smoothCF reset

local function aimbotShouldLock()
    local mc = aimbot.missChance or 0
    if mc <= 0 then return true end
    if mc >= 100 then return false end
    return math.random(1, 100) > mc
end

local function aimbotAimPoint(part)
    local pos = part.Position
    if not aimbot.predictionEnabled then return pos end
    local vel = part.AssemblyLinearVelocity
    if not vel then return pos end
    return pos + Vector3.new(vel.X * aimbot.predX, vel.Y * aimbot.predY, vel.Z * aimbot.predX)
end

local function targetValid(part)
    if not part or not part.Parent or not part:IsDescendantOf(Workspace) then return false end
    local model = part:FindFirstAncestorOfClass("Model")
    local hum = model and model:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then return false end
    return true
end

local function stepAimbot(dt)
    dt = dt or (1 / 240)
    if not aimbot.enabled then clearAimbotLock(); return end
    local cam = Workspace.CurrentCamera
    if not cam then return end
    Camera = cam

    -- validate existing lock
    if aimbot.lockedTarget and not targetValid(aimbot.lockedTarget) then
        clearAimbotLock()
        _lastLockedModel = nil
    end

    -- throttle the expensive player scan to every N frames
    _aimbotScanFrame = _aimbotScanFrame + 1
    local shouldScan = (_aimbotScanFrame >= _aimbotScanInterval)
    if shouldScan then _aimbotScanFrame = 0 end

    if aimbot.sticky then
        if not aimbot.lockedTarget then
            if not shouldScan then return end
            if not aimbotShouldLock() then return end
            aimbot.lockedTarget = closesttocursor()
            aimbot.smoothCF = getUnstretchedCameraCFrame(cam)
            _lastLockedModel = aimbot.lockedTarget
            if not aimbot.lockedTarget then return end
        end
    else
        if shouldScan then
            if not aimbotShouldLock() then clearAimbotLock(); _lastLockedModel = nil; return end
            local newTarget = closesttocursor()
            -- reset smoothCF when target changes so there's no stale-lerp lag
            if newTarget ~= _lastLockedModel then
                aimbot.smoothCF = getUnstretchedCameraCFrame(cam)
                _lastLockedModel = newTarget
            end
            aimbot.lockedTarget = newTarget
        end
        if not aimbot.lockedTarget then return end
    end

    if not targetValid(aimbot.lockedTarget) then
        clearAimbotLock(); _lastLockedModel = nil; return
    end

    library.currentAimTarget = aimbot.lockedTarget:FindFirstAncestorOfClass("Model")
    library.currentAimTargetAt = tick()

    local myChar = localPlayer.Character
    if not myChar or not myChar:FindFirstChild("Head") then clearAimbotLock(); return end

    if not aimbot.smoothCF then aimbot.smoothCF = getUnstretchedCameraCFrame(cam) end

    local aimPos = aimbotAimPoint(aimbot.lockedTarget)
    local alpha  = getAimbotLerpAlpha(dt)

    if aimbot.aimType == "Mouse" then
        -- Mouse mode: move the mouse toward the target on screen
        local targetScreen, onScreen = worldToScreen(aimPos, cam)
        if not onScreen then return end
        local mousePos = inputService:GetMouseLocation()
        local dx = targetScreen.X - mousePos.X
        local dy = targetScreen.Y - mousePos.Y
        -- apply smoothing to the delta
        local moveX = dx * alpha
        local moveY = dy * alpha
        if math.abs(moveX) > 0.5 or math.abs(moveY) > 0.5 then
            pcall(function() mousemoverel(moveX, moveY) end)
        end
    else
        -- Cam mode: rotate the camera toward the target
        if not camController then return end
        local lookCF = CFrame.lookAt(cam.CFrame.Position, aimPos)
        aimbot.smoothCF = aimbot.smoothCF:Lerp(lookCF, alpha)
        if camController.MimicRotation then
            pcall(function() camController:MimicRotation(aimbot.smoothCF) end)
        end
    end
end

local aimbotConnection
local function updaimbot()
    if aimbotConnection then aimbotConnection:Disconnect(); aimbotConnection = nil end
    aimbotFOVContainer.Visible = aimbot.showFov
    if not aimbot.enabled then clearAimbotLock(); return end
    aimbotConnection = RunService.RenderStepped:Connect(stepAimbot)
end

RunService.Heartbeat:Connect(function()
    if aimbot.masterEnabled and aimbot.enabled then
        if not aimbotConnection then updaimbot() end
    else
        if aimbotConnection then aimbotConnection:Disconnect(); aimbotConnection = nil end
    end
end)

getgenv().CombatMods = getgenv().CombatMods or {
    RapidFire=false, NoSpread=false, NoRecoil=false, MaxAccuracy=false, RapidAttack=false,
}
task.spawn(function()
    local ok, GunModule = pcall(function()
        local ps = localPlayer:WaitForChild("PlayerScripts", 20)
        local modules = ps and ps:WaitForChild("Modules", 20)
        local itemTypes = modules and modules:WaitForChild("ItemTypes", 20)
        local gun = itemTypes and itemTypes:WaitForChild("Gun", 20)
        return gun and require(gun)
    end)
    if ok and GunModule then
        if GunModule.StartShooting and not getgenv().CombatMods.OriginalGunStartShooting then
            getgenv().CombatMods.OriginalGunStartShooting = GunModule.StartShooting
            GunModule.StartShooting = function(self, p26, p27)
                local oldCd
                if getgenv().CombatMods.RapidFire then
                    oldCd = self.Info.ShootCooldown
                    self.Info.ShootCooldown = 0
                end
                local result = { getgenv().CombatMods.OriginalGunStartShooting(self, p26, p27) }
                if getgenv().CombatMods.RapidFire then self.Info.ShootCooldown = oldCd end
                return table.unpack(result)
            end
        end
        if GunModule._Recoil and not getgenv().CombatMods.OriginalRecoil then
            getgenv().CombatMods.OriginalRecoil = GunModule._Recoil
            GunModule._Recoil = function(self, m)
                if getgenv().CombatMods.NoRecoil then return end
                return getgenv().CombatMods.OriginalRecoil(self, m)
            end
        end
    end
end)
task.spawn(function()
    local ok, GameplayUtility = pcall(function()
        return require(ReplicatedStorage.Modules.GameplayUtility)
    end)
    if ok and GameplayUtility and GameplayUtility.GetSpread and not getgenv().CombatMods.OriginalGetSpread then
        getgenv().CombatMods.OriginalGetSpread = GameplayUtility.GetSpread
        GameplayUtility.GetSpread = function(spread, aimMul, isAiming, isCrouch, pellet, total, consistent)
            if getgenv().CombatMods.NoSpread or getgenv().CombatMods.MaxAccuracy then
                return CFrame.new()
            end
            return getgenv().CombatMods.OriginalGetSpread(spread, aimMul, isAiming, isCrouch, pellet, total, consistent)
        end
    end
end)
task.spawn(function()
    local ok, MeleeModule = pcall(function()
        local ps = localPlayer:WaitForChild("PlayerScripts", 20)
        local modules = ps and ps:WaitForChild("Modules", 20)
        local itemTypes = modules and modules:WaitForChild("ItemTypes", 20)
        local melee = itemTypes and itemTypes:WaitForChild("Melee", 20)
        return melee and require(melee)
    end)
    if ok and MeleeModule and MeleeModule.StartShooting and not getgenv().CombatMods.OriginalMeleeStartShooting then
        getgenv().CombatMods.OriginalMeleeStartShooting = MeleeModule.StartShooting
        MeleeModule.StartShooting = function(self, p26, p27)
            local oldCd
            if getgenv().CombatMods.RapidAttack then
                oldCd = self.Info.AttackCooldown
                self.Info.AttackCooldown = 0
            end
            local result = { getgenv().CombatMods.OriginalMeleeStartShooting(self, p26, p27) }
            if getgenv().CombatMods.RapidAttack and oldCd then self.Info.AttackCooldown = oldCd end
            return table.unpack(result)
        end
    end
end)

local combatLeft  = combatTab:createTabbox('left')
local silentGroup       = combatLeft:addTab('silent')
local silentCustomGroup = combatLeft:addTab('customization')

local combatRight = combatTab:createTabbox('right')
local aimbotGroup       = combatRight:addTab('aimbot')
local aimbotCustomGroup = combatRight:addTab('customization')

local gunGroup     = combatTab:createGroup('left', 'gun')

silentGroup:addToggle({text = "enable", flag = "SilentAim", callback = function(v) silentAim.enabled = v end})
    :addHotkey({flag = "SilentAimKey"})
silentGroup:addToggle({text = "anti katana", flag = "AntiKatana", callback = function(v) antikatana = v end})
silentGroup:addToggle({text = "backshoot", flag = "BackshootToggle", callback = function(v)
    backshoot.enabled = v
    if v and backshoot.target then backshoot2(); startBackshootMonitor()
    elseif not v then
        stopbs()
        if backshoot.target and backshoot.origCFrame then
            local mc = localPlayer.Character
            if mc and mc:FindFirstChild("HumanoidRootPart") then mc.HumanoidRootPart.CFrame = backshoot.origCFrame end
        end
    end
end}):addHotkey({flag = "SelectTargetKey", callback = function()
    local mc = localPlayer.Character
    if not mc or not mc:FindFirstChild("HumanoidRootPart") then return end
    if backshoot.target then
        if backshoot.origCFrame then mc.HumanoidRootPart.CFrame = backshoot.origCFrame end
        backshoot.target = nil; stopbs()
    else
        backshoot.target = closestplayerbs()
        if backshoot.target then
            backshoot.origCFrame = mc.HumanoidRootPart.CFrame
            if backshoot.enabled then backshoot2() end
            startBackshootMonitor()
        end
    end
end})
silentGroup:addSlider({text = "hit chance", flag = "HitChance", value = 100, min = 0, max = 100,
    callback = function(v) silentAim.hitChance = v end})
silentGroup:addList({text = "hit part", flag = "HitPartDropdown", value = "Head", values = HPlist,
    callback = function(v) silentAim.hitPart = v end})

silentCustomGroup:addToggle({text = "show fov", flag = "ShowFOV",
    callback = function(v) silentFOVContainer.Visible = v end})
    :addColorpicker({text = "outline color 1", flag = "FOVOutlineColor1", color = Color3.fromRGB(255,255,255),
        callback = function(v) silentFOVCfg.OutlineColor1 = v; silentlinegrad() end})
    :addColorpicker({text = "outline color 2", flag = "FOVOutlineColor2", second = true, color = Color3.fromRGB(255,255,255),
        callback = function(v) silentFOVCfg.OutlineColor2 = v; silentlinegrad() end})

silentCustomGroup:addToggle({text = "fov fill", flag = "SilentFOVFilled",
    callback = function(v) silentFOVCfg.FilledEnabled = v; silentFOVFill.Visible = v end})
    :addColorpicker({text = "fill color 1", flag = "SilentFOVFillColor1", color = Color3.fromRGB(255,255,255),
        callback = function(v) silentFOVCfg.FilledColor1 = v; updsilentgrad() end})
    :addColorpicker({text = "fill color 2", flag = "SilentFOVFillColor2", second = true, color = Color3.fromRGB(0,0,0),
        callback = function(v) silentFOVCfg.FilledColor2 = v; updsilentgrad() end})

silentCustomGroup:addToggle({text = "animated fill", flag = "SilentFOVFillAnimated",
    callback = function(v) silentFOVCfg.FilledAnimated = v; if not v then silentFOVFillGrad.Rotation = silentFOVCfg.FilledRotation end end})
silentCustomGroup:addToggle({text = "fov spin", flag = "SilentFOVSpin",
    callback = function(v) silentFOVCfg.SpinOn = v; if not v then silentFOVStrokeGrad.Rotation = silentFOVCfg.OutlineRotation end end})
silentCustomGroup:addToggle({text = "follow muzzle", flag = "SilentFOVFollowMuzzle",
    callback = function(v) silentAim.followMuzzle = v end})
silentCustomGroup:addSlider({text = "fov radius", flag = "FOVRadius", value = 100, min = 10, max = 750,
    callback = function(v) silentAim.fovRadius = v end})
silentCustomGroup:addSlider({text = "outline thickness", flag = "SilentFOVOutlineThickness", value = 1, min = 1, max = 10,
    callback = function(v) silentFOVCfg.OutlineThickness = v; silentFOVStroke.Thickness = v end})
silentCustomGroup:addSlider({text = "outline transparency %", flag = "SilentFOVOutlineTransparency", value = 0, min = 0, max = 100, suffix = "%",
    callback = function(v) silentFOVCfg.OutlineTransparency = v/100; silentFOVStroke.Transparency = v/100 end})
silentCustomGroup:addSlider({text = "fill transparency %", flag = "SilentFOVFillTransparency", value = 70, min = 0, max = 100, suffix = "%",
    callback = function(v) silentFOVCfg.FilledTransparency = v/100; silentFOVFill.BackgroundTransparency = v/100 end})
silentCustomGroup:addSlider({text = "outline rotation", flag = "SilentFOVOutlineRotation", value = 0, min = 0, max = 360,
    callback = function(v) silentFOVCfg.OutlineRotation = v; silentFOVStrokeGrad.Rotation = v end})
silentCustomGroup:addSlider({text = "fill rotation", flag = "SilentFOVFillRotation", value = 0, min = 0, max = 360,
    callback = function(v) silentFOVCfg.FilledRotation = v; if not silentFOVCfg.FilledAnimated then silentFOVFillGrad.Rotation = v end end})
silentCustomGroup:addSlider({text = "fill speed", flag = "SilentFOVFillSpeed", value = 1, min = 1, max = 10,
    callback = function(v) silentFOVCfg.FilledSpeed = v end})
silentCustomGroup:addSlider({text = "spin speed", flag = "SilentFOVSpinSpd", value = 1, min = 1, max = 10,
    callback = function(v) silentFOVCfg.SpinSpd = v end})

aimbotGroup:addToggle({text = "enable", flag = "AimbotToggle",
    callback = function(v) aimbot.masterEnabled = v; aimbot.enabled = v; if not v then aimbot.lockedTarget = nil end end})
    :addHotkey({flag = "AimbotKey"})
aimbotGroup:addToggle({text = "sticky aim", flag = "AimbotSticky", callback = function(v) aimbot.sticky = v end})
aimbotGroup:addToggle({text = "smoothing", flag = "AimbotSmoothing", callback = function(v) aimbot.smoothingEnabled = v end})
aimbotGroup:addSlider({text = "smoothness", flag = "AimbotSmoothness", value = 12, min = 1, max = 30,
    callback = function(v) aimbot.smoothness = v end})
aimbotGroup:addToggle({text = "prediction", flag = "AimbotPrediction", callback = function(v) aimbot.predictionEnabled = v end})
aimbotGroup:addSlider({text = "prediction x", flag = "AimbotPredX", value = 0, min = 0, max = 50,
    callback = function(v) aimbot.predX = v / 100 end})
aimbotGroup:addSlider({text = "prediction y", flag = "AimbotPredY", value = 0, min = 0, max = 50,
    callback = function(v) aimbot.predY = v / 100 end})
aimbotGroup:addSlider({text = "miss chance %", flag = "AimbotMissChance", value = 0, min = 0, max = 100, suffix = "%",
    callback = function(v) aimbot.missChance = v end})
aimbotGroup:addList({text = "hit part", flag = "AimbotHitPart", value = "Head",
    values = {"Head","HumanoidRootPart","Torso","UpperTorso","LowerTorso"},
    callback = function(v) aimbot.targetPart = v end})
aimbotGroup:addList({text = "aimbot type", flag = "AimbotType", value = "Cam",
    values = {"Cam", "Mouse"},
    callback = function(v) aimbot.aimType = v end})
aimbotGroup:addList({text = "checks", flag = "AimbotChecks", multiselect = true,
    values = {"wall", "team", "melee", "dead"},
    callback = function(sel)
        sel = sel or {}
        local function has(name) return table.find(sel, name) ~= nil end
        aimbot.checkWall  = has("wall")
        aimbot.checkTeam  = has("team")
        aimbot.checkMelee = has("melee")
        aimbot.checkDead  = has("dead")
    end})

-- Instant zoom
local instantZoom = { enabled = false, amount = 35, origFov = nil }
local _izConn
local function applyZoom(on)
    local cam = Workspace.CurrentCamera
    if not cam then return end
    if on then
        instantZoom.origFov = cam.FieldOfView
        cam.FieldOfView = math.clamp(instantZoom.amount, 10, 120)
    else
        if instantZoom.origFov then cam.FieldOfView = instantZoom.origFov end
        instantZoom.origFov = nil
    end
end
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    if instantZoom.enabled then
        local cam = Workspace.CurrentCamera
        if cam then cam.FieldOfView = math.clamp(instantZoom.amount, 10, 120) end
    end
end)
aimbotGroup:addToggle({text = "instant zoom", flag = "InstantZoom",
    callback = function(v)
        instantZoom.enabled = v
        applyZoom(v)
    end}):addHotkey({flag = "InstantZoomKey", callback = function()
        instantZoom.enabled = not instantZoom.enabled
        applyZoom(instantZoom.enabled)
        library.options["InstantZoom"].changeState(instantZoom.enabled)
    end})
aimbotGroup:markStart()
aimbotGroup:addSlider({text = "zoom fov", flag = "InstantZoomAmount", value = 35, min = 10, max = 90,
    callback = function(v)
        instantZoom.amount = v
        if instantZoom.enabled then applyZoom(true) end
    end})
aimbotGroup:dependsOn("InstantZoom")

aimbotCustomGroup:addToggle({text = "show fov", flag = "ShowAimbotFOV",
    callback = function(v) aimbot.showFov = v; aimbotFOVContainer.Visible = v end})
    :addColorpicker({text = "outline color 1", flag = "AimbotFOVOutlineColor1", color = Color3.fromRGB(255,255,255),
        callback = function(v) aimbotFOVCfg.OutlineColor1 = v; updaimbotoutlinegrad() end})
    :addColorpicker({text = "outline color 2", flag = "AimbotFOVOutlineColor2", second = true, color = Color3.fromRGB(255,255,255),
        callback = function(v) aimbotFOVCfg.OutlineColor2 = v; updaimbotoutlinegrad() end})

aimbotCustomGroup:addToggle({text = "fov fill", flag = "AimbotFOVFilled",
    callback = function(v) aimbotFOVCfg.FilledEnabled = v; aimbotFOVFill.Visible = v end})
    :addColorpicker({text = "fill color 1", flag = "AimbotFOVFillColor1", color = Color3.fromRGB(255,255,255),
        callback = function(v) aimbotFOVCfg.FilledColor1 = v; updaimbotfillgrad() end})
    :addColorpicker({text = "fill color 2", flag = "AimbotFOVFillColor2", second = true, color = Color3.fromRGB(0,0,0),
        callback = function(v) aimbotFOVCfg.FilledColor2 = v; updaimbotfillgrad() end})

aimbotCustomGroup:addToggle({text = "animated fill", flag = "AimbotFOVFillAnimated",
    callback = function(v) aimbotFOVCfg.FilledAnimated = v; if not v then aimbotFOVFillGrad.Rotation = aimbotFOVCfg.FilledRotation end end})
aimbotCustomGroup:addToggle({text = "fov spin", flag = "AimbotFOVSpin",
    callback = function(v) aimbotFOVCfg.SpinOn = v; if not v then aimbotFOVStrokeGrad.Rotation = aimbotFOVCfg.OutlineRotation end end})
aimbotCustomGroup:addToggle({text = "follow muzzle", flag = "AimbotFOVFollowMuzzle",
    callback = function(v) aimbot.followMuzzle = v end})
aimbotCustomGroup:addSlider({text = "fov radius", flag = "AimbotFOV", value = 500, min = 10, max = 1000,
    callback = function(v) aimbot.fovRadius = v end})
aimbotCustomGroup:addSlider({text = "outline thickness", flag = "AimbotFOVOutlineThickness", value = 1, min = 1, max = 10,
    callback = function(v) aimbotFOVCfg.OutlineThickness = v; aimbotFOVStroke.Thickness = v end})
aimbotCustomGroup:addSlider({text = "outline transparency %", flag = "AimbotFOVOutlineTransparency", value = 0, min = 0, max = 100, suffix = "%",
    callback = function(v) aimbotFOVCfg.OutlineTransparency = v/100; aimbotFOVStroke.Transparency = v/100 end})
aimbotCustomGroup:addSlider({text = "fill transparency %", flag = "AimbotFOVFillTransparency", value = 70, min = 0, max = 100, suffix = "%",
    callback = function(v) aimbotFOVCfg.FilledTransparency = v/100; aimbotFOVFill.BackgroundTransparency = v/100 end})
aimbotCustomGroup:addSlider({text = "outline rotation", flag = "AimbotFOVOutlineRotation", value = 0, min = 0, max = 360,
    callback = function(v) aimbotFOVCfg.OutlineRotation = v; aimbotFOVStrokeGrad.Rotation = v end})
aimbotCustomGroup:addSlider({text = "fill rotation", flag = "AimbotFOVFillRotation", value = 0, min = 0, max = 360,
    callback = function(v) aimbotFOVCfg.FilledRotation = v; if not aimbotFOVCfg.FilledAnimated then aimbotFOVFillGrad.Rotation = v end end})
aimbotCustomGroup:addSlider({text = "fill speed", flag = "AimbotFOVFillSpeed", value = 1, min = 1, max = 10,
    callback = function(v) aimbotFOVCfg.FilledSpeed = v end})
aimbotCustomGroup:addSlider({text = "spin speed", flag = "AimbotFOVSpinSpd", value = 1, min = 1, max = 10,
    callback = function(v) aimbotFOVCfg.SpinSpd = v end})

getgenv().CombatMods = getgenv().CombatMods or {
    RapidFire=false, NoSpread=false, NoRecoil=false, MaxAccuracy=false, RapidAttack=false,
}
gunGroup:addToggle({text = "rapid fire",     flag = "NoCooldown",  callback = function(v) getgenv().CombatMods.RapidFire = v end})
gunGroup:addToggle({text = "no spread",      flag = "NoSpread",    callback = function(v) getgenv().CombatMods.NoSpread = v end})
gunGroup:addToggle({text = "no recoil",      flag = "NoRecoil",    callback = function(v) getgenv().CombatMods.NoRecoil = v end})
gunGroup:addToggle({text = "max accuracy",   flag = "MaxAccuracy", callback = function(v) getgenv().CombatMods.MaxAccuracy = v end})
gunGroup:addToggle({text = "rapid attack",   flag = "RapidAttack", callback = function(v) getgenv().CombatMods.RapidAttack = v end})

-- ─────────────────────────────────────────────────────────────────────────────
-- HIT CHAMS
-- Creates a temporary clone Highlight on the target when we deal damage
-- ─────────────────────────────────────────────────────────────────────────────
local hitChamsCfg = {
    enabled     = false,
    color       = Color3.fromRGB(255,42,42),
    color2      = Color3.fromRGB(255,180,0),
    transparency= 0.3,
    duration    = 0.18,
    throughWalls= true,
}
local _hitChamsHpTrack = setmetatable({}, {__mode="k"})
local function flashHitChams(char)
    if not char or not char.Parent then return end
    local h = Instance.new("Highlight")
    h.Name = "HitChamsFlash"
    h.Adornee = char
    h.FillColor = hitChamsCfg.color
    h.OutlineColor = hitChamsCfg.color2
    h.FillTransparency = hitChamsCfg.transparency
    h.OutlineTransparency = 0
    h.DepthMode = hitChamsCfg.throughWalls
        and Enum.HighlightDepthMode.AlwaysOnTop
        or  Enum.HighlightDepthMode.Occluded
    h.Parent = char
    task.delay(hitChamsCfg.duration, function()
        pcall(function() if h and h.Parent then h:Destroy() end end)
    end)
end

-- hit notify (FIXED preset — no editable message): "hit {username} {bodypart} for {damage}"
-- stored on `library` so the hit-notify UI (built in the vfx block, a separate scope)
-- can reach the same config.
library.hitNotifyCfg = library.hitNotifyCfg or { enabled = false, duration = 3, animation = "fade bounce" }
local hitNotifyCfg = library.hitNotifyCfg

-- subscribe to the shared damage event (hook is set up once, near library setup)
library:onDamage(function(hit_char, hit_root, hit_damage, is_headshot)
    if hitChamsCfg.enabled then pcall(flashHitChams, hit_char) end
    if hitNotifyCfg.enabled then
        local part = is_headshot and "Head" or "Body"
        local plr = players:GetPlayerFromCharacter(hit_char)
        local uname = plr and plr.Name or hit_char.Name
        local msg = string.format("hit %s %s for %d", uname, part, math.floor(hit_damage or 0))
        pcall(function() library:hitNotify(msg, hitNotifyCfg.duration, hitNotifyCfg.animation) end)
    end
end)

local hitChamsGroup = visualsTab:createGroup('right', 'hit chams')
hitChamsGroup:addToggle({text = "enable", flag = "HitChamsEnabled",
    callback = function(v) hitChamsCfg.enabled = v end})
    :addColorpicker({text = "fill color", flag = "HitChamsFill", color = Color3.fromRGB(255,42,42),
        callback = function(v) hitChamsCfg.color = v end})
    :addColorpicker({text = "outline color", flag = "HitChamsOutline", second = true, color = Color3.fromRGB(255,180,0),
        callback = function(v) hitChamsCfg.color2 = v end})
hitChamsGroup:markStart()
hitChamsGroup:addSlider({text = "fill transparency %", flag = "HitChamsTrans", value = 30, min = 0, max = 100, suffix = "%",
    callback = function(v) hitChamsCfg.transparency = v/100 end})
hitChamsGroup:addSlider({text = "flash duration", flag = "HitChamsDuration", value = 18, min = 5, max = 100,
    callback = function(v) hitChamsCfg.duration = v/100 end})
hitChamsGroup:addToggle({text = "through walls", flag = "HitChamsThroughWalls", value = true,
    callback = function(v) hitChamsCfg.throughWalls = v end})
hitChamsGroup:dependsOn("HitChamsEnabled")

-- (old combat-tab hit notify removed; the working hit notify now lives in the
--  visuals tab, wired to the server damage hook alongside damage numbers)

local spinbot = { enabled = false, speed = 25, connection = nil }

local function startSpinbot()
    if spinbot.connection then spinbot.connection:Disconnect() end
    spinbot.connection = RunService.Heartbeat:Connect(function()
        if not spinbot.enabled then return end
        local mc = localPlayer.Character
        local hrp = mc and mc:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        pcall(function()
            hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(spinbot.speed), 0)
        end)
    end)
end
local function stopSpinbot()
    if spinbot.connection then spinbot.connection:Disconnect(); spinbot.connection = nil end
    spinbot.enabled = false
end

localPlayer.CharacterRemoving:Connect(function() stopSpinbot() end)

local spinGroup = combatTab:createGroup('right', 'spinbot')
spinGroup:addToggle({text = "enable", flag = "SpinbotEnabled", callback = function(v)
    spinbot.enabled = v
    if v then startSpinbot() else stopSpinbot() end
end}):addHotkey({flag = "SpinbotKey"})
spinGroup:addSlider({text = "spin speed", flag = "SpinbotSpeed", value = 25, min = 1, max = 100,
    callback = function(v) spinbot.speed = v end})

-- ─────────────────────────────────────────────────────────────────────────────
-- TARGET SECTION
-- ─────────────────────────────────────────────────────────────────────────────
local targetMgr = {
    spectating      = false,
    spectateConn    = nil,
    specCF          = nil,
    tpEnabled       = false,
    tpConn          = nil,
    spamTP          = false,
    orbit           = false,
    orbitRadius     = 8,
    orbitSpeed      = 90,
    orbitAngle      = 0,
    tpOffset        = 3,
}

-- helper: get current valid target character
local function getTargetChar()
    local m = library.currentAimTarget
    if not m or not m.Parent then return nil end
    local hum = m:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 0 then return nil end
    return m
end

-- SPECTATE (smooth third-person orbit-follow of the target)
local function startSpectate()
    if targetMgr.spectateConn then targetMgr.spectateConn:Disconnect() end
    targetMgr.spectating = true
    -- seed the smoothed camera from wherever it is right now
    local cam0 = Workspace.CurrentCamera
    targetMgr.specCF = cam0 and cam0.CFrame or CFrame.new()
    targetMgr.spectateConn = RunService.RenderStepped:Connect(function(dt)
        if not targetMgr.spectating then return end
        local cam = Workspace.CurrentCamera
        if not cam then return end
        local char = getTargetChar()
        if not char then
            -- no valid target: hand control back so we don't lock a frozen view
            if cam.CameraType ~= Enum.CameraType.Custom then
                pcall(function() cam.CameraType = Enum.CameraType.Custom end)
            end
            return
        end
        local hrp = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
        if not hrp then return end

        pcall(function()
            if cam.CameraType ~= Enum.CameraType.Scriptable then
                cam.CameraType = Enum.CameraType.Scriptable
            end
            -- desired camera: behind + above the target, looking at the head/torso
            local head = char:FindFirstChild("Head") or hrp
            local lookAt = head.Position + Vector3.new(0, 1, 0)
            local behind = (hrp.CFrame.LookVector * -9) + Vector3.new(0, 4, 0)
            local desired = CFrame.new(hrp.Position + behind, lookAt)
            -- smooth toward it (slight delay so it isn't jittery)
            local a = math.clamp(dt * 10, 0, 1)
            targetMgr.specCF = targetMgr.specCF:Lerp(desired, a)
            cam.CFrame = targetMgr.specCF
        end)
    end)
end
local function stopSpectate()
    targetMgr.spectating = false
    if targetMgr.spectateConn then targetMgr.spectateConn:Disconnect(); targetMgr.spectateConn = nil end
    pcall(function()
        local cam = Workspace.CurrentCamera
        if cam then
            cam.CameraType = Enum.CameraType.Custom
            cam.CameraSubject = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
        end
    end)
end

-- TP TO TARGET / ORBIT / SPAM TP
local function startTP()
    if targetMgr.tpConn then targetMgr.tpConn:Disconnect(); targetMgr.tpConn = nil end
    targetMgr.tpConn = RunService.Heartbeat:Connect(function(dt)
        -- hard gate: the instant the toggle/hold is off, do nothing (and self-clean)
        if not targetMgr.tpEnabled then
            if targetMgr.tpConn then targetMgr.tpConn:Disconnect(); targetMgr.tpConn = nil end
            return
        end
        local mc  = localPlayer.Character
        local hrp = mc and mc:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local char = getTargetChar()
        if not char then return end
        local tr = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
        if not tr then return end

        if targetMgr.orbit then
            -- orbit around the target
            targetMgr.orbitAngle = (targetMgr.orbitAngle + targetMgr.orbitSpeed * dt) % 360
            local rad = math.rad(targetMgr.orbitAngle)
            local r   = targetMgr.orbitRadius
            local pos = tr.Position + Vector3.new(math.cos(rad)*r, 0, math.sin(rad)*r)
            pcall(function() hrp.CFrame = CFrame.new(pos, tr.Position) end)
        else
            -- follow: sit just behind the target (spam tp = every frame, else only when far)
            local off = tr.CFrame.LookVector * -targetMgr.tpOffset + Vector3.new(0, 0, 0)
            local want = CFrame.new(tr.Position + off, tr.Position)
            if targetMgr.spamTP then
                pcall(function() hrp.CFrame = want end)
            else
                -- non-spam: only reposition when we've drifted away, avoids constant snapping
                if (hrp.Position - tr.Position).Magnitude > (targetMgr.tpOffset + 4) then
                    pcall(function() hrp.CFrame = want end)
                end
            end
        end
    end)
end
local function stopTP()
    targetMgr.tpEnabled = false
    if targetMgr.tpConn then targetMgr.tpConn:Disconnect(); targetMgr.tpConn = nil end
end
-- one-shot TP (hotkey / button)
local function doOneTP()
    local mc  = localPlayer.Character
    local hrp = mc and mc:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    local char = getTargetChar()
    if not char then library:notify("no target locked"); return end
    local tr = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
    if not tr then return end
    local off = tr.CFrame.LookVector * -targetMgr.tpOffset
    pcall(function() hrp.CFrame = CFrame.new(tr.Position + off, tr.Position) end)
end

localPlayer.CharacterRemoving:Connect(function()
    stopSpectate(); stopTP()
end)

local targetLeft  = combatTab:createTabbox('left')
local targetGroup = targetLeft:addTab('target')
local tpGroup     = targetLeft:addTab('tp settings')

targetGroup:addToggle({text = "target hud", flag = "TargetHudCombat",
    callback = function(v) _G.riotsHUD.TargetHud = v end})

targetGroup:addToggle({text = "spectate target", flag = "SpectateTarget",
    callback = function(v)
        if v then startSpectate() else stopSpectate() end
    end}):addHotkey({flag = "SpectateKey"})

targetGroup:addToggle({text = "tp to target", flag = "TPTarget",
    callback = function(v)
        targetMgr.tpEnabled = v
        if v then startTP() else stopTP() end
    end}):addHotkey({flag = "TPTargetKey", key = Enum.KeyCode.Unknown})

-- tp settings (visible when tp to target is on)
targetGroup:markStart()
targetGroup:addToggle({text = "spam tp", flag = "SpamTP",
    callback = function(v)
        targetMgr.spamTP = v
        if targetMgr.tpEnabled then startTP() end
    end})
targetGroup:addToggle({text = "orbit target", flag = "OrbitTarget",
    callback = function(v)
        targetMgr.orbit = v
        targetMgr.orbitAngle = 0
        if targetMgr.tpEnabled then startTP() end
    end})
targetGroup:dependsOn("TPTarget")

tpGroup:addSlider({text = "tp distance", flag = "TPOffset", value = 3, min = 1, max = 20,
    callback = function(v) targetMgr.tpOffset = v end})
tpGroup:addSlider({text = "orbit radius", flag = "OrbitRadius", value = 8, min = 2, max = 50,
    callback = function(v) targetMgr.orbitRadius = v end})
tpGroup:addSlider({text = "orbit speed", flag = "OrbitSpeed", value = 90, min = 10, max = 720,
    callback = function(v) targetMgr.orbitSpeed = v end})
tpGroup:addButton({text = "teleport now", callback = function() doOneTP() end})

local charConfig = { profile = {
    level = { enabled = false, value = 9999 },
    winstreak = { enabled = false, value = 9999 },
    namespoof = {
        displayEnabled = false, displayValue = "riots",
        usernameEnabled = false, usernameValue = "riots",
        verified = false, premium = false,
        spoofOthers = false, devSpoof = false,
    },
    skinchanger = { enabled = false, userid = "1" },
} }
local cp = localPlayer
local lastSpoof = ""
local checkupdating = false

local function escape(str) return str:gsub("([^%w])", "%%%1") end
local function clearbadges(str)
    if typeof(str) ~= "string" then return "" end
    return str:gsub(utf8.char(0xE000), ""):gsub(utf8.char(0xE001), "")
end

local badges = ""
local function badgeSuffix()
    return (charConfig.profile.namespoof.premium and utf8.char(0xE001) or "")
        .. (charConfig.profile.namespoof.verified and utf8.char(0xE000) or "")
end
local function spoofDisplay()
    if charConfig.profile.namespoof.devSpoof then return "riots.wtf" end
    return clearbadges(charConfig.profile.namespoof.displayValue or "riots") .. badgeSuffix()
end
local function spoofUsername()
    if charConfig.profile.namespoof.devSpoof then return "riots.wtf" end
    return clearbadges(charConfig.profile.namespoof.usernameValue or "riots")
end

local nameHooks = {}
local function nsActive()
    local n = charConfig.profile.namespoof
    return n.displayEnabled or n.usernameEnabled or n.spoofOthers or n.devSpoof
end

local function u(c)
    local n = charConfig.profile.namespoof
    if not (n.displayEnabled or n.devSpoof) then return end
    if c then
        local h = c:WaitForChild("Humanoid", 5)
        if h then
            pcall(function()
                h.DisplayName = spoofDisplay()
                local old = h.DisplayDistanceType
                h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
                h.DisplayDistanceType = old
            end)
        end
    end
end

local _nsMapCache, _nsMapAt = nil, 0
players.PlayerAdded:Connect(function() _nsMapCache = nil end)
players.PlayerRemoving:Connect(function() _nsMapCache = nil end)
local function applyNameToLabel(obj)
    if not nsActive() then return end
    if not (obj and obj.Parent) then return end
    local text = obj.Text
    if typeof(text) ~= "string" or text == "" then return end

    -- The replacement map is O(players) to build. Rebuilding it for every label on
    -- every Text change is what melts the client in a full lobby, so cache it and
    -- only rebuild a few times per second (or when the player list changes).
    local replacementMap = _nsMapCache
    if not replacementMap or (tick() - _nsMapAt) > 0.25 then
        local n = charConfig.profile.namespoof
        replacementMap = {}
        if n.devSpoof then
            for _, plr in ipairs(players:GetPlayers()) do
                replacementMap[plr.Name] = "riots.wtf"
                if plr.DisplayName ~= plr.Name then
                    replacementMap[plr.DisplayName] = "riots.wtf"
                end
            end
        else
            if n.displayEnabled and cp.DisplayName ~= "" then
                replacementMap[cp.DisplayName] = spoofDisplay()
            end
            if n.usernameEnabled then
                replacementMap[cp.Name] = spoofUsername()
            end
            if n.spoofOthers then
                for _, plr in ipairs(players:GetPlayers()) do
                    if plr ~= cp then
                        replacementMap[plr.Name] = spoofUsername()
                        if plr.DisplayName ~= plr.Name and not replacementMap[plr.DisplayName] then
                            replacementMap[plr.DisplayName] = spoofUsername()
                        end
                    end
                end
            end
        end
        _nsMapCache = replacementMap
        _nsMapAt = tick()
    end

    -- Skip if we already produced this exact text (prevents re-processing our own output)
    if obj:GetAttribute("riotsSpoofed") == text then return end

    -- Single-pass replacement. Only replace names that are NOT a substring of their
    -- own replacement, and never touch text that is already fully our spoof output.
    local newText = text
    for originalName, replacementName in pairs(replacementMap) do
        if originalName ~= ""
        and originalName ~= replacementName
        and not replacementName:find(escape(originalName))  -- avoid self-growing loops
        and newText:find(escape(originalName), 1, true) then
            newText = newText:gsub(escape(originalName), replacementName)
        end
    end

    if newText ~= text then
        obj:SetAttribute("riotsSpoofed", newText)  -- remember our own output
        obj.Text = newText
    end
end

local function s()
    if nsActive() and library.startNameScan then library.startNameScan() end
    if cp and cp.Character then
        local h = cp.Character:FindFirstChildOfClass("Humanoid")
        if h and (charConfig.profile.namespoof.displayEnabled or charConfig.profile.namespoof.devSpoof) then
            pcall(function()
                h.DisplayName = spoofDisplay()
                local old = h.DisplayDistanceType
                h.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
                h.DisplayDistanceType = old
            end)
        end
    end
    for obj in pairs(nameHooks) do
        if obj and obj.Parent then applyNameToLabel(obj) end
    end
end
library.reapplySpoof = s

local function applyskin(c)
    if not (charConfig.profile.skinchanger.enabled and c) then return end
    local h = c:WaitForChild("Humanoid", 5)
    local targetId = tonumber(charConfig.profile.skinchanger.userid)
    if not h or not targetId then return end
    pcall(function()
        local model = players:CreateHumanoidModelFromUserId(targetId)
        if not model then return end
        for _, obj in ipairs(c:GetChildren()) do
            if obj:IsA("Accessory") or obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("BodyColors") or obj:IsA("CharacterMesh") or obj:IsA("ShirtGraphic") then
                obj:Destroy()
            end
        end
        local head = c:FindFirstChild("Head")
        if head then
            local face = head:FindFirstChildOfClass("Decal")
            if face then face:Destroy() end
        end
        for _, obj in ipairs(model:GetChildren()) do
            if obj:IsA("Accessory") or obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("BodyColors") or obj:IsA("CharacterMesh") or obj:IsA("ShirtGraphic") then
                obj:Clone().Parent = c
            elseif obj.Name == "Head" then
                local targetFace = obj:FindFirstChildOfClass("Decal")
                if targetFace and head then targetFace:Clone().Parent = head end
            end
        end
        model:Destroy()
    end)
end

local function makeBasic(c)
    if not c then return end
    pcall(function()
        for _, obj in ipairs(c:GetDescendants()) do
            if obj:IsA("Accessory") or obj:IsA("Shirt") or obj:IsA("Pants")
                or obj:IsA("CharacterMesh") or obj:IsA("ShirtGraphic") then
                obj:Destroy()
            elseif obj:IsA("Decal") and obj.Parent and obj.Parent.Name == "Head" then
                obj:Destroy()
            elseif obj:IsA("BodyColors") then
                obj.HeadColor3 = Color3.fromRGB(253,234,141)
                obj.LeftArmColor3 = Color3.fromRGB(253,234,141)
                obj.RightArmColor3 = Color3.fromRGB(253,234,141)
                obj.TorsoColor3 = Color3.fromRGB(40,127,71)
                obj.LeftLegColor3 = Color3.fromRGB(40,127,71)
                obj.RightLegColor3 = Color3.fromRGB(40,127,71)
            end
        end
    end)
end
local function applyDevAvatars()
    if not charConfig.profile.namespoof.devSpoof then return end
    for _, plr in ipairs(players:GetPlayers()) do
        if plr.Character then makeBasic(plr.Character) end
    end
end
library.applyDevAvatars = applyDevAvatars

local nameAllowed = {
    DisplayName=true, Username=true, Handle=true,
    TitleText=true, SubtitleText=true, HeaderText=true,
    PlayerName=true, NameLabel=true, UsernameLabel=true, DisplayNameLabel=true,
}
local function registerNameLabel(d)
    if not (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) then return end
    if not nameAllowed[d.Name] then return end
    if nameHooks[d] then return end
    applyNameToLabel(d)
    nameHooks[d] = d:GetPropertyChangedSignal("Text"):Connect(function()
        if nsActive() then applyNameToLabel(d) end
    end)
    d.Destroying:Connect(function()
        if nameHooks[d] then nameHooks[d]:Disconnect(); nameHooks[d] = nil end
    end)
end
local nameScanStarted = false
function library.startNameScan()
    if nameScanStarted then return end
    nameScanStarted = true
    task.spawn(function()
        local n = 0
        for _, o in ipairs(game:GetDescendants()) do
            pcall(registerNameLabel, o)
            n += 1
            if n % 300 == 0 then task.wait() end
        end
    end)
    game.DescendantAdded:Connect(registerNameLabel)
end

cp.CharacterAdded:Connect(function(c) u(c); applyskin(c) end)

for _, plr in ipairs(players:GetPlayers()) do
    if plr ~= cp then
        plr.CharacterAdded:Connect(function(c)
            if charConfig.profile.namespoof.devSpoof then task.wait(0.4); makeBasic(c) end
        end)
    end
end
players.PlayerAdded:Connect(function(plr)
    plr.CharacterAdded:Connect(function(c)
        if charConfig.profile.namespoof.devSpoof then task.wait(0.4); makeBasic(c) end
    end)
end)

task.spawn(function()
    while true do
        if charConfig.profile.level.enabled then
            cp:SetAttribute("Level", charConfig.profile.level.value)
        end
        if charConfig.profile.winstreak.enabled then
            pcall(function()
                local ls = cp:FindFirstChild("CustomLeaderstats")
                if ls then
                    local ws = ls:FindFirstChild("Win Streak")
                    if ws then ws.Value = charConfig.profile.winstreak.value end
                end
            end)
        end
        task.wait(0.4)
    end
end)

_G.cframeactive = false; _G.keyheldcframe = false; _G.cframevalue = 30
_G.cframeflyactive = false; _G.keyheldcframefly = false; _G.cframeflyvalue = 50
local flybp, flybg
local function cleanupfly()
    if flybp then flybp:Destroy() flybp = nil end
    if flybg then flybg:Destroy() flybg = nil end
end
RunService.Heartbeat:Connect(function()
    if not (_G.cframeactive and _G.keyheldcframe) then return end
    local char = cp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end
    local moveDir = hum.MoveDirection
    if moveDir.Magnitude > 0 then
        local targetVel = moveDir * _G.cframevalue
        hrp.AssemblyLinearVelocity = Vector3.new(targetVel.X, hrp.AssemblyLinearVelocity.Y, targetVel.Z)
    end
end)
RunService.Heartbeat:Connect(function(dt)
    if not (_G.cframeflyactive and _G.keyheldcframefly) then return end
    local char = cp.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end
    if not flybp then
        flybp = Instance.new("BodyPosition")
        flybp.MaxForce = Vector3.new(1e5,1e5,1e5); flybp.D = 1000; flybp.P = 10000
        flybp.Position = hrp.Position; flybp.Parent = hrp
    end
    if not flybg then
        flybg = Instance.new("BodyGyro")
        flybg.MaxTorque = Vector3.new(1e5,1e5,1e5); flybg.D = 400; flybg.P = 10000
        flybg.CFrame = hrp.CFrame; flybg.Parent = hrp
    end
    local cam = Workspace.CurrentCamera
    local look = cam.CFrame.LookVector
    local right = cam.CFrame.RightVector
    local move = Vector3.new()
    if inputService:IsKeyDown(Enum.KeyCode.W) then move += look end
    if inputService:IsKeyDown(Enum.KeyCode.S) then move -= look end
    if inputService:IsKeyDown(Enum.KeyCode.A) then move -= right end
    if inputService:IsKeyDown(Enum.KeyCode.D) then move += right end
    if inputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0,1,0) end
    if inputService:IsKeyDown(Enum.KeyCode.LeftShift) then move -= Vector3.new(0,1,0) end
    if move.Magnitude > 0 then move = move.Unit end
    flybp.Position = hrp.Position + (move * _G.cframeflyvalue * dt * 10)
    flybg.CFrame = CFrame.new(hrp.Position, hrp.Position + look * Vector3.new(1,0,1))
end)

-- spoofers live in the "skins & spoofers" tab; movement stays in misc
local spooferBox     = skinsTab:createTabbox('left', 'spoofers')
local profileGroup   = spooferBox:addTab('profile')
local nameGroup      = spooferBox:addTab('name spoof')
local movementBox    = miscTab:createTabbox('left', 'character')
local movementGroup  = movementBox:addTab('movement')

profileGroup:addToggle({text = "level spoof", flag = "LevelSpoof",
    callback = function(v) charConfig.profile.level.enabled = v end})
profileGroup:markStart()
profileGroup:addTextbox({text = "level value", flag = "LevelValue", value = "9999",
    callback = function() charConfig.profile.level.value = tonumber(library.flags["LevelValue"]) or 9999 end})
profileGroup:dependsOn("LevelSpoof")
profileGroup:addToggle({text = "win streak spoof", flag = "WinStreakSpoof",
    callback = function(v) charConfig.profile.winstreak.enabled = v end})
profileGroup:markStart()
profileGroup:addTextbox({text = "win streak value", flag = "WinStreakValue", value = "9999",
    callback = function() charConfig.profile.winstreak.value = tonumber(library.flags["WinStreakValue"]) or 9999 end})
profileGroup:dependsOn("WinStreakSpoof")

local NS = charConfig.profile.namespoof
nameGroup:addToggle({text = "spoof display name", flag = "SpoofDisplayName",
    callback = function(v) NS.displayEnabled = v; if cp.Character then u(cp.Character) end s() end})
nameGroup:addTextbox({text = "display name", flag = "SpoofDisplayValue", value = "riots",
    callback = function() NS.displayValue = clearbadges(library.flags["SpoofDisplayValue"] or "riots"); s() end})
nameGroup:addToggle({text = "spoof username", flag = "SpoofUsername",
    callback = function(v) NS.usernameEnabled = v; s() end})
nameGroup:addTextbox({text = "username", flag = "SpoofUsernameValue", value = "riots",
    callback = function() NS.usernameValue = clearbadges(library.flags["SpoofUsernameValue"] or "riots"); s() end})
nameGroup:addToggle({text = "avatar change", flag = "SkinChangerEnabled",
    callback = function(v) charConfig.profile.skinchanger.enabled = v; if v and cp.Character then applyskin(cp.Character) end end})
nameGroup:addTextbox({text = "userid avatar", flag = "SkinChangerUserId", value = "1",
    callback = function() charConfig.profile.skinchanger.userid = library.flags["SkinChangerUserId"] or "1"; if charConfig.profile.skinchanger.enabled and cp.Character then applyskin(cp.Character) end end})
nameGroup:addToggle({text = "verified", flag = "NameSpoofVerified",
    callback = function(v) NS.verified = v; if cp.Character then u(cp.Character) end s() end})
nameGroup:addToggle({text = "premium", flag = "NameSpoofPremium",
    callback = function(v) NS.premium = v; if cp.Character then u(cp.Character) end s() end})
nameGroup:addToggle({text = "spoof others", flag = "SpoofOthers",
    callback = function(v) NS.spoofOthers = v; s() end})
nameGroup:addToggle({text = "dev spoof", flag = "DevSpoof",
    callback = function(v) NS.devSpoof = v; if v then applyDevAvatars() end; if cp.Character then u(cp.Character) end; s() end})
nameGroup:addButton({text = "reapply spoof names", callback = function()
    if cp.Character then u(cp.Character) end
    s()
    if NS.devSpoof then applyDevAvatars() end
    library:notify("Reapplied name spoof")
end})



movementGroup:addToggle({text = "velocity walkspeed", flag = "cframespf_enabled",
    callback = function(v) _G.cframeactive = v end})
    :addKeybind({text = "walkspeed key", flag = "cframespf_key",
        callback = function() _G.keyheldcframe = not _G.keyheldcframe end})
movementGroup:addSlider({text = "walkspeed", flag = "spdd_value", value = 30, min = 16, max = 750,
    callback = function(v) _G.cframevalue = v end})
movementGroup:addToggle({text = "velocity fly", flag = "cframefly_enabled",
    callback = function(v) _G.cframeflyactive = v; if not v then cleanupfly(); local c=cp.Character; local hrp=c and c:FindFirstChild("HumanoidRootPart"); if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end end end})
    :addKeybind({text = "fly key", flag = "cframefly_key",
        callback = function() _G.keyheldcframefly = not _G.keyheldcframefly; if not _G.keyheldcframefly then cleanupfly() end end})
movementGroup:addSlider({text = "fly speed", flag = "cframefly_speed", value = 50, min = 16, max = 750,
    callback = function(v) _G.cframeflyvalue = v end})

-- ── extra movement features ported from take.lua ─────────────────────────────
;(function() -- own scope to save main-chunk locals
    _G.Features = _G.Features or {}
    _G.Features.Movement = _G.Features.Movement or {
        infDoubleJump = false,
        djHeight = false, djHeightValue = 50,
        autoSlide = false,
    }
    local MV = _G.Features.Movement
    local mech
    task.spawn(function()
        while true do
            local ok, res = pcall(function()
                return require(localPlayer.PlayerScripts.Controllers.MechanicsController)
            end)
            if ok and res then mech = res; break end
            task.wait(1)
        end
        -- infinite double jump: keep resetting the jump count while enabled
        RunService.Heartbeat:Connect(function()
            if MV.infDoubleJump and mech then
                pcall(function()
                    if mech.ResetJumps then mech:ResetJumps()
                    elseif mech._doubleJumped ~= nil then mech._doubleJumped = false
                    elseif mech.CanDoubleJump ~= nil then mech.CanDoubleJump = true end
                end)
            end
            if MV.autoSlide and mech then
                pcall(function()
                    if mech.StartSliding and not mech.IsSliding then mech:StartSliding() end
                end)
            end
        end)
    end)

    movementGroup:addToggle({text = "infinite double jump", flag = "inf_double_jump",
        callback = function(v) MV.infDoubleJump = v end})
    movementGroup:addToggle({text = "auto slide", flag = "auto_slide",
        callback = function(v) MV.autoSlide = v end})
end)() -- end movement features block

;(function() -- ESP block: isolated function scope to avoid 200-local limit
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local guiinset = GuiService:GetGuiInset()
local worldToEspScreen = worldToScreen
local espScreenAnchor = screenAnchor

local function getEspPlayerWeapon(player)
    if not player then return "None" end
    local viewModels = Workspace:FindFirstChild("ViewModels")
    if not viewModels then return "None" end
    local playerName = player.Name
    local function weaponFromModelName(modelName)
        local parts = {}
        for part in modelName:gmatch("[^-]+") do
            table.insert(parts, part:match("^%s*(.-)%s*$"))
        end
        if #parts >= 2 and parts[1] == playerName then return parts[2] end
        return nil
    end
    for _, child in ipairs(viewModels:GetChildren()) do
        local w = weaponFromModelName(child.Name)
        if w then return w end
    end
    local fp = viewModels:FindFirstChild("FirstPerson")
    if fp then
        for _, child in ipairs(fp:GetChildren()) do
            local w = weaponFromModelName(child.Name)
            if w then return w end
        end
    end
    return "None"
end
library.getPlayerWeapon = getEspPlayerWeapon

_G.Config = _G.Config or {
    Box = {
        MasterEnabled = false, Enable = false,
        OutlineColor = Color3.fromRGB(255,255,255), OutlineColor2 = Color3.fromRGB(255,255,255),
        FillColor = Color3.fromRGB(255,255,255),
        Filled = { Enable = false, Transparency = 0.5 },
        Healthbar = { Enable = false, Thickness = 4 },
        HealthLerpColors = { Color1 = Color3.fromRGB(0,255,0), Color2 = Color3.fromRGB(255,255,0), Color3 = Color3.fromRGB(255,0,0) },
    },
    Filled = { Enable = false, Transparency = 0.7, ColorStart = Color3.fromRGB(255,255,255), ColorEnd = Color3.fromRGB(255,255,255), Rotation = 0, Animated = false, Speed = 1 },
    Glow = { Enable = false, Transparency = 0.5, ColorStart = Color3.fromRGB(255,255,255), ColorEnd = Color3.fromRGB(255,255,255), Rotation = 0 },
    TextESP = { Names = false, Distance = false, Tools = false, NameSize = 13, DistanceSize = 11, ToolsSize = 11,
        Gradient = false, Flow = false, FlowSpeed = 1,
        NameColor = Color3.fromRGB(255,255,255), NameColor2 = Color3.fromRGB(255,255,255),
        DistanceColor = Color3.fromRGB(255,255,255), DistanceColor2 = Color3.fromRGB(255,255,255),
        ToolColor = Color3.fromRGB(255,255,255), ToolColor2 = Color3.fromRGB(255,255,255) },
    Skeleton = { Enable = false, Color = Color3.fromRGB(255,255,255), Color2 = Color3.fromRGB(255,255,255), Thickness = 1 },
    Tracers = { Enable = false, Color = Color3.fromRGB(255,255,255), Color2 = Color3.fromRGB(255,255,255), Thickness = 1, FromBottom = true },
    Chams = { Enable = false, Color = Color3.fromRGB(255,42,42), Color2 = Color3.fromRGB(0,0,0), Transparency = 0.35, OutlineTransparency = 0, ThroughWalls = true },
    GlowChams = { Enable = false, Color = Color3.fromRGB(255,42,42), Transparency = 0.7, ThroughWalls = true },
    ESP = { HighRefresh = true, HealthLerpSpeed = 32, TargetHz = 60 },
}
_G.ESPObjects = _G.ESPObjects or {}
local ConfigBox = _G.Config.Box
local ESPObjects = _G.ESPObjects

local espgui = Instance.new("ScreenGui")
espgui.Name = "riotsESP"
espgui.DisplayOrder = 9e9
espgui.ResetOnSpawn = false
espgui.IgnoreGuiInset = true
espgui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() espgui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)

local r15bones = {
    {"UpperTorso","Head"},{"UpperTorso","LowerTorso"},{"UpperTorso","LeftUpperArm"},
    {"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},{"UpperTorso","RightUpperArm"},
    {"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},{"LowerTorso","LeftUpperLeg"},
    {"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},{"LowerTorso","RightUpperLeg"},
    {"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"}
}
local r6bones = { {"Torso","Head"},{"Torso","Left Arm"},{"Torso","Right Arm"},{"Torso","Left Leg"},{"Torso","Right Leg"} }

local fonts = {}
fonts.main = Font.fromEnum(Enum.Font.Code)

local tickval = 0
local function lerpcolor(a, b, t)
    return Color3.new(a.R+(b.R-a.R)*t, a.G+(b.G-a.G)*t, a.B+(b.B-a.B)*t)
end
local function ensureTextGradient(label, c1, c2)
    if not label then return end
    local grad = label:FindFirstChild("EspTextGradient")
    -- gradient toggle: when off, just use the solid first color (no UIGradient)
    if not (_G.Config.TextESP and _G.Config.TextESP.Gradient) then
        if grad then grad.Enabled = false end
        label.TextColor3 = c1
        return
    end
    if not grad then
        grad = Instance.new("UIGradient"); grad.Name = "EspTextGradient"; grad.Rotation = 0; grad.Parent = label
    end
    grad.Enabled = true
    -- flow animation: shift the gradient offset over time when enabled
    if _G.Config.TextESP.Flow then
        grad.Offset = Vector2.new((tickval * (_G.Config.TextESP.FlowSpeed or 1)) % 2 - 1, 0)
        grad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, c1), ColorSequenceKeypoint.new(0.5, c2), ColorSequenceKeypoint.new(1, c1) })
    else
        grad.Offset = Vector2.new(0, 0)
        grad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, c1), ColorSequenceKeypoint.new(1, c2) })
    end
    label.TextColor3 = Color3.fromRGB(255,255,255)
end
local function hpcolor(pct)
    local hc = ConfigBox.HealthLerpColors
    if pct > 0.5 then return lerpcolor(hc.Color2, hc.Color1, (pct-0.5)*2)
    else return lerpcolor(hc.Color3, hc.Color2, pct*2) end
end
local function checkteammate(player)
    if not player or player == localPlayer then return true end
    local myTeam = localPlayer:GetAttribute("TeamID")
    local theirTeam = player:GetAttribute("TeamID")
    if myTeam ~= nil and theirTeam ~= nil then return myTeam == theirTeam end
    return localPlayer.Team and player.Team and localPlayer.Team == player.Team
end
local function findBonePart(char, name)
    local part = char:FindFirstChild(name)
    if part and part:IsA("BasePart") then return part end
    local aliases = {
        ["Left Arm"]={"LeftArm","LeftUpperArm"}, ["Right Arm"]={"RightArm","RightUpperArm"},
        ["Left Leg"]={"LeftLeg","LeftUpperLeg"}, ["Right Leg"]={"RightLeg","RightUpperLeg"},
        ["Torso"]={"UpperTorso","LowerTorso"},
    }
    for _, alt in ipairs(aliases[name] or {}) do
        part = char:FindFirstChild(alt)
        if part and part:IsA("BasePart") then return part end
    end
    return nil
end
local function espknock(player)
    local char = player.Character
    if not char then return false end
    local be = char:FindFirstChild("BodyEffects")
    if be then
        local ko = be:FindFirstChild("K.O") or be:FindFirstChild("KO")
        return ko and ko.Value
    end
    return false
end
local function dist2(player)
    local char = player.Character
    local myChar = localPlayer.Character
    if char and myChar then
        local root = char:FindFirstChild("HumanoidRootPart")
        local myRoot = myChar:FindFirstChild("HumanoidRootPart")
        if root and myRoot then return (root.Position - myRoot.Position).Magnitude end
    end
    return math.huge
end
local function playerweap(player) return getEspPlayerWeapon(player) end
local function makelabel(parent)
    local label = Instance.new("TextLabel")
    label.Parent = parent
    label.Size = UDim2.new(0,200,0,20)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(255,255,255)
    label.TextStrokeTransparency = 0
    label.TextScaled = false
    label.TextSize = 6
    label.TextStrokeColor3 = Color3.fromRGB(0,0,0)
    label.FontFace = fonts.main
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Top
    return label
end
local function CreateCham(char)
    local cfg = _G.Config.Chams
    local h = Instance.new("Highlight")
    h.Name = "ESPHighlight"; h.Adornee = char
    h.FillColor = cfg.Color
    h.OutlineColor = cfg.Color2 or cfg.Color
    h.FillTransparency = math.clamp(cfg.Transparency or 0.35, 0, 1)
    -- keep the outline crisp and independent of the fill
    h.OutlineTransparency = math.clamp(cfg.OutlineTransparency or 0, 0, 1)
    h.DepthMode = (cfg.ThroughWalls == false) and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
    h.Parent = char
    return h
end
local function CreateBox(player)
    if ESPObjects[player] then return end
    local box = {}
    box.box = {}
    box.box.square = Drawing.new("Square")
    box.box.inline = Drawing.new("Square")
    box.box.outline = Drawing.new("Square")
    box.filled = Instance.new("Frame")
    box.filled.BackgroundColor3 = Color3.new(1,1,1)
    box.filled.BackgroundTransparency = _G.Config.Filled.Transparency
    box.filled.BorderSizePixel = 0; box.filled.Visible = false; box.filled.ZIndex = 2; box.filled.Parent = espgui
    box.filled_gradient = Instance.new("UIGradient")
    box.filled_gradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0,_G.Config.Filled.ColorStart), ColorSequenceKeypoint.new(1,_G.Config.Filled.ColorEnd) })
    box.filled_gradient.Rotation = 0; box.filled_gradient.Parent = box.filled
    box.glow = Instance.new("ImageLabel")
    box.glow.Image = "rbxassetid://110204605000367"
    box.glow.ScaleType = Enum.ScaleType.Slice
    box.glow.SliceCenter = Rect.new(Vector2.new(21,21), Vector2.new(79,79))
    box.glow.AutomaticSize = Enum.AutomaticSize.XY
    box.glow.ImageTransparency = _G.Config.Glow.Transparency
    box.glow.ResampleMode = Enum.ResamplerMode.Pixelated
    box.glow.BackgroundTransparency = 1; box.glow.BorderSizePixel = 0
    box.glow.BackgroundColor3 = Color3.fromRGB(255,255,255); box.glow.ZIndex = 1
    box.glow.Visible = false; box.glow.Parent = espgui
    box.glow_gradient = Instance.new("UIGradient")
    box.glow_gradient.Rotation = _G.Config.Glow.Rotation
    box.glow_gradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0,_G.Config.Glow.ColorStart), ColorSequenceKeypoint.new(1,_G.Config.Glow.ColorEnd) })
    box.glow_gradient.Parent = box.glow
    local gp = Instance.new("UIPadding")
    gp.PaddingTop = UDim.new(0,21); gp.PaddingBottom = UDim.new(0,20); gp.PaddingLeft = UDim.new(0,21); gp.PaddingRight = UDim.new(0,20); gp.Parent = box.glow
    box.bars = { hp_bars = {}, hp_outline = Drawing.new("Square"), last_hp = 1 }
    for i=1,12 do box.bars.hp_bars[i] = Drawing.new("Line") end
    box.skeleton = { lines = {}, outlines = {} }
    for i=1,15 do
        local o = Drawing.new("Line"); o.Color = Color3.new(0,0,0); o.Thickness = 3; o.Visible = false; box.skeleton.outlines[i] = o
        local l = Drawing.new("Line"); l.Color = Color3.new(1,1,1); l.Thickness = 1; l.Visible = false; box.skeleton.lines[i] = l
    end
    local studsgui = Instance.new("ScreenGui", espgui.Parent)
    local namegui = Instance.new("ScreenGui", espgui.Parent)
    local toolgui = Instance.new("ScreenGui", espgui.Parent)
    box.text = { studs = makelabel(studsgui), tool = makelabel(toolgui), name = makelabel(namegui) }
    box.Tracer = Drawing.new("Line"); box.Tracer.Visible = false
    box.Tracer.Color = _G.Config.Tracers.Color; box.Tracer.Thickness = _G.Config.Tracers.Thickness
    ESPObjects[player] = box
end
local function RemoveBox(player)
    if ESPObjects[player] then
        local box = ESPObjects[player]
        if box.box then box.box.square:Remove(); box.box.outline:Remove(); box.box.inline:Remove() end
        if box.filled then box.filled:Destroy() end
        if box.glow then box.glow:Destroy() end
        if box.text then
            if box.text.studs then box.text.studs.Parent:Destroy() end
            if box.text.tool then box.text.tool.Parent:Destroy() end
            if box.text.name then box.text.name.Parent:Destroy() end
        end
        if box.bars then box.bars.hp_outline:Remove(); for _,l in pairs(box.bars.hp_bars) do l:Remove() end end
        if box.skeleton then for _,l in pairs(box.skeleton.lines) do l:Remove() end for _,o in pairs(box.skeleton.outlines) do o:Remove() end end
        if box.Tracer then box.Tracer:Remove() end
        if box.Cham then box.Cham:Destroy(); box.Cham = nil end
        if box.ChamGlow then box.ChamGlow:Destroy(); box.ChamGlow = nil end
        ESPObjects[player] = nil
    end
end
local function hideesp(player)
    if not ESPObjects[player] then return end
    local box = ESPObjects[player]
    if box.box then box.box.square.Visible=false; box.box.outline.Visible=false; box.box.inline.Visible=false end
    if box.filled then box.filled.Visible=false end
    if box.glow then box.glow.Visible=false end
    if box.text then box.text.studs.Visible=false; box.text.tool.Visible=false; box.text.name.Visible=false end
    if box.bars then box.bars.hp_outline.Visible=false; for _,l in pairs(box.bars.hp_bars) do l.Visible=false end end
    if box.skeleton then for _,l in pairs(box.skeleton.lines) do l.Visible=false end for _,o in pairs(box.skeleton.outlines) do o.Visible=false end end
    if box.Tracer then box.Tracer.Visible=false end
    if box.Cham then box.Cham.Enabled=false end
    if box.ChamGlow then box.ChamGlow.Enabled=false end
end
local function updatecham(player, box, char)
    local cfg = _G.Config.Chams
    if not cfg.Enable then if box.Cham then box.Cham.Enabled=false end
        if box.ChamGlow then box.ChamGlow.Enabled=false end return end
    if not box.Cham or not box.Cham.Parent then box.Cham = CreateCham(char) end
    if box.Cham then
        box.Cham.Enabled=true
        box.Cham.FillColor=cfg.Color
        box.Cham.OutlineColor=cfg.Color2 or cfg.Color
        box.Cham.FillTransparency=math.clamp(cfg.Transparency or 0.35, 0, 1)
        box.Cham.OutlineTransparency=math.clamp(cfg.OutlineTransparency or 0, 0, 1)
        box.Cham.DepthMode=(cfg.ThroughWalls == false) and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
    end
    -- Glow cham: a second Highlight with no outline and a softer fill layered underneath
    local gcfg = _G.Config.GlowChams
    if gcfg and gcfg.Enable then
        if not box.ChamGlow or not box.ChamGlow.Parent then
            local gh = Instance.new("Highlight")
            gh.Name = "ESPGlowHighlight"; gh.Adornee = char
            gh.OutlineTransparency = 1   -- invisible outline — fill only
            gh.DepthMode = (gcfg.ThroughWalls == false) and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
            gh.Parent = char
            box.ChamGlow = gh
        end
        box.ChamGlow.Enabled = true
        box.ChamGlow.FillColor = gcfg.Color
        box.ChamGlow.FillTransparency = math.clamp(gcfg.Transparency or 0.7, 0, 1)
        box.ChamGlow.DepthMode = (gcfg.ThroughWalls == false) and Enum.HighlightDepthMode.Occluded or Enum.HighlightDepthMode.AlwaysOnTop
    else
        if box.ChamGlow then box.ChamGlow.Enabled=false end
    end
end
local function drawskeleton(player, box, char, hum, size, position)
    if not _G.Config.Skeleton.Enable then
        for _,l in pairs(box.skeleton.lines) do l.Visible=false end
        for _,o in pairs(box.skeleton.outlines) do o.Visible=false end
        return
    end
    local bones = (hum.RigType == Enum.HumanoidRigType.R15) and r15bones or r6bones
    local skelColor = _G.Config.Skeleton.Color
    local skelColor2 = _G.Config.Skeleton.Color2 or skelColor
    local skelThickness = _G.Config.Skeleton.Thickness or 1
    for i=1,15 do
        local boneset = bones[i]
        local line = box.skeleton.lines[i]
        local outline = box.skeleton.outlines[i]
        if boneset then
            local pa = findBonePart(char, boneset[1])
            local pb = findBonePart(char, boneset[2])
            if pa and pb then
                local va, vaOk = worldToEspScreen(pa.Position)
                local vb, vbOk = worldToEspScreen(pb.Position)
                if vaOk and vbOk then
                    local pos2 = Vector2.new(va.X, va.Y)
                    local endpos = Vector2.new(vb.X, vb.Y)
                    outline.Visible=true; outline.From=pos2; outline.To=endpos; outline.Thickness=skelThickness+2; outline.Color=Color3.new(0,0,0)
                    line.Visible=true; line.From=pos2; line.To=endpos; line.Color=skelColor; line.Thickness=skelThickness
                else line.Visible=false; outline.Visible=false end
            else line.Visible=false; outline.Visible=false end
        else line.Visible=false; outline.Visible=false end
    end
end
local function drawhealthbar(player, box, hum, size, position, dt)
    if not (ConfigBox.Healthbar and ConfigBox.Healthbar.Enable) then
        box.bars.hp_outline.Visible=false; for _,l in pairs(box.bars.hp_bars) do l.Visible=false end return
    end
    local target = math.clamp(hum.Health/hum.MaxHealth,0,1)
    local last = box.bars.last_hp or target
    local espCfg = _G.Config.ESP or {}
    local lerpSpeed = espCfg.HealthLerpSpeed or 32
    dt = dt or (1/(espCfg.TargetHz or 240))
    box.bars.last_hp = last + (target-last)*math.min(1, dt*lerpSpeed)
    local lerped = box.bars.last_hp
    local h = math.ceil(size.Y*lerped)
    local hpx = position.X-5
    local hpystart = position.Y+(size.Y-h)
    box.bars.hp_outline.Visible=true
    box.bars.hp_outline.Position=Vector2.new(hpx-1, position.Y-1)
    box.bars.hp_outline.Size=Vector2.new(3, size.Y+2)
    box.bars.hp_outline.Color=Color3.new(0,0,0); box.bars.hp_outline.Filled=false
    local segments = math.max(math.min(math.floor(h/2),12),4)
    for i=1,12 do
        local line = box.bars.hp_bars[i]
        if i<=segments then
            local sh = h/segments
            local yoffset = (i-1)*sh
            local pospct = 1-((yoffset+(size.Y-h))/size.Y)
            line.Visible=true
            line.From=Vector2.new(hpx, hpystart+yoffset)
            line.To=Vector2.new(hpx+1, hpystart+yoffset)
            line.Color=hpcolor(pospct); line.Thickness=math.max(sh,1)
        else line.Visible=false end
    end
end
local function drawbox(player, box, size, position)
    if not (ConfigBox.MasterEnabled and ConfigBox.Enable) then
        box.box.square.Visible=false; box.box.outline.Visible=false; box.box.inline.Visible=false return
    end
    local w = math.max(math.floor(size.X),4)
    local h = math.max(math.floor(size.Y),8)
    size = Vector2.new(w,h)
    position = Vector2.new(math.floor(position.X), math.floor(position.Y))
    box.box.square.Visible=true; box.box.square.Position=position; box.box.square.Size=size
    local boxColor2 = ConfigBox.OutlineColor2 or ConfigBox.OutlineColor
    box.box.square.Color=lerpcolor(ConfigBox.OutlineColor, boxColor2, 0.5)
    box.box.square.Thickness=1; box.box.square.Filled=false
    box.box.outline.Visible=true; box.box.outline.Position=position-Vector2.new(1,1); box.box.outline.Size=size+Vector2.new(2,2)
    box.box.outline.Color=Color3.new(0,0,0); box.box.outline.Thickness=1; box.box.outline.Filled=false
    box.box.inline.Visible=true; box.box.inline.Position=position+Vector2.new(1,1); box.box.inline.Size=Vector2.new(math.max(w-2,2),math.max(h-2,4))
    box.box.inline.Color=Color3.new(0,0,0); box.box.inline.Thickness=1; box.box.inline.Filled=false
end
local function drawfill(player, box, size, position)
    local cfg = _G.Config.Filled
    if not cfg.Enable then box.filled.Visible=false return end
    box.filled.Visible=true; box.filled.BackgroundTransparency=cfg.Transparency
    box.filled.Position=UDim2.fromOffset(position.X, position.Y)
    box.filled.Size=UDim2.fromOffset(size.X, size.Y)
    box.filled_gradient.Color=ColorSequence.new({ ColorSequenceKeypoint.new(0,cfg.ColorStart), ColorSequenceKeypoint.new(1,cfg.ColorEnd) })
    if cfg.Animated then box.filled_gradient.Rotation=(math.sin(tickval*cfg.Speed)*90)+cfg.Rotation
    else box.filled_gradient.Rotation=cfg.Rotation end
end
local function drawglow(player, box, size, position)
    local cfg = _G.Config.Glow
    if not cfg.Enable or not (ConfigBox.MasterEnabled and ConfigBox.Enable) then box.glow.Visible=false return end
    box.glow.Visible=true; box.glow.ImageTransparency=cfg.Transparency; box.glow.ImageColor3=cfg.ColorStart
    box.glow.Position=UDim2.fromOffset(position.X-21, position.Y-21)
    box.glow.Size=UDim2.fromOffset(size.X+42, size.Y+42)
    box.glow_gradient.Color=ColorSequence.new({ ColorSequenceKeypoint.new(0,cfg.ColorStart), ColorSequenceKeypoint.new(1,cfg.ColorEnd) })
    box.glow_gradient.Rotation=0
end
local function drawtext(player, box, size, position, distance)
    local basey = position.Y - guiinset.Y
    if _G.Config.TextESP and _G.Config.TextESP.Names then
        box.text.name.Visible=true
        box.text.name.Position=UDim2.new(0, position.X+(size.X/2)-100, 0, basey-15)
        box.text.name.Text=player.Name
        box.text.name.TextSize=_G.Config.TextESP.NameSize or 13
        ensureTextGradient(box.text.name, _G.Config.TextESP.NameColor, _G.Config.TextESP.NameColor2 or _G.Config.TextESP.NameColor)
        box.text.name.TextXAlignment=Enum.TextXAlignment.Center
    else box.text.name.Visible=false end
    if _G.Config.TextESP and _G.Config.TextESP.Tools then
        box.text.tool.Visible=true
        box.text.tool.Position=UDim2.new(0, position.X+size.X+5, 0, basey)
        box.text.tool.Text=playerweap(player)
        box.text.tool.TextSize=_G.Config.TextESP.ToolsSize or 11
        ensureTextGradient(box.text.tool, _G.Config.TextESP.ToolColor, _G.Config.TextESP.ToolColor2 or _G.Config.TextESP.ToolColor)
        box.text.tool.TextXAlignment=Enum.TextXAlignment.Left
    else box.text.tool.Visible=false end
    if _G.Config.TextESP and _G.Config.TextESP.Distance then
        box.text.studs.Visible=true
        box.text.studs.Position=UDim2.new(0, position.X+(size.X/2)-100, 0, basey+size.Y+2)
        box.text.studs.Text=string.format("%.0f studs", distance)
        box.text.studs.TextSize=_G.Config.TextESP.DistanceSize or 11
        ensureTextGradient(box.text.studs, _G.Config.TextESP.DistanceColor, _G.Config.TextESP.DistanceColor2 or _G.Config.TextESP.DistanceColor)
        box.text.studs.TextXAlignment=Enum.TextXAlignment.Center
    else box.text.studs.Visible=false end
end
local function drawtracers(player, box, root)
    if not (_G.Config.Tracers and _G.Config.Tracers.Enable) then box.Tracer.Visible=false return end
    local pos, vis = worldToEspScreen(root.Position)
    if vis then
        box.Tracer.Visible=true
        box.Tracer.To=Vector2.new(pos.X, pos.Y)
        box.Tracer.From=(_G.Config.Tracers.FromBottom==nil or _G.Config.Tracers.FromBottom) and espScreenAnchor(0.5,1) or espScreenAnchor(0.5,0.5)
        box.Tracer.Color=lerpcolor(_G.Config.Tracers.Color, _G.Config.Tracers.Color2 or _G.Config.Tracers.Color, 0.5)
        box.Tracer.Thickness=_G.Config.Tracers.Thickness or 1
    else box.Tracer.Visible=false end
end

local function getHitboxBounds(char)
    local cam = Workspace.CurrentCamera
    if not cam or not char then return nil,nil end
    local ok, cf, sizeV = pcall(function()
        return char:GetBoundingBox()
    end)
    if not ok or not cf or not sizeV then return nil,nil end
    local hx, hy, hz = sizeV.X/2, sizeV.Y/2, sizeV.Z/2
    local corners = {
        cf*Vector3.new(-hx,-hy,-hz), cf*Vector3.new(hx,-hy,-hz),
        cf*Vector3.new(-hx,hy,-hz),  cf*Vector3.new(hx,hy,-hz),
        cf*Vector3.new(-hx,-hy,hz),  cf*Vector3.new(hx,-hy,hz),
        cf*Vector3.new(-hx,hy,hz),   cf*Vector3.new(hx,hy,hz),
    }
    local minX,minY,maxX,maxY = math.huge,math.huge,-math.huge,-math.huge
    local found = false
    for _, corner in ipairs(corners) do
        local sp, onScreen = worldToEspScreen(corner, cam)
        if onScreen then
            found=true
            minX=math.min(minX,sp.X); minY=math.min(minY,sp.Y)
            maxX=math.max(maxX,sp.X); maxY=math.max(maxY,sp.Y)
        end
    end
    if not found then return nil,nil end
    return Vector2.new(math.max(maxX-minX,4), math.max(maxY-minY,8)), Vector2.new(minX,minY)
end
local function updateesp(player, dt)
    if not player then return end
    if not ConfigBox.MasterEnabled then if ESPObjects[player] then hideesp(player) end; return end
    if player == localPlayer or checkteammate(player) then if ESPObjects[player] then hideesp(player) end; return end
    local char = player.Character
    if not char or espknock(player) then if ESPObjects[player] then hideesp(player) end; return end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildWhichIsA("Humanoid")
    if not root or not hum then if ESPObjects[player] then hideesp(player) end; return end
    -- lazy allocation: only build the (expensive) drawing set once the player is a
    -- valid, alive, non-teammate target AND esp is on. Avoids the load-time freeze
    -- of eagerly allocating ~46 drawings per player in a full server.
    if not ESPObjects[player] then CreateBox(player) end
    if not ESPObjects[player] then return end
    local hrp2d, hrpOk = worldToEspScreen(root.Position)
    if not hrpOk then hideesp(player); return end
    local distance = dist2(player)
    local hitboxSize, hitboxPosition = getHitboxBounds(char)
    local size, position
    if hitboxSize and hitboxPosition then
        size = Vector2.new(math.max(math.floor(hitboxSize.X),4), math.max(math.floor(hitboxSize.Y),8))
        position = Vector2.new(math.floor(hitboxPosition.X), math.floor(hitboxPosition.Y))
    else
        local head = char:FindFirstChild("Head")
        local topWorld = (head and head.Position + Vector3.new(0,0.5,0)) or (root.Position + Vector3.new(0,3,0))
        local bottomWorld = root.Position - Vector3.new(0,3,0)
        local top2d, topOk = worldToEspScreen(topWorld)
        local bottom2d, bottomOk = worldToEspScreen(bottomWorld)
        if not topOk or not bottomOk then hideesp(player); return end
        local boxHeight = math.abs(bottom2d.Y - top2d.Y)
        local boxWidth = math.max(boxHeight*0.55, 8)
        size = Vector2.new(math.max(math.floor(boxWidth),4), math.max(math.floor(math.max(boxHeight,10)),8))
        position = Vector2.new(math.floor(hrp2d.X - size.X/2), math.floor(math.min(top2d.Y, bottom2d.Y)))
    end
    local box = ESPObjects[player]
    local cfg = _G.Config
    drawfill(player, box, size, position)
    drawbox(player, box, size, position)
    drawglow(player, box, size, position)
    if cfg.Skeleton and cfg.Skeleton.Enable then drawskeleton(player, box, char, hum, size, position)
    else for _,l in pairs(box.skeleton.lines) do l.Visible=false end for _,o in pairs(box.skeleton.outlines) do o.Visible=false end end
    drawhealthbar(player, box, hum, size, position, dt)
    drawtext(player, box, size, position, distance)
    if cfg.Tracers and cfg.Tracers.Enable then drawtracers(player, box, root) elseif box.Tracer then box.Tracer.Visible=false end
    if cfg.Chams and cfg.Chams.Enable then updatecham(player, box, char) elseif box.Cham then box.Cham.Enabled=false end
end
local _espMasterWasOn = false
local _espAccum = 0

-- NPC ESP wrapped in its own function scope to avoid hitting Lua's 200-local limit
local function _initNPCAndStepESP()
-- NPC ESP (ShootingRangeEntities) — full feature parity with player ESP
local NPCESPObjects = {}

local function createNPCBox(model)
    if NPCESPObjects[model] then return end
    local b = {}
    b.box = {}
    b.box.square  = Drawing.new("Square"); b.box.square.Filled=false;  b.box.square.Thickness=1;  b.box.square.Visible=false
    b.box.inline  = Drawing.new("Square"); b.box.inline.Filled=false;  b.box.inline.Thickness=1;  b.box.inline.Visible=false
    b.box.outline = Drawing.new("Square"); b.box.outline.Filled=false; b.box.outline.Thickness=1; b.box.outline.Visible=false
    b.filled = Instance.new("Frame")
    b.filled.BackgroundColor3 = Color3.new(1,1,1)
    b.filled.BackgroundTransparency = _G.Config.Filled.Transparency
    b.filled.BorderSizePixel = 0; b.filled.Visible = false; b.filled.ZIndex = 2; b.filled.Parent = espgui
    b.filled_gradient = Instance.new("UIGradient")
    b.filled_gradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0,_G.Config.Filled.ColorStart), ColorSequenceKeypoint.new(1,_G.Config.Filled.ColorEnd) })
    b.filled_gradient.Rotation = 0; b.filled_gradient.Parent = b.filled
    b.glow = Instance.new("ImageLabel")
    b.glow.Image = "rbxassetid://110204605000367"
    b.glow.ScaleType = Enum.ScaleType.Slice
    b.glow.SliceCenter = Rect.new(Vector2.new(21,21), Vector2.new(79,79))
    b.glow.AutomaticSize = Enum.AutomaticSize.XY
    b.glow.ImageTransparency = _G.Config.Glow.Transparency
    b.glow.ResampleMode = Enum.ResamplerMode.Pixelated
    b.glow.BackgroundTransparency = 1; b.glow.BorderSizePixel = 0
    b.glow.BackgroundColor3 = Color3.fromRGB(255,255,255); b.glow.ZIndex = 1
    b.glow.Visible = false; b.glow.Parent = espgui
    b.glow_gradient = Instance.new("UIGradient")
    b.glow_gradient.Rotation = _G.Config.Glow.Rotation
    b.glow_gradient.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0,_G.Config.Glow.ColorStart), ColorSequenceKeypoint.new(1,_G.Config.Glow.ColorEnd) })
    b.glow_gradient.Parent = b.glow
    local gp = Instance.new("UIPadding")
    gp.PaddingTop = UDim.new(0,21); gp.PaddingBottom = UDim.new(0,20); gp.PaddingLeft = UDim.new(0,21); gp.PaddingRight = UDim.new(0,20); gp.Parent = b.glow
    b.bars = { hp_bars = {}, hp_outline = Drawing.new("Square"), last_hp = 1 }
    for i=1,12 do b.bars.hp_bars[i] = Drawing.new("Line") end
    b.skeleton = { lines = {}, outlines = {} }
    for i=1,15 do
        local o = Drawing.new("Line"); o.Color = Color3.new(0,0,0); o.Thickness = 3; o.Visible = false; b.skeleton.outlines[i] = o
        local l = Drawing.new("Line"); l.Color = Color3.new(1,1,1); l.Thickness = 1; l.Visible = false; b.skeleton.lines[i] = l
    end
    local studsgui = Instance.new("ScreenGui", espgui.Parent)
    local namegui  = Instance.new("ScreenGui", espgui.Parent)
    local toolgui  = Instance.new("ScreenGui", espgui.Parent)
    b.text = { studs = makelabel(studsgui), tool = makelabel(toolgui), name = makelabel(namegui) }
    b.Tracer = Drawing.new("Line"); b.Tracer.Visible = false
    b.Tracer.Color = _G.Config.Tracers.Color; b.Tracer.Thickness = _G.Config.Tracers.Thickness
    NPCESPObjects[model] = b
end

local function removeNPCBox(model)
    if not NPCESPObjects[model] then return end
    local b = NPCESPObjects[model]
    if b.box then b.box.square:Remove(); b.box.outline:Remove(); b.box.inline:Remove() end
    if b.filled then b.filled:Destroy() end
    if b.glow then b.glow:Destroy() end
    if b.text then
        if b.text.studs then b.text.studs.Parent:Destroy() end
        if b.text.tool  then b.text.tool.Parent:Destroy() end
        if b.text.name  then b.text.name.Parent:Destroy() end
    end
    if b.bars then b.bars.hp_outline:Remove(); for _,l in pairs(b.bars.hp_bars) do l:Remove() end end
    if b.skeleton then for _,l in pairs(b.skeleton.lines) do l:Remove() end for _,o in pairs(b.skeleton.outlines) do o:Remove() end end
    if b.Tracer then b.Tracer:Remove() end
    if b.Cham then b.Cham:Destroy(); b.Cham = nil end
    NPCESPObjects[model] = nil
end

local function hideNPCBox(model)
    if not NPCESPObjects[model] then return end
    local b = NPCESPObjects[model]
    if b.box then b.box.square.Visible=false; b.box.outline.Visible=false; b.box.inline.Visible=false end
    if b.filled then b.filled.Visible=false end
    if b.glow then b.glow.Visible=false end
    if b.text then b.text.studs.Visible=false; b.text.tool.Visible=false; b.text.name.Visible=false end
    if b.bars then b.bars.hp_outline.Visible=false; for _,l in pairs(b.bars.hp_bars) do l.Visible=false end end
    if b.skeleton then for _,l in pairs(b.skeleton.lines) do l.Visible=false end for _,o in pairs(b.skeleton.outlines) do o.Visible=false end end
    if b.Tracer then b.Tracer.Visible=false end
    if b.Cham then b.Cham.Enabled=false end
end

-- Fake player-like table so draw helpers that take "player" can work with NPC models
local function makeNPCProxy(model)
    return setmetatable({}, {
        __index = function(_, k)
            if k == "Character" then return model end
            if k == "Name"      then return model.Name end
            return nil
        end
    })
end

local function npcDist(model)
    local root = model:FindFirstChild("HumanoidRootPart")
    local myChar = localPlayer.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if root and myRoot then return (root.Position - myRoot.Position).Magnitude end
    return math.huge
end

local function updateNPCesp(model, dt)
    if not NPCESPObjects[model] then return end
    if not ConfigBox.MasterEnabled then hideNPCBox(model); return end
    local hum  = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
    if not hum or hum.Health <= 0 or not root then hideNPCBox(model); return end
    local hrp2d, hrpOk = worldToEspScreen(root.Position)
    if not hrpOk then hideNPCBox(model); return end
    local distance = npcDist(model)
    local hitboxSize, hitboxPosition = getHitboxBounds(model)
    local size, position
    if hitboxSize and hitboxPosition then
        size     = Vector2.new(math.max(math.floor(hitboxSize.X),4),  math.max(math.floor(hitboxSize.Y),8))
        position = Vector2.new(math.floor(hitboxPosition.X), math.floor(hitboxPosition.Y))
    else
        local head     = model:FindFirstChild("Head")
        local topWorld = (head and head.Position + Vector3.new(0,0.5,0)) or (root.Position + Vector3.new(0,3,0))
        local top2d, topOk    = worldToEspScreen(topWorld)
        local bottom2d, botOk = worldToEspScreen(root.Position - Vector3.new(0,3,0))
        if not topOk or not botOk then hideNPCBox(model); return end
        local boxHeight = math.abs(bottom2d.Y - top2d.Y)
        local boxWidth  = math.max(boxHeight*0.55, 8)
        size     = Vector2.new(math.max(math.floor(boxWidth),4), math.max(math.floor(math.max(boxHeight,10)),8))
        position = Vector2.new(math.floor(hrp2d.X - size.X/2), math.floor(math.min(top2d.Y, bottom2d.Y)))
    end
    local b   = NPCESPObjects[model]
    local cfg = _G.Config
    local proxy = makeNPCProxy(model)
    -- reuse the exact same draw helpers as players
    drawfill(proxy, b, size, position)
    drawbox(proxy, b, size, position)
    drawglow(proxy, b, size, position)
    if cfg.Skeleton and cfg.Skeleton.Enable then
        drawskeleton(proxy, b, model, hum, size, position)
    else
        for _,l in pairs(b.skeleton.lines)   do l.Visible=false end
        for _,o in pairs(b.skeleton.outlines) do o.Visible=false end
    end
    drawhealthbar(proxy, b, hum, size, position, dt)
    -- name: show model name; distance; hide weapon
    if cfg.TextESP and cfg.TextESP.Names then
        b.text.name.Visible=true
        b.text.name.Position=UDim2.new(0, position.X+(size.X/2)-100, 0, position.Y-guiinset.Y-15)
        b.text.name.Text=model.Name
        b.text.name.TextSize=cfg.TextESP.NameSize or 13
        ensureTextGradient(b.text.name, cfg.TextESP.NameColor, cfg.TextESP.NameColor2 or cfg.TextESP.NameColor)
        b.text.name.TextXAlignment=Enum.TextXAlignment.Center
    else b.text.name.Visible=false end
    b.text.tool.Visible=false  -- NPCs have no weapon
    if cfg.TextESP and cfg.TextESP.Distance then
        b.text.studs.Visible=true
        b.text.studs.Position=UDim2.new(0, position.X+(size.X/2)-100, 0, position.Y-guiinset.Y+size.Y+2)
        b.text.studs.Text=string.format("%.0f studs", distance)
        b.text.studs.TextSize=cfg.TextESP.DistanceSize or 11
        ensureTextGradient(b.text.studs, cfg.TextESP.DistanceColor, cfg.TextESP.DistanceColor2 or cfg.TextESP.DistanceColor)
        b.text.studs.TextXAlignment=Enum.TextXAlignment.Center
    else b.text.studs.Visible=false end
    if cfg.Tracers and cfg.Tracers.Enable then drawtracers(proxy, b, root) elseif b.Tracer then b.Tracer.Visible=false end
    if cfg.Chams and cfg.Chams.Enable then updatecham(proxy, b, model) elseif b.Cham then b.Cham.Enabled=false end
end

local function stepEspUpdate(dt)
    dt = dt or (1/240)
    tickval = os.clock()
    if not ConfigBox.MasterEnabled then
        if _espMasterWasOn then
            _espMasterWasOn=false
            for plr in pairs(ESPObjects)    do hideesp(plr)     end
            for m   in pairs(NPCESPObjects) do hideNPCBox(m)    end
        end
        return
    end
    _espMasterWasOn = true

    local hz = (_G.Config.ESP and _G.Config.ESP.TargetHz) or 60
    local ESP_INTERVAL = 1 / math.clamp(hz, 15, 240)
    _espAccum = _espAccum + dt
    if _espAccum < ESP_INTERVAL then return end
    local frameDt = _espAccum
    _espAccum = 0
    for _, plr in ipairs(players:GetPlayers()) do
        if plr ~= localPlayer then
            local ok, err = pcall(updateesp, plr, frameDt)
            if not ok then pcall(hideesp, plr) end
        end
    end
    -- NPC ESP — full parity with player ESP via updateNPCesp
    local range = Workspace:FindFirstChild("ShootingRangeEntities")
    local activeNPCs = {}
    if range then
        for _, model in ipairs(range:GetDescendants()) do
            if model:IsA("Model") then
                local hum  = model:FindFirstChildOfClass("Humanoid")
                local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
                if hum and hum.Health > 0 and root then
                    activeNPCs[model] = true
                    createNPCBox(model)
                    local ok2 = pcall(updateNPCesp, model, frameDt)
                    if not ok2 then hideNPCBox(model) end
                end
            end
        end
    end
    -- clean up stale NPC boxes
    for model in pairs(NPCESPObjects) do
        if not activeNPCs[model] then removeNPCBox(model) end
    end
end
RunService.RenderStepped:Connect(stepEspUpdate)
end -- _initNPCAndStepESP
_initNPCAndStepESP()

-- ESP objects are now created lazily inside updateesp (only when ESP is enabled and
-- the player is a valid target), so nothing heavy is allocated at load. We only need
-- to clean up when a player leaves.
players.PlayerRemoving:Connect(RemoveBox)

local WHITE = Color3.fromRGB(255,42,42)   -- default: red
local BLACK = Color3.fromRGB(0,0,0)

local espGroup = visualsTab:createGroup('left', 'esp')
espGroup:addToggle({text = "enable", flag = "box_enabled", callback = function(v) ConfigBox.MasterEnabled = v end})

espGroup:addToggle({text = "boxes", flag = "box_enabled2", callback = function(v) ConfigBox.Enable = v end})
    :addColorpicker({text = "box color", flag = "box_outline_color", color = WHITE, callback = function(v) ConfigBox.OutlineColor = v end})
    :addColorpicker({text = "box outline", flag = "box_outline_color2", second = true, color = BLACK, callback = function(v) ConfigBox.OutlineColor2 = v end})

espGroup:addToggle({text = "box fill", flag = "box_filled", callback = function(v) _G.Config.Filled.Enable = v end})
    :addColorpicker({text = "fill start", flag = "box_filled_color_start", color = WHITE, callback = function(v) _G.Config.Filled.ColorStart = v end})
    :addColorpicker({text = "fill end", flag = "box_filled_color_end", second = true, color = BLACK, callback = function(v) _G.Config.Filled.ColorEnd = v end})
espGroup:markStart()
espGroup:addSlider({text = "fill transparency %", flag = "esp_fill_trans", value = 70, min = 0, max = 100, suffix = "%",
    callback = function(v) _G.Config.Filled.Transparency = v/100 end})
espGroup:addToggle({text = "animated fill", flag = "esp_fill_anim", callback = function(v) _G.Config.Filled.Animated = v end})
espGroup:addSlider({text = "fill anim speed", flag = "esp_fill_speed", value = 1, min = 1, max = 20,
    callback = function(v) _G.Config.Filled.Speed = v end})
espGroup:dependsOn("box_filled")

espGroup:addToggle({text = "box glow", flag = "box_glow", callback = function(v) _G.Config.Glow.Enable = v end})
    :addColorpicker({text = "glow start", flag = "box_glow_color_start", color = WHITE, callback = function(v) _G.Config.Glow.ColorStart = v end})
    :addColorpicker({text = "glow end", flag = "box_glow_color_end", second = true, color = BLACK, callback = function(v) _G.Config.Glow.ColorEnd = v end})
espGroup:markStart()
espGroup:addSlider({text = "glow transparency %", flag = "esp_glow_trans", value = 50, min = 0, max = 100, suffix = "%",
    callback = function(v) _G.Config.Glow.Transparency = v/100 end})
espGroup:dependsOn("box_glow")

espGroup:addToggle({text = "healthbar", flag = "healthbar", callback = function(v) ConfigBox.Healthbar.Enable = v end})
    :addColorpicker({text = "high hp color", flag = "esp_hp_c1", color = Color3.fromRGB(0,255,0), callback = function(v) ConfigBox.HealthLerpColors.Color1 = v end})
    :addColorpicker({text = "low hp color", flag = "esp_hp_c2", second = true, color = Color3.fromRGB(255,0,0), callback = function(v) ConfigBox.HealthLerpColors.Color3 = v end})
espGroup:markStart()
espGroup:addSlider({text = "health lerp speed", flag = "esp_hp_lerp", value = 32, min = 1, max = 100,
    callback = function(v) _G.Config.ESP.HealthLerpSpeed = v end})
espGroup:dependsOn("healthbar")

espGroup:addToggle({text = "names", flag = "esp_names", callback = function(v) _G.Config.TextESP.Names = v end})
    :addColorpicker({text = "name color", flag = "esp_name_c1", color = WHITE, callback = function(v) _G.Config.TextESP.NameColor = v end})
    :addColorpicker({text = "name color 2", flag = "esp_name_c2", second = true, color = WHITE, callback = function(v) _G.Config.TextESP.NameColor2 = v end})
espGroup:markStart()
espGroup:addSlider({text = "name size", flag = "esp_name_size", value = 13, min = 6, max = 48,
    callback = function(v) _G.Config.TextESP.NameSize = v end})
espGroup:dependsOn("esp_names")

espGroup:addToggle({text = "distance", flag = "esp_distance", callback = function(v) _G.Config.TextESP.Distance = v end})
    :addColorpicker({text = "distance color", flag = "esp_dist_c1", color = WHITE, callback = function(v) _G.Config.TextESP.DistanceColor = v end})
    :addColorpicker({text = "distance color 2", flag = "esp_dist_c2", second = true, color = WHITE, callback = function(v) _G.Config.TextESP.DistanceColor2 = v end})
espGroup:markStart()
espGroup:addSlider({text = "distance size", flag = "esp_dist_size", value = 11, min = 6, max = 48,
    callback = function(v) _G.Config.TextESP.DistanceSize = v end})
espGroup:dependsOn("esp_distance")

espGroup:addToggle({text = "weapon", flag = "esp_tools", callback = function(v) _G.Config.TextESP.Tools = v end})
    :addColorpicker({text = "weapon color", flag = "esp_tool_c1", color = WHITE, callback = function(v) _G.Config.TextESP.ToolColor = v end})
    :addColorpicker({text = "weapon color 2", flag = "esp_tool_c2", second = true, color = WHITE, callback = function(v) _G.Config.TextESP.ToolColor2 = v end})
espGroup:markStart()
espGroup:addSlider({text = "weapon size", flag = "esp_tool_size", value = 11, min = 6, max = 48,
    callback = function(v) _G.Config.TextESP.ToolsSize = v end})
espGroup:dependsOn("esp_tools")

espGroup:addToggle({text = "gradient text", flag = "esp_text_gradient",
    callback = function(v) _G.Config.TextESP.Gradient = v end})
espGroup:markStart()
espGroup:addToggle({text = "flow animation", flag = "esp_text_flow",
    callback = function(v) _G.Config.TextESP.Flow = v end})
espGroup:addSlider({text = "flow speed", flag = "esp_text_flow_speed", value = 1, min = 1, max = 5,
    callback = function(v) _G.Config.TextESP.FlowSpeed = v end})
espGroup:dependsOn("esp_text_gradient")

espGroup:addToggle({text = "skeleton", flag = "esp_skeleton", callback = function(v) _G.Config.Skeleton.Enable = v end})
    :addColorpicker({text = "skeleton color", flag = "esp_skel_c1", color = WHITE, callback = function(v) _G.Config.Skeleton.Color = v end})
    :addColorpicker({text = "skeleton color 2", flag = "esp_skel_c2", second = true, color = WHITE, callback = function(v) _G.Config.Skeleton.Color2 = v end})
espGroup:markStart()
espGroup:addSlider({text = "skeleton thickness", flag = "esp_skel_thick", value = 1, min = 1, max = 10,
    callback = function(v) _G.Config.Skeleton.Thickness = v end})
espGroup:dependsOn("esp_skeleton")

espGroup:addToggle({text = "tracers", flag = "esp_tracers", callback = function(v) _G.Config.Tracers.Enable = v end})
    :addColorpicker({text = "tracer color", flag = "esp_tracer_c1", color = WHITE, callback = function(v) _G.Config.Tracers.Color = v end})
    :addColorpicker({text = "tracer color 2", flag = "esp_tracer_c2", second = true, color = WHITE, callback = function(v) _G.Config.Tracers.Color2 = v end})
espGroup:markStart()
espGroup:addSlider({text = "tracer thickness", flag = "esp_tracer_thick", value = 1, min = 1, max = 10,
    callback = function(v) _G.Config.Tracers.Thickness = v end})
espGroup:addList({text = "tracer origin", flag = "esp_tracer_origin", value = "bottom", values = {"bottom","center"},
    callback = function(v) _G.Config.Tracers.FromBottom = (v == "bottom") end})
espGroup:dependsOn("esp_tracers")

espGroup:addToggle({text = "chams", flag = "esp_chams", callback = function(v) _G.Config.Chams.Enable = v end})
    :addColorpicker({text = "chams color", flag = "esp_chams_c1", color = Color3.fromRGB(255,42,42), callback = function(v) _G.Config.Chams.Color = v end})
    :addColorpicker({text = "chams outline", flag = "esp_chams_c2", second = true, color = BLACK, callback = function(v) _G.Config.Chams.Color2 = v end})
espGroup:markStart()
espGroup:addSlider({text = "chams fill transparency %", flag = "esp_chams_trans", value = 35, min = 0, max = 100, suffix = "%",
    callback = function(v) _G.Config.Chams.Transparency = v/100 end})
espGroup:addSlider({text = "chams outline transparency %", flag = "esp_chams_otrans", value = 0, min = 0, max = 100, suffix = "%",
    callback = function(v) _G.Config.Chams.OutlineTransparency = v/100 end})
espGroup:addToggle({text = "chams through walls", flag = "esp_chams_walls", value = true,
    callback = function(v) _G.Config.Chams.ThroughWalls = v end})
espGroup:dependsOn("esp_chams")

espGroup:addToggle({text = "glow chams", flag = "esp_glowchams", callback = function(v) _G.Config.GlowChams.Enable = v end})
    :addColorpicker({text = "glow color", flag = "esp_glowchams_c1", color = Color3.fromRGB(255,42,42), callback = function(v) _G.Config.GlowChams.Color = v end})
espGroup:markStart()
espGroup:addSlider({text = "glow transparency %", flag = "esp_glowchams_trans", value = 70, min = 0, max = 100, suffix = "%",
    callback = function(v) _G.Config.GlowChams.Transparency = v/100 end})
espGroup:addToggle({text = "glow through walls", flag = "esp_glowchams_walls", value = true,
    callback = function(v) _G.Config.GlowChams.ThroughWalls = v end})
espGroup:dependsOn("esp_glowchams")
end)() -- end ESP function scope

-- ═══════════════════════════════════════════════════════════════════════════
-- ported take.lua visual features: throwable esp, damage numbers, trajectory,
-- bullet tracers. Own IIFE scope (200-local safety) + own ScreenGui.
-- ═══════════════════════════════════════════════════════════════════════════
;(function()
local vfxGui = Instance.new("ScreenGui")
vfxGui.Name = "riotsVFX"
vfxGui.DisplayOrder = 9e8
vfxGui.ResetOnSpawn = false
vfxGui.IgnoreGuiInset = true
vfxGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() vfxGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)

local cam = Workspace.CurrentCamera
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function() cam = Workspace.CurrentCamera end)

-- ─── throwable esp ───────────────────────────────────────────────────────────
local throwCfg = {
    enable = false, name = true, distance = true,
    nameColor = Color3.fromRGB(255,255,255), nameSize = 14,
    distColor = Color3.fromRGB(200,200,200), distSize = 12,
    whitelist = { Grenade=true, Flashbang=true, Molotov=true, Satchel=true,
                  ["Smoke Grenade"]=true, ["Subspace Tripmine"]=true },
}
local subspaceMap = { ["Subspace Tripmine"] = "SubspaceTripmineHitbox" }
local thrower = {}
local function killThrow(obj)
    if thrower[obj] then
        pcall(function() thrower[obj].name:Destroy(); thrower[obj].dist:Destroy() end)
        thrower[obj] = nil
    end
end
Workspace.ChildRemoved:Connect(function(o) killThrow(o) end)

RunService.RenderStepped:Connect(function()
    if not throwCfg.enable then
        for _, v in pairs(thrower) do v.name.Visible=false; v.dist.Visible=false end
        return
    end
    local active = {}
    for _, v in ipairs(Workspace:GetChildren()) do
        local disp = nil
        for name, on in pairs(throwCfg.whitelist) do
            if on then
                local target = subspaceMap[name] or name
                if v.Name == target or v.Name == name then disp = name; break end
            end
        end
        if disp then
            local root = v:FindFirstChildWhichIsA("BasePart")
            if root then
                active[v] = true
                if not thrower[v] then
                    local nameLbl = Instance.new("TextLabel")
                    nameLbl.BackgroundTransparency = 1; nameLbl.TextStrokeTransparency = 0
                    nameLbl.Font = Enum.Font.Code; nameLbl.Size = UDim2.fromOffset(120,14)
                    nameLbl.TextXAlignment = Enum.TextXAlignment.Center; nameLbl.Visible = false
                    nameLbl.Parent = vfxGui
                    local distLbl = Instance.new("TextLabel")
                    distLbl.BackgroundTransparency = 1; distLbl.TextStrokeTransparency = 0
                    distLbl.Font = Enum.Font.Code; distLbl.Size = UDim2.fromOffset(120,12)
                    distLbl.TextXAlignment = Enum.TextXAlignment.Center; distLbl.Visible = false
                    distLbl.Parent = vfxGui
                    thrower[v] = { name = nameLbl, dist = distLbl }
                end
                local t = thrower[v]
                local sp, on = (cam or Workspace.CurrentCamera):WorldToViewportPoint(root.Position)
                t.name.Visible = on and throwCfg.name
                t.dist.Visible = on and throwCfg.distance
                if on then
                    t.name.TextColor3 = throwCfg.nameColor; t.name.TextSize = throwCfg.nameSize
                    t.name.Position = UDim2.fromOffset(sp.X-60, sp.Y-8); t.name.Text = disp
                    t.dist.TextColor3 = throwCfg.distColor; t.dist.TextSize = throwCfg.distSize
                    t.dist.Position = UDim2.fromOffset(sp.X-60, sp.Y+8)
                    local c = cam or Workspace.CurrentCamera
                    t.dist.Text = string.format("%.0fm", (c.CFrame.Position - root.Position).Magnitude * 0.28)
                end
            end
        end
    end
    for o in pairs(thrower) do if not active[o] then killThrow(o) end end
end)

local throwGroup = visualsTab:createGroup('left', 'throwable esp')
throwGroup:addToggle({text = "enable", flag = "ThrowEsp", callback = function(v) throwCfg.enable = v end})
throwGroup:markStart()
throwGroup:addToggle({text = "name", flag = "ThrowName", value = true, callback = function(v) throwCfg.name = v end})
    :addColorpicker({text = "name color", flag = "ThrowNameColor", color = Color3.fromRGB(255,255,255), callback = function(v) throwCfg.nameColor = v end})
throwGroup:addToggle({text = "distance", flag = "ThrowDist", value = true, callback = function(v) throwCfg.distance = v end})
    :addColorpicker({text = "distance color", flag = "ThrowDistColor", color = Color3.fromRGB(200,200,200), callback = function(v) throwCfg.distColor = v end})
throwGroup:addList({text = "throwables", flag = "ThrowSelect", multiselect = true,
    value = {"Grenade","Flashbang","Molotov","Satchel","Smoke Grenade","Subspace Tripmine"},
    values = {"Grenade","Flashbang","Molotov","Satchel","Smoke Grenade","Subspace Tripmine"},
    callback = function(v)
        local set = {}
        if type(v) == "table" then for _, n in ipairs(v) do set[n] = true end end
        throwCfg.whitelist = set
    end})
throwGroup:dependsOn("ThrowEsp")

-- ─── damage numbers (take's damage hook logic, rewritten rise/fade visual) ────
local dmgCfg = {
    enable = false,
    color1 = Color3.fromRGB(255,80,80), color2 = Color3.fromRGB(255,210,90),
    duration = 0.8, rise = 42, textSize = 18,
}
local function spawnDamageNumber(worldPos, amount, headshot)
    if not dmgCfg.enable or not worldPos then return end
    local c = cam or Workspace.CurrentCamera
    local sp, on = c:WorldToViewportPoint(worldPos)
    if not on then return end
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1
    lbl.AnchorPoint = Vector2.new(0.5, 0.5)
    lbl.Position = UDim2.fromOffset(sp.X, sp.Y)
    lbl.Size = UDim2.fromOffset(120, 26)
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = dmgCfg.textSize * (headshot and 1.25 or 1)
    lbl.TextStrokeTransparency = 0
    lbl.Text = "-" .. tostring(math.floor(amount + 0.5))
    lbl.TextColor3 = dmgCfg.color1
    lbl.ZIndex = 50
    lbl.Parent = vfxGui
    -- rewritten visual: a 2-color gradient + rise & fade tween
    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, dmgCfg.color1), ColorSequenceKeypoint.new(1, dmgCfg.color2) })
    grad.Rotation = 90
    grad.Parent = lbl
    lbl.TextColor3 = Color3.new(1,1,1)
    local dur = dmgCfg.duration
    local ti = TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    tweenService:Create(lbl, ti, {
        Position = UDim2.fromOffset(sp.X, sp.Y - dmgCfg.rise),
        TextTransparency = 1,
        TextStrokeTransparency = 1,
    }):Play()
    task.delay(dur + 0.05, function() pcall(function() lbl:Destroy() end) end)
end

-- damage numbers subscribe to the shared damage event (hook set up once at top)
library:onDamage(function(hit_char, hit_root, hit_damage, is_headshot)
    if not dmgCfg.enable then return end
    local ok, pos = pcall(function()
        return hit_root.Position + Vector3.new(0, is_headshot and 2.6 or 2.1, 0)
    end)
    spawnDamageNumber(ok and pos or hit_root.Position, hit_damage or 0, is_headshot)
end)

local dmgGroup = visualsTab:createGroup('left', 'damage numbers')
dmgGroup:addToggle({text = "enable", flag = "DamageNumbers", callback = function(v) dmgCfg.enable = v end})
    :addColorpicker({text = "color 1", flag = "DmgColor1", color = Color3.fromRGB(255,80,80), callback = function(v) dmgCfg.color1 = v end})
    :addColorpicker({text = "color 2", flag = "DmgColor2", second = true, color = Color3.fromRGB(255,210,90), callback = function(v) dmgCfg.color2 = v end})
dmgGroup:markStart()
dmgGroup:addSlider({text = "text size", flag = "DmgSize", value = 18, min = 10, max = 40, callback = function(v) dmgCfg.textSize = v end})
dmgGroup:addSlider({text = "rise", flag = "DmgRise", value = 42, min = 0, max = 120, callback = function(v) dmgCfg.rise = v end})
dmgGroup:addSlider({text = "duration", flag = "DmgDuration", value = 80, min = 20, max = 200, suffix = "", callback = function(v) dmgCfg.duration = v/100 end})
dmgGroup:dependsOn("DamageNumbers")

-- hit notify (fixed preset "hit {username} {bodypart} for {damage}") — no message editing
local hnGroup = visualsTab:createGroup('left', 'hit notify')
hnGroup:addToggle({text = "enable", flag = "HitNotifyEnabled", callback = function(v) library.hitNotifyCfg.enabled = v end})
hnGroup:markStart()
hnGroup:addSlider({text = "duration", flag = "HitNotifyDur", value = 3, min = 1, max = 8, callback = function(v) library.hitNotifyCfg.duration = v end})
hnGroup:addList({text = "animation", flag = "HitNotifyAnim", value = "fade bounce",
    values = library.hitNotifAnimStyles,
    callback = function(v) library.hitNotifyCfg.animation = v end})
hnGroup:dependsOn("HitNotifyEnabled")

-- ─── bullet tracers (full settings + spring expand) ──────────────────────────
local tracerCfg = {
    enable = false,
    colorStart = Color3.fromRGB(255,255,255), colorEnd = Color3.fromRGB(255,42,42),
    lifeTime = 1.5, width0 = 0.35, width1 = 0.15,
    springExpand = false, expandSpeed = 12, expandDamper = 0.6,
    throughWalls = false,
    texture = "lightning",
}
local tracerTextures = {
    ["none (solid)"] = "",
    ["beam"] = "rbxassetid://12781852245",
    ["lightning"] = "rbxassetid://446111271",
    ["glow"] = "rbxassetid://2382169232",
}
local function spawnTracer(fromPos, toPos)
    if not tracerCfg.enable then return end
    local a0p = Instance.new("Part")
    a0p.Anchored = true; a0p.CanCollide = false; a0p.Transparency = 1
    a0p.Size = Vector3.new(0.1,0.1,0.1); a0p.CFrame = CFrame.new(fromPos); a0p.Parent = vfxGui
    local a1p = a0p:Clone(); a1p.CFrame = CFrame.new(toPos); a1p.Parent = vfxGui
    local a0 = Instance.new("Attachment", a0p)
    local a1 = Instance.new("Attachment", a1p)
    local beam = Instance.new("Beam")
    beam.Attachment0 = a0; beam.Attachment1 = a1
    beam.Width0 = tracerCfg.width0; beam.Width1 = tracerCfg.width1
    beam.FaceCamera = true
    beam.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, tracerCfg.colorStart), ColorSequenceKeypoint.new(1, tracerCfg.colorEnd) })
    beam.Texture = tracerTextures[tracerCfg.texture] or ""
    beam.TextureSpeed = 0; beam.TextureLength = 4
    beam.Parent = a0p
    -- spring expand: animate the beam width outwards with a damped spring feel
    if tracerCfg.springExpand then
        local t0 = os.clock()
        local conn
        conn = RunService.RenderStepped:Connect(function()
            local e = os.clock() - t0
            local s = 1 + math.sin(e * tracerCfg.expandSpeed) * math.exp(-e / math.max(tracerCfg.expandDamper,0.05)) * 2
            beam.Width0 = tracerCfg.width0 * s
            beam.Width1 = tracerCfg.width1 * s
            if e > tracerCfg.lifeTime then conn:Disconnect() end
        end)
    end
    task.delay(tracerCfg.lifeTime, function()
        pcall(function() a0p:Destroy(); a1p:Destroy() end)
    end)
end
-- hook the shot origin/direction: on mouse-down, trace from muzzle toward aim
RunService.Heartbeat:Connect(function()
    -- lightweight: bullet tracers are spawned by the shoot hook below, nothing per-frame
end)
-- spawn a tracer whenever the local player fires (reuse the global shot marker)
do
    -- muzzle position from the view model's _muzzle attachment (accurate origin)
    local function muzzlePos()
        local vm = Workspace:FindFirstChild("ViewModels")
        local fp = vm and vm:FindFirstChild("FirstPerson")
        if not fp then return nil end
        local pn = localPlayer.Name
        for _, model in ipairs(fp:GetChildren()) do
            if model:IsA("Model") and model.Name:find("^" .. pn) then
                local iv = model:FindFirstChild("ItemVisual")
                local body = iv and iv:FindFirstChild("Body")
                local bp = body and body:FindFirstChild("BodyPrimary")
                local muzzle = bp and bp:FindFirstChild("_muzzle")
                if muzzle and muzzle:IsA("Attachment") then return muzzle.WorldPosition end
            end
        end
        return nil
    end

    -- PRIMARY: hook the game's TracerEffect.Play (ported from take1.lua) for
    -- pixel-accurate muzzle → hit tracers. Retries until the module resolves.
    local tracerHooked = false
    local function hookTracerEffect()
        if tracerHooked then return end
        pcall(function()
            local TE = require(localPlayer.PlayerScripts.Modules.TracerEffect)
            local origPlay = TE.Play
            TE.Play = function(self, tracerData, config, extraData)
                if tracerCfg.enable and tracerData and tracerData.IsLocal and tracerData.RaycastResults then
                    local mPos = muzzlePos()
                    if mPos then
                        for _, hit in ipairs(tracerData.RaycastResults) do
                            if hit.Position then pcall(spawnTracer, mPos, hit.Position) end
                        end
                    end
                end
                return origPlay(self, tracerData, config, extraData)
            end
            tracerHooked = true
        end)
    end
    task.spawn(function()
        for _ = 1, 40 do
            hookTracerEffect()
            if tracerHooked then break end
            task.wait(0.5)
        end
    end)

    -- FALLBACK: if the TracerEffect hook never resolved, fall back to shot
    -- detection so tracers still show something.
    local lastShotTracer = 0
    RunService.Heartbeat:Connect(function()
        if not tracerCfg.enable then return end
        if tracerHooked then return end   -- accurate hook is active; skip fallback
        local shotAt = getgenv().InstanceCombatLastShotAt or 0
        if shotAt > lastShotTracer then
            lastShotTracer = shotAt
            local c = cam or Workspace.CurrentCamera
            local char = localPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if c and hrp then
                local origin = muzzlePos() or hrp.Position
                local dir = c.CFrame.LookVector
                local params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterType.Exclude
                params.FilterDescendantsInstances = { char, vfxGui }
                local res = Workspace:Raycast(origin, dir * 500, params)
                local hitPos = res and res.Position or (origin + dir * 500)
                pcall(spawnTracer, origin, hitPos)
            end
        end
    end)
end

local tracerGroup = visualsTab:createGroup('right', 'bullet tracers')
tracerGroup:addToggle({text = "enable", flag = "Tracers2", callback = function(v) tracerCfg.enable = v end})
    :addColorpicker({text = "color start", flag = "TracerC1", color = Color3.fromRGB(255,255,255), callback = function(v) tracerCfg.colorStart = v end})
    :addColorpicker({text = "color end", flag = "TracerC2", second = true, color = Color3.fromRGB(255,42,42), callback = function(v) tracerCfg.colorEnd = v end})
tracerGroup:markStart()
tracerGroup:addList({text = "texture", flag = "TracerTex", value = "lightning",
    values = {"none (solid)","beam","lightning","glow"},
    callback = function(v) tracerCfg.texture = v end})
tracerGroup:addSlider({text = "life time", flag = "TracerLife", value = 15, min = 1, max = 50, callback = function(v) tracerCfg.lifeTime = v/10 end})
tracerGroup:addSlider({text = "width start", flag = "TracerW0", value = 35, min = 1, max = 200, callback = function(v) tracerCfg.width0 = v/100 end})
tracerGroup:addSlider({text = "width end", flag = "TracerW1", value = 15, min = 1, max = 200, callback = function(v) tracerCfg.width1 = v/100 end})
tracerGroup:addToggle({text = "spring expand", flag = "TracerSpring", callback = function(v) tracerCfg.springExpand = v end})
tracerGroup:addSlider({text = "expand speed", flag = "TracerExpSpd", value = 12, min = 1, max = 40, callback = function(v) tracerCfg.expandSpeed = v end})
tracerGroup:addSlider({text = "expand damper", flag = "TracerExpDmp", value = 60, min = 5, max = 100, callback = function(v) tracerCfg.expandDamper = v/100 end})
tracerGroup:dependsOn("Tracers2")

-- ─── trajectory prediction (arc line) ────────────────────────────────────────
local trajCfg = { enable = false, speed = 90, arcUp = 10, color = Color3.fromRGB(255,42,42) }
local trajLines = {}
for i = 1, 30 do
    local l = Drawing.new("Line"); l.Visible = false; l.Thickness = 2; trajLines[i] = l
end
RunService.RenderStepped:Connect(function()
    if not trajCfg.enable then
        for _, l in ipairs(trajLines) do l.Visible = false end
        return
    end
    local c = cam or Workspace.CurrentCamera
    local char = localPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not c or not hrp then for _, l in ipairs(trajLines) do l.Visible = false end return end
    -- simulate a projectile launched from the camera forward with an upward arc
    local origin = hrp.Position + Vector3.new(0, 2, 0)
    local vel = c.CFrame.LookVector * trajCfg.speed + Vector3.new(0, trajCfg.arcUp, 0)
    local g = Vector3.new(0, -workspace.Gravity, 0)
    local pts = {}
    local step = 0.08
    for i = 0, 30 do
        local t = i * step
        pts[i+1] = origin + vel * t + 0.5 * g * t * t
    end
    for i = 1, 30 do
        local p0, on0 = c:WorldToViewportPoint(pts[i])
        local p1, on1 = c:WorldToViewportPoint(pts[i+1])
        local l = trajLines[i]
        if on0 and on1 then
            l.From = Vector2.new(p0.X, p0.Y)
            l.To = Vector2.new(p1.X, p1.Y)
            l.Color = trajCfg.color
            l.Visible = true
        else
            l.Visible = false
        end
    end
end)

local trajGroup = visualsTab:createGroup('right', 'trajectory')
trajGroup:addToggle({text = "enable", flag = "Trajectory", callback = function(v) trajCfg.enable = v end})
    :addColorpicker({text = "color", flag = "TrajColor", color = Color3.fromRGB(255,42,42), callback = function(v) trajCfg.color = v end})
trajGroup:markStart()
trajGroup:addSlider({text = "speed", flag = "TrajSpeed", value = 90, min = 10, max = 300, callback = function(v) trajCfg.speed = v end})
trajGroup:addSlider({text = "arc up", flag = "TrajArc", value = 10, min = 0, max = 100, callback = function(v) trajCfg.arcUp = v end})
trajGroup:dependsOn("Trajectory")

-- ─── viewmodel override (arm transparency / hide / fov) ──────────────────────
local vmCfg = { enable = false, transparency = 0, hide = false }
RunService.RenderStepped:Connect(function()
    if not vmCfg.enable then return end
    local vms = Workspace:FindFirstChild("ViewModels")
    if not vms then return end
    for _, m in ipairs(vms:GetDescendants()) do
        if m:IsA("BasePart") or m:IsA("Decal") or m:IsA("Texture") then
            pcall(function()
                if vmCfg.hide then
                    m.Transparency = 1
                else
                    m.Transparency = math.clamp(vmCfg.transparency, 0, 1)
                end
            end)
        end
    end
end)

local vmGroup = visualsTab:createGroup('right', 'viewmodel')
vmGroup:addToggle({text = "enable override", flag = "VmOverride", callback = function(v) vmCfg.enable = v end})
vmGroup:markStart()
vmGroup:addToggle({text = "hide viewmodel", flag = "VmHide", callback = function(v) vmCfg.hide = v end})
vmGroup:addSlider({text = "transparency %", flag = "VmTrans", value = 0, min = 0, max = 100, suffix = "%",
    callback = function(v) vmCfg.transparency = v/100 end})
vmGroup:dependsOn("VmOverride")
end)() -- end ported-vfx block

-- ═══════════════════════════════════════════════════════════════════════════
-- viewmodel chams (gun chams + arm chams) — ported from take.lua, own IIFE
-- ═══════════════════════════════════════════════════════════════════════════
;(function()
    local materialPresets = {
        ["Neon"]       = { material = Enum.Material.Neon },
        ["ForceField"] = { material = Enum.Material.ForceField },
        ["Glass"]      = { material = Enum.Material.Glass, reflectance = 0.10, transparency = 0.20 },
        ["Chrome"]     = { material = Enum.Material.Metal, reflectance = 1.00 },
        ["Ice"]        = { material = Enum.Material.Ice, reflectance = 0.35 },
        ["Diamond"]    = { material = Enum.Material.Glass, reflectance = 0.65, transparency = 0.10 },
        ["Hologram"]   = { material = Enum.Material.ForceField, transparency = 0.35 },
        ["Ghost"]      = { material = Enum.Material.Neon, transparency = 0.55 },
        ["Gold Foil"]  = { material = Enum.Material.Foil, reflectance = 0.50 },
        ["Plastic"]    = { material = Enum.Material.SmoothPlastic },
    }
    local materialNames = { "Neon","ForceField","Glass","Chrome","Ice","Diamond","Hologram","Ghost","Gold Foil","Plastic" }

    local cfg = {
        weapon = { enable=false, color=Color3.fromRGB(255,255,255), color2=Color3.fromRGB(255,255,255),
                   gradient=false, speed=1, material="Neon", transparency=0 },
        arm    = { enable=false, color=Color3.fromRGB(255,255,255), color2=Color3.fromRGB(255,255,255),
                   gradient=false, speed=1, material="Neon", transparency=0, invisible=false },
    }
    local gunPhase, armPhase = 0, 0
    local function lerpColor(a, b, t)
        return Color3.new(a.R+(b.R-a.R)*t, a.G+(b.G-a.G)*t, a.B+(b.B-a.B)*t)
    end
    -- ping-pong gradient between two colors
    local function gradColor(c1, c2, phase)
        local t = phase % 1
        if t > 0.5 then t = 1 - t end
        return lerpColor(c1, c2, t * 2)
    end

    local armKeywords = { "arm","hand","sleeve","elbow","wrist","shoulder","finger","thumb","glove" }
    local armCache = setmetatable({}, {__mode="k"})
    local function isArm(part)
        local c = armCache[part]
        if c ~= nil then return c end
        local result = false
        local name = string.lower(part.Name)
        for i = 1, #armKeywords do
            if string.find(name, armKeywords[i], 1, true) then result = true; break end
        end
        if not result then
            local a = part.Parent
            while a and a.Name ~= "FirstPerson" do
                local an = string.lower(a.Name)
                if string.find(an, "arm", 1, true) or string.find(an, "rig", 1, true) then result = true; break end
                a = a.Parent
            end
        end
        armCache[part] = result
        return result
    end

    local tracked = {}
    local function store(part)
        if not tracked[part] then
            local rec = { Material=part.Material, Color=part.Color, Reflectance=part.Reflectance,
                          Transparency=part.Transparency, LTM=part.LocalTransparencyModifier,
                          textures = {} }
            if part:IsA("MeshPart") then rec.TextureID = part.TextureID end
            -- remember texture/decal transparency so we can restore them
            for _, child in ipairs(part:GetChildren()) do
                if child:IsA("Texture") or child:IsA("Decal") then
                    rec.textures[child] = child.Transparency
                end
            end
            tracked[part] = rec
        end
    end
    local function restore(part)
        local s = tracked[part]
        if s then
            if part.Parent then
                pcall(function()
                    part.Material=s.Material; part.Color=s.Color; part.Reflectance=s.Reflectance
                    part.Transparency=s.Transparency; part.LocalTransparencyModifier=s.LTM
                    if part:IsA("MeshPart") and s.TextureID ~= nil then part.TextureID = s.TextureID end
                    for child, tr in pairs(s.textures) do
                        if child and child.Parent then child.Transparency = tr end
                    end
                end)
            end
            tracked[part] = nil
        end
    end
    local function clearAll()
        for p in pairs(tracked) do restore(p) end
        table.clear(tracked)
    end
    -- paint a clean cham: apply material/color AND hide the original textures/
    -- decals/surface appearance so the material shows cleanly (this is the fix
    -- for chams looking "off" — the gun's own texture was bleeding through).
    local function paint(part, presetName, color, transparency)
        local preset = materialPresets[presetName] or materialPresets["Neon"]
        pcall(function()
            part.Material = preset.material
            part.Reflectance = preset.reflectance or 0
            part.Transparency = math.clamp((preset.transparency or 0) + (transparency or 0), 0, 1)
            part.LocalTransparencyModifier = 0
            part.Color = color
            if part:IsA("MeshPart") then part.TextureID = "" end
            for _, child in ipairs(part:GetChildren()) do
                if child:IsA("Texture") or child:IsA("Decal") then
                    child.Transparency = 1
                elseif child:IsA("SurfaceAppearance") or child:IsA("WrapLayer") then
                    child:Destroy()
                elseif child:IsA("SpecialMesh") then
                    child.TextureId = ""
                    child.VertexColor = Vector3.new(color.R, color.G, color.B)
                end
            end
        end)
    end

    local function vmOwned()
        local fp = Workspace:FindFirstChild("ViewModels")
        fp = fp and fp:FindFirstChild("FirstPerson")
        if not fp then return nil end
        local char = localPlayer.Character
        if not char then return nil end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return nil end
        return fp
    end

    local last = 0
    RunService.Heartbeat:Connect(function()
        local wc, ac = cfg.weapon, cfg.arm
        if not (wc.enable or ac.enable) then
            if next(tracked) then clearAll() end
            return
        end
        local fp = vmOwned()
        if not fp then if next(tracked) then clearAll() end return end
        local now = tick()
        -- advance gradient phases every frame (independent of the 10hz apply)
        gunPhase = (gunPhase + (now - (last ~= 0 and last or now)) * (wc.speed or 1) * 0.5) % 1
        armPhase = (armPhase + (now - (last ~= 0 and last or now)) * (ac.speed or 1) * 0.5) % 1
        if now - last < 0.08 then return end   -- ~12hz apply throttle
        last = now
        local gunCol = wc.gradient and gradColor(wc.color, wc.color2, gunPhase) or wc.color
        local armCol = ac.gradient and gradColor(ac.color, ac.color2, armPhase) or ac.color
        for _, part in ipairs(fp:GetDescendants()) do
            if part:IsA("BasePart") and part.Transparency < 1 and part.Size.Magnitude < 40 then
                local arm = isArm(part)
                if arm and ac.enable then
                    store(part)
                    if ac.invisible then
                        pcall(function() part.LocalTransparencyModifier = 1; part.Transparency = 1 end)
                    else
                        paint(part, ac.material, armCol, ac.transparency)
                    end
                elseif (not arm) and wc.enable then
                    store(part)
                    paint(part, wc.material, gunCol, wc.transparency)
                else
                    restore(part)
                end
            end
        end
    end)

    -- UI: a tabbox on the visuals tab with weapon + arms sub-tabs
    local vmBox   = visualsTab:createTabbox('right')
    local wTab    = vmBox:addTab('gun chams')
    local aTab    = vmBox:addTab('arm chams')

    wTab:addToggle({text = "enable", flag = "GunChamsEnable", callback = function(v) cfg.weapon.enable = v end})
        :addColorpicker({text = "color", flag = "GunChamsColor", color = Color3.fromRGB(255,255,255),
            callback = function(v) cfg.weapon.color = v end})
        :addColorpicker({text = "color 2", flag = "GunChamsColor2", second = true, color = Color3.fromRGB(0,170,255),
            callback = function(v) cfg.weapon.color2 = v end})
    wTab:markStart()
    wTab:addList({text = "material", flag = "GunChamsMat", value = "Neon", values = materialNames,
        callback = function(v) cfg.weapon.material = v end})
    wTab:addToggle({text = "gradient", flag = "GunChamsGradient", callback = function(v) cfg.weapon.gradient = v end})
    wTab:addSlider({text = "gradient speed", flag = "GunChamsSpeed", value = 10, min = 1, max = 50,
        callback = function(v) cfg.weapon.speed = v/10 end})
    wTab:addSlider({text = "transparency %", flag = "GunChamsTrans", value = 0, min = 0, max = 100, suffix = "%",
        callback = function(v) cfg.weapon.transparency = v/100 end})
    wTab:dependsOn("GunChamsEnable")

    aTab:addToggle({text = "enable", flag = "ArmChamsEnable", callback = function(v) cfg.arm.enable = v end})
        :addColorpicker({text = "color", flag = "ArmChamsColor", color = Color3.fromRGB(255,255,255),
            callback = function(v) cfg.arm.color = v end})
        :addColorpicker({text = "color 2", flag = "ArmChamsColor2", second = true, color = Color3.fromRGB(0,170,255),
            callback = function(v) cfg.arm.color2 = v end})
    aTab:markStart()
    aTab:addList({text = "material", flag = "ArmChamsMat", value = "Neon", values = materialNames,
        callback = function(v) cfg.arm.material = v end})
    aTab:addToggle({text = "gradient", flag = "ArmChamsGradient", callback = function(v) cfg.arm.gradient = v end})
    aTab:addSlider({text = "gradient speed", flag = "ArmChamsSpeed", value = 10, min = 1, max = 50,
        callback = function(v) cfg.arm.speed = v/10 end})
    aTab:addSlider({text = "transparency %", flag = "ArmChamsTrans", value = 0, min = 0, max = 100, suffix = "%",
        callback = function(v) cfg.arm.transparency = v/100 end})
    aTab:addToggle({text = "invisible arms", flag = "ArmChamsInvisible", callback = function(v) cfg.arm.invisible = v end})
    aTab:dependsOn("ArmChamsEnable")
end)() -- end viewmodel chams block

-- ═══════════════════════════════════════════════════════════════════════════
-- NO ANIMATIONS (ported from take1.lua) — stops selected view-model animation
-- tracks (idle/reload/sprint/crouch/shoot/aim) under Workspace.ViewModels.
-- ═══════════════════════════════════════════════════════════════════════════
;(function()
    local enabled = false
    local blocked = {}          -- { Idle=true, Reloading=true, ... }
    local conns = {}
    local loop = nil

    local PATTERNS = {
        Idle       = { "idle" },
        Reloading  = { "reload" },
        Sprinting  = { "sprint" },
        Crouching  = { "crouch" },
        Shooting   = { "shoot", "fire", "shot" },
        Aiming     = { "aim", "ads", "scope" },
    }

    local function trackName(track)
        local parts = { string.lower(track.Name) }
        local anim = track.Animation
        if anim then
            parts[#parts+1] = string.lower(anim.Name)
            parts[#parts+1] = string.lower(tostring(anim.AnimationId))
        end
        return table.concat(parts, " ")
    end
    local function shouldBlock(track)
        if not enabled then return false end
        local name = trackName(track)
        for cat, pats in pairs(PATTERNS) do
            if blocked[cat] then
                for _, p in ipairs(pats) do
                    if string.find(name, p, 1, true) then return true end
                end
            end
        end
        return false
    end
    local function stopIfBlocked(track)
        if shouldBlock(track) then pcall(function() track:Stop(0) end) end
    end
    local function bindAnimator(animator)
        if typeof(animator) ~= "Instance" or not animator:IsA("Animator") then return end
        if animator:GetAttribute("riotsNoAnimBound") then return end
        animator:SetAttribute("riotsNoAnimBound", true)
        local parent = animator.Parent
        if parent and parent:IsA("Humanoid") then
            conns[#conns+1] = parent.AnimationPlayed:Connect(function(track)
                if enabled then task.defer(stopIfBlocked, track) end
            end)
        end
    end
    local function scan(root)
        if not root then return end
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("Animator") then
                bindAnimator(d)
                if enabled then
                    for _, t in ipairs(d:GetPlayingAnimationTracks()) do stopIfBlocked(t) end
                end
            end
        end
    end
    local function hookVM()
        local vm = Workspace:FindFirstChild("ViewModels")
        if not vm then return end
        local fp = vm:FindFirstChild("FirstPerson")
        if fp then
            scan(fp)
            if not vm:GetAttribute("riotsNoAnimVmHooked") then
                vm:SetAttribute("riotsNoAnimVmHooked", true)
                conns[#conns+1] = fp.DescendantAdded:Connect(function(d)
                    if d:IsA("Animator") then bindAnimator(d) end
                end)
            end
        end
    end
    local function stopLoop()
        if loop then loop:Disconnect(); loop = nil end
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        table.clear(conns)
        local vm = Workspace:FindFirstChild("ViewModels")
        if vm then
            vm:SetAttribute("riotsNoAnimVmHooked", nil)
            for _, d in ipairs(vm:GetDescendants()) do
                if d:IsA("Animator") then d:SetAttribute("riotsNoAnimBound", nil) end
            end
        end
    end
    local function startLoop()
        stopLoop()
        hookVM()
        loop = RunService.RenderStepped:Connect(function()
            if not enabled then return end
            hookVM()
            local vm = Workspace:FindFirstChild("ViewModels")
            local fp = vm and vm:FindFirstChild("FirstPerson")
            if not fp then return end
            for _, d in ipairs(fp:GetDescendants()) do
                if d:IsA("Animator") then
                    for _, t in ipairs(d:GetPlayingAnimationTracks()) do stopIfBlocked(t) end
                end
            end
        end)
    end
    local function update()
        if enabled then startLoop() else stopLoop() end
    end

    local naGroup = visualsTab:createGroup('right', 'no animations')
    naGroup:addToggle({text = "enable", flag = "NoAnimations", callback = function(v) enabled = v; update() end})
    naGroup:markStart()
    naGroup:addList({text = "disabled animations", flag = "NoAnimList", multiselect = true,
        values = { "Idle", "Reloading", "Sprinting", "Crouching", "Shooting", "Aiming" },
        callback = function(v)
            local t = {}
            if type(v) == "table" then for _, s in ipairs(v) do t[s] = true end end
            blocked = t
        end})
    naGroup:dependsOn("NoAnimations")
end)()

;(function() -- Lighting block: own local scope
local Lighting = game:GetService("Lighting")
_G.LightingSettings = _G.LightingSettings or {
    Enabled = false,
    Ambient = { Enabled = false, Color = Color3.fromRGB(255,255,255) },
    OutdoorAmbient = { Enabled = false, Color = Color3.fromRGB(255,255,255) },
    GlobalShadows = { Enabled = true },
    ShadowSoftness = { Enabled = false, Value = 0.2 },
    SunColor = { Enabled = false, Color = Color3.fromRGB(255,255,255) },
    ColorShiftTop = { Enabled = false, Color = Color3.fromRGB(255,255,255) },
    ColorShiftBottom = { Enabled = false, Color = Color3.fromRGB(255,255,255) },
    ClockTime = { Enabled = false, Value = 12 },
    GeographicLatitude = { Enabled = false, Value = 41.8 },
    Fog = { Enabled = false, Color = Color3.fromRGB(255,255,255), Start = 0, End = 100 },
    EnvironmentDiffuseScale = { Enabled = false, Value = 1 },
    EnvironmentSpecularScale = { Enabled = false, Value = 1 },
    ColorCorrection = { Enabled = false, Contrast = 0, Saturation = 0, Brightness = 0 },
    Bloom = { Enabled = false, Multiplier = 0.3, Threshold = 0.6, Size = 4 },
}
local LS = _G.LightingSettings
local origvalues = {}
local updateconn = nil
local extraColorCorrection = nil
local bloomOrigCache = {}

local function blendColor(base, tint, factor)
    return Color3.new(base.R+(tint.R-base.R)*factor, base.G+(tint.G-base.G)*factor, base.B+(tint.B-base.B)*factor)
end
local function applyBloomModifier()
    local b = LS.Bloom
    if not b then return end
    local mult = math.clamp(tonumber(b.Multiplier) or 1, 0, 1.5)
    for _, child in ipairs(Lighting:GetChildren()) do
        if child:IsA("BloomEffect") and child.Name ~= "riotsExtraBloom" then
            if not bloomOrigCache[child] then
                bloomOrigCache[child] = { Intensity=child.Intensity, Size=child.Size, Threshold=child.Threshold, Enabled=child.Enabled }
            end
            child.Enabled = false
        end
    end
    if b.Enabled then
        local eb = Lighting:FindFirstChild("riotsExtraBloom")
        if not eb then eb = Instance.new("BloomEffect"); eb.Name = "riotsExtraBloom"; eb.Parent = Lighting end
        eb.Intensity = mult * 0.8
        eb.Size = b.Size or 4
        eb.Threshold = b.Threshold or 0.7
        eb.Enabled = true
    else
        local eb = Lighting:FindFirstChild("riotsExtraBloom")
        if eb then eb:Destroy() end
        for c, base in pairs(bloomOrigCache) do
            if c.Parent then c.Intensity=base.Intensity; c.Size=base.Size; c.Threshold=base.Threshold; c.Enabled=base.Enabled end
        end
    end
end
local function ensureExtraEffects()
    local cc = LS.ColorCorrection
    if cc and cc.Enabled then
        if not extraColorCorrection or not extraColorCorrection.Parent then
            extraColorCorrection = Instance.new("ColorCorrectionEffect")
            extraColorCorrection.Name = "riotsExtraCC"
            extraColorCorrection.Parent = Lighting
        end
        extraColorCorrection.Contrast = cc.Contrast/10
        extraColorCorrection.Saturation = cc.Saturation/10
        extraColorCorrection.Brightness = cc.Brightness/10
        extraColorCorrection.Enabled = true
    elseif extraColorCorrection then
        extraColorCorrection.Enabled = false
    end
    applyBloomModifier()
end
local function storeorigvalues()
    origvalues.Ambient = Lighting.Ambient
    origvalues.OutdoorAmbient = Lighting.OutdoorAmbient
    origvalues.GlobalShadows = Lighting.GlobalShadows
    origvalues.ShadowSoftness = Lighting.ShadowSoftness
    origvalues.ColorShift_Top = Lighting.ColorShift_Top
    origvalues.ColorShift_Bottom = Lighting.ColorShift_Bottom
    origvalues.ClockTime = Lighting.ClockTime
    origvalues.GeographicLatitude = Lighting.GeographicLatitude
    origvalues.FogColor = Lighting.FogColor
    origvalues.FogStart = Lighting.FogStart
    origvalues.FogEnd = Lighting.FogEnd
    origvalues.EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale
    origvalues.EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale
end
storeorigvalues()

local function lightupdater()
    if updateconn then updateconn:Disconnect() end
    updateconn = RunService.RenderStepped:Connect(function()
        if not LS.Enabled then return end
        if LS.Ambient.Enabled then Lighting.Ambient = LS.Ambient.Color else Lighting.Ambient = origvalues.Ambient end
        if LS.SunColor.Enabled then
            local base = LS.OutdoorAmbient.Enabled and LS.OutdoorAmbient.Color or origvalues.OutdoorAmbient
            Lighting.OutdoorAmbient = blendColor(base, LS.SunColor.Color, 0.55)
        elseif LS.OutdoorAmbient.Enabled then Lighting.OutdoorAmbient = LS.OutdoorAmbient.Color
        else Lighting.OutdoorAmbient = origvalues.OutdoorAmbient end
        Lighting.GlobalShadows = (LS.GlobalShadows.Enabled ~= nil) and LS.GlobalShadows.Enabled or origvalues.GlobalShadows
        if LS.ShadowSoftness.Enabled then Lighting.ShadowSoftness = LS.ShadowSoftness.Value else Lighting.ShadowSoftness = origvalues.ShadowSoftness end
        if LS.SunColor.Enabled then Lighting.ColorShift_Top = LS.SunColor.Color
        elseif LS.ColorShiftTop.Enabled then Lighting.ColorShift_Top = LS.ColorShiftTop.Color
        else Lighting.ColorShift_Top = origvalues.ColorShift_Top end
        if LS.ColorShiftBottom.Enabled then Lighting.ColorShift_Bottom = LS.ColorShiftBottom.Color else Lighting.ColorShift_Bottom = origvalues.ColorShift_Bottom end
        if LS.ClockTime.Enabled then Lighting.ClockTime = LS.ClockTime.Value else Lighting.ClockTime = origvalues.ClockTime end
        if LS.GeographicLatitude.Enabled then Lighting.GeographicLatitude = LS.GeographicLatitude.Value else Lighting.GeographicLatitude = origvalues.GeographicLatitude end
        if LS.Fog.Enabled then Lighting.FogColor = LS.Fog.Color; Lighting.FogStart = LS.Fog.Start; Lighting.FogEnd = LS.Fog.End
        else Lighting.FogColor = origvalues.FogColor; Lighting.FogStart = origvalues.FogStart; Lighting.FogEnd = origvalues.FogEnd end
        if LS.EnvironmentDiffuseScale.Enabled then Lighting.EnvironmentDiffuseScale = LS.EnvironmentDiffuseScale.Value else Lighting.EnvironmentDiffuseScale = origvalues.EnvironmentDiffuseScale end
        if LS.EnvironmentSpecularScale.Enabled then Lighting.EnvironmentSpecularScale = LS.EnvironmentSpecularScale.Value else Lighting.EnvironmentSpecularScale = origvalues.EnvironmentSpecularScale end
    end)
end
local function stoplightupdater()
    if updateconn then updateconn:Disconnect(); updateconn = nil end
    Lighting.GlobalShadows = origvalues.GlobalShadows
    Lighting.ClockTime = origvalues.ClockTime
    Lighting.GeographicLatitude = origvalues.GeographicLatitude
    Lighting.FogColor = origvalues.FogColor
    Lighting.FogStart = origvalues.FogStart
    Lighting.FogEnd = origvalues.FogEnd
    Lighting.Ambient = origvalues.Ambient
    Lighting.OutdoorAmbient = origvalues.OutdoorAmbient
    Lighting.ShadowSoftness = origvalues.ShadowSoftness
    Lighting.ColorShift_Top = origvalues.ColorShift_Top
    Lighting.ColorShift_Bottom = origvalues.ColorShift_Bottom
    Lighting.EnvironmentDiffuseScale = origvalues.EnvironmentDiffuseScale
    Lighting.EnvironmentSpecularScale = origvalues.EnvironmentSpecularScale
    ensureExtraEffects()
end

local WHITE = Color3.fromRGB(255,255,255)
local lightGroup = visualsTab:createGroup('right', 'lighting')
lightGroup:addToggle({text = "enable", flag = "lighting_master",
    callback = function(v) LS.Enabled = v; if v then lightupdater() else stoplightupdater() end end})
lightGroup:addToggle({text = "custom ambient", flag = "lighting_ambient", callback = function(v) LS.Ambient.Enabled = v end})
    :addColorpicker({text = "ambient color", flag = "lighting_ambient_color", color = WHITE, callback = function(c) LS.Ambient.Color = c end})
lightGroup:addToggle({text = "custom outdoor ambient", flag = "lighting_outdoor", callback = function(v) LS.OutdoorAmbient.Enabled = v end})
    :addColorpicker({text = "outdoor color", flag = "lighting_outdoor_color", color = WHITE, callback = function(c) LS.OutdoorAmbient.Color = c end})
lightGroup:addToggle({text = "custom sun color", flag = "lighting_suncolor", callback = function(v) LS.SunColor.Enabled = v end})
    :addColorpicker({text = "sun color", flag = "lighting_suncolor_color", color = WHITE, callback = function(c) LS.SunColor.Color = c end})
lightGroup:addToggle({text = "global shadows", flag = "lighting_shadows", value = true, callback = function(v) LS.GlobalShadows.Enabled = v end})
lightGroup:addToggle({text = "custom fog", flag = "lighting_fog", callback = function(v) LS.Fog.Enabled = v end})
    :addColorpicker({text = "fog color", flag = "lighting_fog_color", color = WHITE, callback = function(c) LS.Fog.Color = c end})
lightGroup:markStart()
lightGroup:addSlider({text = "fog start", flag = "lighting_fogstart", value = 0, min = 0, max = 1000,
    callback = function(v) LS.Fog.Start = v end})
lightGroup:addSlider({text = "fog end", flag = "lighting_fogend", value = 100, min = 0, max = 5000,
    callback = function(v) LS.Fog.End = v end})
lightGroup:dependsOn("lighting_fog")
lightGroup:addToggle({text = "custom time", flag = "lighting_clocktime", callback = function(v) LS.ClockTime.Enabled = v end})
lightGroup:markStart()
lightGroup:addSlider({text = "hour", flag = "lighting_clocktime_value", value = 12, min = 0, max = 24,
    callback = function(v) LS.ClockTime.Value = v end})
lightGroup:dependsOn("lighting_clocktime")
lightGroup:addToggle({text = "custom shadow softness", flag = "lighting_shadowsoft", callback = function(v) LS.ShadowSoftness.Enabled = v end})
lightGroup:markStart()
lightGroup:addSlider({text = "shadow softness %", flag = "lighting_shadowsoft_val", value = 20, min = 0, max = 100, suffix = "%",
    callback = function(v) LS.ShadowSoftness.Value = v/100 end})
lightGroup:dependsOn("lighting_shadowsoft")

local colorTab = visualsTab:createGroup('right', 'color correction')

colorTab:addToggle({text = "enable", flag = "lighting_cc", callback = function(v) LS.ColorCorrection.Enabled = v; ensureExtraEffects() end})
colorTab:addSlider({text = "contrast", flag = "lighting_cc_contrast", value = 0, min = -10, max = 10,
    callback = function(v) LS.ColorCorrection.Contrast = v; if LS.ColorCorrection.Enabled then ensureExtraEffects() end end})
colorTab:addSlider({text = "saturation", flag = "lighting_cc_sat", value = 0, min = -10, max = 10,
    callback = function(v) LS.ColorCorrection.Saturation = v; if LS.ColorCorrection.Enabled then ensureExtraEffects() end end})
colorTab:addSlider({text = "brightness", flag = "lighting_cc_bright", value = 0, min = -10, max = 10,
    callback = function(v) LS.ColorCorrection.Brightness = v; if LS.ColorCorrection.Enabled then ensureExtraEffects() end end})

--[==[ CROSSHAIR REMOVED
do
-- ─── Crosshair ────────────────────────────────────────────────────────────────
getgenv().crosshair = getgenv().crosshair or {
    enabled      = false,
    type         = "static",      -- "static" | "pulse"
    color1       = Color3.fromRGB(255,42,42),
    color2       = Color3.fromRGB(255,120,120),
    spin         = false,
    spin_speed   = 150,
    radius       = 11,
    length       = 10,
    width        = 1.5,
    -- outline
    outline      = true,
    outline_color= Color3.fromRGB(0,0,0),
    outline_thick= 1,
    -- center dot
    dot          = false,
    dot_size     = 2,
    dot_color    = Color3.fromRGB(255,42,42),
    -- clean-look options
    tstyle       = false,     -- hides the top line for a cleaner "T" crosshair
    show_top     = true,
    show_bottom  = true,
    show_left    = true,
    show_right   = true,
    dynamic      = false,     -- expand gap while moving
    dynamic_amt  = 8,
    -- watermark (follows the crosshair, sits under the bottom line)
    watermark    = false,
}
local cc = getgenv().crosshair

-- 4 outline lines drawn first (behind), 4 main lines on top
local outlines = {}
for i=1,4 do
    local l = Drawing.new("Line"); l.Visible=false; l.ZIndex=1; outlines[i]=l
end
local lines = {}
for i=1,4 do
    local l = Drawing.new("Line"); l.Visible=false; l.ZIndex=2; lines[i]=l
end
-- center dot (+ its outline)
local dotOutline = Drawing.new("Circle"); dotOutline.Visible=false; dotOutline.Filled=true; dotOutline.NumSides=24; dotOutline.ZIndex=1
local dot = Drawing.new("Circle"); dot.Visible=false; dot.Filled=true; dot.NumSides=24; dot.ZIndex=2

-- pulse: oscillate gap between radius and radius+pulseAmp
local _pulseT = 0
local _pulseAmp = 6
local _spinRot = 0

local function solve(a, r)
    local rad = math.rad(a)
    return Vector2.new(math.sin(rad)*r, math.cos(rad)*r)
end

-- ─── crosshair watermark (wave effect) ─────────────────────────────────────
local cwGui = Instance.new("ScreenGui")
cwGui.Name = "riotsCrosshairWatermark"
cwGui.ResetOnSpawn = false; cwGui.IgnoreGuiInset = true
cwGui.DisplayOrder = 998000; cwGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() cwGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)

local CW_TEXT = "riots.wtf"
local CW_LEN  = #CW_TEXT
local cwLabels = {}
local cwFrame = Instance.new("Frame")
cwFrame.Name = "cwFrame"; cwFrame.BackgroundTransparency = 1
cwFrame.BorderSizePixel = 0; cwFrame.Size = UDim2.fromOffset(200, 30)
cwFrame.Position = UDim2.new(0.5, -100, 0, 6); cwFrame.Parent = cwGui
cwFrame.Visible = false

-- individual letter labels so each can shift Y independently
local LETTER_W = 12
for i = 1, CW_LEN do
    local ch = CW_TEXT:sub(i,i)
    local lbl = Instance.new("TextLabel")
    lbl.BackgroundTransparency = 1; lbl.BorderSizePixel = 0
    lbl.Size = UDim2.fromOffset(LETTER_W, 20)
    lbl.Position = UDim2.fromOffset((i-1)*LETTER_W, 0)
    lbl.Font = Enum.Font.Code; lbl.TextSize = 14
    lbl.TextStrokeTransparency = 0; lbl.Text = ch
    lbl.RichText = false; lbl.ZIndex = 3
    lbl.Parent = cwFrame
    cwLabels[i] = lbl
end

-- color gradient across letters: red -> light red
local function cwColor(t)
    local c1, c2 = Color3.fromRGB(255,42,42), Color3.fromRGB(255,140,140)
    return Color3.new(c1.R+(c2.R-c1.R)*t, c1.G+(c2.G-c1.G)*t, c1.B+(c2.B-c1.B)*t)
end

local _cwT = 0
RunService.RenderStepped:Connect(function(dt)
    _cwT = _cwT + dt
    cwFrame.Visible = cc.watermark and not menu.Enabled

    if cwFrame.Visible then
        local cam = Workspace.CurrentCamera
        local center = cam and (cam.ViewportSize / 2) or Vector2.new(960, 540)
        -- follow the crosshair: sit just under the bottom line
        local gap = cc.radius
        if cc.type == "pulse" then gap = cc.radius + _pulseAmp end
        local belowY = center.Y + gap + cc.length + 8
        local total  = (CW_LEN - 1) * LETTER_W
        cwFrame.Position = UDim2.fromOffset(math.floor(center.X - total/2), math.floor(belowY))
        for i = 1, CW_LEN do
            local phase = _cwT * 3 - (i-1) * 0.45
            local yOff  = math.sin(phase) * 3   -- wave amplitude ±3px
            cwLabels[i].Position = UDim2.fromOffset((i-1)*LETTER_W, 3 - yOff)
            cwLabels[i].TextColor3 = cwColor((i-1)/(CW_LEN-1))
        end
    end
end)

-- ─── crosshair render ────────────────────────────────────────────────────────
-- smoothed (slight delay) gap + spin so movement/pulse feels less jerky
local _smoothGap = cc.radius
local _smoothSpin = 0
RunService.RenderStepped:Connect(function(dt)
    if not cc.enabled or menu.Enabled then
        for i=1,4 do lines[i].Visible=false; outlines[i].Visible=false end
        dot.Visible=false; dotOutline.Visible=false
        return
    end
    local cam = Workspace.CurrentCamera
    if not cam then return end
    local pos = cam.ViewportSize / 2

    -- pulse mode: oscillate the target gap
    local targetGap = cc.radius
    if cc.type == "pulse" then
        _pulseT = _pulseT + dt * 3
        targetGap = cc.radius + math.abs(math.sin(_pulseT)) * _pulseAmp
    end

    -- spin target
    local targetSpin = _smoothSpin
    if cc.spin then
        _spinRot = _spinRot + cc.spin_speed * dt
        targetSpin = _spinRot
    else
        _spinRot = 0
        targetSpin = 0
    end

    -- dynamic: expand the gap while the character is moving
    if cc.dynamic then
        local ch = localPlayer.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        if hum and hum.MoveDirection.Magnitude > 0.1 then
            targetGap = targetGap + cc.dynamic_amt
        end
    end

    -- slight delay / smoothing toward the targets
    local a = math.clamp(dt * 14, 0, 1)
    _smoothGap  = _smoothGap  + (targetGap  - _smoothGap)  * a
    _smoothSpin = _smoothSpin + (targetSpin - _smoothSpin) * a
    local gap     = _smoothGap
    local spinOff = _smoothSpin

    local angles = {0, 90, 180, 270}
    local colors = {cc.color1, cc.color2, cc.color1, cc.color2}
    -- per-line visibility: [1]=top [2]=right [3]=bottom [4]=left; tstyle hides top
    local lineOn = {
        cc.show_top and not cc.tstyle,
        cc.show_right,
        cc.show_bottom,
        cc.show_left,
    }

    for i=1,4 do
        local l = lines[i]
        local o = outlines[i]
        if not lineOn[i] then
            l.Visible = false; o.Visible = false
        else
            local ang = angles[i] + spinOff
            local from = pos + solve(ang, gap)
            local to   = pos + solve(ang, gap + cc.length)

            -- outline (thicker, behind)
            if cc.outline then
                o.From = from; o.To = to
                o.Thickness = cc.width + cc.outline_thick * 2
                o.Color = cc.outline_color
                o.Visible = true
            else
                o.Visible = false
            end

            l.From = from; l.To = to
            l.Thickness = cc.width
            l.Color = colors[i]
            l.Visible = true
        end
    end

    -- center dot
    if cc.dot then
        dot.Position = pos
        dot.Radius = cc.dot_size
        dot.Color = cc.dot_color
        dot.Visible = true
        if cc.outline then
            dotOutline.Position = pos
            dotOutline.Radius = cc.dot_size + cc.outline_thick
            dotOutline.Color = cc.outline_color
            dotOutline.Visible = true
        else
            dotOutline.Visible = false
        end
    else
        dot.Visible = false
        dotOutline.Visible = false
    end
end)

-- ─── UI ──────────────────────────────────────────────────────────────────────
local crosshairGroup = visualsTab:createGroup('right', 'crosshair')
crosshairGroup:addToggle({text = "enable", flag = "crosshaireeee",
    callback = function(v) cc.enabled = v end})
    :addColorpicker({text = "color 1", flag = "CrosshairC1", color = Color3.fromRGB(255,42,42),
        callback = function(v) cc.color1 = v end})
    :addColorpicker({text = "color 2", flag = "CrosshairC2", second = true, color = Color3.fromRGB(255,120,120),
        callback = function(v) cc.color2 = v end})
crosshairGroup:markStart()
crosshairGroup:addList({text = "type", flag = "CrosshairType", value = "static",
    values = {"static", "pulse"},
    callback = function(v) cc.type = v end})
crosshairGroup:addSlider({text = "gap", flag = "crosshair_radius", value = 11, min = 0, max = 40,
    callback = function(v) cc.radius = v end})
crosshairGroup:addSlider({text = "length", flag = "crosshair_length", value = 10, min = 1, max = 40,
    callback = function(v) cc.length = v end})
crosshairGroup:addSlider({text = "thickness", flag = "crosshair_width", value = 2, min = 1, max = 10,
    callback = function(v) cc.width = v end})
crosshairGroup:addToggle({text = "spin", flag = "crosshair_spin",
    callback = function(v) cc.spin = v end})
crosshairGroup:addSlider({text = "spin amount", flag = "crosshair_spin_speed", value = 150, min = 0, max = 720,
    callback = function(v) cc.spin_speed = v end})
crosshairGroup:dependsOn("crosshaireeee")

crosshairGroup:addToggle({text = "outline", flag = "crosshair_outline", value = true,
    callback = function(v) cc.outline = v end})
    :addColorpicker({text = "outline color", flag = "CrosshairOutline", color = Color3.fromRGB(0,0,0),
        callback = function(v) cc.outline_color = v end})
crosshairGroup:markStart()
crosshairGroup:addSlider({text = "outline thickness", flag = "crosshair_outline_thick", value = 1, min = 1, max = 5,
    callback = function(v) cc.outline_thick = v end})
crosshairGroup:dependsOn("crosshair_outline")

crosshairGroup:addToggle({text = "center dot", flag = "crosshair_dot",
    callback = function(v) cc.dot = v end})
    :addColorpicker({text = "dot color", flag = "CrosshairDot", color = Color3.fromRGB(255,42,42),
        callback = function(v) cc.dot_color = v end})
crosshairGroup:markStart()
crosshairGroup:addSlider({text = "dot size", flag = "crosshair_dot_size", value = 2, min = 1, max = 10,
    callback = function(v) cc.dot_size = v end})
crosshairGroup:dependsOn("crosshair_dot")

crosshairGroup:addToggle({text = "t-style (no top line)", flag = "crosshair_tstyle",
    callback = function(v) cc.tstyle = v end})
crosshairGroup:addToggle({text = "dynamic (expand on move)", flag = "crosshair_dynamic",
    callback = function(v) cc.dynamic = v end})
crosshairGroup:markStart()
crosshairGroup:addSlider({text = "dynamic amount", flag = "crosshair_dynamic_amt", value = 8, min = 1, max = 30,
    callback = function(v) cc.dynamic_amt = v end})
crosshairGroup:dependsOn("crosshair_dynamic")

crosshairGroup:addToggle({text = "watermark (follows crosshair)", flag = "CrosshairWatermark",
    callback = function(v) cc.watermark = v end})
end
]==]

do
local Lighting = game:GetService("Lighting")
_G.SkyboxSettings = _G.SkyboxSettings or {
    Enabled = false, CurrentSkybox = "Default", DisabledElements = {},
}
-- large preset library ported from take.lua
local Skyboxes = {
    ["Default"] = { SkyboxBk = "rbxassetid://6444884337", SkyboxDn = "rbxassetid://6444884785", SkyboxFt = "rbxassetid://6444884337", SkyboxLf = "rbxassetid://6444884337", SkyboxRt = "rbxassetid://6444884337", SkyboxUp = "rbxassetid://6412503613" },
    ["Deep Space"] = { SkyboxBk = "rbxassetid://159248188", SkyboxDn = "rbxassetid://159248183", SkyboxFt = "rbxassetid://159248187", SkyboxLf = "rbxassetid://159248173", SkyboxRt = "rbxassetid://159248192", SkyboxUp = "rbxassetid://159248176" },
    ["One Piece"] = { SkyboxBk = "rbxassetid://158516797", SkyboxDn = "rbxassetid://158516788", SkyboxFt = "rbxassetid://158516797", SkyboxLf = "rbxassetid://158516797", SkyboxRt = "rbxassetid://158516797", SkyboxUp = "rbxassetid://158516792" },
    ["Matcha"] = { SkyboxBk = "rbxassetid://151165214", SkyboxDn = "rbxassetid://151165197", SkyboxFt = "rbxassetid://151165224", SkyboxLf = "rbxassetid://151165191", SkyboxRt = "rbxassetid://151165206", SkyboxUp = "rbxassetid://151165227" },
    ["Abyssal Blues"] = { SkyboxBk = "rbxassetid://16269815885", SkyboxDn = "rbxassetid://16269839652", SkyboxFt = "rbxassetid://16269798011", SkyboxLf = "rbxassetid://16269813852", SkyboxRt = "rbxassetid://16269814948", SkyboxUp = "rbxassetid://16269829700" },
    ["Pink Sky"] = { SkyboxBk = "rbxassetid://271042516", SkyboxDn = "rbxassetid://271077243", SkyboxFt = "rbxassetid://271042556", SkyboxLf = "rbxassetid://271042310", SkyboxRt = "rbxassetid://271042467", SkyboxUp = "rbxassetid://271077958" },
    ["Green Sky"] = { SkyboxBk = "rbxassetid://921882045", SkyboxDn = "rbxassetid://921881907", SkyboxFt = "rbxassetid://921882121", SkyboxLf = "rbxassetid://921881811", SkyboxRt = "rbxassetid://921881989", SkyboxUp = "rbxassetid://921882259" },
    ["Vaporwave"] = { SkyboxBk = "rbxassetid://1417494030", SkyboxDn = "rbxassetid://1417494146", SkyboxFt = "rbxassetid://1417494253", SkyboxLf = "rbxassetid://1417494402", SkyboxRt = "rbxassetid://1417494499", SkyboxUp = "rbxassetid://1417494643" },
    ["Minecraft"] = { SkyboxBk = "rbxassetid://1876545003", SkyboxDn = "rbxassetid://1876544331", SkyboxFt = "rbxassetid://1876542941", SkyboxLf = "rbxassetid://1876543392", SkyboxRt = "rbxassetid://1876543764", SkyboxUp = "rbxassetid://1876544642" },
    ["Red Night"] = { SkyboxBk = "rbxassetid://401664839", SkyboxDn = "rbxassetid://401664862", SkyboxFt = "rbxassetid://401664960", SkyboxLf = "rbxassetid://401664881", SkyboxRt = "rbxassetid://401664901", SkyboxUp = "rbxassetid://401664936" },
    ["Night"] = { SkyboxBk = "rbxassetid://48020371", SkyboxDn = "rbxassetid://48020144", SkyboxFt = "rbxassetid://48020234", SkyboxLf = "rbxassetid://48020211", SkyboxRt = "rbxassetid://48020254", SkyboxUp = "rbxassetid://48020383" },
    ["Space"] = { SkyboxBk = "rbxassetid://149397692", SkyboxDn = "rbxassetid://149397686", SkyboxFt = "rbxassetid://149397697", SkyboxLf = "rbxassetid://149397684", SkyboxRt = "rbxassetid://149397688", SkyboxUp = "rbxassetid://149397702" },
    ["Vibe Night"] = { SkyboxBk = "rbxassetid://5084575798", SkyboxDn = "rbxassetid://5084575916", SkyboxFt = "rbxassetid://5103949679", SkyboxLf = "rbxassetid://5103948542", SkyboxRt = "rbxassetid://5103948784", SkyboxUp = "rbxassetid://5084576400" },
    ["Purple Splash"] = { SkyboxBk = "rbxassetid://8539982183", SkyboxDn = "rbxassetid://8539981943", SkyboxFt = "rbxassetid://8539981721", SkyboxLf = "rbxassetid://8539981424", SkyboxRt = "rbxassetid://8539980766", SkyboxUp = "rbxassetid://8539981085" },
    ["Snowy"] = { SkyboxBk = "rbxassetid://155657655", SkyboxDn = "rbxassetid://155674246", SkyboxFt = "rbxassetid://155657609", SkyboxLf = "rbxassetid://155657671", SkyboxRt = "rbxassetid://155657619", SkyboxUp = "rbxassetid://155674931" },
    ["Sunset"] = { SkyboxBk = "rbxassetid://150939022", SkyboxDn = "rbxassetid://150939038", SkyboxFt = "rbxassetid://150939047", SkyboxLf = "rbxassetid://150939056", SkyboxRt = "rbxassetid://150939063", SkyboxUp = "rbxassetid://150939082" },
    ["Cartoon Sky"] = { SkyboxBk = "rbxassetid://6778646360", SkyboxDn = "rbxassetid://6778658683", SkyboxFt = "rbxassetid://6778648039", SkyboxLf = "rbxassetid://6778649136", SkyboxRt = "rbxassetid://6778650519", SkyboxUp = "rbxassetid://6778658364" },
    ["Anime"] = { SkyboxBk = "rbxassetid://7643700666", SkyboxDn = "rbxassetid://7643743687", SkyboxFt = "rbxassetid://7644304186", SkyboxLf = "rbxassetid://7644288724", SkyboxRt = "rbxassetid://7643700819", SkyboxUp = "rbxassetid://7643757404" },
    ["Hell Sky"] = { SkyboxBk = "rbxassetid://437430787", SkyboxDn = "rbxassetid://437430804", SkyboxFt = "rbxassetid://437430543", SkyboxLf = "rbxassetid://437430732", SkyboxRt = "rbxassetid://437430747", SkyboxUp = "rbxassetid://437430771" },
    ["Starry Night"] = { SkyboxBk = "rbxassetid://8291078911", SkyboxDn = "rbxassetid://8291077403", SkyboxFt = "rbxassetid://8291081613", SkyboxLf = "rbxassetid://8291074004", SkyboxRt = "rbxassetid://8291080353", SkyboxUp = "rbxassetid://8291075054" },
    ["Clear Day"] = { SkyboxBk = "rbxassetid://591058823", SkyboxDn = "rbxassetid://591059876", SkyboxFt = "rbxassetid://591058104", SkyboxLf = "rbxassetid://591057861", SkyboxRt = "rbxassetid://591057625", SkyboxUp = "rbxassetid://591059642" },
    ["Large Forest"] = { SkyboxBk = "rbxassetid://17428978603", SkyboxDn = "rbxassetid://17428977445", SkyboxFt = "rbxassetid://17428977114", SkyboxLf = "rbxassetid://17428978399", SkyboxRt = "rbxassetid://17428976828", SkyboxUp = "rbxassetid://17428976669" },
    ["Crimson"] = { SkyboxBk = "rbxassetid://15832429892", SkyboxDn = "rbxassetid://15832430998", SkyboxFt = "rbxassetid://15832430210", SkyboxLf = "rbxassetid://15832430671", SkyboxRt = "rbxassetid://15832431198", SkyboxUp = "rbxassetid://15832429401" },
    ["Pumpkin Hill"] = { SkyboxBk = "rbxassetid://11202510597", SkyboxDn = "rbxassetid://11202510255", SkyboxFt = "rbxassetid://11202509993", SkyboxLf = "rbxassetid://11202510806", SkyboxRt = "rbxassetid://11202511066", SkyboxUp = "rbxassetid://11202509704" },
    ["Desert"] = { SkyboxBk = "rbxassetid://161319957", SkyboxDn = "rbxassetid://161319965", SkyboxFt = "rbxassetid://161319970", SkyboxLf = "rbxassetid://161319983", SkyboxRt = "rbxassetid://161319989", SkyboxUp = "rbxassetid://161319996" },
    ["Earth Space"] = { SkyboxBk = "rbxassetid://15753305495", SkyboxDn = "rbxassetid://15753362674", SkyboxFt = "rbxassetid://15753305823", SkyboxLf = "rbxassetid://15753310707", SkyboxRt = "rbxassetid://15753304774", SkyboxUp = "rbxassetid://15753304473" },
    ["Underwater"] = { SkyboxBk = "rbxassetid://227635868", SkyboxDn = "rbxassetid://227635921", SkyboxFt = "rbxassetid://227635954", SkyboxLf = "rbxassetid://227635974", SkyboxRt = "rbxassetid://227635990", SkyboxUp = "rbxassetid://227636031" },
    ["Poison"] = { SkyboxBk = "rbxassetid://1370716695", SkyboxDn = "rbxassetid://1370716766", SkyboxFt = "rbxassetid://1370716833", SkyboxLf = "rbxassetid://1370716898", SkyboxRt = "rbxassetid://1370716955", SkyboxUp = "rbxassetid://1370717024" },
    ["Blue Space"] = { SkyboxBk = "rbxassetid://1127563035", SkyboxDn = "rbxassetid://1127563006", SkyboxFt = "rbxassetid://1127563026", SkyboxLf = "rbxassetid://1127563216", SkyboxRt = "rbxassetid://1127563115", SkyboxUp = "rbxassetid://1127562999" },
    ["Clouds"] = { SkyboxBk = "rbxassetid://570557514", SkyboxDn = "rbxassetid://570557775", SkyboxFt = "rbxassetid://570557559", SkyboxLf = "rbxassetid://570557620", SkyboxRt = "rbxassetid://570557672", SkyboxUp = "rbxassetid://570557727" },
    ["Elegant Morning"] = { SkyboxBk = "rbxassetid://153767241", SkyboxDn = "rbxassetid://153767216", SkyboxFt = "rbxassetid://153767266", SkyboxLf = "rbxassetid://153767200", SkyboxRt = "rbxassetid://153767231", SkyboxUp = "rbxassetid://153767288" },
    ["Fade Blue"] = { SkyboxBk = "rbxassetid://153695414", SkyboxDn = "rbxassetid://153695352", SkyboxFt = "rbxassetid://153695452", SkyboxLf = "rbxassetid://153695320", SkyboxRt = "rbxassetid://153695383", SkyboxUp = "rbxassetid://153695471" },
    ["Neptune"] = { SkyboxBk = "rbxassetid://218955819", SkyboxDn = "rbxassetid://218953419", SkyboxFt = "rbxassetid://218954524", SkyboxLf = "rbxassetid://218958493", SkyboxRt = "rbxassetid://218957134", SkyboxUp = "rbxassetid://218950090" },
    ["Night Sky"] = { SkyboxBk = "rbxassetid://12064107", SkyboxDn = "rbxassetid://12064152", SkyboxFt = "rbxassetid://12064121", SkyboxLf = "rbxassetid://12063984", SkyboxRt = "rbxassetid://12064115", SkyboxUp = "rbxassetid://12064131" },
    ["Purple Nebula"] = { SkyboxBk = "rbxassetid://159454299", SkyboxDn = "rbxassetid://159454296", SkyboxFt = "rbxassetid://159454293", SkyboxLf = "rbxassetid://159454286", SkyboxRt = "rbxassetid://159454300", SkyboxUp = "rbxassetid://159454288" },
    ["Setting Sun"] = { SkyboxBk = "rbxassetid://626460377", SkyboxDn = "rbxassetid://626460216", SkyboxFt = "rbxassetid://626460513", SkyboxLf = "rbxassetid://626473032", SkyboxRt = "rbxassetid://626458639", SkyboxUp = "rbxassetid://626460625" },
    ["Twilight"] = { SkyboxBk = "rbxassetid://264908339", SkyboxDn = "rbxassetid://264907909", SkyboxFt = "rbxassetid://264909420", SkyboxLf = "rbxassetid://264909758", SkyboxRt = "rbxassetid://264908886", SkyboxUp = "rbxassetid://264907379" },
    ["Vivid Skies"] = { SkyboxBk = "rbxassetid://271042516", SkyboxDn = "rbxassetid://271077243", SkyboxFt = "rbxassetid://271042556", SkyboxLf = "rbxassetid://271042310", SkyboxRt = "rbxassetid://271042467", SkyboxUp = "rbxassetid://271077958" },
    ["Elisium Sky"] = { SkyboxBk = "rbxassetid://1898724755", SkyboxDn = "rbxassetid://1898727189", SkyboxFt = "rbxassetid://1898722814", SkyboxLf = "rbxassetid://1898729298", SkyboxRt = "rbxassetid://1898741025", SkyboxUp = "rbxassetid://1898736761" },
}
_G.SkyboxSettings.Rotate = _G.SkyboxSettings.Rotate or false
_G.SkyboxSettings.RotateSpeed = _G.SkyboxSettings.RotateSpeed or 1
_G.SkyboxSettings.RotateMethod = _G.SkyboxSettings.RotateMethod or "Spin"
_G.SkyboxSettings.RotateDir = _G.SkyboxSettings.RotateDir or "Horizontal"
local skyboxconn, customSky
local function ormakeskybox()
    if not customSky then customSky = Instance.new("Sky"); customSky.Name = "riotsSkybox"; customSky.Parent = Lighting end
    return customSky
end
local function removecustomsky() if customSky then customSky:Destroy(); customSky = nil end end
local _skyRotTick = 0
local function skyboxupdater()
    if skyboxconn then skyboxconn:Disconnect() end
    skyboxconn = RunService.RenderStepped:Connect(function(dt)
        if not _G.SkyboxSettings.Enabled then removecustomsky(); return end
        local sky = ormakeskybox()
        local t = Skyboxes[_G.SkyboxSettings.CurrentSkybox] or Skyboxes.Default
        sky.SkyboxBk=t.SkyboxBk; sky.SkyboxDn=t.SkyboxDn; sky.SkyboxFt=t.SkyboxFt
        sky.SkyboxLf=t.SkyboxLf; sky.SkyboxRt=t.SkyboxRt; sky.SkyboxUp=t.SkyboxUp
        local de = _G.SkyboxSettings.DisabledElements
        sky.SunAngularSize = (de.Sun or table.find(de,"Sun")) and 0 or 20
        sky.MoonAngularSize = (de.Moon or table.find(de,"Moon")) and 0 or 11
        sky.StarCount = (de.Stars or table.find(de,"Stars")) and 0 or 3000
        -- rotation (ported from take.lua)
        if _G.SkyboxSettings.Rotate then
            _skyRotTick = _skyRotTick + dt * _G.SkyboxSettings.RotateSpeed * 0.5
            local angle = 0
            local m = _G.SkyboxSettings.RotateMethod
            if m == "Spin" then angle = (_skyRotTick * 20) % 360
            elseif m == "Wave" then angle = math.sin(_skyRotTick) * 180
            elseif m == "Alternate" then angle = math.abs((_skyRotTick * 40 % 720) - 360) - 180 end
            local d = _G.SkyboxSettings.RotateDir
            local v = Vector3.new(0,0,0)
            if d == "Horizontal" then v = Vector3.new(0, angle, 0)
            elseif d == "Vertical" then v = Vector3.new(angle, 0, 0)
            elseif d == "Diagonal" then v = Vector3.new(angle, angle, angle) end
            pcall(function() sky.SkyboxOrientation = v end)
        end
        for _, obj in pairs(Lighting:GetChildren()) do
            if obj:IsA("Sky") and obj ~= sky then obj:Destroy() end
        end
    end)
end
local function stopSkyboxUpdater() if skyboxconn then skyboxconn:Disconnect(); skyboxconn=nil end removecustomsky() end

local skyBox = worldTab:createTabbox('left')
local skyTab = skyBox:addTab('skybox')

local skyList = {}
for name in pairs(Skyboxes) do table.insert(skyList, name) end
table.sort(skyList)

skyTab:addToggle({text = "enable", flag = "skybox_master",
    callback = function(v) _G.SkyboxSettings.Enabled = v; if v then skyboxupdater() else stopSkyboxUpdater() end end})
skyTab:addList({text = "skybox", flag = "skybox_selection", value = "Default", values = skyList,
    callback = function(v) _G.SkyboxSettings.CurrentSkybox = v end})
skyTab:addToggle({text = "rotate", flag = "skybox_rotate",
    callback = function(v) _G.SkyboxSettings.Rotate = v end})
skyTab:addSlider({text = "rotate speed", flag = "skybox_rotate_speed", value = 1, min = 0, max = 100,
    callback = function(v) _G.SkyboxSettings.RotateSpeed = v end})
skyTab:addList({text = "rotate method", flag = "skybox_rotate_method", value = "Spin", values = {"Spin","Wave","Alternate"},
    callback = function(v) _G.SkyboxSettings.RotateMethod = v end})
skyTab:addList({text = "rotate direction", flag = "skybox_rotate_dir", value = "Horizontal", values = {"Horizontal","Vertical","Diagonal"},
    callback = function(v) _G.SkyboxSettings.RotateDir = v end})
end

do
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
_G.LightingSettings = _G.LightingSettings or {}
_G.LightingSettings.Atmosphere = _G.LightingSettings.Atmosphere or {
    Enabled=false, Density=12, Offset=0.25, Haze=8, Glare=0.6,
    Color=Color3.fromRGB(140,160,190), Decay=Color3.fromRGB(90,110,140),
    SoundEnabled=false, SelectedSound="None", SoundVolume=0.6,
}
local AT = _G.LightingSettings.Atmosphere
local curambientsound
local ambientSounds = { ["None"]=nil, ["Rain"]=132717551555191, ["Night"]=125710682931536,
    ["Birds Chirping"]=9112831327, ["Jungle Birds"]=9114892930, ["Campfire Crackling"]=109494611784143,
    ["Night Crickets"]=9112764040, ["Snow Storm"]=551546110 }
local function clearcustomatmo()
    for _, v in pairs(Lighting:GetChildren()) do
        if v:IsA("Atmosphere") and v.Name == "riotsAtmosphere" then v:Destroy() end
    end
end
local function applycustomatmo()
    clearcustomatmo()
    if not AT.Enabled then return end
    local atm = Instance.new("Atmosphere")
    atm.Name = "riotsAtmosphere"
    atm.Density=AT.Density; atm.Offset=AT.Offset; atm.Haze=AT.Haze; atm.Glare=AT.Glare
    atm.Color=AT.Color; atm.Decay=AT.Decay; atm.Parent=Lighting
end
local function playambientsound()
    if curambientsound then curambientsound:Stop(); curambientsound:Destroy(); curambientsound=nil end
    local id = ambientSounds[AT.SelectedSound]
    if not id or not AT.SoundEnabled then return end
    curambientsound = Instance.new("Sound")
    curambientsound.Name="riotsAmbient"; curambientsound.SoundId="rbxassetid://"..id
    curambientsound.Looped=true; curambientsound.Volume=AT.SoundVolume; curambientsound.Parent=SoundService
    pcall(function() curambientsound:Play() end)
end
RunService.Heartbeat:Connect(function()
    if AT.Enabled and not Lighting:FindFirstChild("riotsAtmosphere") then applycustomatmo() end
end)

local atmoBox = worldTab:createTabbox('right')
local atmoTab = atmoBox:addTab('atmosphere')
local ambienceTab = atmoBox:addTab('ambience')

atmoTab:addToggle({text = "enable", flag = "atmosphere_master",
    callback = function(v) AT.Enabled = v; applycustomatmo() end})
    :addColorpicker({text = "atmosphere color", flag = "atmosphere_color", color = Color3.fromRGB(140,160,190),
        callback = function(c) AT.Color = c; applycustomatmo() end})
    :addColorpicker({text = "decay color", flag = "atmosphere_decay", second = true, color = Color3.fromRGB(90,110,140),
        callback = function(c) AT.Decay = c; applycustomatmo() end})
atmoTab:addSlider({text = "density", flag = "atmosphere_density", value = 12, min = 0, max = 100,
    callback = function(v) AT.Density = v/10; applycustomatmo() end})
atmoTab:addSlider({text = "haze", flag = "atmosphere_haze", value = 8, min = 0, max = 10,
    callback = function(v) AT.Haze = v; applycustomatmo() end})
atmoTab:addSlider({text = "glare", flag = "atmosphere_glare", value = 6, min = 0, max = 10,
    callback = function(v) AT.Glare = v/10; applycustomatmo() end})

ambienceTab:addToggle({text = "enable", flag = "ambience_master",
    callback = function(v) AT.SoundEnabled = v; playambientsound() end})
ambienceTab:addList({text = "sound", flag = "ambience_sound", value = "None",
    values = {"None","Rain","Night","Birds Chirping","Jungle Birds","Campfire Crackling","Night Crickets","Snow Storm"},
    callback = function(v) AT.SelectedSound = v; playambientsound() end})
ambienceTab:addSlider({text = "volume %", flag = "ambience_volume", value = 60, min = 0, max = 100, suffix = "%",
    callback = function(v) AT.SoundVolume = v/100; if curambientsound then curambientsound.Volume = v/100 end end})
end

do
local hitCfg = { enabled=false, removeDefault=false, style="rust", volume=50, pitch=100 }
-- sound library ported from take.lua (the "better" script)
local hitSoundIds = {
    ["windows xp"]                = "rbxassetid://108009100115241",
    ["minecraft bow"]             = "rbxassetid://3442683707",
    ["neverlose"]                 = "rbxassetid://97643101798871",
    ["steve"]                     = "rbxassetid://132883456216684",
    ["among us"]                  = "rbxassetid://93866204681438",
    ["bonk"]                      = "rbxassetid://5766898159",
    ["rust"]                      = "rbxassetid://1255040462",
    ["fatality"]                  = "rbxassetid://6534947869",
    ["hitmarker"]                 = "rbxassetid://133749572213659",
    ["csgo"]                      = "rbxassetid://5764885315",
    ["minecraft success bow hit"] = "rbxassetid://131197435969853",
}
local hitSoundList = {
    "rust","hitmarker","csgo","neverlose","fatality","bonk","among us",
    "steve","windows xp","minecraft bow","minecraft success bow hit",
}
local lastHitAt = 0
local function playHS()
    if not hitCfg.enabled then return end
    local sid = hitSoundIds[hitCfg.style] or hitSoundIds["rust"]
    local s = Instance.new("Sound")
    s.SoundId = sid
    s.Volume = math.clamp(hitCfg.volume/100, 0, 1) * 3   -- take uses 0-5 range; scale up
    s.PlaybackSpeed = math.clamp(hitCfg.pitch/100, 0.1, 3)
    s.RollOffMaxDistance = 1e9; s.RollOffMinDistance = 1e9
    s.Parent = Workspace.CurrentCamera or Workspace
    pcall(function() s:Play() end)
    task.delay(5, function() if s and s.Parent then s:Destroy() end end)
end

-- subscribe to the shared hitmarker hook (ClientViewModel.PlayHitmarkerSound,
-- wired once at library setup with the correct module path). Returning true
-- suppresses the game's default hitsound when "remove default" is on.
library:onHitmarker(function()
    if not hitCfg.enabled then return end
    lastHitAt = tick()
    pcall(playHS)
    return hitCfg.removeDefault
end)
-- also fire on the reliable billboard detection (ported from take1.lua). Dedupe
-- against the hitmarker hook so a single hit doesn't play the sound twice.
library:onHitBillboard(function()
    if not hitCfg.enabled then return end
    if tick() - lastHitAt < 0.06 then return end
    lastHitAt = tick()
    pcall(playHS)
end)
local hitSoundsGroup = worldTab:createGroup('right', 'hit sounds')
hitSoundsGroup:addToggle({text = "enable", flag = "HitSounds", callback = function(v) hitCfg.enabled = v end})
hitSoundsGroup:markStart()
hitSoundsGroup:addToggle({text = "remove default hitsound", flag = "HitSoundRemoveDefault",
    callback = function(v) hitCfg.removeDefault = v end})
hitSoundsGroup:addList({text = "sound", flag = "HitSoundStyle", value = "rust",
    values = hitSoundList,
    callback = function(v) hitCfg.style = v end})
hitSoundsGroup:addSlider({text = "volume", flag = "HitSoundVolume", value = 50, min = 0, max = 100,
    callback = function(v) hitCfg.volume = v end})
hitSoundsGroup:addSlider({text = "pitch", flag = "HitSoundPitch", value = 100, min = 50, max = 200,
    callback = function(v) hitCfg.pitch = v end})
hitSoundsGroup:dependsOn("HitSounds")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- HIT EFFECTS (ported from take1.lua) — spawns a visual burst at the hit part
-- when you land a hit. Wired to the reliable BillboardGui detection.
-- ═══════════════════════════════════════════════════════════════════════════
do
    local hitFxCfg = {
        enabled   = false,
        color     = Color3.fromRGB(159, 133, 195),
        styles    = { Particles = true },
        aliveScale = 1,
    }

    local function fxPart(adornee)
        if not adornee then return nil end
        if adornee:IsA("BasePart") then return adornee end
        if adornee:IsA("Attachment") then return adornee.Parent end
        if adornee:IsA("Model") and adornee.PrimaryPart then return adornee.PrimaryPart end
        return nil
    end
    local function scaleDur(s) return s * (hitFxCfg.aliveScale or 1) end

    -- expanding neon ring (cylinder), like take1 spawnHitRing
    local function spawnRing(part, color, startSize, endSize, dur, startTrans)
        local ring = Instance.new("Part")
        ring.Shape = Enum.PartType.Cylinder
        ring.Anchored = true; ring.CanCollide = false; ring.CanQuery = false; ring.CanTouch = false
        ring.Material = Enum.Material.Neon; ring.Color = color
        ring.Transparency = startTrans or 0.35
        ring.Size = Vector3.new(0.05, startSize, startSize)
        ring.CFrame = part.CFrame * CFrame.Angles(0, 0, math.rad(90))
        ring.Parent = Workspace.CurrentCamera
        local d = scaleDur(dur or 0.55)
        tweenService:Create(ring, TweenInfo.new(d, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Size = Vector3.new(0.05, endSize, endSize), Transparency = 1 }):Play()
        task.delay(d + 0.1, function() if ring and ring.Parent then ring:Destroy() end end)
    end

    -- point-light flash
    local function spawnFlash(part, color, brightness, range, dur)
        local light = Instance.new("PointLight")
        light.Color = color; light.Brightness = brightness or 6; light.Range = range or 14
        light.Parent = part
        local d = scaleDur(dur or 0.35)
        tweenService:Create(light, TweenInfo.new(d, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            { Brightness = 0, Range = 0 }):Play()
        task.delay(d + 0.05, function() if light and light.Parent then light:Destroy() end end)
    end

    -- generic particle burst
    local function burst(part, cfg)
        local e = Instance.new("ParticleEmitter")
        e.Texture = cfg.texture or "rbxassetid://6603835352"
        e.Color = typeof(cfg.color) == "ColorSequence" and cfg.color or ColorSequence.new(cfg.color or hitFxCfg.color)
        e.LightEmission = cfg.lightEmission or 1
        e.Brightness = cfg.brightness or 8
        e.LightInfluence = 0
        e.Orientation = Enum.ParticleOrientation.FacingCamera
        e.LockedToPart = false
        e.Size = cfg.size or NumberSequence.new(0.12)
        e.Transparency = cfg.transparency or NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
        e.Speed = cfg.speed or NumberRange.new(12, 18)
        e.SpreadAngle = cfg.spread or Vector2.new(120, 120)
        e.EmissionDirection = cfg.dir or Enum.NormalId.Top
        local lt = cfg.life or NumberRange.new(0.6, 1.2)
        local sc = hitFxCfg.aliveScale or 1
        e.Lifetime = NumberRange.new(lt.Min * sc, lt.Max * sc)
        e.Drag = cfg.drag or 2
        e.Acceleration = cfg.accel or Vector3.new(0, 4, 0)
        e.RotSpeed = cfg.rotSpeed or NumberRange.new(0, 0)
        e.Rate = 0
        e.Parent = part
        e:Emit(cfg.emit or 42)
        task.delay(scaleDur(cfg.cleanup or 4), function() if e and e.Parent then e:Destroy() end end)
    end

    local function blend(c, a) a = a or 0.35; return Color3.new(
        math.clamp(c.R + a, 0, 1), math.clamp(c.G + a * 0.5, 0, 1), math.clamp(c.B + a * 0.25, 0, 1)) end
    local function darken(c, a) a = a or 0.45; return Color3.new(
        math.clamp(c.R - a, 0, 1), math.clamp(c.G - a, 0, 1), math.clamp(c.B - a * 0.5, 0, 1)) end

    -- style handlers
    local handlers = {}
    handlers.Particles = function(part, color)
        burst(part, { color = color, emit = 46, speed = NumberRange.new(22, 29), brightness = 13, drag = 3.2,
            size = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.09), NumberSequenceKeypoint.new(0.5,0.135), NumberSequenceKeypoint.new(1,0.068) }),
            life = NumberRange.new(4, 4.1), accel = Vector3.new(0,5,0) })
    end
    handlers.Shockwave = function(part, color)
        spawnRing(part, color, 0.35, 6, 0.5, 0.2)
        spawnFlash(part, color, 5, 12, 0.35)
    end
    handlers.Lightning = function(part, color)
        burst(part, { color = color, texture = "rbxassetid://446111271", emit = 18, brightness = 16,
            speed = NumberRange.new(30, 45), spread = Vector2.new(180,180), life = NumberRange.new(0.25,0.4),
            size = NumberSequence.new(0.8), rotSpeed = NumberRange.new(-200,200) })
        spawnFlash(part, color, 8, 16, 0.25)
    end
    handlers.Blood = function(part, color)
        local c = darken(Color3.fromRGB(200, 0, 0), 0)
        burst(part, { color = c, emit = 40, brightness = 1, lightEmission = 0, speed = NumberRange.new(14,26),
            drag = 5, accel = Vector3.new(0,-18,0), life = NumberRange.new(0.5,0.9), size = NumberSequence.new(0.18) })
    end
    handlers.Fire = function(part, color)
        burst(part, { color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255,200,60)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255,60,0)) }), emit = 36, brightness = 14,
            speed = NumberRange.new(8,16), accel = Vector3.new(0,16,0), life = NumberRange.new(0.5,0.9),
            size = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.35), NumberSequenceKeypoint.new(1,0.05) }) })
        spawnFlash(part, Color3.fromRGB(255,120,0), 6, 14, 0.4)
    end
    handlers.Ice = function(part, color)
        burst(part, { color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(180,240,255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(90,160,255)) }), emit = 30, brightness = 10,
            speed = NumberRange.new(16,24), life = NumberRange.new(0.6,1), size = NumberSequence.new(0.16),
            rotSpeed = NumberRange.new(-120,120) })
    end
    handlers.Hearts = function(part, color)
        burst(part, { color = color, texture = "rbxassetid://7546931297", emit = 20, brightness = 6,
            speed = NumberRange.new(6,12), accel = Vector3.new(0,10,0), life = NumberRange.new(0.8,1.4),
            size = NumberSequence.new(0.4), drag = 3 })
    end
    handlers.Stars = function(part, color)
        burst(part, { color = color, texture = "rbxassetid://6588564340", emit = 28, brightness = 12,
            speed = NumberRange.new(18,30), life = NumberRange.new(0.5,1), size = NumberSequence.new(0.3),
            rotSpeed = NumberRange.new(-160,160), spread = Vector2.new(160,160) })
    end
    handlers.Sparks = function(part, color)
        burst(part, { color = blend(color, 0.4), emit = 34, brightness = 15, speed = NumberRange.new(28,44),
            drag = 6, accel = Vector3.new(0,-10,0), life = NumberRange.new(0.3,0.6),
            size = NumberSequence.new({ NumberSequenceKeypoint.new(0,0.14), NumberSequenceKeypoint.new(1,0) }) })
        spawnFlash(part, color, 6, 12, 0.2)
    end
    handlers.Neon = function(part, color)
        spawnRing(part, color, 0.3, 4, 0.45, 0.1)
        burst(part, { color = color, emit = 24, brightness = 18, speed = NumberRange.new(10,18),
            life = NumberRange.new(0.4,0.8), size = NumberSequence.new(0.2) })
    end
    handlers.Confetti = function(part, color)
        burst(part, { color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255,80,80)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(80,255,120)), ColorSequenceKeypoint.new(1, Color3.fromRGB(80,140,255)) }),
            emit = 40, brightness = 6, speed = NumberRange.new(16,28), accel = Vector3.new(0,-14,0),
            life = NumberRange.new(0.8,1.4), size = NumberSequence.new(0.16), rotSpeed = NumberRange.new(-200,200) })
    end

    local styleNames = { "Particles","Shockwave","Lightning","Blood","Fire","Ice","Hearts","Stars","Sparks","Neon","Confetti" }

    library:onHitBillboard(function(info)
        if not hitFxCfg.enabled then return end
        local part = fxPart(info.adornee)
        if not part then return end
        for name, on in pairs(hitFxCfg.styles) do
            local styleName = (type(name) == "number") and on or name
            if (type(name) == "number") or on == true then
                local h = handlers[styleName]
                if h then pcall(h, part, hitFxCfg.color) end
            end
        end
    end)

    local fxGroup = worldTab:createGroup('right', 'hit effects')
    fxGroup:addToggle({text = "enable", flag = "HitEffects", callback = function(v) hitFxCfg.enabled = v end})
        :addColorpicker({text = "color", flag = "HitEffectColor", color = Color3.fromRGB(159,133,195),
            callback = function(v) hitFxCfg.color = v end})
    fxGroup:markStart()
    fxGroup:addList({text = "style", flag = "HitEffectStyle", value = { "Particles" }, multiselect = true,
        values = styleNames,
        callback = function(v)
            local t = {}
            if type(v) == "table" then for _, s in ipairs(v) do t[s] = true end
            elseif type(v) == "string" then t[v] = true end
            hitFxCfg.styles = t
        end})
    fxGroup:addSlider({text = "alive time", flag = "HitEffectAlive", value = 28, min = 5, max = 80, suffix = "",
        callback = function(v) hitFxCfg.aliveScale = (v/10) / 2.8 end})
    fxGroup:dependsOn("HitEffects")
end
end)() -- close Lighting IIFE



_G.Features = _G.Features or {}

do
_G.Features.SlideBoost = _G.Features.SlideBoost or { Enabled = false, Speed = 200 }
task.spawn(function()
    local mech
    while true do
        local ok, res = pcall(function()
            return require(localPlayer.PlayerScripts.Controllers.MechanicsController)
        end)
        if ok and res then mech = res; break end
        task.wait(1)
    end
    RunService.RenderStepped:Connect(function()
        if _G.Features.SlideBoost.Enabled and mech and mech.IsSliding then
            pcall(function()
                mech._sliding_velocity.Velocity = mech._sliding_velocity.Velocity.Unit * _G.Features.SlideBoost.Speed
            end)
        end
    end)
end)
local slideGroup = miscTab:createGroup('right', 'slide boost')
slideGroup:addToggle({text = "enable", flag = "slide_boost", callback = function(v) _G.Features.SlideBoost.Enabled = v end})
slideGroup:markStart()
slideGroup:addSlider({text = "slide speed", flag = "slide_speed", value = 200, min = 50, max = 1000,
    callback = function(v) _G.Features.SlideBoost.Speed = v end})
slideGroup:dependsOn("slide_boost")
end -- end SlideBoost block

;(function() -- SmoothTextures block: own local scope
_G.Features.SmoothTextures = _G.Features.SmoothTextures or { Enabled = false }
_G.Features.WorldTextures = _G.Features.WorldTextures or { Dark = false }

local smoothOrig = {}
local smoothConn
local function smoothInst(inst)
    if not inst:IsA("BasePart") then return end
    if smoothOrig[inst] ~= nil then return end
    smoothOrig[inst] = inst.Material
    pcall(function() inst.Material = Enum.Material.SmoothPlastic end)
end
local function applySmooth()
    -- chunked scan so we never freeze the frame on large workspaces
    local all = Workspace:GetDescendants()
    task.spawn(function()
        for i, inst in ipairs(all) do
            if not _G.Features.SmoothTextures.Enabled then return end
            smoothInst(inst)
            if i % 600 == 0 then task.wait() end
        end
    end)
    if smoothConn then smoothConn:Disconnect() end
    smoothConn = Workspace.DescendantAdded:Connect(function(inst)
        task.defer(function() if _G.Features.SmoothTextures.Enabled then smoothInst(inst) end end)
    end)
end
local function restoreSmooth()
    if smoothConn then smoothConn:Disconnect(); smoothConn = nil end
    for inst, mat in pairs(smoothOrig) do
        if inst and inst.Parent then pcall(function() inst.Material = mat end) end
    end
    table.clear(smoothOrig)
end

local function darkenColor(c)
    if not c then return Color3.new(0.2,0.2,0.2) end
    return Color3.new(c.R*0.45, c.G*0.45, c.B*0.45)
end
local darkOrig = {}
local darkConn
local function darkInst(inst)
    if not inst:IsA("BasePart") then return end
    if darkOrig[inst] ~= nil then return end
    darkOrig[inst] = inst.Color
    pcall(function() inst.Color = darkenColor(inst.Color) end)
end
local function applyDark()
    -- chunked scan so we never freeze the frame on large workspaces
    local all = Workspace:GetDescendants()
    task.spawn(function()
        for i, inst in ipairs(all) do
            if not _G.Features.WorldTextures.Dark then return end
            darkInst(inst)
            if i % 600 == 0 then task.wait() end
        end
    end)
    if darkConn then darkConn:Disconnect() end
    darkConn = Workspace.DescendantAdded:Connect(function(inst)
        task.defer(function() if _G.Features.WorldTextures.Dark then darkInst(inst) end end)
    end)
end
local function restoreDark()
    if darkConn then darkConn:Disconnect(); darkConn = nil end
    for inst, col in pairs(darkOrig) do
        if inst and inst.Parent then pcall(function() inst.Color = col end) end
    end
    table.clear(darkOrig)
end

_G.Features.FpsBoost = _G.Features.FpsBoost or { Enabled = false }

local fpsHidden = {}
local fpsMat = {}
local fpsConn

local function fpsStrip(inst)

    if inst:IsA("Decal") or inst:IsA("Texture") then
        if fpsHidden[inst] == nil then fpsHidden[inst] = inst.Transparency end
        pcall(function() inst.Transparency = 1 end)
    elseif inst:IsA("SurfaceAppearance") then

        if fpsHidden[inst] == nil then
            fpsHidden[inst] = { parent = inst.Parent, clone = inst:Clone() }
            pcall(function() inst:Destroy() end)
        end
    elseif inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Beam")
        or inst:IsA("Smoke") or inst:IsA("Fire") or inst:IsA("Sparkles") then
        if fpsHidden[inst] == nil then fpsHidden[inst] = inst.Enabled end
        pcall(function() inst.Enabled = false end)
    elseif inst:IsA("BasePart") then
        if fpsMat[inst] == nil then fpsMat[inst] = inst.Material end
        pcall(function() inst.Material = Enum.Material.Plastic end)
    end
end

local function applyFps()

    local all = game:GetDescendants()
    task.spawn(function()
        for i, inst in ipairs(all) do
            if not _G.Features.FpsBoost.Enabled then return end
            fpsStrip(inst)
            if i % 800 == 0 then task.wait() end
        end
    end)
    if fpsConn then fpsConn:Disconnect() end
    fpsConn = game.DescendantAdded:Connect(function(inst)
        task.defer(function() if _G.Features.FpsBoost.Enabled then fpsStrip(inst) end end)
    end)

    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Level01 end)
end

local function restoreFps()
    if fpsConn then fpsConn:Disconnect(); fpsConn = nil end
    for inst, val in pairs(fpsHidden) do
        if typeof(val) == "table" then

            if val.clone and val.parent and val.parent.Parent then
                pcall(function() val.clone.Parent = val.parent end)
            end
        elseif inst and inst.Parent then
            if inst:IsA("Decal") or inst:IsA("Texture") then
                pcall(function() inst.Transparency = val end)
            else
                pcall(function() inst.Enabled = val end)
            end
        end
    end
    for part, mat in pairs(fpsMat) do
        if part and part.Parent then pcall(function() part.Material = mat end) end
    end
    table.clear(fpsHidden)
    table.clear(fpsMat)
    pcall(function() settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic end)
end

local texturesGroup = miscTab:createGroup('left', 'textures')
texturesGroup:addToggle({text = "fps boost (no textures)", flag = "fps_boost",
    callback = function(v) _G.Features.FpsBoost.Enabled = v; if v then applyFps() else restoreFps() end end})
texturesGroup:addToggle({text = "smooth textures", flag = "smooth_textures",
    callback = function(v) _G.Features.SmoothTextures.Enabled = v; if v then applySmooth() else restoreSmooth() end end})
texturesGroup:addToggle({text = "dark textures", flag = "dark_textures",
    callback = function(v) _G.Features.WorldTextures.Dark = v; if v then applyDark() else restoreDark() end end})
end)() -- close SmoothTextures IIFE

-- ═══════════════════════════════════════════════════════════════════════════
-- optimizations (ported from take.lua) — own IIFE scope, misc tab
-- ═══════════════════════════════════════════════════════════════════════════
;(function()
    local Lighting = game:GetService("Lighting")
    local opt = { no_particles=false, no_shadows=false, no_postfx=false,
                  low_quality=false, no_atmosphere=false, fps_cap_enable=false, fps_cap=60 }
    local particle_classes = { ParticleEmitter=true, Trail=true, Smoke=true, Fire=true, Sparkles=true }
    local post_classes = { BloomEffect=true, BlurEffect=true, ColorCorrectionEffect=true,
                           SunRaysEffect=true, DepthOfFieldEffect=true }
    local particle_saved = setmetatable({}, {__mode="k"})
    local post_saved = setmetatable({}, {__mode="k"})
    local orig_shadows, orig_quality, orig_atmo
    local shadows_saved, quality_saved, atmo_saved = false, false, false

    local function applyParticle(inst, on)
        if not particle_classes[inst.ClassName] then return end
        if on then
            if particle_saved[inst] == nil then particle_saved[inst] = inst.Enabled end
            pcall(function() inst.Enabled = false end)
        elseif particle_saved[inst] ~= nil then
            pcall(function() inst.Enabled = particle_saved[inst] end); particle_saved[inst] = nil
        end
    end
    local function applyPost(inst, on)
        if not post_classes[inst.ClassName] then return end
        if on then
            if post_saved[inst] == nil then post_saved[inst] = inst.Enabled end
            pcall(function() inst.Enabled = false end)
        elseif post_saved[inst] ~= nil then
            pcall(function() inst.Enabled = post_saved[inst] end); post_saved[inst] = nil
        end
    end
    local scanning = false
    local function scanWorkspace()
        if scanning then return end
        scanning = true
        task.spawn(function()
            local list = Workspace:GetDescendants()
            for i = 1, #list do
                applyParticle(list[i], opt.no_particles)
                if i % 800 == 0 then task.wait() end
            end
            scanning = false
        end)
    end
    local function scanLighting()
        for _, inst in ipairs(Lighting:GetDescendants()) do applyPost(inst, opt.no_postfx) end
    end
    local function applyShadows()
        if opt.no_shadows then
            if not shadows_saved then orig_shadows = Lighting.GlobalShadows; shadows_saved = true end
            pcall(function() Lighting.GlobalShadows = false end)
        elseif shadows_saved then
            pcall(function() Lighting.GlobalShadows = orig_shadows end); shadows_saved = false
        end
    end
    local function applyQuality()
        pcall(function()
            local render = settings().Rendering
            if opt.low_quality then
                if not quality_saved then orig_quality = render.QualityLevel; quality_saved = true end
                render.QualityLevel = Enum.QualityLevel.Level01
            elseif quality_saved then
                render.QualityLevel = orig_quality; quality_saved = false
            end
        end)
    end
    local function applyAtmosphere()
        local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
        if opt.no_atmosphere then
            if atmo then
                if not atmo_saved then orig_atmo = atmo.Density; atmo_saved = true end
                pcall(function() atmo.Density = 0 end)
            end
            local clouds = Workspace:FindFirstChild("Terrain") and Workspace.Terrain:FindFirstChildOfClass("Clouds")
            if clouds then pcall(function() clouds.Enabled = false end) end
        else
            if atmo and atmo_saved then pcall(function() atmo.Density = orig_atmo end); atmo_saved = false end
            local clouds = Workspace:FindFirstChild("Terrain") and Workspace.Terrain:FindFirstChildOfClass("Clouds")
            if clouds then pcall(function() clouds.Enabled = true end) end
        end
    end
    local function applyFpsCap()
        if not setfpscap then return end
        pcall(setfpscap, opt.fps_cap_enable and opt.fps_cap or 1000)
    end

    Workspace.DescendantAdded:Connect(function(inst)
        if opt.no_particles then task.defer(applyParticle, inst, true) end
    end)
    Lighting.DescendantAdded:Connect(function(inst)
        if opt.no_postfx then task.defer(applyPost, inst, true) end
    end)

    local optGroup = miscTab:createGroup('left', 'optimizations')
    optGroup:addToggle({text = "no particles & effects", flag = "opt_no_particles",
        callback = function(v) opt.no_particles = v; scanWorkspace() end})
    optGroup:addToggle({text = "disable shadows", flag = "opt_no_shadows",
        callback = function(v) opt.no_shadows = v; applyShadows() end})
    optGroup:addToggle({text = "disable post processing", flag = "opt_no_postfx",
        callback = function(v) opt.no_postfx = v; scanLighting() end})
    optGroup:addToggle({text = "low render quality", flag = "opt_low_quality",
        callback = function(v) opt.low_quality = v; applyQuality() end})
    optGroup:addToggle({text = "disable atmosphere & clouds", flag = "opt_no_atmosphere",
        callback = function(v) opt.no_atmosphere = v; applyAtmosphere() end})
    optGroup:addButton({text = "quick boost (all)", callback = function()
        for _, f in ipairs({"opt_no_particles","opt_no_shadows","opt_no_postfx","opt_low_quality","opt_no_atmosphere"}) do
            local o = library.options[f]
            if o and o.changeState then pcall(o.changeState, true) end
        end
        library:notify("Applied fps boost", 3)
    end})

    local frGroup = miscTab:createGroup('left', 'frame rate')
    frGroup:addToggle({text = "limit fps", flag = "opt_fps_cap_enable",
        callback = function(v) opt.fps_cap_enable = v; applyFpsCap()
            if v and not setfpscap then library:notify("no setfpscap in this executor", 5) end end})
    frGroup:markStart()
    frGroup:addSlider({text = "fps limit", flag = "opt_fps_cap", value = 60, min = 30, max = 240,
        callback = function(v) opt.fps_cap = v; applyFpsCap() end})
    frGroup:dependsOn("opt_fps_cap_enable")
end)() -- end optimizations block

do
_G.Features.DeviceSpoof = _G.Features.DeviceSpoof or { Enabled=false, CurrentDevice="Console", LastApplied=0 }
local DS = _G.Features.DeviceSpoof
local devicecfgs = {
    Mobile = "Touch", Console = "Gamepad", VR = "VR", PC = "MouseKeyboard",
}
local function applydevice()
    if not DS.Enabled then return end
    local code = devicecfgs[DS.CurrentDevice]
    if not code then return end
    if tick() - DS.LastApplied < 0.5 then return end
    DS.LastApplied = tick()
    pcall(function()
        local r = ReplicatedStorage:FindFirstChild("Remotes")
        r = r and r:FindFirstChild("Replication")
        r = r and r:FindFirstChild("Fighter")
        r = r and r:FindFirstChild("SetControls")
        if r then r:FireServer(code) end
    end)
end
task.spawn(function()
    while true do task.wait(10); applydevice() end
end)
localPlayer.CharacterAdded:Connect(function() task.wait(1.5); applydevice() end)
local deviceGroup = miscTab:createGroup('right', 'device spoof')
deviceGroup:addToggle({text = "enable", flag = "DeviceSpoofEnabled",
    callback = function(v) DS.Enabled = v; if v then applydevice() end end})
deviceGroup:markStart()
deviceGroup:addList({text = "device", flag = "DeviceSpoofDevice", value = "Console",
    values = {"Mobile","Console","VR","PC"},
    callback = function(v) DS.CurrentDevice = v; applydevice() end})
deviceGroup:dependsOn("DeviceSpoofEnabled")
end -- end DeviceSpoof block

;(function() -- emote player (ported from take.lua) — own scope to save main-chunk locals
    local emoteCfg = { enabled = false, selected = "Meditate", customId = "", speed = 2 }
    -- animation ids for the emote presets
    local emoteIds = {
        ["Meditate"]     = "3576686446",
        ["Orbit"]        = "4841405708",
        ["Floss"]        = "5104836297",
        ["OJ"]           = "3576717965",
        ["Kicking Feet"] = "4849427632",
        ["Take the L"]   = "3576968026",
        ["Hype"]         = "3695333486",
    }
    local track, lastId, lastSpeed = nil, "", 0
    local function stopEmote()
        if track then pcall(function() track:Stop() end); track = nil end
        lastId = ""
    end
    RunService.Heartbeat:Connect(function()
        pcall(function()
            if not emoteCfg.enabled then stopEmote(); return end
            local char = localPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local animator = hum and hum:FindFirstChildOfClass("Animator")
            if not animator then stopEmote(); return end
            if track and not track.IsPlaying then track = nil; lastId = "" end

            local id = (emoteCfg.customId ~= "" and emoteCfg.customId) or emoteIds[emoteCfg.selected]
            if not id then return end
            if id ~= lastId then
                if track then pcall(function() track:Stop() end); track = nil end
                lastId = id
                local anim = Instance.new("Animation")
                anim.AnimationId = "rbxassetid://" .. id
                local ok, t = pcall(function() return animator:LoadAnimation(anim) end)
                if not ok or not t then lastId = ""; return end
                track = t
                pcall(function()
                    track.Priority = Enum.AnimationPriority.Action4
                    track:Play()
                    track:AdjustSpeed(emoteCfg.speed)
                end)
                lastSpeed = emoteCfg.speed
            end
            if track and emoteCfg.speed ~= lastSpeed then
                pcall(function() track:AdjustSpeed(emoteCfg.speed) end)
                lastSpeed = emoteCfg.speed
            end
        end)
    end)

    local emoteGroup = miscTab:createGroup('left', 'emote player')
    emoteGroup:addToggle({text = "enable", flag = "EmoteEnabled",
        callback = function(v) emoteCfg.enabled = v end})
    emoteGroup:markStart()
    emoteGroup:addList({text = "emote", flag = "EmoteSelected", value = "Meditate",
        values = {"Meditate","Orbit","Floss","OJ","Kicking Feet","Take the L","Hype"},
        callback = function(v) emoteCfg.selected = v; lastId = "" end})
    emoteGroup:addTextbox({text = "custom id", flag = "EmoteCustomId",
        callback = function(v) emoteCfg.customId = v or ""; lastId = "" end})
    emoteGroup:addSlider({text = "speed", flag = "EmoteSpeed", value = 2, min = 1, max = 10,
        callback = function(v) emoteCfg.speed = v end})
    emoteGroup:dependsOn("EmoteEnabled")
end)() -- end emote player block


;(function() -- Skinchanger block: own local scope
local ReplicatedFirst = game:GetService("ReplicatedFirst")

-- (anti-cheat neutralization now runs at the very TOP of the script, exactly
--  like take.lua does — see the top of the file. The old handshake-spoofing
--  bypass below is fully removed via a block comment.)
--[==[ OLD AC BYPASS REMOVED
    local ac_script = nil
    if not (hookmetamethod and hookfunction and newcclosure and checkcaller) then return end

    local last, first_seen, hijack_ready, client_id
    local expected_interval, min_interval, ema_alpha, samples = 0.6, 0.25, 0.5, 0
    local hidden_fn = {}

    setstackhidden = setstackhidden or function(fn_or_level, hidden)
        local ok, fn = pcall(function()
            if typeof(fn_or_level) == "number" then return debug.info(fn_or_level + 2, "f") end
            return fn_or_level
        end)
        if ok and fn then hidden_fn[fn] = not hidden end
    end

    local TrustedFunctions = setmetatable({}, {__mode = "k"})
    local HookReferences = {}
    local function TrustFunction(fn)
        if type(fn) == "function" then TrustedFunctions[fn] = true end
        return fn
    end

    local function SafeHook(hookfn, ...)
        local args = {...}
        local func, inst, metamethod, detour
        if hookfn == hookmetamethod then
            inst, metamethod, detour = args[1], args[2], args[3]
        else
            func, detour = args[1], args[2]
        end
        if hookfn == hookfunction and iscclosure(func) then detour = newcclosure(detour) end
        if not iscclosure(detour) then detour = newcclosure(detour) end
        pcall(setstackhidden, detour, true)
        HookReferences[#HookReferences + 1] = detour
        local original
        pcall(function()
            TrustFunction(detour)
            if hookfn == hookmetamethod then
                original = hookfn(inst, metamethod, detour)
            else
                original = hookfn(func, detour)
            end
        end)
        if original then HookReferences[#HookReferences + 1] = original end
        return original
    end

    local function SafeCall(func, ...)
        if checkcaller() then return func(...) end
        local old = getthreadidentity()
        if old ~= 2 then setthreadidentity(2) end
        local r = {func(...)}
        if old ~= 2 then setthreadidentity(old) end
        return table.unpack(r)
    end

    local oldindex
    oldindex = SafeHook(hookmetamethod, ac_script, "__index", function(t, k)
        if t == ac_script and not checkcaller() and kProtectedProperties[k] ~= nil and not bypassed then
            return kProtectedProperties[k]
        end
        if checkcaller() then return oldindex(t, k) end
        return SafeCall(oldindex, t, k)
    end)

    local oldnewindex
    oldnewindex = SafeHook(hookmetamethod, ac_script, "__newindex", function(t, k, v)
        if t == ac_script and not checkcaller() and kProtectedProperties[k] ~= nil and not bypassed then
            kProtectedProperties[k] = v
            if k == "Enabled" then kProtectedProperties.Disabled = not v end
            if k == "Disabled" then kProtectedProperties.Enabled = not v end
            return
        end
        if checkcaller() then return oldnewindex(t, k, v) end
        return SafeCall(oldnewindex, t, k, v)
    end)

    client_id, last = "", tick()
    local oldfireserver
    oldfireserver = SafeHook(hookfunction, ac_event.FireServer, function(self, ...)
        local now, args = tick(), {...}
        if not first_seen then
            first_seen = true
            local a = args[1]
            if type(a) == "table" and #a >= 1 and (type(a[1]) == "string" or type(a[1]) == "number") then
                client_id = tostring(a[1])
            end
            last, samples, hijack_ready = tick(), 1, true
            return SafeCall(oldfireserver, self, ...)
        end
        local interval = now - (last or now)
        if interval > 0 then
            expected_interval = samples == 0 and interval or (ema_alpha * interval + (1 - ema_alpha) * expected_interval)
            samples += 1
            if expected_interval < min_interval then expected_interval = min_interval end
        end
        local res = SafeCall(oldfireserver, self, ...)
        last = tick()
        return res
    end)

    local function BuildSubTable()
        local num_empty = math.random(1, 5)
        local empty_map, empty_slots = {[7]=true}, {7}
        while #empty_slots < num_empty do
            local s = math.random(1, 6)
            if not empty_map[s] then empty_map[s] = true; table.insert(empty_slots, s) end
        end
        table.sort(empty_slots)
        local r = {}
        for i = 1, 7 do r[i] = empty_map[i] and {} or kFilledSub end
        return r, empty_slots
    end

    local function ApplyTransforms(t, mask, empty_slots)
        local payload = t[1]
        local outer_index = #payload
        local inner_index = empty_slots[math.random(1, #empty_slots)]
        local derived, outer_val = nil, payload[outer_index]
        if type(outer_val) == "table" and type(inner_index) == "number" then
            derived = outer_val[inner_index]
        else
            for i = outer_index, 1, -1 do
                if type(payload[i]) == "table" then
                    local c = payload[i]
                    derived = (type(inner_index) == "number" and c[inner_index] ~= nil) and c[inner_index] or c
                    break
                end
            end
            derived = derived or {}
        end
        local written = {}
        for _, v in ipairs(mask) do
            local slot = kSlotMap[v]
            if slot and not written[slot] then t[slot] = derived; written[slot] = true end
        end
        return t
    end

    local function BuildPayload(challenge, mask)
        local sub, empty = BuildSubTable()
        local total = math.random(1, 8)
        local payload = {client_id, buffer.tostring(challenge)}
        for _ = 1, math.random(0, 2) do payload[#payload+1] = "" end
        while #payload < (total - 1) do payload[#payload+1] = math.random(5, 100000) end
        payload[#payload+1] = sub
        return ApplyTransforms({payload, {}, nil, nil, nil, nil, nil}, mask, empty)
    end

    task.spawn(function()
        getfenv().script = ac_script
        while not hijack_ready do task.wait() end
        ac_script.Enabled = false
        ac_event.OnClientEvent:Connect(function(...)
            last = tick()
            local remote = Instance.new("RemoteEvent")
            remote:FireServer()
            local t = {...}
            local challenge, index, mask = t[1], t[2], t[3]
            if typeof(challenge) ~= "buffer" or type(index) ~= "number" or type(mask) ~= "table" then
                return
            end
            local payload = BuildPayload(challenge, mask)
            task.defer(function()
                local wait_t = expected_interval - (tick() - (last or 0))
                if wait_t > 0 then task.wait(wait_t) end
                ac_event:FireServer(table.unpack(payload, 1, 5))
                last = tick()
                remote:Destroy()
            end)
        end)
        bypassed = true
    end)

    for _, name in ipairs(kKickNames) do
        local f = localPlayer[name]
        if type(f) == "function" then
            local old
            old = SafeHook(hookfunction, f, function(self, ...)
                if self == localPlayer and not checkcaller() then return end
                return old(self, ...)
            end)
        end
    end

    local bypass_tries = 0
    while not bypassed and bypass_tries < 20 do
        bypass_tries += 1
        task.wait(0.5)
    end
]==] -- END OLD AC BYPASS REMOVED

local modules = {}
-- IMPORTANT: require() of game ModuleScripts can YIELD (controllers wait for
-- replicated data), and PlayerDataController:Get before data loads blocks. Doing
-- this synchronously at load froze the client until the data finally replicated
-- (~the "freezes then says loaded" symptom). Run it on a background thread so the
-- main thread never blocks — every consumer already guards on `modules.X`.
task.spawn(function()
    pcall(function()
        local PS = localPlayer:FindFirstChild("PlayerScripts") or localPlayer:WaitForChild("PlayerScripts", 5)
        local Controllers = PS and PS:FindFirstChild("Controllers")
        local RSModules = ReplicatedStorage:FindFirstChild("Modules")
        if Controllers then
            local pdc = Controllers:FindFirstChild("PlayerDataController")
            if pdc then pcall(function() modules.PlayerDataController = require(pdc) end) end
        end
        if RSModules then
            local function req(name)
                local m = RSModules:FindFirstChild(name)
                if m then pcall(function() modules[name] = require(m) end) end
            end
            req("CosmeticLibrary"); req("ItemLibrary"); req("ShopLibrary"); req("MonetizationLibrary")
        end
    end)
    pcall(function()
        if modules.PlayerDataController and modules.PlayerDataController.WaitUntilLoaded then
            modules.PlayerDataController:WaitUntilLoaded()
        end
    end)
end)

local function SafeGet(key, fallback)
    local ok, v = pcall(function()
        return modules.PlayerDataController and modules.PlayerDataController:Get(key)
    end)
    return (ok and v ~= nil) and v or fallback
end

local states = {
    skinchanger_state = {
        fake_owned = SafeGet("CosmeticInventory", {}),
        fake_weapon_owned = SafeGet("WeaponInventory", {}),
        fake_weapon_names = {},
        equipped = {},
        favorites = {},
        constructing_weapon = nil,
        placed_object_map = {},
        viewing_profile = nil,
        general_unlocker = { unlock_type = "Skin", unlock_rarity = "Common" },
        specific_unlocker = { unlock_type = "Skin", cosmetic_name = "", weapon_name = "" },
        equip_unlocker = { unlock_type = "Skin", cosmetic_name = "", weapon_name = "", inverted = false },
    },
}

pcall(function()
    if not modules.PlayerDataController then return end
    local original = modules.PlayerDataController.Get
    modules.PlayerDataController.Get = function(self, key, ...)
        local data = original(self, key, ...)
        if key == "CosmeticInventory" then return states.skinchanger_state.fake_owned or data end
        if key == "WeaponInventory" or key == "FreeWeaponUnlockCheck" then return states.skinchanger_state.fake_weapon_owned or data end
        return data
    end
end)

pcall(function()
    if not modules.CosmeticLibrary then return end
    local cos = modules.CosmeticLibrary
    local function WrapOwnership(old, expected_args)
        return function(...)
            local args = {...}
            local name = args[expected_args]
            if type(name) == "string" and states.skinchanger_state.fake_owned[name] then return true end
            if old then return old(...) end
            return false
        end
    end
    local orig_normal = cos.OwnsCosmeticNormally
    cos.OwnsCosmeticNormally = WrapOwnership(orig_normal, 3)
    local orig_universal = cos.OwnsCosmeticUniversally
    cos.OwnsCosmeticUniversally = WrapOwnership(orig_universal, 3)
    local orig_for_something = cos.OwnsCosmeticForSomething
    cos.OwnsCosmeticForSomething = WrapOwnership(orig_for_something, 3)
    local orig_for_weapon = cos.OwnsCosmeticForWeapon
    cos.OwnsCosmeticForWeapon = WrapOwnership(orig_for_weapon, 3)
    local orig_owns = cos.OwnsCosmetic
    cos.OwnsCosmetic = function(self, inventory, name, weapon)
        if type(name) == "string" and states.skinchanger_state.fake_owned[name] then return true end
        if orig_owns then return orig_owns(self, inventory, name, weapon) end
        return false
    end
end)

pcall(function()
    if not modules.PlayerDataController then return end
    local pdc = modules.PlayerDataController
    if pdc.GetWeaponData then
        local orig_getweapondata = pdc.GetWeaponData
        pdc.GetWeaponData = function(p1, ...)
            local weapon_name = ({...})[1]
            local original_data, index = orig_getweapondata(p1, ...)
            local fake_owned = false
            for _, weapon in ipairs(states.skinchanger_state.fake_weapon_owned) do
                if weapon.Name == weapon_name then fake_owned = true break end
            end
            if fake_owned and not original_data then
                local fake_data = { Name = weapon_name, Level = 1, XP = 0, IsFavorited = false, Skin = nil }
                local equipped = states.skinchanger_state.equipped
                if equipped and equipped[weapon_name] then
                    for cos_type, cos_data in pairs(equipped[weapon_name]) do
                        if type(cos_data) == "table" and (cos_data.Name == "NONE_COSMETIC" or cos_data.Name == "None") then
                            fake_data[cos_type] = nil
                        else
                            fake_data[cos_type] = cos_data
                        end
                    end
                end
                return fake_data, index
            end
            local equipped = states.skinchanger_state.equipped
            if original_data and equipped and equipped[weapon_name] then
                for cos_type, cos_data in pairs(equipped[weapon_name]) do
                    if type(cos_data) == "table" and (cos_data.Name == "NONE_COSMETIC" or cos_data.Name == "None") then
                        original_data[cos_type] = nil
                    else
                        original_data[cos_type] = cos_data
                    end
                end
            end
            return original_data, index
        end
    end
end)

local function PatchCurrentDataGet(current_data)
    if not current_data or type(current_data.Get) ~= "function" or current_data._fakeWeaponOwnedPatched then return end
    local old_get = current_data.Get
    current_data.Get = function(self, ...)
        local data = old_get(self, ...)
        local key = ({...})[1]
        if key == "CosmeticInventory" then return states.skinchanger_state.fake_owned or data end
        if key == "WeaponInventory" or key == "FreeWeaponUnlockCheck" then return states.skinchanger_state.fake_weapon_owned or data end
        return data
    end
    current_data._fakeWeaponOwnedPatched = true
end
task.spawn(function()
    while not (modules.PlayerDataController and modules.PlayerDataController.CurrentData) do task.wait(0.1) end
    PatchCurrentDataGet(modules.PlayerDataController.CurrentData)
end)

local NamecallDispatcher = { Hooks = {}, Original = nil }
function NamecallDispatcher:Register(callback) self.Hooks[#self.Hooks + 1] = callback; return #self.Hooks end
pcall(function()
    if not (hookmetamethod and newcclosure and getnamecallmethod) then return end
    NamecallDispatcher.Original = hookmetamethod(game, "__namecall", newcclosure(function(object, ...)
        local hooks = NamecallDispatcher.Hooks
        local count = #hooks
        if count == 0 then return NamecallDispatcher.Original(object, ...) end
        local method = getnamecallmethod()
        for i = 1, count do
            local result = hooks[i](object, method, ...)
            if result ~= nil and result ~= false then
                if result == true then return nil end
                return result
            end
        end
        return NamecallDispatcher.Original(object, ...)
    end))
end)

local function CloneCosmetic(name, cosmetic_type, options)
    if not modules.CosmeticLibrary or not modules.CosmeticLibrary.Cosmetics then return nil end
    local base = modules.CosmeticLibrary.Cosmetics[name]
    if not base then return nil end
    local data = table.clone(base)
    data.Name = name
    data.Type = data.Type or cosmetic_type
    data.Seed = math.random(1, 1000000)
    if options then
        if options.inverted then data.Inverted = true end
        if options.favorites_only then data.OnlyUseFavorites = true end
    end
    return data
end

local function HandleSkinchangerEquip(args)
    local weapon_name = args[1]
    local cosmetic_type = args[2]
    local cosmetic_name = args[3]
    local options = args[4] or {}
    states.skinchanger_state.equipped[weapon_name] = states.skinchanger_state.equipped[weapon_name] or {}
    if not cosmetic_name or cosmetic_name == "" or cosmetic_name == "None" or cosmetic_name == "NONE_COSMETIC" then
        states.skinchanger_state.equipped[weapon_name][cosmetic_type] = { Name = "NONE_COSMETIC" }
    elseif cosmetic_name == "Random" or cosmetic_name == "RANDOM_COSMETIC" then
        states.skinchanger_state.equipped[weapon_name][cosmetic_type] = {
            Name = cosmetic_name, Type = cosmetic_type,
            Inverted = options.IsInverted, OnlyUseFavorites = options.OnlyUseFavorites,
            Seed = math.random(1, 1000000),
        }
    else
        local cloned = CloneCosmetic(cosmetic_name, cosmetic_type, {
            inverted = options.IsInverted, favorites_only = options.OnlyUseFavorites,
        })
        if cloned then states.skinchanger_state.equipped[weapon_name][cosmetic_type] = cloned end
    end
    task.spawn(function()
        task.wait(0.1)
        pcall(function()
            if modules.PlayerDataController and modules.PlayerDataController.CurrentData then
                modules.PlayerDataController.CurrentData:Replicate("WeaponInventory")
            end
        end)
    end)
end

pcall(function()
    NamecallDispatcher:Register(function(self, method, ...)
        if method ~= "FireServer" then return false end
        local args = {...}
        if self.Name == "EquipCosmetic" then
            HandleSkinchangerEquip(args)
            return true
        end
        return false
    end)
end)

local function ResolveCosmetic(weaponName, cosmeticType)
    local equipped = states.skinchanger_state.equipped[weaponName]
        and states.skinchanger_state.equipped[weaponName][cosmeticType]
    if not equipped then return nil end
    if equipped.Name == "None" or equipped.Name == "NONE_COSMETIC" then return nil end
    return equipped
end

pcall(function()
    if not modules.ItemLibrary then return end
    local orig = modules.ItemLibrary.GetViewModelImageFromWeaponData
    modules.ItemLibrary.GetViewModelImageFromWeaponData = function(p1, p2, p3)
        if not p2 then return orig(p1, p2, p3) end
        local weapon_name = p2.Name
        local skin = ResolveCosmetic(weapon_name, "Skin")
        local should_show = skin and (
            (p2.Skin and states.skinchanger_state.equipped[weapon_name])
            or (states.skinchanger_state.viewing_profile == localPlayer and states.skinchanger_state.equipped[weapon_name])
        )
        if should_show and skin then
            local skin_info = p1.ViewModels[skin.Name]
            if skin_info then
                return skin_info[p3 and "ImageHighResolution" or "Image"] or skin_info.Image
            end
        end
        return orig(p1, p2, p3)
    end
end)

-- deferred: require(ClientItem) can yield at load; run it off the main thread
task.spawn(function() pcall(function()
    local ok, clientItemPath = pcall(function()
        return localPlayer.PlayerScripts.Modules.ClientReplicatedClasses.ClientFighter.ClientItem
    end)
    if not ok or not clientItemPath then return end
    local ClientItem = require(clientItemPath)

    if ClientItem._CreateViewModel then
        local orig = ClientItem._CreateViewModel
        ClientItem._CreateViewModel = function(self, viewmodelRef)
            local weaponName = self.Name
            local weaponPlayer = self.ClientFighter and self.ClientFighter.Player
            states.skinchanger_state.constructing_weapon = (weaponPlayer == localPlayer) and weaponName or nil
            if weaponPlayer == localPlayer and states.skinchanger_state.equipped[weaponName] and ResolveCosmetic(weaponName, "Skin") and viewmodelRef then
                pcall(function()
                    local ReplicatedClass = require(ReplicatedStorage.Modules.ReplicatedClass)
                    local dataKey = ReplicatedClass:ToEnum("Data")
                    local skinKey = ReplicatedClass:ToEnum("Skin")
                    local nameKey = ReplicatedClass:ToEnum("Name")
                    if viewmodelRef[dataKey] then
                        viewmodelRef[dataKey][skinKey] = ResolveCosmetic(weaponName, "Skin")
                        viewmodelRef[dataKey][nameKey] = ResolveCosmetic(weaponName, "Skin").Name
                    elseif viewmodelRef.Data then
                        viewmodelRef.Data.Skin = ResolveCosmetic(weaponName, "Skin")
                        viewmodelRef.Data.Name = ResolveCosmetic(weaponName, "Skin").Name
                    end
                end)
            end
            local result = orig(self, viewmodelRef)
            states.skinchanger_state.constructing_weapon = nil
            return result
        end
    end

    pcall(function()
        local viewModelModule = clientItemPath:FindFirstChild("ClientViewModel")
        if not viewModelModule then return end
        local ClientViewModel = require(viewModelModule)

        if ClientViewModel.GetWrap then
            local origGetWrap = ClientViewModel.GetWrap
            ClientViewModel.GetWrap = function(self)
                local weaponName = self.ClientItem and self.ClientItem.Name
                local weaponPlayer = self.ClientItem and self.ClientItem.ClientFighter and self.ClientItem.ClientFighter.Player
                if weaponName and weaponPlayer == localPlayer and states.skinchanger_state.equipped[weaponName] and ResolveCosmetic(weaponName, "Wrap") then
                    return ResolveCosmetic(weaponName, "Wrap")
                end
                return origGetWrap(self)
            end
        end

        local origNew = ClientViewModel.new
        ClientViewModel.new = function(replicatedData, clientItem)
            local weaponPlayer = clientItem.ClientFighter and clientItem.ClientFighter.Player
            local weaponName = states.skinchanger_state.constructing_weapon or clientItem.Name
            if weaponPlayer == localPlayer and states.skinchanger_state.equipped[weaponName] then
                pcall(function()
                    local ReplicatedClass = require(ReplicatedStorage.Modules.ReplicatedClass)
                    local dataKey = ReplicatedClass:ToEnum("Data")
                    replicatedData[dataKey] = replicatedData[dataKey] or {}
                    if ResolveCosmetic(weaponName, "Skin") then
                        replicatedData[dataKey][ReplicatedClass:ToEnum("Skin")] = ResolveCosmetic(weaponName, "Skin")
                    end
                    if ResolveCosmetic(weaponName, "Wrap") then
                        replicatedData[dataKey][ReplicatedClass:ToEnum("Wrap")] = ResolveCosmetic(weaponName, "Wrap")
                    end
                    if ResolveCosmetic(weaponName, "Charm") then
                        replicatedData[dataKey][ReplicatedClass:ToEnum("Charm")] = ResolveCosmetic(weaponName, "Charm")
                    end
                end)
            end
            local result = origNew(replicatedData, clientItem)
            pcall(function()
                local objectID = nil
                pcall(function()
                    local ReplicatedClass = require(ReplicatedStorage.Modules.ReplicatedClass)
                    local dataKey = ReplicatedClass:ToEnum("Data")
                    local objKey = ReplicatedClass:ToEnum("ObjectID")
                    if replicatedData[dataKey] then objectID = replicatedData[dataKey][objKey] end
                end)
                if objectID == nil then
                    pcall(function() objectID = result:Get("ObjectID") or result.ObjectID end)
                end
                if objectID and weaponPlayer == localPlayer and states.skinchanger_state.equipped[weaponName] then
                    states.skinchanger_state.placed_object_map[objectID] = weaponName
                end
            end)
            if weaponPlayer == localPlayer and states.skinchanger_state.equipped[weaponName] and ResolveCosmetic(weaponName, "Wrap") and result._UpdateWrap then
                task.spawn(function()
                    result:_UpdateWrap()
                    task.wait(0.1)
                    if not result._destroyed then result:_UpdateWrap() end
                end)
            end
            return result
        end
    end)
end) end) -- close deferred ClientItem task.spawn

local function GetCosmeticsByRarity(rarity)
    local results = {}
    if not modules.CosmeticLibrary or not modules.CosmeticLibrary.Cosmetics then return results end
    for name, cosmetic in pairs(modules.CosmeticLibrary.Cosmetics) do
        if cosmetic.Rarity == rarity then table.insert(results, name) end
    end
    return results
end
local function GetCosmeticsByType(type_name)
    local results = {}
    if not modules.CosmeticLibrary or not modules.CosmeticLibrary.Cosmetics then return results end
    for name, cosmetic in pairs(modules.CosmeticLibrary.Cosmetics) do
        if cosmetic.Type == type_name then table.insert(results, name) end
    end
    return results
end
local function GetAllCosmetics()
    local results = {}
    if not modules.CosmeticLibrary or not modules.CosmeticLibrary.Cosmetics then return results end
    for name, _ in pairs(modules.CosmeticLibrary.Cosmetics) do table.insert(results, name) end
    return results
end
local function UnlockAll()
    local list = GetAllCosmetics()
    local n = 0
    for _, cosmetic in ipairs(list) do
        if cosmetic:find("MISSING_") then continue end
        states.skinchanger_state.fake_owned[cosmetic] = true
        n += 1

        if n % 500 == 0 then task.wait() end
    end
end
local function LockAll()
    for _, cosmetic in ipairs(GetAllCosmetics()) do
        if cosmetic:find("MISSING_") then continue end
        states.skinchanger_state.fake_owned[cosmetic] = nil
    end
end
local function GetSpecificCosmetic(type_name, cos_name, weapon_name)
    local cos = modules.CosmeticLibrary and modules.CosmeticLibrary.Cosmetics
    if not cos then return nil end
    for name, cosmetic in pairs(cos) do
        if type_name == "Skin" then
            if name == cos_name and cosmetic.Type == type_name and cosmetic.ItemName == weapon_name then return name end
        else
            if name == cos_name and cosmetic.Type == type_name then return name end
        end
    end
    return nil
end
local function GetAllCosmeticsOfWeapon(weapon_name)
    local results = {}
    local cos = modules.CosmeticLibrary and modules.CosmeticLibrary.Cosmetics
    if not cos then return results end
    for name, cosmetic in pairs(cos) do
        if cosmetic.Type == "Skin" then
            if cosmetic.ItemName == weapon_name then results[#results+1] = name end
        else
            results[#results+1] = name
        end
    end
    return results
end

local function UnlockAllOfType()
    for _, c in ipairs(GetCosmeticsByType(states.skinchanger_state.general_unlocker.unlock_type)) do
        if not c:find("MISSING_") then states.skinchanger_state.fake_owned[c] = true end
    end
end
local function LockAllOfType()
    for _, c in ipairs(GetCosmeticsByType(states.skinchanger_state.general_unlocker.unlock_type)) do
        if not c:find("MISSING_") then states.skinchanger_state.fake_owned[c] = nil end
    end
end
local function UnlockSelectedRarity()
    for _, c in ipairs(GetCosmeticsByRarity(states.skinchanger_state.general_unlocker.unlock_rarity)) do
        if not c:find("MISSING_") then states.skinchanger_state.fake_owned[c] = true end
    end
end
local function LockSelectedRarity()
    for _, c in ipairs(GetCosmeticsByRarity(states.skinchanger_state.general_unlocker.unlock_rarity)) do
        if not c:find("MISSING_") then states.skinchanger_state.fake_owned[c] = nil end
    end
end
local function UnlockAllForWeapon(weapon_name)
    for _, c in ipairs(GetAllCosmeticsOfWeapon(weapon_name)) do
        if not c:find("MISSING_") then states.skinchanger_state.fake_owned[c] = true end
    end
end

local function UnlockAllWeapons()
    local cd = modules.PlayerDataController and modules.PlayerDataController.CurrentData
    if not cd then return end
    local owned = {}
    local inv = cd:Get("WeaponInventory")
    if type(inv) == "table" then
        for _, w in pairs(inv) do
            if type(w) == "table" and w.Name then owned[w.Name] = true end
        end
    end
    if not (modules.ShopLibrary and modules.ShopLibrary.GetReleasedOwnableWeapons) then return end
    for _, wname in pairs(modules.ShopLibrary:GetReleasedOwnableWeapons()) do
        if not owned[wname] and not states.skinchanger_state.fake_weapon_names[wname] then
            table.insert(states.skinchanger_state.fake_weapon_owned, {
                Name = wname, Level = 1, XP = 0, IsFavorited = false, Skin = nil,
            })
            states.skinchanger_state.fake_weapon_names[wname] = true
        end
    end
end
local function LockAllWeapons()
    local fake = states.skinchanger_state.fake_weapon_owned
    local names = states.skinchanger_state.fake_weapon_names
    for i = #fake, 1, -1 do
        if names[fake[i].Name] then table.remove(fake, i) end
    end
    table.clear(names)
end

local function EquipCosmetic(weapon_name, cosmetic_type, cosmetic_name, options)
    if typeof(weapon_name) ~= "string" or weapon_name == "" then return end
    options = options or {}
    local name_to_send = (cosmetic_name ~= nil and cosmetic_name ~= "") and cosmetic_name or nil
    pcall(function()
        ReplicatedStorage.Remotes.Data.EquipCosmetic:FireServer(weapon_name, cosmetic_type, name_to_send, options)
    end)
end

local SKINS_FILE = "riots/skins.json"
function library:saveSkins()
    local out = {}
    for weapon, byType in pairs(states.skinchanger_state.equipped) do
        for ctype, data in pairs(byType) do
            local nm = type(data) == "table" and data.Name or data
            if nm and nm ~= "NONE_COSMETIC" and nm ~= "None" then
                out[#out+1] = { weapon = weapon, ctype = ctype, name = nm }
            end
        end
    end
    pcall(function() writefile(SKINS_FILE, game:GetService("HttpService"):JSONEncode(out)) end)
    library:notify("Saved "..#out.." skins")
end
function library:loadSkins()
    local ok, data = pcall(function() if isfile(SKINS_FILE) then return readfile(SKINS_FILE) end end)
    if not ok or not data then return library:notify("No saved skins") end
    local ok2, list = pcall(function() return game:GetService("HttpService"):JSONDecode(data) end)
    if not ok2 or type(list) ~= "table" then return library:notify("Invalid skins file") end
    task.spawn(function()
        for _, e in ipairs(list) do
            if e.weapon and e.name then
                states.skinchanger_state.fake_owned[e.name] = true
                EquipCosmetic(e.weapon, e.ctype or "Skin", e.name, {})
                task.wait(0.05)
            end
        end
        library:notify("Loaded "..#list.." skins")
    end)
end

local function allWeapons()
    local seen, list = {}, {}
    if modules.CosmeticLibrary and modules.CosmeticLibrary.Cosmetics then
        for _, c in pairs(modules.CosmeticLibrary.Cosmetics) do
            if (c.Type == "Skin" or c.Type == "Wrap") and c.ItemName and not seen[c.ItemName] then
                seen[c.ItemName] = true; list[#list+1] = c.ItemName
            end
        end
    end
    table.sort(list)
    return list
end
local function cosmeticsForWeapon(weapon, ctype)
    local t = {}
    if modules.CosmeticLibrary and modules.CosmeticLibrary.Cosmetics then
        for name, c in pairs(modules.CosmeticLibrary.Cosmetics) do
            if c.Type == ctype and ((ctype == "Skin" and c.ItemName == weapon) or ctype ~= "Skin") and not name:find("MISSING_") then
                t[#t+1] = name
            end
        end
    end
    table.sort(t)
    return t
end

local function cosmeticImage(name)
    local cos = modules.CosmeticLibrary and modules.CosmeticLibrary.Cosmetics
    local c = cos and cos[name]
    if not c then return "" end

    local weapon = c.ItemName
    if weapon and modules.ItemLibrary and modules.ItemLibrary.Items then
        local item = modules.ItemLibrary.Items[weapon]
        local vms = item and item.ViewModels
        local vm = vms and vms[name]
        if vm then
            local img = vm.ImageHighResolution or vm.Image
            if img and img ~= "" then return img end
        end

        vm = c.ViewModels and c.ViewModels[name]
        if vm then
            local img = vm.ImageHighResolution or vm.Image
            if img and img ~= "" then return img end
        end
    end

    if c.Image and c.Image ~= "" then return c.Image end
    if c.Icon and c.Icon ~= "" then return c.Icon end
    if c.ImageId and c.ImageId ~= "" then return c.ImageId end

    if weapon and modules.ItemLibrary and modules.ItemLibrary.Items then
        local item = modules.ItemLibrary.Items[weapon]
        if item then return item.Image or item.Icon or "" end
    end
    return ""
end
local function weaponIcon(weapon)
    if modules.ItemLibrary and modules.ItemLibrary.Items then
        local it = modules.ItemLibrary.Items[weapon]
        if it then return it.Image or it.Icon or "" end
    end
    return ""
end
library.getWeaponImage = weaponIcon

local WHITE = Color3.fromRGB(255,255,255)
local selWeapon, selType, selCosmetic = nil, "Skin", nil

local grp = skinsTab:createGroup('left', 'cosmetics')

grp:addList({text = "cosmetic type", flag = "SkinType", value = "Skin", values = {"Skin","Wrap","Charm","Finisher"},
    callback = function(v) selType = v; if skinRefreshCosmetics then skinRefreshCosmetics() end end})

grp:addList({text = "weapon", flag = "SkinWeapon", value = "", values = {},
    callback = function(v) selWeapon = v; if skinRefreshCosmetics then skinRefreshCosmetics() end end})

grp:addSkinGrid({text = "cosmetic", flag = "SkinCosmetic", height = 240, columns = 4,
    imageFor = function(name) return cosmeticImage(name) end,
    callback = function(v) selCosmetic = v end})

grp:addButton({text = "equip", callback = function()
    if not selWeapon or selWeapon == "" then return library:notify("select a weapon") end
    if not selCosmetic or selCosmetic == "" then return library:notify("select a cosmetic") end
    states.skinchanger_state.fake_owned[selCosmetic] = true
    EquipCosmetic(selWeapon, selType, selCosmetic, {})
    library:notify("Equipped "..selCosmetic:gsub("_"," "))
end})
grp:addButton({text = "unequip", callback = function()
    if selWeapon and selWeapon ~= "" then EquipCosmetic(selWeapon, selType, "None", {}) end
end})
grp:addButton({text = "refresh weapons", callback = function() skinRefreshWeapons() end})
grp:addButton({text = "save skins", callback = function() library:saveSkins() end})
grp:addButton({text = "load skins", callback = function() library:loadSkins() end})

-- ── unlock all emotes (lets you play any emote locally, even locked ones) ────
local emoteUnlockInstalled = false
local function installEmoteUnlock()
    if emoteUnlockInstalled then return true end
    local ok = pcall(function()
        local PlayerScripts = localPlayer:WaitForChild("PlayerScripts")
        local Controllers = PlayerScripts:WaitForChild("Controllers")
        local Modules = game:GetService("ReplicatedStorage"):WaitForChild("Modules")

        local CosmeticLibrary = require(Modules:WaitForChild("CosmeticLibrary"))
        local EmoteController = require(Controllers:WaitForChild("EmoteController"))
        local FighterController = require(Controllers:WaitForChild("FighterController"))
        local PlayerDataController = require(Controllers:WaitForChild("PlayerDataController"))

        local isLocalEmoting = false
        local localEmoteObject = nil
        local currentLocalEmote = nil
        local runningConnection = nil
        local previousCameraMode = nil
        local previousMinZoom = nil

        local function safeFire(signal)
            if not signal then return end
            if type(signal) == "table" then
                if type(signal.Fire) == "function" then
                    pcall(function() signal:Fire() end)
                elseif type(signal.fire) == "function" then
                    pcall(function() signal:fire() end)
                end
            elseif typeof(signal) == "Instance" and signal:IsA("BindableEvent") then
                pcall(function() signal:Fire() end)
            end
        end

        local function stopCurrentLocalEmote()
            if not isLocalEmoting then return end
            isLocalEmoting = false
            localEmoteObject = nil
            pcall(function()
                if previousCameraMode ~= nil then
                    localPlayer.CameraMode = previousCameraMode
                    previousCameraMode = nil
                end
                if previousMinZoom ~= nil then
                    localPlayer.CameraMinZoomDistance = previousMinZoom
                    previousMinZoom = nil
                end
            end)
            local fighter = FighterController:GetFighter(localPlayer)
            local entity = fighter and fighter.Entity
            if entity and entity.EmoteStatusChanged then
                safeFire(entity.EmoteStatusChanged)
            end
            if currentLocalEmote then
                pcall(function() currentLocalEmote:Destroy() end)
                currentLocalEmote = nil
            end
        end

        local function setupHumanoidMonitoring(character)
            if not character then return end
            local humanoid = character:WaitForChild("Humanoid", 10)
            if not humanoid then return end
            if runningConnection then
                runningConnection:Disconnect()
                runningConnection = nil
            end
            runningConnection = humanoid.Running:Connect(function(speed)
                if speed > 0.1 and isLocalEmoting then
                    stopCurrentLocalEmote()
                end
            end)
        end

        setupHumanoidMonitoring(localPlayer.Character)
        localPlayer.CharacterAdded:Connect(function(character)
            stopCurrentLocalEmote()
            setupHumanoidMonitoring(character)
        end)

        local oldOwnsCosmetic = CosmeticLibrary.OwnsCosmetic
        CosmeticLibrary.OwnsCosmetic = function(self, inventory, cosmeticName)
            local cosmetic = CosmeticLibrary.Cosmetics[cosmeticName]
            if cosmetic and cosmetic.Type == "Emote" then
                return true
            end
            return oldOwnsCosmetic(self, inventory, cosmeticName)
        end

        local oldCanEmote = EmoteController.CanEmote
        EmoteController.CanEmote = function(self, p2)
            local success, result = pcall(oldCanEmote, self, p2)
            if success and result then
                return true
            end
            local fighter = FighterController:GetFighter(localPlayer)
            if fighter and fighter.IsLocalPlayer and fighter:IsAlive() then
                local entity = fighter.Entity
                if entity and not entity:Get("IsFrozen") then
                    return true
                end
            end
            return false
        end

        local function getLocalFighterEntity()
            local fighter = FighterController:GetFighter(localPlayer)
            if fighter and fighter.IsLocalPlayer then
                return fighter.Entity
            end
            return nil
        end

        local oldIsEmoting = nil
        local oldGetCurrentEmote = nil
        local hookedEntity = nil
        local unhookEntity  -- forward declaration

        local function hookEntity(entity)
            if not entity then return end
            if hookedEntity == entity then return end
            if hookedEntity and hookedEntity ~= entity then
                unhookEntity()
            end
            hookedEntity = entity
            oldIsEmoting = entity.IsEmoting
            oldGetCurrentEmote = entity.GetCurrentEmote
            entity.IsEmoting = function(self, ...)
                if isLocalEmoting then
                    return true
                end
                return oldIsEmoting(self, ...)
            end
            entity.GetCurrentEmote = function(self, ...)
                if isLocalEmoting and localEmoteObject then
                    return localEmoteObject
                end
                return oldGetCurrentEmote(self, ...)
            end
        end

        function unhookEntity()
            if hookedEntity and oldIsEmoting then
                pcall(function() hookedEntity.IsEmoting = oldIsEmoting end)
            end
            if hookedEntity and oldGetCurrentEmote then
                pcall(function() hookedEntity.GetCurrentEmote = oldGetCurrentEmote end)
            end
            hookedEntity = nil
            oldIsEmoting = nil
            oldGetCurrentEmote = nil
        end

        local oldUseEmoteByName = EmoteController.UseEmoteByName
        EmoteController.UseEmoteByName = function(self, emoteName)
            stopCurrentLocalEmote()
            local ownsEmote = oldOwnsCosmetic(CosmeticLibrary, PlayerDataController:Get("CosmeticInventory"), emoteName)
            pcall(function() oldUseEmoteByName(self, emoteName) end)
            if not ownsEmote then
                task.spawn(function()
                    local EmotesFolder = Modules:FindFirstChild("Emotes")
                    local emoteModule = EmotesFolder and EmotesFolder:FindFirstChild(emoteName)
                    local character = localPlayer.Character
                    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
                    if emoteModule and humanoid then
                        task.wait(0.1)
                        pcall(function()
                            currentLocalEmote = require(emoteModule).new(humanoid)
                            previousCameraMode = localPlayer.CameraMode
                            previousMinZoom = localPlayer.CameraMinZoomDistance
                            localPlayer.CameraMode = Enum.CameraMode.Classic
                            localPlayer.CameraMinZoomDistance = 8
                            isLocalEmoting = true
                            localEmoteObject = currentLocalEmote
                            local entity = getLocalFighterEntity()
                            if entity then
                                hookEntity(entity)
                                if entity.EmoteStatusChanged then
                                    safeFire(entity.EmoteStatusChanged)
                                end
                            end
                            task.defer(currentLocalEmote.Simulate, currentLocalEmote)
                            currentLocalEmote.Destroying:Wait()
                            if isLocalEmoting then
                                stopCurrentLocalEmote()
                            end
                            unhookEntity()
                        end)
                    end
                end)
            end
        end
    end)
    if ok then emoteUnlockInstalled = true end
    return ok
end

local unlockGrp = skinsTab:createGroup('right', 'unlocker')
unlockGrp:addButton({text = "unlock all emotes", callback = function()
    task.spawn(function()
        if installEmoteUnlock() then
            library:notify("Unlocked all emotes! Play any emote from the shop.")
        else
            library:notify("Failed to unlock emotes (module not ready)")
        end
    end)
end})
unlockGrp:addList({text = "type", flag = "UnlockType", value = "Skin", values = {"Skin","Wrap","Charm","Finisher"},
    callback = function(v) states.skinchanger_state.general_unlocker.unlock_type = v end})
unlockGrp:addList({text = "rarity", flag = "UnlockRarity", value = "Common",
    values = {"Common","Rare","Legendary","Mythical","Unique","Unobtainable"},
    callback = function(v) states.skinchanger_state.general_unlocker.unlock_rarity = v end})
unlockGrp:addButton({text = "unlock all cosmetics", callback = function()
    task.spawn(function() UnlockAll(); library:notify("Unlocked all cosmetics!") end)
end})
unlockGrp:addButton({text = "lock all cosmetics", callback = function()
    task.spawn(function() LockAll(); library:notify("Locked all cosmetics") end)
end})
unlockGrp:addButton({text = "unlock all of type", callback = function()
    UnlockAllOfType(); library:notify("Unlocked all "..states.skinchanger_state.general_unlocker.unlock_type)
end})
unlockGrp:addButton({text = "lock all of type", callback = function()
    LockAllOfType(); library:notify("Locked all "..states.skinchanger_state.general_unlocker.unlock_type)
end})
unlockGrp:addButton({text = "unlock selected rarity", callback = function()
    UnlockSelectedRarity(); library:notify("Unlocked all "..states.skinchanger_state.general_unlocker.unlock_rarity)
end})
unlockGrp:addButton({text = "lock selected rarity", callback = function()
    LockSelectedRarity(); library:notify("Locked all "..states.skinchanger_state.general_unlocker.unlock_rarity)
end})
unlockGrp:addButton({text = "unlock cosmetics for weapon", callback = function()
    if not selWeapon or selWeapon == "" then return library:notify("select a weapon") end
    UnlockAllForWeapon(selWeapon); library:notify("Unlocked cosmetics for "..selWeapon)
end})

local weaponGrp = skinsTab:createGroup('right', 'weapons')
weaponGrp:addButton({text = "unlock all weapons", callback = function()
    task.spawn(function() UnlockAllWeapons(); library:notify("Unlocked all weapons!") end)
end})
weaponGrp:addButton({text = "lock all weapons", callback = function()
    LockAllWeapons(); library:notify("Locked all weapons")
end})

function skinRefreshWeapons()
    local list = allWeapons()
    local opt = library.options["SkinWeapon"]
    if opt and opt.refresh then opt.refresh(list) end
end
function skinRefreshCosmetics()
    if not selWeapon then return end
    local list = cosmeticsForWeapon(selWeapon, selType)
    local opt = library.options["SkinCosmetic"]
    if opt and opt.refresh then opt.refresh(list) end
end

task.spawn(function()
    local tries = 0
    while (not (modules.CosmeticLibrary and modules.CosmeticLibrary.Cosmetics)) and tries < 80 do
        task.wait(0.5); tries = tries + 1
    end
    pcall(skinRefreshWeapons)
end)
end)() -- end Skinchanger block

-- ── player list (clean two-panel layout inside the "players" tab) ────────────
;(function() -- own function scope so its locals don't count against the 200-local main chunk
    local ENEMY  = Color3.fromRGB(255,90,90)
    local CLIENT = Color3.fromRGB(150,150,150)
    local DIM    = Color3.fromRGB(210,210,210)

    -- host group fills the players tab; make it tall and full width
    local plGroup, plBox = playersTab:createGroup('left', 'players')
    plBox.Size = UDim2.new(1, 0, 0, 360)

    local root = Instance.new("Frame")
    root.Name = "riotsPlayerList"
    root.Size = UDim2.new(1, -8, 1, -10)
    root.Position = UDim2.fromOffset(4, 6)
    root.BackgroundTransparency = 1
    root.ZIndex = 250
    root.Parent = plBox

    local function panel(px, wScale, wOff)
        local f = Instance.new("Frame")
        f.BackgroundColor3 = Color3.fromRGB(16,16,16)
        f.BorderColor3 = Color3.fromRGB(35,35,35)
        f.BorderSizePixel = 1
        f.Position = UDim2.fromOffset(px, 0)
        f.Size = UDim2.new(wScale, wOff, 1, 0)
        f.ZIndex = 251
        f.Parent = root
        return f
    end

    -- LEFT: search + scrolling list (55% width)
    local left = panel(0, 0.55, -4)
    local searchBg = Instance.new("Frame")
    searchBg.Position = UDim2.fromOffset(6, 6)
    searchBg.Size = UDim2.new(1,-12,0,22)
    searchBg.BackgroundColor3 = Color3.fromRGB(24,24,24)
    searchBg.BorderColor3 = Color3.fromRGB(0,0,0); searchBg.BorderSizePixel = 1
    searchBg.ZIndex = 252; searchBg.Parent = left
    local searchBox = Instance.new("TextBox")
    searchBox.BackgroundTransparency = 1
    searchBox.Size = UDim2.new(1,-8,1,0); searchBox.Position = UDim2.fromOffset(5,0)
    searchBox.Font = Enum.Font.Code; searchBox.PlaceholderText = "search players..."
    searchBox.PlaceholderColor3 = Color3.fromRGB(110,110,110)
    searchBox.Text = ""; searchBox.TextColor3 = Color3.fromRGB(220,220,220)
    searchBox.TextSize = 13; searchBox.TextXAlignment = Enum.TextXAlignment.Left
    searchBox.ClearTextOnFocus = false; searchBox.ZIndex = 253; searchBox.Parent = searchBg

    local scroll = Instance.new("ScrollingFrame")
    scroll.Position = UDim2.fromOffset(6, 34)
    scroll.Size = UDim2.new(1,-12,1,-40)
    scroll.BackgroundColor3 = Color3.fromRGB(20,20,20)
    scroll.BorderColor3 = Color3.fromRGB(0,0,0); scroll.BorderSizePixel = 1
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = library.libColor
    scroll.CanvasSize = UDim2.new(0,0,0,0); scroll.ZIndex = 252; scroll.Parent = left
    library:registerAccent(scroll, "ScrollBarImageColor3")
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0,2); layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = scroll
    local scrollPad = Instance.new("UIPadding")
    scrollPad.PaddingTop = UDim.new(0,3); scrollPad.PaddingLeft = UDim.new(0,3); scrollPad.PaddingRight = UDim.new(0,3)
    scrollPad.Parent = scroll

    -- RIGHT: selected-player card (45% width) — avatar + name + stats + actions
    local right = panel(0, 0.45, -0)
    right.Position = UDim2.new(0.55, 2, 0, 0)
    local rStrip = Instance.new("Frame")
    rStrip.BackgroundColor3 = library.libColor; rStrip.BorderSizePixel = 0
    rStrip.Size = UDim2.new(1,0,0,1); rStrip.ZIndex = 253; rStrip.Parent = right
    library:registerAccent(rStrip)

    local avatar = Instance.new("ImageLabel")
    avatar.BackgroundColor3 = Color3.fromRGB(24,24,24)
    avatar.BorderColor3 = Color3.fromRGB(0,0,0); avatar.BorderSizePixel = 1
    avatar.Position = UDim2.fromOffset(8, 10)
    avatar.Size = UDim2.fromOffset(64, 64)
    avatar.ZIndex = 253; avatar.Parent = right

    local selName = Instance.new("TextLabel")
    selName.BackgroundTransparency = 1
    selName.Position = UDim2.fromOffset(80, 12)
    selName.Size = UDim2.new(1,-88,0,16)
    selName.Font = Enum.Font.Code; selName.Text = "no player selected"
    selName.TextColor3 = DIM; selName.TextSize = 13
    selName.TextXAlignment = Enum.TextXAlignment.Left; selName.TextTruncate = Enum.TextTruncate.AtEnd
    selName.TextStrokeTransparency = 0; selName.ZIndex = 253; selName.Parent = right

    local selInfo = Instance.new("TextLabel")
    selInfo.BackgroundTransparency = 1
    selInfo.Position = UDim2.fromOffset(80, 30)
    selInfo.Size = UDim2.new(1,-88,0,40)
    selInfo.Font = Enum.Font.Code; selInfo.Text = ""
    selInfo.TextColor3 = Color3.fromRGB(150,150,150); selInfo.TextSize = 12
    selInfo.TextXAlignment = Enum.TextXAlignment.Left; selInfo.TextYAlignment = Enum.TextYAlignment.Top
    selInfo.TextStrokeTransparency = 0; selInfo.ZIndex = 253; selInfo.Parent = right

    local function mkBtn(yOff, text)
        local b = Instance.new("TextButton")
        b.Position = UDim2.new(0, 8, 0, yOff)
        b.Size = UDim2.new(1, -16, 0, 22)
        b.BackgroundColor3 = Color3.fromRGB(28,28,28)
        b.BorderColor3 = Color3.fromRGB(0,0,0); b.BorderSizePixel = 1
        b.Font = Enum.Font.Code; b.Text = text
        b.TextColor3 = DIM; b.TextSize = 13; b.AutoButtonColor = true
        b.ZIndex = 253; b.Parent = right
        return b
    end
    local tpBtn   = mkBtn(84, "teleport")
    local specBtn = mkBtn(110, "spectate")
    local viewBtn = mkBtn(136, "copy name")

    local selectedPlayer
    local buttons = {}
    local plSpectateConn, plSpecCF

    local function headshot(uid)
        return "rbxthumb://type=AvatarHeadShot&id="..uid.."&w=150&h=150"
    end

    local function stopPlSpectate()
        if plSpectateConn then plSpectateConn:Disconnect(); plSpectateConn = nil end
        specBtn.Text = "spectate"
        pcall(function()
            local cam = Workspace.CurrentCamera
            if cam then
                cam.CameraType = Enum.CameraType.Custom
                cam.CameraSubject = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
            end
        end)
    end

    local function selectPlayer(p)
        selectedPlayer = p
        if p then
            selName.Text = (p == localPlayer) and (p.DisplayName.." (you)") or p.DisplayName
            selName.TextColor3 = (p == localPlayer) and CLIENT or DIM
            pcall(function() avatar.Image = headshot(p.UserId) end)
        else
            selName.Text = "no player selected"; selName.TextColor3 = DIM
            selInfo.Text = ""; avatar.Image = ""
        end
    end

    -- live stats for the selected player's card
    RunService.Heartbeat:Connect(function()
        if not (right.Visible and selectedPlayer and selectedPlayer.Parent) then return end
        local p = selectedPlayer
        local ch = p.Character
        local hum = ch and ch:FindFirstChildOfClass("Humanoid")
        local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
        local hp = hum and string.format("%d/%d", math.floor(hum.Health+0.5), math.floor(hum.MaxHealth+0.5)) or "-"
        local dist = "-"
        local mc = localPlayer.Character
        local mr = mc and mc:FindFirstChild("HumanoidRootPart")
        if hrp and mr then dist = string.format("%dm", math.floor((mr.Position-hrp.Position).Magnitude*0.28+0.5)) end
        selInfo.Text = string.format("@%s\nhp: %s   dist: %s", p.Name, hp, dist)
    end)

    local refreshing = false
    local function refresh()
        if refreshing then return end
        refreshing = true
        task.defer(function()
            refreshing = false
            if not scroll.Parent then return end
            for _, b in ipairs(buttons) do b:Destroy() end
            table.clear(buttons)
            local filter = string.lower(searchBox.Text or "")
            local order = 0
            for _, p in ipairs(players:GetPlayers()) do
                local label = (p == localPlayer) and (p.Name.." (you)") or p.Name
                if filter == "" or string.find(string.lower(label), filter, 1, true) then
                    order += 1
                    local b = Instance.new("TextButton")
                    b.BackgroundColor3 = (p == selectedPlayer) and Color3.fromRGB(30,30,30) or Color3.fromRGB(24,24,24)
                    b.BackgroundTransparency = (p == selectedPlayer) and 0 or 0.35
                    b.BorderSizePixel = 0
                    b.Size = UDim2.new(1,-6,0,20)
                    b.Font = Enum.Font.Code
                    b.Text = "  "..label
                    local isEnemy = p:GetAttribute("TeamID") ~= nil and localPlayer:GetAttribute("TeamID") ~= nil
                        and p:GetAttribute("TeamID") ~= localPlayer:GetAttribute("TeamID")
                    b.TextColor3 = (p == localPlayer) and CLIENT
                        or (p == selectedPlayer and library.libColor)
                        or (isEnemy and ENEMY or DIM)
                    b.TextSize = 13
                    b.TextXAlignment = Enum.TextXAlignment.Left
                    b.LayoutOrder = order
                    b.AutoButtonColor = true
                    b.ZIndex = 253
                    b.Parent = scroll
                    b.MouseButton1Click:Connect(function() selectPlayer(p); refresh() end)
                    buttons[#buttons+1] = b
                end
            end
            scroll.CanvasSize = UDim2.new(0,0,0, order*22 + 6)
        end)
    end

    searchBox:GetPropertyChangedSignal("Text"):Connect(refresh)
    players.PlayerAdded:Connect(refresh)
    players.PlayerRemoving:Connect(function(p)
        if selectedPlayer == p then selectPlayer(nil); stopPlSpectate() end
        refresh()
    end)

    tpBtn.MouseButton1Click:Connect(function()
        if not selectedPlayer or selectedPlayer == localPlayer then return end
        local tc = selectedPlayer.Character
        local tr = tc and tc:FindFirstChild("HumanoidRootPart")
        local mc = localPlayer.Character
        local mr = mc and mc:FindFirstChild("HumanoidRootPart")
        if tr and mr then pcall(function() mr.CFrame = tr.CFrame + Vector3.new(0,0,3) end) end
    end)

    viewBtn.MouseButton1Click:Connect(function()
        if selectedPlayer and setclipboard then pcall(setclipboard, selectedPlayer.Name); library:notify("copied "..selectedPlayer.Name) end
    end)

    specBtn.MouseButton1Click:Connect(function()
        if plSpectateConn then stopPlSpectate(); return end
        if not selectedPlayer or selectedPlayer == localPlayer then return end
        specBtn.Text = "unspectate"
        local cam0 = Workspace.CurrentCamera
        plSpecCF = cam0 and cam0.CFrame or CFrame.new()
        plSpectateConn = RunService.RenderStepped:Connect(function(dt)
            local p = selectedPlayer
            local tc = p and p.Character
            local hrp = tc and (tc:FindFirstChild("HumanoidRootPart") or tc:FindFirstChild("Head"))
            local cam = Workspace.CurrentCamera
            if not hrp or not cam then return end
            pcall(function()
                if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
                local head = tc:FindFirstChild("Head") or hrp
                local desired = CFrame.new(hrp.Position + hrp.CFrame.LookVector * -9 + Vector3.new(0,4,0), head.Position + Vector3.new(0,1,0))
                plSpecCF = plSpecCF:Lerp(desired, math.clamp(dt*10,0,1))
                cam.CFrame = plSpecCF
            end)
        end)
    end)
    localPlayer.CharacterRemoving:Connect(stopPlSpectate)

    refresh()
end)() -- end player list block

local menuGroup   = settingsTab:createGroup('left',  'menu settings')
local serverGroup = settingsTab:createGroup('right', 'server')
local configGroup = settingsTab:createGroup('left',  'configs')

menuGroup:addToggle({text = "show keybinds", flag = "ShowKeybinds"})
menuGroup:addToggle({text = "watermark", flag = "ShowWatermark", callback = function(v) _G.riotsHUD.Watermark = v end})

-- custom animated text watermark
menuGroup:addToggle({text = "text watermark", flag = "TextWatermark", value = false,
    callback = function(v) library.textWatermarkCfg.enabled = v end})
    :addColorpicker({text = "color", flag = "TextWatermarkColor", color = Color3.fromRGB(255,42,42),
        callback = function(v) library.textWatermarkCfg.color = v end})
menuGroup:markStart()
menuGroup:addTextbox({text = "text", flag = "TextWatermarkText", value = "riots.wtf",
    callback = function() library.textWatermarkCfg.text = library.flags["TextWatermarkText"] end})
menuGroup:addList({text = "animation", flag = "TextWatermarkAnim", value = "wave",
    values = {"static", "wave", "rainbow", "wave+rainbow"},
    callback = function(v) library.textWatermarkCfg.anim = v end})
menuGroup:dependsOn("TextWatermark")
menuGroup:addToggle({text = "click through", flag = "MenuClickThrough", callback = function(v) library.setClickThrough(v) end})
menuGroup:addColorpicker({text = "accent color", flag = "MenuAccent", color = Color3.fromRGB(255,42,42),
    callback = function(v) library:recolor(v) end})

configGroup:addTextbox({text = "config name",   flag = "config_name"})
configGroup:addConfigbox({flag = "selected_config", values = {}})
configGroup:addButton({text = "Create", callback = function() library:createConfig() end})
configGroup:addButton({text = "Load",   callback = function() library:loadConfig() end})
configGroup:addButton({text = "Save",   callback = function() library:saveConfig() end})
configGroup:addButton({text = "Delete", callback = function() library:deleteConfig() end})
configGroup:addButton({text = "Refresh",callback = function() library:refreshConfigs() end})
configGroup:addButton({text = "Set Autoload", callback = function() library:setAutoload(library.flags["selected_config"]) end})
configGroup:addButton({text = "Clear Autoload", callback = function() library:clearAutoload() end})

local themeGroup = settingsTab:createGroup('right', 'theme')
themeGroup:addList({text = "theme", flag = "ThemePreset", value = "classic",
    values = {"classic", "nebula", "sunrise", "galaxy", "gold"},
    callback = function(v) library:applyThemePreset(v) end})

serverGroup:addButton({text = "Copy Game Invite",  callback = function() end})
serverGroup:addButton({text = "Rejoin Server",     callback = function() end})
serverGroup:addButton({text = "Server Hop",        callback = function() end})

task.spawn(function()
    pcall(function() library:loadTheme() end)
    pcall(function() library:refreshConfigs() end)
    pcall(function() library:runAutoload() end)
end)

pcall(function() library:notify("loading riots.wtf...", 2) end)
menu.Enabled = true
pcall(playMenuIntro)
