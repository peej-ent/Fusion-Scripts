-- Rewrite Globals (No UI) by PeeJ Ent --
--------------------
-- REWRITE CORE  --
--------------------
-- Gives you the option to change the Global In or Out of selected generators in the comp, including the ones in macros and groups.

local inputTime = 100
local parameterIDString = "GlobalOut" -- "GlobalIn"

local function RewriteGlobals(wantedTime, parameter)
    comp:EndUndo(true)


    comp:StartUndo("Set Global across tools")
    comp:Lock()

    local desiredTime = wantedTime

    local function StoreNodeTypes(tools)
        for _, tool in pairs(tools) do
            local a = tool:GetAttrs()
            local id = a and a.TOOLS_RegID

            -- recurse into Groups/Macros
            if id == "MacroOperator" or id == "GroupOperator" then
                local kids = tool.GetChildrenList and tool:GetChildrenList()
                if kids then StoreNodeTypes(kids) end

            -- same whitelist you had, just referencing `id` once
            elseif id == "MediaIn" or id == "Loader" or id == "Background"
                or id == "FastNoise" or id == "TextPlus" or id == "Plasma"
                or id == "DaySky" or id == "MultiText" or id == "pRender"
                or id == "Renderer3D" or id == "sRender" or id == "uRenderer" then

                -- only set if different to cut work & undo noise
                local cur = tool:GetInput(parameter)
                if cur ~= desiredTime then
                    tool:SetInput(parameter, desiredTime)
                end
            end
        end
    end

    StoreNodeTypes(comp:GetToolList(true))

    comp:Unlock()
    comp:Unlock()
    comp:Unlock()
    comp:EndUndo(true)

end

RewriteGlobals(inputTime, parameterIDString) 