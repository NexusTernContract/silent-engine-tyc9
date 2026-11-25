if _G.__SYMPHONY_AP then
    local old = _G.__SYMPHONY_AP
    old.alive = false
    pcall(function() old.conn:Disconnect() end)
    pcall(function() old.win:Destroy() end)
    _G.__SYMPHONY_AP = nil
end

local Players = game:GetService('Players')
local RunService = game:GetService('RunService')
local LP = Players.LocalPlayer

local state = { alive = true, enabled = false, lastNote = {} }
_G.__SYMPHONY_AP = state

local function upsOf(f)
    local ok, ups = pcall(getupvalues, f)
    if not ok or type(ups) ~= 'table' then return nil end
    return ups
end

local engine, resolveErr = nil, nil
do
    local function isKeymap(t)
        for k in pairs(t) do
            return typeof(k) == 'EnumItem'
        end
        return false
    end

    local function validateLaneDown(f)
        if type(f) ~= 'function' then return nil end
        local ld = upsOf(f)
        if not ld or #ld < 13 then return nil end
        local Config = ld[8]
        if type(Config) ~= 'table' then return nil end
        if type(rawget(Config, 'PerfectWindow')) ~= 'number' then return nil end
        if type(rawget(Config, 'DefaultLaneKeys')) ~= 'table' then return nil end
        if type(ld[4]) ~= 'number' or type(ld[7]) ~= 'number' then return nil end
        if type(ld[10]) ~= 'table' or type(ld[2]) ~= 'table' then return nil end
        if type(ld[11]) ~= 'number' or type(ld[12]) ~= 'function' then return nil end
        return { laneDown = f, Config = Config, held = ld[2] }
    end

    local ok, res = pcall(function()
        local conns = getconnections(LP:GetAttributeChangedSignal('OrchestraPadKeys'))
        local found = nil
        for _, c in ipairs(conns) do
            if found then break end
            local u = upsOf(c.Function)
            if u and type(u[1]) == 'function' and type(u[2]) == 'boolean' and type(u[3]) == 'function' then
                local bl = upsOf(u[3])
                if bl then
                    for i = 1, #bl do
                        if found then break end
                        if type(bl[i]) == 'function' then
                            local ola = upsOf(bl[i])
                            if ola then
                                for j = 1, #ola do
                                    if found then break end
                                    if type(ola[j]) == 'function' then
                                        local hit = validateLaneDown(ola[j])
                                        if hit then
                                            local keymap
                                            for k = 1, #ola do
                                                if type(ola[k]) == 'table' and isKeymap(ola[k]) then
                                                    keymap = ola[k]
                                                end
                                            end
                                            if keymap then
                                                hit.onLaneAction = bl[i]
                                                hit.keymap = keymap
                                                found = hit
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        assert(found, 'RhythmClient lane engine not found')
        return found
    end)
    if ok then engine = res else resolveErr = tostring(res) end
end
state.engine = engine

local function pressLane(lane)
    local Config = engine.Config
    local keymap = engine.keymap
    local key = Config.LaneKeys and Config.LaneKeys[lane]
    if not (key and keymap[key] == lane) then
        key = nil
        for k, v in pairs(keymap) do
            if v == lane then key = k break end
        end
    end
    if not key then return false end
    return pcall(engine.onLaneAction, nil, Enum.UserInputState.Begin, { KeyCode = key })
end

