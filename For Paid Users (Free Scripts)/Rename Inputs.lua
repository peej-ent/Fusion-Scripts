local function Rename(renamePath)

-- rename_inputs.lua
-- Renames keys in `Inputs = ordered() { ... }` to the string found in each entry's `Source = "..."`.
-- Preserves bodies exactly; sanitizes names; dedupes collisions with _2, _3, ...

-- ========= CONFIG (edit these) =========
local INPUT_PATH  = renamePath      -- e.g. "C:/Users/you/Desktop/MacroTransform.setting"
local OUTPUT_PATH = ""      -- leave "" to auto-write next to input as *_renamed.setting
-- ======================================

-- Read/Write helpers
local function read_file(p)
  local f, err = io.open(p, "rb"); if not f then return nil, err end
  local s = f:read("*a"); f:close(); return s
end
local function write_file(p, s)
  local f, err = io.open(p, "wb"); if not f then return nil, err end
  f:write(s); f:close(); return true
end

-- Utilities
local function sanitize_name(s)
  s = s:gsub("[^%w_]", "_")
  if not s:match("^[A-Za-z_]") then s = "_" .. s end
  return s
end

local function find_matching_brace(s, open_pos)
  local depth, i, in_str, esc = 0, open_pos, false, false
  while i <= #s do
    local c = s:sub(i,i)
    if in_str then
      if esc then esc = false
      elseif c == "\\" then esc = true
      elseif c == '"' then in_str = false end
    else
      if c == '"' then in_str = true
      elseif c == '{' then depth = depth + 1
      elseif c == '}' then
        depth = depth - 1
        if depth == 0 then return i end
      end
    end
    i = i + 1
  end
  return nil
end

local function replace_range(s, s1, s2, rep)
  return s:sub(1, s1 - 1) .. rep .. s:sub(s2 + 1)
end

