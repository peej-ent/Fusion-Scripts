-- Transfers each item on a chosen subtitle track onto its own Text+ clip
-- (duplicated from a Media Pool template) on a brand new video track at the
-- top of the timeline. One Text+ per subtitle line.
--
-- The Text+ template is taken from whatever clip is under the timeline
-- playhead when you run the script: the script reads that clip's name and
-- looks for a Media Pool bin item with the same name. Park the playhead
-- over an instance of your styled Text+ template clip, make sure a bin item
-- with that same name exists somewhere in your Media Pool (drag it in there
-- once if it doesn't yet), then run.

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
-- 0) Figure out which subtitle tracks exist, for the dropdown below
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
-- 0.5) AskUser dialog: which subtitle track, and gap-closing option
--------------------------------------------------------------------------------

local fields = {
    {"SubtitleTrack", "Dropdown", Name = "Subtitle Track", Options = subtitleTrackOptions, Default = 0},
    {"CloseGaps", "Checkbox", Default = 0},
}

local itm = comp:AskUser("Subtitle to Text+", fields)
if not itm then
    print("Cancelled.")
    os.exit()
end

local SUBTITLE_TRACK_INDEX = itm.SubtitleTrack + 1  -- Dropdown options are 0-indexed
local CLOSE_GAPS = itm.CloseGaps == 1

--------------------------------------------------------------------------------
-- 1) Get the Text+ template: read the playhead clip's name, then find a
--    Media Pool bin item with that same name (recursive folder search)
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

local playheadItem = timeline:GetCurrentVideoItem()
if not playheadItem then
    fail("No clip found under the playhead. Park the playhead over your Text+ template clip on the timeline and try again.")
end

local playheadName = playheadItem:GetName()

local templateClip = findClipByName(mediaPool:GetRootFolder(), playheadName)
if not templateClip then
    fail(string.format(
        "The clip under the playhead is named '%s', but no Media Pool bin item with that exact name was found.\n\n" ..
        "Drag that Text+ clip into a Media Pool bin (it needs to match the timeline clip's name exactly) and try again.",
        playheadName))
end

print(string.format("Using Media Pool item '%s' as the Text+ template.", templateClip:GetName()))

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