if engine then
    state.conn = RunService.Heartbeat:Connect(function()
        if not state.alive then return end
        if not state.enabled then return end

        local ld = upsOf(engine.laneDown)
        if not ld then return end
        local clockOff, songStart, notes = ld[4], ld[7], ld[10]
        if type(clockOff) ~= 'number' or type(songStart) ~= 'number' or type(notes) ~= 'table' then return end
        local n = #notes
        if n == 0 then return end

        local Config = engine.Config
        local audioOff = (Config.AudioOffset or 0) + (LP:GetAttribute('OrchestraAudioOffset') or 0) / 1000
        local pos = (os.clock() + clockOff) - songStart - audioOff

        local goodWindow = (type(ld[11]) == 'number' and ld[11]) or (Config.GoodWindow or 0.12)
        local horizon = goodWindow + (Config.LateGrace or 0.05) - 0.02

        for i = 1, n do
            local note = notes[i]
            if type(note) == 'table' and not note.Judged then
                local t = note.Time
                if type(t) == 'number' then
                    local dt = pos - t
                    if dt >= 0 and dt <= horizon then
                        local lane = note.Lane
                        if type(lane) == 'number' and lane >= 1 and lane <= 4 then
                            if pressLane(lane) then
                                state.lastNote[lane] = { t = t, len = tonumber(note.Length) or 0 }
                            end
                        end
                    end
                end
            end
        end

        for lane, info in pairs(state.lastNote) do
            if pos > info.t + info.len + 0.06 then
                engine.held[lane] = nil
                state.lastNote[lane] = nil
            end
        end
    end)
    print('[SymphonyAP] engine hooked: laneDown/onLaneAction/note-list online')
else
    warn('[SymphonyAP] engine hook FAILED: ' .. tostring(resolveErr))
end

local function setEnabled(v)
    state.enabled = v
    if not v then state.lastNote = {} end
end

local function fallbackGui()
    local gui = Instance.new('ScreenGui')
    gui.Name = 'SymphonyAutoplay'
    gui.ResetOnSpawn = false
    gui.Parent = LP:WaitForChild('PlayerGui')
    local btn = Instance.new('TextButton')
    btn.Size = UDim2.fromOffset(150, 40)
    btn.Position = UDim2.new(0.5, -75, 0, 8)
    btn.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.TextSize = 16
    btn.Font = Enum.Font.GothamMedium
    btn.Text = 'Autoplay: OFF'
    btn.Parent = gui
    btn.MouseButton1Click:Connect(function()
        setEnabled(not state.enabled)
        btn.Text = 'Autoplay: ' .. (state.enabled and 'ON' or 'OFF')
        btn.BackgroundColor3 = state.enabled and Color3.fromRGB(46, 160, 84) or Color3.fromRGB(40, 40, 48)
    end)
    state.win = { Destroy = function() gui:Destroy() end }
    print('[SymphonyAP] WindUI unavailable, using fallback toggle')
end

local windOk = pcall(function()
    local WindUI = loadstring(game:HttpGet('https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua'))()
    assert(typeof(WindUI) == 'table' and WindUI.CreateWindow, 'WindUI load failed')

    local Window = WindUI:CreateWindow({
        Title = 'Symphony Autoplay',
        Icon = 'music-note-bold-duotone',
        Folder = 'SymphonyAutoplay',
        OpenButton = { Enabled = true, Title = 'Symphony Autoplay' },
    })
    state.win = Window

    local Tab = Window:Tab({ Title = 'Autoplay', Icon = 'music-note-bold-duotone' })
    Tab:Toggle({
        Title = 'Autoplay Notes',
        Desc = 'Hits every note perfectly - holds included. Start any song and watch it play itself.',
        Default = false,
        Callback = function(v)
            setEnabled(v)
            WindUI:Notify({
                Title = 'Symphony Autoplay',
                Content = v and 'Enabled - start or keep playing a song.' or 'Disabled.',
                Icon = 'music-note-bold-duotone',
                Duration = 3,
            })
        end,
    })

    WindUI:Notify({
        Title = 'Symphony Autoplay',
        Content = engine and 'Engine hooked - ready to play.' or ('Hook failed: ' .. tostring(resolveErr)),
        Icon = 'music-note-bold-duotone',
        Duration = 5,
    })
    print('[SymphonyAP] WindUI ready')
end)

if not windOk then fallbackGui() end