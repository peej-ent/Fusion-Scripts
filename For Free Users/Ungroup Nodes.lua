-- Ungroup Script
local originalClipboard = bmd.getclipboard()
comp:Copy(comp.ActiveTool:GetChildrenList())
comp.ActiveTool:Delete()
comp:Paste()
bmd.setclipboard(originalClipboard)