-- Transfers each item on a chosen subtitle track onto its own Text+ clip
-- (duplicated from a bin template) on a brand new video track at the top
-- of the timeline. One Text+ per subtitle line.

local resolve = app:GetResolve()
local project = resolve:GetProjectManager():GetCurrentProject()
local mediaPool = project:GetMediaPool()

fusion = Fusion()
fu = fusion
comp = fu.CurrentComp

if not comp then
    resolve:OpenPage("fusion")
    resolve:OpenPage("edit")
    comp = fu.CurrentComp
end

--------------------------------------------------------------------------------
-- Error/message helper: shows an AskUser popup (console prints alone aren't
-- reliably visible), then exits for fail().
--------------------------------------------------------------------------------

local function showMessage(title, msg)
    if comp then
        comp:AskUser(title, {
            {"Msg", "Text", Name = title, ReadOnly = true, Lines = 6, Wrap = true, Default = msg},
        })
    end
    print(title .. ": " .. msg)
end

local function fail(msg)
    showMessage("Error", msg)
    os.exit()
end

local timeline = project:GetCurrentTimeline()
if not timeline then
    fail("No current timeline.")
end

--------------------------------------------------------------------------------
-- 0) Settings persistence (remembers the last template name you typed)
--------------------------------------------------------------------------------

local function getSettingsPath()
    local sep = package.config:sub(1, 1)
    local home = os.getenv("HOME") or os.getenv("USERPROFILE") or "."
    return home .. sep .. ".resolve_subtitle_to_textplus_settings.txt"
end

local function loadLastTemplateName()
    local f = io.open(getSettingsPath(), "r")
    if not f then return "" end
    local name = f:read("*l") or ""
    f:close()
    return name
end

local function saveLastTemplateName(name)
    local f = io.open(getSettingsPath(), "w")
    if f then
        f:write(name)
        f:close()
    end
end

--------------------------------------------------------------------------------
-- 0.5) Figure out which subtitle tracks exist, for the dropdown below
--------------------------------------------------------------------------------

local subCount = timeline:GetTrackCount("subtitle")
if subCount == 0 then
    fail("This timeline has no subtitle tracks.")
end

local subtitleTrackOptions = {}
for i = 1, subCount do
    table.insert(subtitleTrackOptions, string.format("Track %d", i))
end

--------------------------------------------------------------------------------
-- 0.75) AskUser dialog: template name, subtitle track, gap-closing option
--------------------------------------------------------------------------------

local lastName = loadLastTemplateName()

local fields = {
    {"TemplateName", "Text", Default = lastName, Lines = 1},
    {"SubtitleTrack", "Dropdown", Name = "Subtitle Track", Options = subtitleTrackOptions, Default = 0},
    {"CloseGaps", "Checkbox", Default = 0},
}

local itm = comp:AskUser("Subtitle to Text+", fields)
if not itm then
    print("Cancelled.")
    os.exit()
end

local TEMPLATE_NAME = itm.TemplateName
local SUBTITLE_TRACK_INDEX = itm.SubtitleTrack + 1  -- Dropdown options are 0-indexed
local CLOSE_GAPS = itm.CloseGaps == 1

if not TEMPLATE_NAME or TEMPLATE_NAME == "" then
    fail("Cancelled (no template name given).")
end
saveLastTemplateName(TEMPLATE_NAME)

--------------------------------------------------------------------------------
-- 1) Find the template clip in the Media Pool (recursive folder search)
--------------------------------------------------------------------------------

local function findClipByName(folder, targetName)
    local clips = folder:GetClipList()
    for _, clip in ipairs(clips) do
        if clip:GetName() == targetName then
            return clip
        end
    end
    local subfolders = folder:GetSubFolderList()
    for _, sub in ipairs(subfolders) do
        local found = findClipByName(sub, targetName)
        if found then return found end
    end
    return nil
end

local templateClip = findClipByName(mediaPool:GetRootFolder(), TEMPLATE_NAME)
if not templateClip then
    fail(string.format("No bin item named '%s' found.", TEMPLATE_NAME))
