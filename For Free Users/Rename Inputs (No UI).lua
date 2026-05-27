-- Rename Inputs (Selected Node).lua
-- Renames Input keys to match their Source values in a selected Macro/Group node
-- Special case: Source = "Input" becomes "MainInput1", "MainInput2", etc.
-- Runs immediately without UI when executed

--------------------------------
-- ENGINE: RenameSelected() ----
--------------------------------
local function RenameSelected()
  
  -- ===== Utility Functions =====
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

  -- ===== Core: Rename keys within Inputs block =====
  local function rename_inputs_block(text)
    local hdr_s, hdr_e = text:find("Inputs%s*=%s*ordered%(%s*%)%s*{")
    if not hdr_s then return nil, "Could not find 'Inputs = ordered() {' block." end

    local open_brace = text:find("{", hdr_e - 1)
    if not open_brace then return nil, "Malformed Inputs block (no '{')." end
    local close_brace = find_matching_brace(text, open_brace)
    if not close_brace then return nil, "Malformed Inputs block (no matching '}')." end

    local inner_start = open_brace + 1
    local inner_end   = close_brace
    local inner = text:sub(inner_start, inner_end)

    -- Parse top-level entries:  Key = <Type> { ... }
    local i = 1
    local entries = {}
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
      
      -- Special case: if Source is exactly "Input", use "MainInput" as base
      local new_name
      if src_raw == "Input" then
        new_name = "MainInput"
      else
        new_name = sanitize_name(src_raw)
      end

      table.insert(entries, {
        key = key, k_s = k_s, k_e = k_e,
        source_raw = src_raw, new_name = new_name
      })

      i = b_close + 1
      ::continue::
    end

    -- Ensure unique names with numbering
    local seen = {}
    for _, e in ipairs(entries) do
      local base = e.new_name
      if not seen[base] then
        seen[base] = 1
        -- For MainInput, always add the number suffix
        if base == "MainInput" then
          e.final_name = base .. "1"
        else
          e.final_name = base
        end
      else
        seen[base] = seen[base] + 1
        -- For MainInput and others, use number suffix
        if base == "MainInput" then
          e.final_name = base .. seen[base]
        else
          e.final_name = string.format("%s_%d", base, seen[base])
        end
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

  -- ===== Get selected tool and copy to text =====
  local comp = comp
  if not comp then return false, "No comp found." end
  local tool = comp.ActiveTool
  if not tool then return false, "Select a MacroOperator or GroupOperator node first." end

  local attrs = tool:GetAttrs() or {}
  local regID = attrs.TOOLS_RegID
  if regID ~= "MacroOperator" and regID ~= "GroupOperator" then
    return false, "Selected node must be MacroOperator or GroupOperator."
  end

  -- Remember position and connections to restore
  local function getPrevConnectedTool(t)
    if not t then return nil end
    local inp = t:FindMainInput(1); if not inp then return nil end
    local outp = inp:GetConnectedOutput(); if not outp then return nil end
    return outp:GetTool()
  end
  local function getNextConnectedTool(t)
    if not t then return nil end
    local outp = t:FindMainOutput(1); if not outp then return nil end
    local conns = outp:GetConnectedInputs() or {}
    for _, inp in pairs(conns) do return inp:GetTool() end
    return nil
  end

  local prevConnectedTool = getPrevConnectedTool(tool)
  local nextConnectedTool = getNextConnectedTool(tool)
  local px, py = nil, nil
  if tool.GetPos then local p = tool:GetPos(); if p then px, py = p[1], p[2] end end

  comp:Copy(tool)
  local txt = bmd.getclipboard()
  if not txt or #txt == 0 then return false, "Clipboard empty after Copy()." end

  -- ===== Parse/modify the copied text =====
  local new_txt, entries_or_err = rename_inputs_block(txt)
  if not new_txt then
    return false, tostring(entries_or_err)
  end

  -- Build summary message
  local msg = "Renamed " .. #entries_or_err .. " input(s)"
  local details = {}
  for _, e in ipairs(entries_or_err) do
    if e.key ~= e.final_name then
      table.insert(details, e.key .. " → " .. e.final_name)
    end
  end
  if #details > 0 then
    msg = msg .. ": " .. table.concat(details, ", ")
  end

  -- ===== Replace selected tool with modified text, keep wiring/pos =====
  comp:StartUndo("Rename Inputs (Selected Node)")
  comp:Lock()
  local ok, err = pcall(function()
    tool:Delete()
    bmd.setclipboard(new_txt)
    comp:SetActiveTool()
    comp:Paste()
    local newTool = comp.ActiveTool
    if not newTool then error("Paste failed") end

    -- restore position
    if newTool.SetPos and px and py then newTool:SetPos(px, py) end

    -- reconnect forward
    if nextConnectedTool then
      local o = newTool:FindMainOutput(1)
      local i = nextConnectedTool:FindMainInput(1)
      if o and i then i:ConnectTo(o) end
    end
    -- reconnect backward
    if prevConnectedTool then
      local o = prevConnectedTool:FindMainOutput(1)
      local i = newTool:FindMainInput(1)
      if o and i then i:ConnectTo(o) end
    end

    if newTool.SetPos and px and py then newTool:SetPos(px, py) end
  end)
  comp:Unlock()
  comp:EndUndo(not ok)
  if not ok then return false, err end
  return true, msg
end

-- Run immediately
local ok, msg = RenameSelected()
if ok then
  print("[Rename Inputs] ✅ " .. msg)
else
  print("[Rename Inputs] ❌ " .. msg)
end
