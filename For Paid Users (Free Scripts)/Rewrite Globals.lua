-- Rewrite Globals by PeeJ Ent --
--------------------
-- REWRITE CORE  --
--------------------
-- Gives you the option to change the Global In or Out of selected generators in the comp, including the ones in macros and groups.

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
    return true
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
        WindowTitle = 'Rewrite Global In/Outs',
        Geometry = { guiPosX, guiPosY, width, height },
        Spacing = 10,

        ui:VGroup{
            ID = 'root',

            ui:HGroup{
                ui:Label   { Text = "Global:", Weight = 0.2 },
                ui:ComboBox{ ID = "GLO", Weight = 0.3 },
                ui:Label   { Text = "Frame:", Weight = 0.2 },
                ui:LineEdit{ ID = "FRAME", Text = "100", Weight = 0.3 },
            },

            ui:HGroup{
                ui:Button{ ID = "ChangeGlobal", Text = "Rewrite", Weight = 0.35 },
                ui:Label { ID = "Status", Text = "Ready.", Weight = 0.65, WordWrap = true },
            },
        },
    })

    local itm = MainWindow:GetItems()

    -- Populate global choices
    itm.GLO:AddItem("GlobalOut")
    itm.GLO:AddItem("GlobalIn")
    itm.GLO.CurrentIndex = 0

    -- Rotate button
    function MainWindow.On.ChangeGlobal.Clicked(ev)
        
        -- Global
        local dir = (itm.GLO.CurrentIndex == 0) and "GlobalOut" or "GlobalIn"

        -- steps (sanitize to non-negative int)
        local steps = tonumber(itm.FRAME.Text or "100") or 1
        steps = math.floor(steps + 0.0)

        local ok = RewriteGlobals(steps, tostring(dir)) 
        if ok then
            itm.Status.Text = "✅ Global"..dir.." Changed"
            print(dir.. " changed to " .. steps)
        else
            itm.Status.Text = "❌ Global"..dir.." NOT Changed"
            print("Error: "..dir.. " NOT changed")
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
