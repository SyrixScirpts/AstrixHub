-- Astrix Hub

local SOURCE = "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"

-- No teardown on purpose: running the script again stacks a second window
-- instead of replacing the one already on screen. Unload() closes yours.

local loaded, WindUI = pcall(function()
    return loadstring(game:HttpGet(SOURCE))()
end)

if not loaded or type(WindUI) ~= "table" then
    warn("[Astrix Hub] UI library did not load: " .. tostring(WindUI))
    return
end

getgenv().__WindUIRef = WindUI

local notifyEnabled = true
local notifyDuration = 4
local defaultTheme = "Crimson"
-- The theme the window should be showing; the title paint reads it by name.
local currentTheme = defaultTheme

-- Extra callbacks fired after any theme change (swatch ring sync, etc).
local themeChangeHooks = {}

local function notify(title, content, duration)
    if not notifyEnabled then
        return
    end
    pcall(function()
        WindUI:Notify({
            Title = title,
            Content = content,
            Duration = duration or notifyDuration,
        })
    end)
end

local function applyTheme(name)
    if type(name) ~= "string" then
        return false
    end
    local ok = pcall(function()
        WindUI:SetTheme(name)
    end)
    if ok then
        currentTheme = name
        for _, hook in ipairs(themeChangeHooks) do
            pcall(hook, name)
        end
    end
    return ok
end

local function toKeyCode(value)
    if typeof(value) == "EnumItem" then
        return value
    end
    if type(value) == "string" then
        local ok, code = pcall(function()
            return Enum.KeyCode[value]
        end)
        if ok and code then
            return code
        end
    end
    return nil
end

local function sanitise(value)
    local text = tostring(value)
    text = text:gsub("[^%w%-_ ]", "")
    text = text:gsub("%s+", "_")
    if #text > 40 then
        text = text:sub(1, 40)
    end
    if text == "" then
        text = "Game_" .. tostring(game.PlaceId)
    end
    return text
end

local gameName = game.Name
pcall(function()
    local info = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
    if info and type(info.Name) == "string" and info.Name ~= "" then
        gameName = info.Name
    end
end)

-- One config per game, so the same script keeps separate settings everywhere.
local gameConfigName = sanitise(gameName)
-- The name box starts empty; nothing is typed in for the user.
local configName = ""

-- Window title - edit the game name here yourself every time.
local titleText = "Astrix Hub | Army Commander Tycoon | discord.gg/b97Q6ph3TE"

local Window = WindUI:CreateWindow({
    Title = titleText,
    Author = "",
    Folder = "AstrixHub",
    Size = UDim2.fromOffset(700, 500),
    Theme = defaultTheme,
    ToggleKey = Enum.KeyCode.RightShift,
    Resizable = true,
    Transparent = true,
    HideSearchBar = false,
    SearchBarEnabled = true,
    SideBarWidth = 190,
})

-- Slightly translucent panel background.
pcall(function()
    Window:SetBackgroundTransparency(0.2)
end)

-- Paint the title in the current UI colour, kept legible against the dark panel.
-- Walks every hub screen so stacked instances all get painted.

-- The library's own `Theme` field stays on the Dark default until someone calls
-- SetTheme, so read the accent straight out of the theme table we asked for.
local function themeAccent()
    local ok, themes = pcall(function()
        return WindUI:GetThemes()
    end)
    if ok and type(themes) == "table" then
        local theme = themes[currentTheme]
        if type(theme) == "table" then
            if typeof(theme.Accent) == "Color3" then
                return theme.Accent
            end
            if typeof(theme.ElementBackground) == "Color3" then
                return theme.ElementBackground
            end
        end
    end
    local okLive, live = pcall(function()
        return WindUI.Theme
    end)
    if okLive and type(live) == "table" and typeof(live.Accent) == "Color3" then
        return live.Accent
    end
    return Color3.fromHex("#b91c1c")
end

local function paintTitle()
    local guis = {}
    for _, child in ipairs(gethui():GetChildren()) do
        if child:IsA("ScreenGui") and child.Name == "WindUI" then
            table.insert(guis, child)
        end
    end
    if #guis == 0 then
        return
    end
    local labels = {}
    local function walk(inst, depth)
        if depth > 16 then
            return
        end
        for _, child in ipairs(inst:GetChildren()) do
            if child:IsA("TextLabel") and child.Text == titleText then
                table.insert(labels, child)
            end
            walk(child, depth + 1)
        end
    end
    for _, gui in ipairs(guis) do
        walk(gui, 0)
    end
    local colour = themeAccent():Lerp(Color3.new(1, 1, 1), 0.35)
    for _, label in ipairs(labels) do
        label.TextColor3 = colour
    end
