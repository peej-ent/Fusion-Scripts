-- Toggle MacroOperator <-> GroupOperator in place, preserving main-chain connections when present.
-- Safe against nodes with no main input/output.
-- Preserves original clipboard contents.

local comp = comp

-- ---------- Helpers ----------
local function getPrevConnectedTool(t) -- upstream into t's MainInput
    if not t then return nil end
    local inp = t:FindMainInput(1)
    if not inp then return nil end
    local outp = inp:GetConnectedOutput()
    if not outp then return nil end
    return outp:GetTool()
end

local function getNextConnectedTool(t) -- first downstream from t's MainOutput
    if not t then return nil end
    local outp = t:FindMainOutput(1)
    if not outp then return nil end
    local conns = outp:GetConnectedInputs() or {} -- no index arg
    for _, inp in pairs(conns) do                -- use pairs (can be non-sequence)
        return inp:GetTool() -- take first
    end
    return nil
end

local function convert_regid_in_setting_text(srcRegID, dstRegID, node)
    -- Copy selected node's .setting to clipboard and swap header RegID.
    comp:Copy(node)
    local clip = bmd.getclipboard()
    if not clip or #clip == 0 then
        return nil, "Clipboard empty after Copy()"
    end
    -- Ensure a closing brace exists
    if clip:sub(-1) ~= "}" then
        clip = clip .. "\n}"
    end

    -- Replace the first occurrence of "= <RegID> {" (most common header)
    local from1 = "= " .. srcRegID .. " {"
    local to1   = "= " .. dstRegID .. " {"
    local out, n = clip:gsub(from1, to1, 1)

    if n == 0 then
        -- Fallback: try header variant without "= "
        local from2 = srcRegID .. " {"
        local to2   = dstRegID .. " {"
        out, n = clip:gsub(from2, to2, 1)
        if n == 0 then
            return nil, ("Could not find a header matching '%s {'"):format(srcRegID)
        end
    end
    return out, nil
end
-- ---------- /Helpers ----------

local tool = comp.ActiveTool
if not tool then
    print("No Node Selected")
    return
end

local attrs  = tool:GetAttrs() or {}
local regID  = attrs.TOOLS_RegID
if regID ~= "MacroOperator" and regID ~= "GroupOperator" then
    print("Select Macro or Group")
    return
end

-- Save original clipboard contents
local originalClipboard = bmd.getclipboard()

-- remember the Flow tile position of the original node
local origX, origY = nil, nil
if tool.GetPos then
    local p = tool:GetPos()
    if p then origX, origY = p[1], p[2] end
end

-- Snapshot neighbors (may be nil if tool has no main ports)
local prevConnectedTool = getPrevConnectedTool(tool)
local nextConnectedTool = getNextConnectedTool(tool)

-- Build replacement text BEFORE deleting anything
local dstRegID = (regID == "MacroOperator") and "GroupOperator" or "MacroOperator"
local settingText, convErr = convert_regid_in_setting_text(regID, dstRegID, tool)
if not settingText then
    print("Conversion error:", convErr or "(unknown)")
    -- Restore original clipboard before returning
    if originalClipboard then
        bmd.setclipboard(originalClipboard)
    end
    return
end

comp:StartUndo("Toggle Macro/Group")
comp:Lock()
local ok, err = pcall(function()
    -- Delete the original
    tool:Delete()

    -- Paste the converted version
    bmd.setclipboard(settingText)
    comp:SetActiveTool() -- clear selection so Paste selects the new node
    comp:Paste()

    local sTool = comp.ActiveTool
    if not sTool then error("Paste failed (no ActiveTool)") end

    -- restore original tile position (first pass)
    if sTool and sTool.SetPos and origX and origY then
        sTool:SetPos(origX, origY)
    end

    -- Reconnect downstream (if any)
    if nextConnectedTool then
        local sOut = sTool:FindMainOutput(1)
        local nIn  = nextConnectedTool:FindMainInput(1)
        if sOut and nIn then
            nIn:ConnectTo(sOut)
        end
    end

    -- Reconnect upstream (if any)
    if prevConnectedTool then
        local pOut = prevConnectedTool:FindMainOutput(1)
        local sIn  = sTool:FindMainInput(1)
        if pOut and sIn then
            sIn:ConnectTo(pOut)
        end
    end

    -- final position snap (some nodes shift after connections)
    if sTool and sTool.SetPos and origX and origY then
        sTool:SetPos(origX, origY)
    end
end)
comp:Unlock()

-- Restore original clipboard contents
if originalClipboard then
    bmd.setclipboard(originalClipboard)
end

if not ok then
    comp:EndUndo(true) -- abort
    print("Error:", err)
    return
end
comp:EndUndo(false)