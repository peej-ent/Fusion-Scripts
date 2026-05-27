-- Rotate Polyline Keyframe by PeeJ Ent --

--------------------
-- ROTATION CORE  --
--------------------

function rotateSplinePoints(pointsTable, steps)
    steps = steps or 1
    local numPoints = #pointsTable
    if numPoints < 2 then return pointsTable end
    steps = steps % numPoints
    if steps == 0 then return pointsTable end

    local newPoints = {}
    for i = 1, numPoints do
        local oldIndex = ((i - 1 + steps) % numPoints) + 1
        newPoints[i] = pointsTable[oldIndex]
    end
    return newPoints
end

function swapHandles(point)
    return {
        Linear = point.Linear,
        LockP  = point.LockP,
        LockPF = point.LockPF,
        Tagged = point.Tagged,
        X  = point.X,
        Y  = point.Y,
        LX = point.RX,
        LY = point.RY,
        RX = point.LX,
        RY = point.LY,
    }
end

function flipSplinePoints(pointsTable)
    local numPoints = #pointsTable
    if numPoints < 2 then return pointsTable end

    local newPoints = {}
    -- Keep point 1 as the anchor, reverse the rest — swap handles on all points
    newPoints[1] = swapHandles(pointsTable[1])
    for i = 2, numPoints do
        newPoints[i] = swapHandles(pointsTable[numPoints - i + 2])
    end
    return newPoints
end

function serializePoint(point)
    local parts = {}
    if point.Linear then table.insert(parts, "Linear = true") end
    if point.LockP  then table.insert(parts, "LockP = true")  end
    if point.LockPF then table.insert(parts, "LockPF = true") end
    if point.Tagged then table.insert(parts, "Tagged = true") end
    table.insert(parts, string.format("X = %.17e",  point.X))
    table.insert(parts, string.format("Y = %.17e",  point.Y))
    table.insert(parts, string.format("LX = %.17e", point.LX))
    table.insert(parts, string.format("LY = %.17e", point.LY))
    table.insert(parts, string.format("RX = %.17e", point.RX))
    table.insert(parts, string.format("RY = %.17e", point.RY))
    return "{ " .. table.concat(parts, ", ") .. " }"
end

function findSplineKey(data)
    for k, v in pairs(data) do
        if type(v) == "table" and v.KeyFrames then
            for frameIdx, _ in pairs(v.KeyFrames) do
                return k, frameIdx
            end
        end
    end
    return nil, nil
end