end

pcall(function()
    WindUI:OnThemeChange(function(name)
        if type(name) == "string" then
            currentTheme = name
        end
        task.defer(paintTitle)
    end)
end)

-- The library stamps its theme colours onto the topbar while the window builds,
-- so paint a few times until the window has settled instead of trusting one shot.
task.spawn(function()
    for _ = 1, 12 do
        task.wait(0.4)
        paintTitle()
    end
end)

-- Config helpers.
local NONE_CONFIG = "None"
-- Old builds wrote a "Default" config; the list shows "None" instead.
local LEGACY_CONFIG = "Default"

-- Filled in once the config widgets exist.
local configDropdown
local configInput
local configReady = false
-- Name picked in the dropdown; Load and Delete act on this, never on the box.
local selectedConfig = NONE_CONFIG

-- The configs that are actually saved on disk.
local function savedConfigs()
    local ok, list = pcall(function()
        return Window.ConfigManager:AllConfigs()
    end)
    local names = {}
    if ok and type(list) == "table" then
        for _, name in ipairs(list) do
            local clean = tostring(name)
            if clean ~= "" and clean ~= NONE_CONFIG and clean ~= LEGACY_CONFIG then
                table.insert(names, clean)
            end
        end
    end
    return names
end

local function configExists(name)
    if type(name) ~= "string" or name == "" or name == NONE_CONFIG or name == LEGACY_CONFIG then
        return false
    end
    for _, candidate in ipairs(savedConfigs()) do
        if candidate == name then
            return true
        end
    end
    return false
end

-- "None" always sits on top as the blank-name entry, then the saved configs.
local function configList()
    local ordered = { NONE_CONFIG }
    local rest = savedConfigs()
    table.sort(rest)
    for _, name in ipairs(rest) do
        table.insert(ordered, name)
    end
    return ordered
end

local function getConfig(name)
    local ok, cfg = pcall(function()
        return Window.ConfigManager:Config(name or configName)
    end)
    if ok and cfg then
        return cfg
    end
    return nil
end

-- Rebuild the config dropdown after a save or delete.
local function refreshConfigs(preferred)
    if not configDropdown then
        return
    end
    local values = configList()

    -- Sit on the caller's pick, else the current selection, else None.
    local target = preferred
    if type(target) ~= "string" or not table.find(values, target) then
        target = table.find(values, selectedConfig) and selectedConfig or NONE_CONFIG
    end

    -- Refresh and Select both fire the dropdown callback, so settle the pick after them.
    pcall(function()
        configDropdown:Refresh(values)
        configDropdown:Select(target)
    end)

    selectedConfig = target
end

local function saveConfig()
    local name = selectedConfig
    if type(name) ~= "string" or name == "" or name == NONE_CONFIG then
        notify("Config", "Select a config in the list first")
        return
    end
    local cfg = getConfig(name)
    if not cfg then
        notify("Config", "Config manager unavailable")
        return
    end
    local ok = pcall(function()
        cfg:SetAsCurrent()
        cfg:Save()
    end)
    notify("Config", ok and ("Saved " .. name) or ("Could not save " .. name))
    refreshConfigs(name)
end

-- Typing a name creates that config and selects it, so Save can fill it in.
local pendingCreate
local function createFromTyping(value)
    local name = type(value) == "string" and value or ""
    configName = name
    if name == "" or name == NONE_CONFIG or name == LEGACY_CONFIG then
        return
    end

    -- Wait for a short pause in typing, so half a word never lands on disk.
    if pendingCreate then
        task.cancel(pendingCreate)
    end
    pendingCreate = task.delay(0.6, function()
        pendingCreate = nil
        if configName ~= name or configExists(name) then
            return
        end
        local cfg = getConfig(name)
        if not cfg then
            notify("Config", "Config manager unavailable")
            return
        end
        local ok = pcall(function()
            cfg:Save()
        end)
        if ok then
            notify("Config", "Created " .. name .. " - press Save to store your settings")
        else
            notify("Config", "Could not create " .. name)
        end
        refreshConfigs(name)
    end)
end

local function loadConfig()
    local name = selectedConfig
    if not configExists(name) then
        notify("Config", "No config named " .. tostring(name))
        return
    end
    local cfg = getConfig(name)
    if not cfg then
        notify("Config", "Config manager unavailable")
        return
    end
    local ok = pcall(function()
        cfg:SetAsCurrent()
        cfg:Load()
    end)
    notify("Config", ok and ("Loaded " .. name) or ("Could not load " .. name))
