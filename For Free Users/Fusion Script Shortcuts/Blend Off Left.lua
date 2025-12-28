-- Blend Off Left --
-- by PeeJ Ent --
-- Details --

-- Version: 01 --

--[[--
 A script that sets the blend of a node to the one that you are on. Best for making one framers

--]]--


-- ---------------------------------
-- MAIN CODE 
-- ---------------------------------

comp:Lock()

--Checks for Inputs
tool = comp.ActiveTool

local currentFrame = comp.CurrentTime
local prevFrame = comp.CurrentTime - 1
local nextFrame = comp.CurrentTime + 1

local parm = "Blend"

-- Get Desried Input
local function GetParm(setting, sTool)
local table = sTool:GetInputList()

	for _, i in ipairs(table) do
		if i:GetAttrs().INPS_ID == setting then
			--print(i)
			return i
		end
	end

end

local parameter = GetParm(parm, tool)
local param = parameter:GetAttrs().INPS_ID

if parameter:GetConnectedOutput() == nil then
    tool:AddModifier(param, "BezierSpline")
    local splineOut = parameter:GetConnectedOutput()
    local spline = splineOut:GetTool()
else
end

parameter[prevFrame] = 0
parameter[currentFrame] = 1
--parameter[nextFrame] = 0


comp:Unlock()
comp:Unlock()
