-- Rotate Polyline Keyframe by PeeJ Ent --
-- No UI version: always rotates by 1 step --

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

--------------------
--      MAIN      --
--------------------

local clipboardStr = bmd.getclipboard()

local env = {
    BezierSpline = function(t) return t end,
    Polyline     = function(t) return t end,
}
setmetatable(env, { __index = _G })

local loadFunc, err = load("return " .. clipboardStr, "clipboard", "t", env)
if not loadFunc then
    print("Error parsing clipboard: " .. tostring(err))
    return
end

local splineData = loadFunc()
if not splineData then
    print("Invalid data in clipboard.")
    return
end

local splineKey, frameIdx = findSplineKey(splineData)
if not splineKey then
    print("No spline data found in clipboard.")
    return
end

local keyframe = splineData[splineKey].KeyFrames[frameIdx]
if not keyframe or not keyframe.Value or not keyframe.Value.Points then
    print("Keyframe has no Points.")
    return
end

local rotated = rotateSplinePoints(keyframe.Value.Points, 1)
splineData[splineKey].KeyFrames[frameIdx].Value.Points = rotated

local output = serializeSpline(splineData, splineKey, frameIdx, keyframe.Flags)
bmd.setclipboard(output)

print("Rotated by 1 step. (key: " .. splineKey .. ", frame: " .. tostring(frameIdx) .. ")")