end

local function deleteConfig()
    local name = selectedConfig
    if type(name) ~= "string" or name == "" or name == NONE_CONFIG then
        notify("Config", "Nothing to delete")
        return
    end
    if not configExists(name) then
        notify("Config", "No config named " .. name)
        refreshConfigs()
        return
    end
    local ok, success, message = pcall(function()
        return Window.ConfigManager:DeleteConfig(name)
    end)
    if ok and success then
        notify("Config", "Deleted " .. name)
    elseif ok and message then
        notify("Config", tostring(message))
    else
        notify("Config", "Could not delete " .. name)
    end
    refreshConfigs()
end

-- Restore this game's settings on load, but only when it has been saved before.
task.spawn(function()
    if not configExists(gameConfigName) then
        return
    end
    local cfg = getConfig(gameConfigName)
    if not cfg then
        return
    end
    pcall(function()
        cfg:SetAsCurrent()
        cfg:SetAutoLoad(true)
        cfg:Load()
    end)
end)

-- Anti-AFK
local antiAfkConnection
local function setAntiAfk(state)
    if state then
        if antiAfkConnection then
            return
        end
        local vu = game:GetService("VirtualUser")
        antiAfkConnection = game:GetService("Players").LocalPlayer.Idled:Connect(function()
            pcall(function()
                vu:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
                task.wait(1)
                vu:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
            end)
        end)
        notify("Anti AFK", "Enabled")
    else
        if antiAfkConnection then
            antiAfkConnection:Disconnect()
            antiAfkConnection = nil
        end
        notify("Anti AFK", "Disabled")
    end
end

local function unload()
    if antiAfkConnection then
        antiAfkConnection:Disconnect()
        antiAfkConnection = nil
    end
    pcall(function()
        Window:Destroy()
    end)
    -- Only clear the shared handles if they point at this instance; another
    -- copy of the script may still be alive with its own window.
    if getgenv then
        local hub = getgenv().AstrixHub
        if type(hub) == "table" and hub.Window == Window then
            getgenv().AstrixHub = nil
        end
        if getgenv().__WindUIRef == WindUI then
            getgenv().__WindUIRef = nil
        end
    end
end

local Home = Window:Tab({ Title = "Home", Icon = "house" })
Home:Section({ Title = "Overview" })
Home:Paragraph({
    Title = "Astrix Hub",
    Desc = "RightShift opens and closes the menu. Drag the topbar to move it.",
})

local Settings = Window:Tab({ Title = "Settings", Icon = "settings" })

local themes = WindUI:GetThemes()
local swatchOrder = {
    { "Crimson", "Red" },
    { "Indigo", "Blue" },
    { "Violet", "Purple" },
    { "Emerald", "Green" },
    { "Rose", "Pink" },
    { "Sky", "Cyan" },
    { "Amber", "Orange" },
    { "Dark", "Dark" },
}

Settings:Section({ Title = "Game" })
Settings:Toggle({
    Title = "Anti AFK",
    Desc = "Keeps you out of the idle kick",
    Value = false,
    Flag = "anti_afk",
    Callback = function(state)
        setAntiAfk(state)
    end,
})
Settings:Keybind({
    Title = "Toggle Key",
    Desc = "Click, then press the key you want",
    Value = "RightShift",
    Flag = "toggle_key",
    Callback = function(key)
        local code = toKeyCode(key)
        if code then
            pcall(function()
                Window:SetToggleKey(code)
            end)
            notify("Keybind", "Toggle key set to " .. tostring(key))
        end
    end,
})

Settings:Section({ Title = "Config" })
local initialConfigs = configList()
local initialSelection = table.find(initialConfigs, selectedConfig) and selectedConfig or NONE_CONFIG

configDropdown = Settings:Dropdown({
    Title = "Configs",
    Desc = "Pick a config, then save, load or delete it",
    Values = initialConfigs,
    Value = initialSelection,
    Callback = function(selected)
        -- The widget fires this once while building too; ignore that fire.
        if not configReady then
            return
        end
        selectedConfig = tostring(selected)
    end,
})
configInput = Settings:Input({
    Title = "Config Name",
    Value = "",
    Placeholder = "Type a name to create it",
    Callback = function(value)
        createFromTyping(value)
    end,
})
configReady = true
Settings:Button({ Title = "Save Config", Callback = saveConfig })
Settings:Button({ Title = "Load Config", Callback = loadConfig })
Settings:Button({ Title = "Delete Config", Callback = deleteConfig })