end

--------------------------------------------------------------------------------
-- 2) Read the subtitle items we're transferring
--------------------------------------------------------------------------------

local subtitleItems = timeline:GetItemListInTrack("subtitle", SUBTITLE_TRACK_INDEX)
if #subtitleItems == 0 then
    fail("No subtitle items found on that track.")
end

print(string.format("Transferring %d subtitle item(s) from subtitle track %d...",
    #subtitleItems, SUBTITLE_TRACK_INDEX))

--------------------------------------------------------------------------------
-- 3) Add a new video track at the top
--------------------------------------------------------------------------------

if not timeline:AddTrack("video") then
    fail("Failed to add new video track.")
end

local newTrackIndex = timeline:GetTrackCount("video")
print(string.format("New Text+ track is video track %d.", newTrackIndex))

--------------------------------------------------------------------------------
-- 4) Build the clip-info list and append all Text+ clips in one batch
--------------------------------------------------------------------------------

-- The template's startFrame/endFrame are interpreted in ITS OWN native frame
-- rate, not the timeline's. If those differ (e.g. a 30fps template on a
-- 24fps timeline), a duration measured in timeline frames has to be
-- converted to the template's native frame count first, or the clip comes
-- out shorter/longer than intended.
local projectFps = tonumber(project:GetSetting("timelineFrameRate"))
local nativeFps = tonumber(templateClip:GetClipProperty("FPS"))

if not projectFps or not nativeFps then
    print("WARNING: Could not read frame rates for conversion; assuming 1:1 (may cause wrong durations).")
    projectFps = projectFps or 1
    nativeFps = nativeFps or 1
end

local fpsRatio = nativeFps / projectFps
print(string.format("Project fps=%.3f, template native fps=%.3f, ratio=%.4f",
    projectFps, nativeFps, fpsRatio))

local clipInfos = {}
for i, item in ipairs(subtitleItems) do
    local startFrame = item:GetStart()
    local endFrame = item:GetEnd()

    -- Gap-closing: extend this clip's back edge to the start of the NEXT
    -- subtitle instead of stopping at its own end, so there's no gap
    -- between consecutive Text+ clips. The last item has no "next" to
    -- extend to, so it keeps its own end.
    if CLOSE_GAPS and subtitleItems[i + 1] then
        endFrame = subtitleItems[i + 1]:GetStart()
    end

    local durationFrames = endFrame - startFrame

    local nativeDuration = math.floor(durationFrames * fpsRatio + 0.5)
    if nativeDuration < 1 then nativeDuration = 1 end

    table.insert(clipInfos, {
        mediaPoolItem = templateClip,
        startFrame = 0,
        endFrame = nativeDuration,
        trackIndex = newTrackIndex,
        recordFrame = startFrame,
        mediaType = 1  -- video
    })
end

local newItems = mediaPool:AppendToTimeline(clipInfos)

if not newItems or #newItems ~= #subtitleItems then
    showMessage("Warning", string.format("Expected %d new clips, got %s.",
        #subtitleItems, newItems and tostring(#newItems) or "nil"))
end

--------------------------------------------------------------------------------
-- 5) Set each new Text+ clip's text
--------------------------------------------------------------------------------

for i, newItem in ipairs(newItems or {}) do
    local subtitleText = subtitleItems[i]:GetName()

    local itemComp = newItem:GetFusionCompByIndex(1)
    if not itemComp then
        print(string.format("[%d] WARNING: No Fusion comp on new clip, skipping text.", i))
    else
        local tools = itemComp:GetToolList(false, "TextPlus")
        local textTool = tools and tools[1]
        if not textTool then
            print(string.format("[%d] WARNING: No TextPlus tool found in template's comp, skipping text.", i))
        else
            textTool:SetInput("StyledText", subtitleText)
            print(string.format("[%d] Set text: |%s|", i, subtitleText))
        end
    end
end

print("Done.")