-- Core: rename keys within a specific ordered() block (here: "Inputs")
local function rename_block(text, block_name)
  local hdr_s, hdr_e = text:find(block_name .. "%s*=%s*ordered%(%s*%)%s*{")
  if not hdr_s then return nil, "Could not find '" .. block_name .. " = ordered() {' block." end

  local open_brace = text:find("{", hdr_e - 1)
  if not open_brace then return nil, "Malformed " .. block_name .. " block (no '{')." end
  local close_brace = find_matching_brace(text, open_brace)
  if not close_brace then return nil, "Malformed " .. block_name .. " block (no matching '}')." end

  local inner_start = open_brace + 1
  local inner_end   = close_brace
  local inner = text:sub(inner_start, inner_end)

  -- Parse top-level entries:  Key = <Type> { ... }
  local i = 1
  local entries = {}  -- { key, k_s, k_e, source_raw, new_name, final_name }
  while i <= #inner do
    -- skip whitespace/commas/newlines
    while i <= #inner and inner:sub(i,i):match("[,%s]") do i = i + 1 end
    if i > #inner then break end

    -- key (identifier)
    local k_s = i
    if not inner:sub(i,i):match("[%a_]") then
      local nl = inner:find("\n", i) or (#inner + 1)
      i = nl + 1
      goto continue
    end
    while i <= #inner and inner:sub(i,i):match("[%w_]") do i = i + 1 end
    local k_e = i - 1
    local key = inner:sub(k_s, k_e)

    -- spaces, expect '='
    while i <= #inner and inner:sub(i,i):match("[%s]") do i = i + 1 end
    if inner:sub(i,i) ~= "=" then
      local nl = inner:find("\n", i) or (#inner + 1)
      i = nl + 1
      goto continue
    end
    i = i + 1
    while i <= #inner and inner:sub(i,i):match("[%s]") do i = i + 1 end

    -- find body braces
    local b_open = inner:find("{", i)
    if not b_open then break end
    local b_close = find_matching_brace(inner, b_open)
    if not b_close then break end

    local body = inner:sub(b_open, b_close)
    local src_raw = body:match('Source%s*=%s*"([^"]+)"') or key
    local new_name = sanitize_name(src_raw)

    table.insert(entries, {
      key = key, k_s = k_s, k_e = k_e,
      source_raw = src_raw, new_name = new_name
    })

    i = b_close + 1
    ::continue::
  end

  -- Ensure unique names
  local seen = {}
  for _, e in ipairs(entries) do
    local base = e.new_name
    if not seen[base] then
      seen[base] = 1
      e.final_name = base
    else
      seen[base] = seen[base] + 1
      e.final_name = string.format("%s_%d", base, seen[base])
    end
  end

  -- Replace keys from right to left so indices stay valid
  table.sort(entries, function(a,b) return a.k_s > b.k_s end)
  local new_inner = inner
  for _, e in ipairs(entries) do
    new_inner = replace_range(new_inner, e.k_s, e.k_e, e.final_name)
  end

  local new_text = text:sub(1, inner_start - 1) .. new_inner .. text:sub(inner_end + 1)
  return new_text, entries
end

-- Resolve input/output paths
local in_path = INPUT_PATH
if in_path == "" then
  if arg and arg[1] and arg[1] ~= "" then
    in_path = arg[1]
  elseif fusion and fusion.RequestFile then
    in_path = fusion:RequestFile("Select a .setting file", "*.setting")
  end
end
if not in_path or in_path == "" then
  print("[rename_inputs] No input path provided.")
  return
end

local txt, rerr = read_file(in_path)
if not txt then
  print("[rename_inputs] Read failed:", rerr)
  return
end

local new_txt, entries_or_err = rename_block(txt, "Inputs")
if not new_txt then
  print("[rename_inputs] Error:", entries_or_err)
  return
end

local out_path = OUTPUT_PATH ~= "" and OUTPUT_PATH or (in_path:gsub("%.setting$", "") .. "_renamed.setting")
local ok, werr = write_file(out_path, new_txt)
if not ok then
  print("[rename_inputs] Write failed:", werr)
  return
end

print("[rename_inputs] Wrote:", out_path)
print("[rename_inputs] Renamed keys (Old -> New):")
for _, e in ipairs(entries_or_err) do
  print(string.format("  %s -> %s   [Source=\"%s\"]", e.key, e.final_name, e.source_raw))
end

if fusion and fusion:GetResolve() then
  fusion:Print("[rename_inputs] Done: " .. out_path)
end
  return ok
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
        WindowTitle = 'Rename Setting File',
        Geometry = { guiPosX, guiPosY, width, height },
        Spacing = 10,

        ui:VGroup{
            ID = 'root',

            ui:HGroup{
                ui:LineEdit{ ID = "FilePath", PlaceholderText = "Select a .setting file", ReadOnly = true, Weight = 0.65 },
                ui:Button  { ID = "Browse",   Text = "Browse", Weight = 0.35 },
            },


            ui:HGroup{
                ui:Button{ ID = "Rename", Text = "Rename", Weight = 0.35 },
                ui:Label { ID = "Status", Text = "Ready.", Weight = 0.65, WordWrap = true },
            },
        },
    })

    local itm = MainWindow:GetItems()


    -- Browse: use the same pattern you used (fu:RequestFile)
    function MainWindow.On.Browse.Clicked(ev)
        local startDir = os.getenv("USERPROFILE") or os.getenv("HOME") or "C:/"
        local sel = tostring(fu:RequestFile(
            startDir,
            { FReqS_Title = 'Choose .setting File…' }
        ))
        if sel and sel ~= "" then
            itm.FilePath.Text = sel
            itm.Status.Text   = "File selected."
        else
            itm.Status.Text   = "No file selected."
        end
    end

    -- Rename button
    function MainWindow.On.Rename.Clicked(ev)
        local path  = itm.FilePath.Text or ""
        if path == "" then
            itm.Status.Text = "Please select a .setting file first."
            return
        end

        itm.Status.Text = "Renaming "
        local ok, msg = Rename(path)
        if ok then
            itm.Status.Text = "✅ Saved at file location"
            print("[SETTING] Renamed -> ")
        else
            itm.Status.Text = "❌ "
            print("[SETTING] Error: " )
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