-- Last row of the tab: the colour picker.
Settings:Section({ Title = "UI Color" })

-- Small circular swatches parented straight into the tab's scroll frame,
-- so they sit as one compact row instead of full-width buttons.
local swatchElements = {}
local swatchRow = Instance.new("Frame")
swatchRow.Name = "AstrixSwatches"
swatchRow.BackgroundTransparency = 1
swatchRow.BorderSizePixel = 0
swatchRow.Size = UDim2.new(1, 0, 0, 34)
swatchRow.Parent = Settings.UIElements.ContainerFrame

local swatchLayout = Instance.new("UIListLayout")
swatchLayout.FillDirection = Enum.FillDirection.Horizontal
swatchLayout.VerticalAlignment = Enum.VerticalAlignment.Center
swatchLayout.Padding = UDim.new(0, 10)
swatchLayout.SortOrder = Enum.SortOrder.LayoutOrder
swatchLayout.Parent = swatchRow

local activeStroke
local function markActive(stroke)
    if activeStroke then
        activeStroke.Enabled = false
    end
    activeStroke = stroke
    if stroke then
        stroke.Enabled = true
    end
end

for order, entry in ipairs(swatchOrder) do
    local themeName, label = entry[1], entry[2]
    local theme = themes[themeName]
    local colour
    if theme then
        if typeof(theme.Accent) == "Color3" then
            colour = theme.Accent
        elseif typeof(theme.ElementBackground) == "Color3" then
            colour = theme.ElementBackground
        end
    end
    colour = colour or Color3.fromRGB(90, 90, 90)

    local dot = Instance.new("TextButton")
    dot.Name = "Swatch_" .. themeName
    dot.Text = ""
    dot.AutoButtonColor = true
    dot.BorderSizePixel = 0
    dot.BackgroundColor3 = colour
    dot.Size = UDim2.fromOffset(26, 26)
    dot.LayoutOrder = order
    dot.Parent = swatchRow

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = dot

    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 2
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Transparency = 0.25
    stroke.Enabled = false
    stroke.Parent = dot

    dot.MouseButton1Click:Connect(function()
        if applyTheme(themeName) then
            markActive(stroke)
            notify("UI Color", label)
        end
    end)

    table.insert(swatchElements, {
        element = dot,
        colour = colour,
        theme = themeName,
        label = label,
        SetActive = function(state)
            if state then
                markActive(stroke)
            elseif activeStroke == stroke then
                markActive(nil)
            end
        end,
    })
end

-- Ring the swatch matching the current theme.
table.insert(themeChangeHooks, function(current)
    for _, swatch in ipairs(swatchElements) do
        if swatch.theme == current then
            markActive(swatch.element:FindFirstChildOfClass("UIStroke"))
            break
        end
    end
end)
task.defer(function()
    local ok, current = pcall(function()
        return WindUI:GetCurrentTheme()
    end)
    if ok and type(current) == "string" then
        for _, swatch in ipairs(swatchElements) do
            if swatch.theme == current then
                markActive(swatch.element:FindFirstChildOfClass("UIStroke"))
                break
            end
        end
    end
end)

-- Drops an implicit self, so both AstrixHub:Save() and AstrixHub.Save() work.
local function bind(fn)
    return function(first, ...)
        if type(first) == "table" then
            return fn(...)
        end
        return fn(first, ...)
    end
end

getgenv().AstrixHub = {
    Window = Window,
    WindUI = WindUI,
    Notify = bind(notify),
    Unload = bind(unload),
    SetTheme = bind(applyTheme),
    Save = bind(saveConfig),
    Load = bind(loadConfig),
    Delete = bind(deleteConfig),
    Create = bind(function(name)
        createFromTyping(type(name) == "string" and name or configName)
    end),
    AntiAfk = bind(setAntiAfk),
    ConfigName = bind(function(name)
        if type(name) == "string" and name ~= "" then
            configName = name
            if configInput then
                pcall(function()
                    configInput:Set(name)
                end)
            end
        end
        return configName
    end),
    Configs = function()
        return configList()
    end,
    -- The dropdown pick: what Load and Delete act on. Never touches the name box.
    Selected = bind(function(name)
        if type(name) == "string" and name ~= "" then
            pcall(function()
                configDropdown:Select(name)
            end)
        end
        return selectedConfig
    end),
    Swatches = swatchElements,
}

task.delay(0.6, function()
    notify("Astrix Hub", "Loaded - RightShift to toggle")
end)
