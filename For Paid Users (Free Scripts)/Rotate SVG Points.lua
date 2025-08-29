
-- Rotate SVG Points by PeeJ Ent --
--------------------
-- ROTATION CORE  --
--------------------
-- Works with your DFSH format:
-- Line 1: "DFSH"
-- Lines 2..N: point rows (last is the closing duplicate of the first)

-- clone (don’t mutate original)
local function clone_points(t)
    local out = {}
    for i = 1, #t do out[i] = t[i] end
    return out
end

-- YOUR 1-step CW primitive (exactly what you do manually)
local function rotate_clockwise_1(points)
    local p = clone_points(points)
    table.insert(p, 1, p[#p - 1])  -- insert 2nd-to-last at top
    table.remove(p, #p)            -- drop last (closing dup)
    return p
end

-- True inverse: 1-step CCW primitive (keeps closed shape)
local function rotate_counter_1(points)
    local p = clone_points(points)
    table.remove(p, 1)             -- drop first
    table.insert(p, p[1])          -- re-close by duplicating NEW first at end
    return p
end

-- Loop the primitive N times. We mod by (#points-1) to skip no-op spins.
local function rotate_points(points, dir, steps)
    local spins = tonumber(steps or 0) or 0
    if spins <= 0 then return clone_points(points) end
    local period = math.max(#points - 1, 1)
    spins = spins % period

    local p = clone_points(points)
    if dir == "ccw" then
        for i = 1, spins do p = rotate_counter_1(p) end
    else -- default "cw"
        for i = 1, spins do p = rotate_clockwise_1(p) end
    end
    return p
end

-- Read DFSH (header + point lines)
local function read_dfsh(path)
    local f, err = io.open(path, "r")
    if not f then return nil, nil, "Can't open file: " .. tostring(err) end
    local lines = {}
    for ln in f:lines() do lines[#lines + 1] = ln end
    f:close()

    if #lines < 3 then return nil, nil, "Not enough lines (need DFSH + points)" end

    local header = lines[1]
    local points = {}
    for i = 2, #lines do
        local s = lines[i]:match("^%s*(.-)%s*$")
        if s ~= "" then points[#points + 1] = s end
    end
    if #points < 2 then return nil, nil, "Not enough point rows" end

    return header, points, nil
end

-- Write DFSH back
local function write_dfsh(path, header, points)
    local out, err = io.open(path, "w")
    if not out then return false, "Can't write output: " .. tostring(err) end
    out:write(header .. "\n")
    for i = 1, #points do out:write(points[i] .. "\n") end
    out:close()
    return true
end

-- One-shot file rotate (reads, rotates, writes). Uses your naming style.
local function rotate_dfsh_file(input_path, dir, steps)
    local header, pts, rerr = read_dfsh(input_path)
    if not header then return false, rerr end

    local rotated = rotate_points(pts, dir, steps)
    local suffix  = "_" .. (dir or "cw") .. "_" .. tostring(steps or 0)
    local output_path = input_path:gsub("(.+)%.(.-)$", "%1_rotated" .. suffix .. ".%2")

    local ok, werr = write_dfsh(output_path, header, rotated)
    if not ok then return false, werr end
    return true, output_path
end


---------------
-- GUI PANEL --
---------------
-- keep your style; default window position if none set
if guiPosXY ~= nil then
    guiPosX = guiPosXY[1]
    guiPosY = guiPosXY[2]
else
    guiPosX = 1500
    guiPosY = 600
end

function PopUpInfo()
    local ui   = fu.UIManager
    local disp = bmd.UIDispatcher(ui)
    local width, height = 360, 100

    MainWindow = disp:AddWindow({
        ID = 'MainWind',
        WindowTitle = 'Rotate Closed DFSH',
        Geometry = { guiPosX, guiPosY, width, height },
        Spacing = 10,

        ui:VGroup{
            ID = 'root',

            ui:HGroup{
                ui:LineEdit{ ID = "FilePath", PlaceholderText = "Select a .dfsh file", ReadOnly = true, Weight = 0.65 },
                ui:Button  { ID = "Browse",   Text = "Browse", Weight = 0.35 },
            },

            ui:HGroup{
                ui:Label   { Text = "Direction:", Weight = 0.2 },
                ui:ComboBox{ ID = "Dir", Weight = 0.3 },
                ui:Label   { Text = "Steps:", Weight = 0.2 },
                ui:LineEdit{ ID = "Steps", Text = "1", Weight = 0.3 },
            },

            ui:HGroup{
                ui:Button{ ID = "Rotate", Text = "Rotate", Weight = 0.35 },
                ui:Label { ID = "Status", Text = "Ready.", Weight = 0.65, WordWrap = true },
            },
        },
    })

    local itm = MainWindow:GetItems()

    -- Populate direction choices
    itm.Dir:AddItem("Clockwise")
    itm.Dir:AddItem("Counter-clockwise")
    itm.Dir.CurrentIndex = 0

    -- Browse: use the same pattern you used (fu:RequestFile)
    function MainWindow.On.Browse.Clicked(ev)
        local startDir = os.getenv("USERPROFILE") or os.getenv("HOME") or "C:/"
        local sel = tostring(fu:RequestFile(
            startDir,
            { FReqS_Title = 'Choose .dfsh File…' }
        ))
        if sel and sel ~= "" then
            itm.FilePath.Text = sel
            itm.Status.Text   = "File selected."
        else
            itm.Status.Text   = "No file selected."
        end
    end

    -- Rotate button
    function MainWindow.On.Rotate.Clicked(ev)
        local path  = itm.FilePath.Text or ""
        if path == "" then
            itm.Status.Text = "Please select a .dfsh file first."
            return
        end

        -- direction
        local dir = (itm.Dir.CurrentIndex == 0) and "cw" or "ccw"

        -- steps (sanitize to non-negative int)
        local steps = tonumber(itm.Steps.Text or "1") or 1
        steps = math.max(0, math.floor(steps + 0.0))

        itm.Status.Text = "Rotating " .. dir .. " x" .. tostring(steps) .. "…"
        local ok, msg = rotate_dfsh_file(path, dir, steps)
        if ok then
            itm.Status.Text = "✅ Saved at file location"
            print("[DFSH] Rotated -> " .. msg)
        else
            itm.Status.Text = "❌ " .. tostring(msg)
            print("[DFSH] Error: " .. tostring(msg))
        end
    end

    function MainWindow.On.MainWind.Close(ev)
        -- optionally: fusion:SetData("your.panelPosition", itm.MainWind.Geometry)
        disp:ExitLoop()
    end

    MainWindow:Show()
    disp:RunLoop()
    MainWindow:Hide()
end

PopUpInfo()
