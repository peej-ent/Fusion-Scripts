------------------------------------------------------------
-- Rotate Closed DFSH (No GUI)
-- - Uses your proven 1-step CW primitive
-- - Supports CCW via the exact inverse
-- - Repeats N times
-- - Writes next to input with a suffix (or a fixed path)
------------------------------------------------------------

--------------------------
-- Config (edit these)  --
--------------------------
local INPUT_PATH          = "C:/path/to/shape.dfsh"  -- <-- set this
local DIRECTION           = "cw"                     -- "cw" or "ccw"
local STEPS               = 3                        -- integer >= 0
local AUTO_SUFFIX_OUTPUT  = true                     -- true = auto name; false = use OUTPUT_PATH below
local OUTPUT_PATH         = "C:/path/to/shape_rotated.dfsh"  -- used only if AUTO_SUFFIX_OUTPUT=false

--------------------------
-- Core helpers         --
--------------------------
local function clone_points(t)
    local out = {}; for i=1,#t do out[i] = t[i] end; return out
end

-- Your exact 1-step clockwise primitive:
local function rotate_clockwise_1(points)
    local p = clone_points(points)
    table.insert(p, 1, p[#p - 1])  -- insert 2nd-to-last at top
    table.remove(p, #p)            -- drop last (closing duplicate)
    return p
end

-- True inverse (1-step counter-clockwise):
local function rotate_counter_1(points)
    local p = clone_points(points)
    table.remove(p, 1)             -- drop first
    table.insert(p, p[1])          -- re-close by duplicating NEW first at end
    return p
end

-- Repeat the primitive N times (mod by #points-1 to skip no-ops)
local function rotate_points(points, dir, steps)
    local spins = math.max(0, math.floor(tonumber(steps or 0) or 0))
    if spins == 0 then return clone_points(points) end
    local period = math.max(#points - 1, 1)
    spins = spins % period

    local p = clone_points(points)
    if dir == "ccw" then
        for _=1,spins do p = rotate_counter_1(p) end
    else -- default "cw"
        for _=1,spins do p = rotate_clockwise_1(p) end
    end
    return p
end

--------------------------
-- File I/O            --
--------------------------
local function read_dfsh(path)
    local f, err = io.open(path, "r"); if not f then return nil, nil, "open failed: "..tostring(err) end
    local lines = {}; for ln in f:lines() do lines[#lines+1] = ln end; f:close()
    if #lines < 3 then return nil, nil, "not enough lines (need DFSH + points)" end
    if not tostring(lines[1]):match("^%s*DFSH%s*$") then return nil, nil, "line 1 must be 'DFSH'" end

    local header = lines[1]
    local points = {}
    for i=2,#lines do
        local s = lines[i]:match("^%s*(.-)%s*$")
        if s ~= "" then points[#points+1] = s end
    end
    if #points < 2 then return nil, nil, "not enough point rows" end
    return header, points
end

local function write_dfsh(path, header, points)
    local out, err = io.open(path, "w"); if not out then return false, "write failed: "..tostring(err) end
    out:write(header .. "\n")
    for i=1,#points do out:write(points[i] .. "\n") end
    out:close()
    return true
end

local function with_suffix(path, dir, steps)
    local suffix = string.format("_rotated_%s_%d", dir or "cw", steps or 0)
    local out = path:gsub("(.+)%.(.-)$", "%1"..suffix..".%2")
    if out == path then out = path .. suffix end
    return out
end

--------------------------
-- Main                 --
--------------------------
local function main()
    -- read
    local header, pts, rerr = read_dfsh(INPUT_PATH)
    if not header then
        print("❌ Read error:", rerr); return
    end

    -- rotate
    local dir = (DIRECTION == "ccw") and "ccw" or "cw"
    local steps = math.max(0, math.floor(tonumber(STEPS or 0) or 0))
    local rotated = rotate_points(pts, dir, steps)

    -- output path
    local outPath = AUTO_SUFFIX_OUTPUT and with_suffix(INPUT_PATH, dir, steps) or OUTPUT_PATH

    -- write
    local ok, werr = write_dfsh(outPath, header, rotated)
    if not ok then
        print("❌ Write error:", werr); return
    end

    print("✅ Saved:", outPath)
end

main()