function serializeSpline(splineData, splineKey, frameIdx, flags)
    local flagParts = {}
    if flags then
        for k, v in pairs(flags) do
            if v == true then table.insert(flagParts, k .. " = true") end
        end
    end
    local flagsStr = (#flagParts > 0) and ("Flags = { " .. table.concat(flagParts, ", ") .. " }, ") or ""

    local output = {}
    table.insert(output, "{")
    table.insert(output, "\t" .. splineKey .. " = BezierSpline {")
    table.insert(output, "\t\tKeyFrames = {")
    table.insert(output, "\t\t\t[" .. frameIdx .. "] = { 0, " .. flagsStr .. "Value = Polyline {")
    table.insert(output, "\t\t\t\t\tClosed = true,")
    table.insert(output, "\t\t\t\t\tPoints = {")

    local points = splineData[splineKey].KeyFrames[frameIdx].Value.Points
    for i, point in ipairs(points) do
        local comma = (i < #points) and "," or ""
        table.insert(output, "\t\t\t\t\t\t" .. serializePoint(point) .. comma)
    end

    table.insert(output, "\t\t\t\t\t}")
    table.insert(output, "\t\t\t\t} }")
    table.insert(output, "\t\t}")
    table.insert(output, "\t}")
    table.insert(output, "}")

    return table.concat(output, "\n")
end

function parseClipboard()
    local clipboardStr = bmd.getclipboard()
    local env = {
        BezierSpline = function(t) return t end,
        Polyline     = function(t) return t end,
    }
    setmetatable(env, { __index = _G })

    local loadFunc, err = load("return " .. clipboardStr, "clipboard", "t", env)
    if not loadFunc then return nil, nil, nil, "Error parsing clipboard: " .. tostring(err) end

    local splineData = loadFunc()
    if not splineData then return nil, nil, nil, "Invalid data in clipboard." end

    local splineKey, frameIdx = findSplineKey(splineData)
    if not splineKey then return nil, nil, nil, "No spline data found." end

    local keyframe = splineData[splineKey].KeyFrames[frameIdx]
    if not keyframe or not keyframe.Value or not keyframe.Value.Points then
        return nil, nil, nil, "Keyframe has no Points."
    end

    return splineData, splineKey, frameIdx, nil
end

function doRotate(steps, itm)
    local splineData, splineKey, frameIdx, err = parseClipboard()
    if err then itm.Status.Text = err; return end

    local keyframe = splineData[splineKey].KeyFrames[frameIdx]
    local rotated  = rotateSplinePoints(keyframe.Value.Points, steps)
    splineData[splineKey].KeyFrames[frameIdx].Value.Points = rotated

    bmd.setclipboard(serializeSpline(splineData, splineKey, frameIdx, keyframe.Flags))

    local dir = steps > 0 and "CW" or "CCW"
    itm.Status.Text = "Rotated " .. dir .. " by " .. math.abs(steps) .. " step(s)."
    print("Rotated " .. dir .. " -> key: " .. splineKey .. ", frame: " .. tostring(frameIdx))
end

function doFlip(itm)
    local splineData, splineKey, frameIdx, err = parseClipboard()
    if err then itm.Status.Text = err; return end

    local keyframe = splineData[splineKey].KeyFrames[frameIdx]
    local flipped  = flipSplinePoints(keyframe.Value.Points)
    splineData[splineKey].KeyFrames[frameIdx].Value.Points = flipped

    bmd.setclipboard(serializeSpline(splineData, splineKey, frameIdx, keyframe.Flags))

    itm.Status.Text = "Order flipped."
    print("Flipped -> key: " .. splineKey .. ", frame: " .. tostring(frameIdx))
end

---------------
-- GUI PANEL --
---------------
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
    local width, height = 360, 130

    MainWindow = disp:AddWindow({
        ID = 'MainWind',
        WindowTitle = 'Rotate Polyline Keyframe',
        Geometry = { guiPosX, guiPosY, width, height },
        Spacing = 10,

        ui:VGroup{
            ID = 'root',

            ui:HGroup{
                ui:Label   { Text = "Steps:", Weight = 0.2 },
                ui:LineEdit{ ID = "Steps", Text = "1", Weight = 0.3 },
            },

            ui:HGroup{
                ui:Button{ ID = "RotateCCW", Text = "◀ CCW",   Weight = 0.4 },
                ui:Button{ ID = "RotateCW",  Text = "CW ▶",    Weight = 0.4 },
            },

            ui:HGroup{
                ui:Button{ ID = "Flip", Text = "⇅ Flip Order", Weight = 1.0 },
            },

            ui:HGroup{
                ui:Label{ ID = "Status", Text = "Ready.", Weight = 1.0, WordWrap = true },
            },
        },
    })

    local itm = MainWindow:GetItems()

    function MainWindow.On.RotateCW.Clicked(ev)
        local steps = math.floor((tonumber(itm.Steps.Text or "1") or 1) + 0.5)
        doRotate(steps, itm)
    end

    function MainWindow.On.RotateCCW.Clicked(ev)
        local steps = math.floor((tonumber(itm.Steps.Text or "1") or 1) + 0.5)
        doRotate(-steps, itm)
    end

    function MainWindow.On.Flip.Clicked(ev)
        doFlip(itm)
    end

    function MainWindow.On.MainWind.Close(ev)
        disp:ExitLoop()
    end

    MainWindow:Show()
    disp:RunLoop()
    MainWindow:Hide()
end

PopUpInfo()