-- Objective Forever: replaces the default objective tracker.
-- Quests, Professions (tracked recipes) and - when QuestMates is installed - Party Quests.
-- Click a quest = track it (diamond + 3D arrow), click again = untrack, Ctrl-click = map, right-click = quest log.
-- QuestMates is optional: party features use it when it's there, otherwise these stand-ins are used
local hold = nil
local NOQM = {
  Friends = function() return {} end,
  FriendsOnQuest = function() return {} end,
  FriendQuests = function() return {} end,
  MyQuest = function() return nil end,
  FriendQuest = function() return nil end,
  Color = function() return { 1, 1, 1 } end,
  PinFriend = function() end,
  HoldPointer = function(on) hold = on and true or nil end,
  Pinned = function() return nil, hold end,
  Unpin = function()
    hold = nil
    if C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
  end,
  QuestTooltip = function(owner, q)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT"); GameTooltip:AddLine(q.title or "", 1, 0.82, 0); GameTooltip:Show()
  end,
  OpenQuest = function(q)
    if IsShiftKeyDown() then
      local link = GetQuestLink and GetQuestLink(q.id)
      if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
      return
    end
    if QuestLedgerForever_OpenQuest then pcall(QuestLedgerForever_OpenQuest, q.id) return end
    if QuestMapFrame_OpenToQuestDetails then pcall(QuestMapFrame_OpenToQuestDetails, q.id) return end
    if ToggleQuestLog then ToggleQuestLog() end
  end,
}
local API = setmetatable({}, { __index = function(_, k)
  local qm = QuestMatesAPI
  if qm and qm[k] then return qm[k] end
  return NOQM[k]
end })
local P = "|cff33d9ffObjective Forever:|r "
------------------------------------------------------------------------
-- Edit Mode ("Edit UI") support: shows with Blizzard's highlight, drag to move
-- (saved per Edit Mode layout), click for a small settings panel
------------------------------------------------------------------------
local EM = { items = {} }
function EM.Layout()
  local ok, info = pcall(function()
    return EditModeManagerFrame and EditModeManagerFrame.GetActiveLayoutInfo and EditModeManagerFrame:GetActiveLayoutInfo()
  end)
  if ok and type(info) == "table" and info.layoutName then return info.layoutName end
  if C_EditMode and C_EditMode.GetLayouts then
    local ok2, l = pcall(C_EditMode.GetLayouts)
    if ok2 and type(l) == "table" and l.activeLayout then
      local e = l.layouts and l.layouts[l.activeLayout - 2]
      if e and e.layoutName then return e.layoutName end
      return "preset" .. l.activeLayout
    end
  end
  return "default"
end
function EM.Active()
  return EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive() or false
end

local function HasAtlas(a) return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(a) and true or false end
local function Piece(sel, layer, atlas, r, g, b, a)
  local t = sel:CreateTexture(nil, layer)
  if HasAtlas(atlas) then t:SetAtlas(atlas) else t:SetColorTexture(r or 0.25, g or 0.6, b or 1, a or 0.35) end
  return t
end
local function Highlight(sel)
  local E = 16
  local c = Piece(sel, "BACKGROUND", "editmode-actionbar-highlight-nineslice-center", 0.25, 0.6, 1, 0.25)
  c:SetPoint("TOPLEFT", E / 2, -E / 2); c:SetPoint("BOTTOMRIGHT", -E / 2, E / 2)
  local corners = {}
  for i, pt in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
    local t = Piece(sel, "BORDER", "editmode-actionbar-highlight-nineslice-corner", 0.3, 0.7, 1, 0.9)
    t:SetSize(E, E); t:SetPoint(pt)
    local l, r, tp, bt = 0, 1, 0, 1
    if pt:find("RIGHT") then l, r = 1, 0 end
    if pt:find("BOTTOM") then tp, bt = 1, 0 end
    if t:GetAtlas() then t:SetTexCoord(l, r, tp, bt) end
    corners[pt] = t
  end
  local top = Piece(sel, "BORDER", "_editmode-actionbar-highlight-nineslice-edgetop", 0.3, 0.7, 1, 0.9)
  top:SetPoint("TOPLEFT", corners.TOPLEFT, "TOPRIGHT"); top:SetPoint("BOTTOMRIGHT", corners.TOPRIGHT, "BOTTOMLEFT")
  local bot = Piece(sel, "BORDER", "_editmode-actionbar-highlight-nineslice-edgebottom", 0.3, 0.7, 1, 0.9)
  bot:SetPoint("TOPLEFT", corners.BOTTOMLEFT, "TOPRIGHT"); bot:SetPoint("BOTTOMRIGHT", corners.BOTTOMRIGHT, "BOTTOMLEFT")
  local lft = Piece(sel, "BORDER", "!editmode-actionbar-highlight-nineslice-edgeleft", 0.3, 0.7, 1, 0.9)
  lft:SetPoint("TOPLEFT", corners.TOPLEFT, "BOTTOMLEFT"); lft:SetPoint("BOTTOMRIGHT", corners.BOTTOMLEFT, "TOPRIGHT")
  local rgt = Piece(sel, "BORDER", "!editmode-actionbar-highlight-nineslice-edgeright", 0.3, 0.7, 1, 0.9)
  rgt:SetPoint("TOPLEFT", corners.TOPRIGHT, "BOTTOMLEFT"); rgt:SetPoint("BOTTOMRIGHT", corners.BOTTOMRIGHT, "TOPRIGHT")
end

-- settings panel widgets
function EM.Check(p, y, text, get, set)
  local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
  cb:SetSize(24, 24); cb:SetPoint("TOPLEFT", 12, y)
  local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); fs:SetPoint("LEFT", cb, "RIGHT", 2, 0); fs:SetText(text)
  cb:SetScript("OnShow", function(s) s:SetChecked(get() and true or false) end)
  cb:SetScript("OnClick", function(s) set(s:GetChecked() and true or false) end)
  cb:SetChecked(get() and true or false)
  return y - 28
end
function EM.Slider(p, y, text, lo, hi, step, get, set, fmt)
  local fs = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); fs:SetPoint("TOPLEFT", 16, y)
  local val = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); val:SetPoint("TOPRIGHT", -16, y)
  fs:SetText(text)
  local s = CreateFrame("Slider", nil, p)
  s:SetOrientation("HORIZONTAL"); s:SetSize(196, 16); s:SetPoint("TOPLEFT", 16, y - 18)
  s:SetMinMaxValues(lo, hi); s:SetValueStep(step); if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  local bg = s:CreateTexture(nil, "BACKGROUND"); bg:SetColorTexture(0, 0, 0, 0.5)
  bg:SetPoint("LEFT", 0, 0); bg:SetPoint("RIGHT", 0, 0); bg:SetHeight(6)
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  local function show(v) val:SetText((fmt or "%d%%"):format(v * 100 + 0.5)) end
  s:SetScript("OnValueChanged", function(_, v) v = math.floor(v / step + 0.5) * step; show(v); set(v) end)
  s:SetScript("OnShow", function(self) self:SetValue(get()); show(get()) end)
  s:SetValue(get()); show(get())
  return y - 42
end
function EM.Button(p, y, text, fn)
  local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  b:SetSize(140, 22); b:SetPoint("TOP", 0, y); b:SetText(text); b:SetScript("OnClick", fn)
  return y - 28
end

local panel
local function Panel()
  if panel then return panel end
  panel = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
  panel:SetFrameStrata("DIALOG"); panel:SetSize(228, 100); panel:SetClampedToScreen(true); panel:EnableMouse(true)
  if panel.SetBackdrop then
    panel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
  end
  panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal"); panel.title:SetPoint("TOP", 0, -12)
  local x = CreateFrame("Button", nil, panel, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT", 0, 0)
  x:SetScript("OnClick", function() EM.Select(nil) end)
  panel:Hide()
  return panel
end

function EM.Select(item)
  for _, it in ipairs(EM.items) do
    if it.sel.label then it.sel.label:SetTextColor(it == item and 1 or 0.8, it == item and 0.82 or 0.8, it == item and 0 or 0.8) end
    if it.content then it.content:Hide() end
  end
  local p = Panel()
  if not item then p:Hide() return end
  p.title:SetText(item.label)
  if not item.content then
    item.content = CreateFrame("Frame", nil, p); item.content:SetAllPoints()
    item.height = -(item.o.panel(item.content, -36)) + 10
  end
  item.content:Show()
  p:SetHeight(item.height)
  p:ClearAllPoints()
  local cx = item.frame:GetCenter()
  if cx and cx > (UIParent:GetWidth() or 0) / 2 then p:SetPoint("TOPRIGHT", item.frame, "TOPLEFT", -12, 0)
  else p:SetPoint("TOPLEFT", item.frame, "TOPRIGHT", 12, 0) end
  p:Show()
end

-- magnetism: snap to Blizzard's Edit Mode frames, the screen, the grid and other addons' Edit Mode frames
_G.EditModeExtraFrames = _G.EditModeExtraFrames or {}
local SNAP = 12
local function SnapOn()
  local m = EditModeManagerFrame
  if not m then return false end
  if m.IsSnapEnabled then local ok, v = pcall(m.IsSnapEnabled, m); if ok then return v and true or false end end
  local cb = m.EnableSnapCheckButton
  if cb and cb.IsControlChecked then local ok, v = pcall(cb.IsControlChecked, cb); if ok then return v end end
  if cb and cb.GetChecked then return cb:GetChecked() and true or false end
  return true
end
local function Rect(fr)
  if not (fr and fr.IsVisible and fr:IsVisible() and fr:GetLeft()) then return end
  local k = (fr:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  local l, b, w, h = fr:GetLeft() * k, fr:GetBottom() * k, fr:GetWidth() * k, fr:GetHeight() * k
  return l, b, w, h
end
local function Lines(self)
  local xs, ys = {}, {}
  local W, H = UIParent:GetWidth(), UIParent:GetHeight()
  local function add(fr)
    if fr == self then return end
    local l, b, w, h = Rect(fr)
    if l then
      xs[#xs + 1] = l; xs[#xs + 1] = l + w; xs[#xs + 1] = l + w / 2
      ys[#ys + 1] = b; ys[#ys + 1] = b + h; ys[#ys + 1] = b + h / 2
    end
  end
  xs[#xs + 1] = 0; xs[#xs + 1] = W / 2; xs[#xs + 1] = W
  ys[#ys + 1] = 0; ys[#ys + 1] = H / 2; ys[#ys + 1] = H
  local m = EditModeManagerFrame
  for _, fr in ipairs((m and m.registeredSystemFrames) or {}) do add(fr) end
  for _, fr in ipairs(_G.EditModeExtraFrames) do add(fr) end
  -- grid lines run out from the screen center
  local grid = m and m.Grid
  if grid and grid.IsShown and grid:IsShown() then
    local sp = grid.gridSpacing or m.gridSpacing
    if type(sp) == "number" and sp > 4 then
      for i = -math.ceil(W / sp), math.ceil(W / sp) do local x = W / 2 + i * sp; if x >= 0 and x <= W then xs[#xs + 1] = x end end
      for i = -math.ceil(H / sp), math.ceil(H / sp) do local y = H / 2 + i * sp; if y >= 0 and y <= H then ys[#ys + 1] = y end end
    end
  end
  return xs, ys
end
local function Best(edges, lines)
  local bd, bl
  for _, e in ipairs(edges) do
    for _, ln in ipairs(lines) do
      local d = ln - e
      if math.abs(d) <= SNAP and (not bd or math.abs(d) < math.abs(bd)) then bd, bl = d, ln end
    end
  end
  return bd, bl
end
local function SnapOffset(frame)
  local l, b, w, h = Rect(frame)
  if not l then return end
  local xs, ys = Lines(frame)
  local dx, lx = Best({ l, l + w, l + w / 2 }, xs)
  local dy, ly = Best({ b, b + h, b + h / 2 }, ys)
  return dx, dy, lx, ly, l, b
end
-- guide lines while dragging
local guide = CreateFrame("Frame", nil, UIParent)
guide:SetFrameStrata("TOOLTIP"); guide:SetAllPoints(); guide:Hide()
guide.v = guide:CreateTexture(nil, "OVERLAY"); guide.v:SetColorTexture(0.3, 0.8, 1, 0.9); guide.v:SetWidth(2)
guide.h = guide:CreateTexture(nil, "OVERLAY"); guide.h:SetColorTexture(0.3, 0.8, 1, 0.9); guide.h:SetHeight(2)
guide:SetScript("OnUpdate", function(g)
  local fr = g.frame
  if not (fr and fr.emMoving) or not SnapOn() then g.v:Hide(); g.h:Hide(); return end
  local _, _, lx, ly = SnapOffset(fr)
  if lx then g.v:ClearAllPoints(); g.v:SetPoint("TOP", UIParent, "TOPLEFT", lx, 0); g.v:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", lx, 0); g.v:Show() else g.v:Hide() end
  if ly then g.h:ClearAllPoints(); g.h:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, ly); g.h:SetPoint("RIGHT", UIParent, "BOTTOMRIGHT", 0, ly); g.h:Show() else g.h:Hide() end
end)
-- after a drag: snap (if on) and always anchor by the TOP-left corner, so collapsing/growing keeps the top in place
local function SnapNow(frame, noSnap)
  local l, b, w, h = Rect(frame)
  if not l then return end
  local dx, dy
  if not noSnap and SnapOn() then dx, dy = SnapOffset(frame) end
  local k = (frame:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1)
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", (l + (dx or 0)) / k, (b + h + (dy or 0)) / k)
end
EM.TopAnchor = function(frame) SnapNow(frame, true) end

function EM.Attach(frame, label, o)
  local sel = CreateFrame("Button", nil, frame)
  sel:SetAllPoints(); sel:SetFrameStrata("HIGH"); sel:Hide()
  Highlight(sel)
  sel.label = sel:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); sel.label:SetPoint("CENTER"); sel.label:SetText(label)
  sel:RegisterForDrag("LeftButton"); sel:RegisterForClicks("LeftButtonUp")
  local item = { frame = frame, sel = sel, label = label, o = o }
  sel:SetScript("OnDragStart", function()
    frame.emMoving = true; frame:SetMovable(true); frame:StartMoving()
    guide.frame = frame; guide:Show()
  end)
  sel:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing(); frame.emMoving = nil
    guide:Hide(); guide.frame = nil
    SnapNow(frame)
    local p, _, rp, x, y = frame:GetPoint()
    o.save({ p, rp, x, y }, EM.Layout())
    EM.Select(item)
  end)
  sel:SetScript("OnClick", function() EM.Select(item) end)
  EM.items[#EM.items + 1] = item
  _G.EditModeExtraFrames[#_G.EditModeExtraFrames + 1] = frame
  if EM.Active() then o.enter(); sel:Show() end
  return item
end

local function Enter() for _, it in ipairs(EM.items) do it.o.enter(); it.sel:Show() end end
local function Exit()
  EM.Select(nil)
  for _, it in ipairs(EM.items) do it.sel:Hide(); it.o.exit() end
end
local function Relayout() for _, it in ipairs(EM.items) do it.o.apply() end end
if EventRegistry and EventRegistry.RegisterCallback then
  EventRegistry:RegisterCallback("EditMode.Enter", Enter, EM)
  EventRegistry:RegisterCallback("EditMode.Exit", Exit, EM)
end
if EditModeManagerFrame then
  if EditModeManagerFrame.EnterEditMode then hooksecurefunc(EditModeManagerFrame, "EnterEditMode", Enter) end
  if EditModeManagerFrame.ExitEditMode then hooksecurefunc(EditModeManagerFrame, "ExitEditMode", Exit) end
end
local emEv = CreateFrame("Frame")
pcall(emEv.RegisterEvent, emEv, "EDIT_MODE_LAYOUTS_UPDATED")
emEv:SetScript("OnEvent", function() C_Timer.After(0, Relayout) end)
local WIDTH, HEADH = 255, 58
local ICON_PROGRESS = "Interface\\GossipFrame\\IncompleteQuestIcon"
local ICON_DONE = "Interface\\GossipFrame\\ActiveQuestIcon"

local db
local tab = "mine"
local collapsedFriend = {}
local hider = CreateFrame("Frame"); hider:Hide()
local blizzParent = {}
local pinnedOwn -- quest id I pinned from the tracker
local Place -- defined further down
local Untrack -- defined further down
local STGet, STSet, Arrow3D, FriendArrow -- defined further down
local QuestTimeEnd -- defined further down
local ProgressColor, CHECK -- defined further down
local scrollOff, viewH = 0, 600 -- pixels scrolled down, visible list height
local barHold = 0 -- seconds before the scroll bar fades

------------------------------------------------------------------------
-- Frame
------------------------------------------------------------------------
local f = CreateFrame("Frame", "ObjectiveForeverFrame", UIParent)
f:SetSize(WIDTH, 40); f:SetMovable(true); f:SetClampedToScreen(true); f:Hide()
-- lowest layer: every window, the minimap, unit frames and action bars draw on top of it
f:SetFrameStrata("BACKGROUND"); f:SetFrameLevel(1); f:SetToplevel(false)

f:EnableMouseWheel(true)
f:SetScript("OnMouseWheel", function(_, delta)
  if not f.maxOff or f.maxOff <= 0 then return end
  scrollOff = math.max(0, math.min(f.maxOff, scrollOff - delta * 40))
  barHold = 1.5; f.bar:SetAlpha(1)
  QuestMatesTracker_Refresh()
end)
-- slim scroll bar on the right: shows while scrolling / hovering, fades out after
local bar = CreateFrame("Frame", nil, f)
bar:SetWidth(4); bar:SetFrameLevel(f:GetFrameLevel() + 5); bar:SetAlpha(0); bar:Hide()
bar.track = bar:CreateTexture(nil, "BACKGROUND"); bar.track:SetAllPoints()
bar.track:SetColorTexture(0, 0, 0, 0.35)
local thumb = CreateFrame("Button", nil, bar)
thumb:SetWidth(12); thumb:SetPoint("LEFT", bar, "LEFT", -4, 0)
thumb.tex = thumb:CreateTexture(nil, "ARTWORK")
thumb.tex:SetPoint("TOP"); thumb.tex:SetPoint("BOTTOM"); thumb.tex:SetWidth(4)
thumb.tex:SetColorTexture(1, 0.82, 0, 0.75)
thumb:SetScript("OnEnter", function() thumb.tex:SetColorTexture(1, 0.9, 0.3, 1) end)
thumb:SetScript("OnLeave", function() if not thumb.drag then thumb.tex:SetColorTexture(1, 0.82, 0, 0.75) end end)
local function Poke() barHold = 1.5; bar:SetAlpha(1) end
thumb:RegisterForDrag("LeftButton")
thumb:SetScript("OnDragStart", function()
  local _, cy = GetCursorPosition()
  thumb.drag = { y = cy / thumb:GetEffectiveScale(), off = scrollOff }
end)
thumb:SetScript("OnDragStop", function() thumb.drag = nil; thumb.tex:SetColorTexture(1, 0.82, 0, 0.75) end)
bar:SetScript("OnUpdate", function(_, el)
  if thumb.drag and f.maxOff and f.maxOff > 0 then
    local _, cy = GetCursorPosition()
    cy = cy / thumb:GetEffectiveScale()
    local free = bar:GetHeight() - thumb:GetHeight()
    if free > 0 then
      local new = thumb.drag.off + (thumb.drag.y - cy) / free * f.maxOff
      new = math.floor(math.max(0, math.min(f.maxOff, new)) + 0.5)
      if new ~= scrollOff then scrollOff = new; QuestMatesTracker_Refresh() end
    end
    Poke()
  elseif f:IsMouseOver() then
    Poke()
  elseif barHold > 0 then
    barHold = barHold - el
  else
    local a = bar:GetAlpha() - el * 3
    bar:SetAlpha(a > 0 and a or 0)
  end
end)
f.bar, f.thumb = bar, thumb

local head = CreateFrame("Button", nil, f)
head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT"); head:SetHeight(26)
head:SetScript("OnEnter", function(s)
  GameTooltip:SetOwner(s, "ANCHOR_LEFT"); GameTooltip:AddLine("Objective Forever")
  GameTooltip:AddLine("Move it in Edit Mode (Esc > Edit Mode).", 1, 1, 1)
  GameTooltip:AddLine("Click a quest to track it (diamond + arrow), click again to untrack. Right-click for the quest log, Ctrl-click for the map.", 1, 1, 1, true)
  GameTooltip:AddLine("Click the quest icon to point the in-world marker at it.", 1, 1, 1, true)
  GameTooltip:Show()
end)
head:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- default-UI look: use the game's own tracker art when this client has it
local function HasAtlas(a)
  return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(a) and true or false
end
local function FirstAtlas(list) for _, a in ipairs(list) do if HasAtlas(a) then return a end end end
local function HeaderArt(parent, list)
  local t = parent:CreateTexture(nil, "BACKGROUND")
  local a = FirstAtlas(list)
  if a then t:SetAtlas(a, false)
  else t:SetTexture("Interface\\QuestFrame\\ObjectiveTracker"); t:SetTexCoord(0, 0.6, 0.25, 0.35) end
  return t
end
-- Blizzard-style minimize button: atlas names straight from the default tracker (/qmt icons)
local function MinButton(parent, w, h, collapse, expand, highlight)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, h)
  function b:SetCollapsed(c)
    local base = (c and HasAtlas(expand)) and expand or collapse
    if HasAtlas(base) then
      self:SetNormalAtlas(base)
      self:SetPushedAtlas(HasAtlas(base .. "-Pressed") and (base .. "-Pressed") or base)
      if HasAtlas(highlight) then self:SetHighlightAtlas(highlight, "ADD") end
      local t = self:GetNormalTexture()
      if t and t.SetTexCoord then
        -- no "expand" art in this client: flip the collapse art so it reads as "open"
        if c and base == collapse then t:SetTexCoord(0, 1, 1, 0) else t:SetTexCoord(0, 1, 0, 1) end
      end
    else
      self:SetNormalTexture(c and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
      self:SetPushedTexture(c and "Interface\\Buttons\\UI-PlusButton-Down" or "Interface\\Buttons\\UI-MinusButton-Down")
      self:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    end
  end
  return b
end

-- top bar: "All Objectives" + collapse-all button
local hbg = HeaderArt(head, { "UI-QuestTracker-Primary-Objective-Header", "Objective-Header" })
hbg:SetPoint("TOPLEFT", -12, 7); hbg:SetPoint("BOTTOMRIGHT", 12, -7)
local minBtn = MinButton(head, 17, 18, "UI-QuestTrackerButton-Collapse-All", "UI-QuestTrackerButton-Expand-All", "UI-QuestTrackerButton-Red-Highlight")
minBtn:SetPoint("RIGHT", -2, 0)
minBtn:SetScript("OnClick", function() db.utMin = not db.utMin; QuestMatesTracker_Refresh() end)
local title = head:CreateFontString(nil, "OVERLAY", "GameFontNormalMed2" and _G.GameFontNormalMed2 and "GameFontNormalMed2" or "GameFontNormal")
title:SetPoint("LEFT", 6, 0); title:SetText("All Objectives")

-- section bar: "Quests" / "Party Quests", click to collapse, party button to switch
local sec = CreateFrame("Button", nil, f)
sec:SetPoint("TOPLEFT", 0, -30); sec:SetPoint("TOPRIGHT", 0, -30); sec:SetHeight(24)
local sbg = HeaderArt(sec, { "UI-QuestTracker-Secondary-Objective-Header", "Objective-Header" })
sbg:SetPoint("TOPLEFT", -12, 3); sbg:SetPoint("BOTTOMRIGHT", 12, -3)
local secMin = MinButton(sec, 16, 15, "UI-QuestTrackerButton-Secondary-Collapse", "UI-QuestTrackerButton-Secondary-Expand", "UI-QuestTrackerButton-Yellow-Highlight")
secMin:SetPoint("RIGHT", -2, 0)
local secText = sec:CreateFontString(nil, "OVERLAY", "GameFontNormal")
secText:SetPoint("LEFT", 6, 0)
local function ToggleSection() db.utSecMin = not db.utSecMin; scrollOff = 0; QuestMatesTracker_Refresh() end
sec:SetScript("OnClick", ToggleSection)
secMin:SetScript("OnClick", ToggleSection)

local partyBtn = CreateFrame("Button", nil, sec)
partyBtn:SetSize(20, 20); partyBtn:SetPoint("RIGHT", secMin, "LEFT", -6, 0)
partyBtn.icon = partyBtn:CreateTexture(nil, "ARTWORK"); partyBtn.icon:SetAllPoints()
partyBtn.icon:SetTexture("Interface\\AddOns\\QuestMates\\PartyIcon")
partyBtn.ring = partyBtn:CreateTexture(nil, "OVERLAY")
partyBtn.ring:SetTexture("Interface\\Buttons\\CheckButtonHilight"); partyBtn.ring:SetBlendMode("ADD")
partyBtn.ring:SetPoint("TOPLEFT", -4, 4); partyBtn.ring:SetPoint("BOTTOMRIGHT", 4, -4)
partyBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
partyBtn.count = partyBtn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
partyBtn.count:SetPoint("BOTTOMRIGHT", 3, -2)
partyBtn:SetScript("OnClick", function()
  tab = (tab == "party") and "mine" or "party"; scrollOff = 0; db.utSecMin = false; QuestMatesTracker_Refresh()
end)
partyBtn:SetScript("OnEnter", function(b)
  GameTooltip:SetOwner(b, "ANCHOR_LEFT")
  GameTooltip:AddLine(tab == "party" and "Show my quests" or "Show party quests", 1, 0.82, 0)
  GameTooltip:Show()
end)
partyBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

------------------------------------------------------------------------
-- My watched quests
------------------------------------------------------------------------
local function Watched(qid, idx)
  if C_QuestLog and C_QuestLog.GetQuestWatchType then
    local ok, w = pcall(C_QuestLog.GetQuestWatchType, qid); if ok and w ~= nil then return true end
  end
  if C_QuestLog and C_QuestLog.IsQuestWatched then
    local ok, w = pcall(C_QuestLog.IsQuestWatched, qid); if ok and w then return true end
  end
  if IsQuestWatched and idx then
    local ok, w = pcall(IsQuestWatched, idx); if ok and w then return true end
  end
  if QuestLedgerForever_IsWatched then
    local ok, w = pcall(QuestLedgerForever_IsWatched, qid, idx); if ok and w then return true end
  end
  return false
end

local function Tag(qid)
  if C_QuestLog and C_QuestLog.GetQuestTagInfo then
    local ok, t = pcall(C_QuestLog.GetQuestTagInfo, qid)
    if ok and type(t) == "table" and t.tagName and t.tagName ~= "" then return t.tagName end
  end
end

local function MyObjectives(qid, idx)
  local out = {}
  if C_QuestLog and C_QuestLog.GetQuestObjectives then
    local ok, objs = pcall(C_QuestLog.GetQuestObjectives, qid)
    if ok and type(objs) == "table" then
      for _, o in ipairs(objs) do
        if o.text and o.text ~= "" then
          local h, nd = o.numFulfilled, o.numRequired
          if not nd or nd == 0 then local a, b = tostring(o.text):match("(%d+)%s*/%s*(%d+)"); h, nd = tonumber(a), tonumber(b) end
          out[#out + 1] = { text = o.text, done = o.finished and true or false, have = h, need = nd }
        end
      end
    end
  end
  if #out == 0 and idx and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
    for j = 1, (GetNumQuestLeaderBoards(idx) or 0) do
      local text, _, finished = GetQuestLogLeaderBoard(j, idx)
      if text and text ~= "" then
        local a, b = tostring(text):match("(%d+)%s*/%s*(%d+)")
        out[#out + 1] = { text = text, done = finished and true or false, have = tonumber(a), need = tonumber(b) }
      end
    end
  end
  return out
end

-- quests with no counted objectives show the short "what to do" text, like the default tracker
local function ShortText(idx)
  if not (GetQuestLogQuestText and idx) then return nil end
  if SelectQuestLogEntry then
    local prev = GetQuestLogSelection and GetQuestLogSelection()
    pcall(SelectQuestLogEntry, idx)
    local ok, _, objText = pcall(GetQuestLogQuestText)
    if prev and prev > 0 then pcall(SelectQuestLogEntry, prev) end
    if ok then return objText end
  else
    local ok, _, objText = pcall(GetQuestLogQuestText, idx)
    if ok then return objText end
  end
end

-- timed quests: GetTime() at which the timer runs out, or nil
local timerByIndex = {}
local function ReadTimers()
  wipe(timerByIndex)
  if GetQuestTimers and GetQuestIndexForTimer then
    local t = { GetQuestTimers() }
    for i, left in ipairs(t) do
      local idx = GetQuestIndexForTimer(i)
      if idx and tonumber(left) then timerByIndex[idx] = GetTime() + tonumber(left) end
    end
  end
end
QuestTimeEnd = function(qid, idx)
  if C_QuestLog and C_QuestLog.GetTimeAllowed then
    local ok, total, elapsed = pcall(C_QuestLog.GetTimeAllowed, qid)
    if ok and total and elapsed and total > 0 and total > elapsed then return GetTime() + (total - elapsed) end
  end
  return idx and timerByIndex[idx] or nil
end

local function MyQuests()
  ReadTimers()
  local list = {}
  local logFlag
  local function add(qid, title, level, complete, idx)
    if not qid or qid == 0 or not Watched(qid, idx) then return end
    local objs = MyObjectives(qid, idx)
    if #objs == 0 then
      complete = (complete == 1 or complete == true) and logFlag
    else
      local all = true
      for _, o in ipairs(objs) do if not o.done then all = false end end
      complete = all or (logFlag and true or false)
    end
    list[#list + 1] = { id = qid, title = title or ("Quest " .. qid), level = level or 0, complete = complete and true or false,
      objs = objs, desc = (#objs == 0 and not complete) and ShortText(idx) or nil, tag = Tag(qid), timeEnd = QuestTimeEnd(qid, idx) }
  end
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    for i = 1, (C_QuestLog.GetNumQuestLogEntries() or 0) do
      local info = C_QuestLog.GetInfo(i)
      if info and not info.isHeader and info.questID then
        logFlag = (info.isComplete == 1 or info.isComplete == true)
        add(info.questID, info.title, info.level, logFlag, i)
      end
    end
  elseif GetNumQuestLogEntries and GetQuestLogTitle then
    for i = 1, (GetNumQuestLogEntries() or 0) do
      local t, lvl, _, isHeader, _, isComplete, _, qid = GetQuestLogTitle(i)
      logFlag = (isComplete == 1 or isComplete == true)
      if t and not isHeader then add(qid, t, lvl, logFlag, i) end
    end
  end
  table.sort(list, function(a, b)
    if a.level ~= b.level then return a.level < b.level end -- lowest level first
    return a.title < b.title
  end)
  return list
end

------------------------------------------------------------------------
-- Clicks
------------------------------------------------------------------------
local function LevelColor(level)
  if GetQuestDifficultyColor then
    local c = GetQuestDifficultyColor(level or 0)
    if c then return c.r, c.g, c.b end
  end
  return 1, 0.82, 0
end

local function QuestMapID(q, who)
  local src = who and API.FriendQuest(who, q.id) or API.MyQuest(q.id) or q
  local p = src and src.pois and src.pois[1]
  if p then return p.m end
  if not who and GetQuestUiMapID then
    local ok, m = pcall(GetQuestUiMapID, q.id); if ok and m and m > 0 then return m end
  end
end

local function ShowOnMap(q, who)
  local m = QuestMapID(q, who)
  if not m then
    DEFAULT_CHAT_FRAME:AddMessage(P .. "No map location known for " .. q.title .. " yet.")
    return
  end
  if OpenWorldMap then OpenWorldMap(m)
  elseif WorldMapFrame then
    if not WorldMapFrame:IsShown() then ToggleWorldMap() end
    WorldMapFrame:SetMapID(m)
  end
end

Untrack = function(qid)
  local idx = C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(qid)
  if not idx and GetQuestLogIndexByID then idx = GetQuestLogIndexByID(qid) end
  local function try(fn, ...) if fn then return (pcall(fn, ...)) end end
  if not (C_QuestLog and C_QuestLog.RemoveQuestWatch and try(C_QuestLog.RemoveQuestWatch, qid)) then
    if idx then try(RemoveQuestWatch, idx) end
  end
  if QuestWatch_Update then pcall(QuestWatch_Update) end
  if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_CLOSE then pcall(PlaySound, SOUNDKIT.IG_QUEST_LIST_CLOSE) end
  QuestMatesTracker_Refresh()
end

-- super tracking (the in-world diamond): modern C_SuperTrack, or the older global functions
STGet = function()
  if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
    local ok, v = pcall(C_SuperTrack.GetSuperTrackedQuestID); if ok and v then return v end
  end
  if GetSuperTrackedQuestID then local ok, v = pcall(GetSuperTrackedQuestID); if ok then return v end end
end
STSet = function(id)
  local done = false
  if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then done = pcall(C_SuperTrack.SetSuperTrackedQuestID, id) end
  if SetSuperTrackedQuestID then done = pcall(SetSuperTrackedQuestID, id) or done end
  -- nav CVar only if this client has it
  if id and id > 0 and GetCVar and GetCVar("showInGameNavigation") == "0" then pcall(SetCVar, "showInGameNavigation", "1") end
  return done
end

-- the 3D arrow Quest Ledger Forever uses: Rally Point's if installed, otherwise Quest Ledger's own
Arrow3D = function(qid)
  if QuestLedgerForever_ArrowOff and QuestLedgerForever_ArrowOff() then return end
  if qid then
    if RallyPoint_FollowQuest then pcall(RallyPoint_FollowQuest, qid)
    elseif QLF_OwnArrow then pcall(QLF_OwnArrow, qid) end
  else
    if RallyPoint_StopFollow then pcall(RallyPoint_StopFollow) end
    if QLF_HideArrow then pcall(QLF_HideArrow) end
  end
end

-- 3D arrow at a party member's quest (their nearest objective spot)
FriendArrow = function(who, q)
  if QuestLedgerForever_ArrowOff and QuestLedgerForever_ArrowOff() then return end
  local p = API.NearestPoint and API.NearestPoint(who, q.id)
  if p and QLF_PointArrow then pcall(QLF_PointArrow, p.m, p.x, p.y, who .. ": " .. (q.title or "")) end
end

-- QuestMates tells us what the party picked: the newest pick (mine or theirs) gets the diamond + 3D arrow
function ObjectiveForever_PinnedQuest()
  local _, hold = API.Pinned()
  return hold and pinnedOwn or nil
end
function ObjectiveForever_FriendPinned(who, q)
  if not (db and q and q.pois and #q.pois > 0) then return end
  pinnedOwn = nil
  STSet(0)
  API.PinFriend(who, q)
  FriendArrow(who, q)
  local c = API.Color(who)
  DEFAULT_CHAT_FRAME:AddMessage(P .. ("Arrow now on |cff%02x%02x%02x%s|r's quest: %s"):format(
    c[1] * 255, c[2] * 255, c[3] * 255, who, q.title or "?"))
  if API.PinChanged then API.PinChanged() end
  QuestMatesTracker_Refresh()
end
function ObjectiveForever_FriendUnpinned(who, qid)
  local key = API.Pinned()
  if key == (who .. ":" .. qid) then
    API.Unpin(); Arrow3D(nil)
    QuestMatesTracker_Refresh()
  end
end

local function TogglePin(q, who, keepOn)
  local key, hold = API.Pinned()
  if who then
    if key == (who .. ":" .. q.id) then
      if not keepOn then API.Unpin(); Arrow3D(nil); QuestMatesTracker_Refresh() end
      return
    end
    local fq = API.FriendQuest(who, q.id)
    if not (fq and fq.pois and #fq.pois > 0) then
      if not keepOn then DEFAULT_CHAT_FRAME:AddMessage(P .. "No location known for " .. who .. "'s " .. q.title .. " yet.") end
      return
    end
    pinnedOwn = nil
    STSet(0)
    API.PinFriend(who, fq)
    FriendArrow(who, fq)
    if API.PinChanged then API.PinChanged() end
  else
    if hold and pinnedOwn == q.id then
      if keepOn then return end
      -- untrack: diamond and 3D arrow off
      pinnedOwn = nil
      API.Unpin()
      STSet(0)
      Arrow3D(nil)
      if API.PinChanged then API.PinChanged() end
      QuestMatesTracker_Refresh()
      return
    end
    API.Unpin()
    if C_Map and C_Map.ClearUserWaypoint then pcall(C_Map.ClearUserWaypoint) end
    pinnedOwn = q.id
    STSet(q.id)
    API.HoldPointer(true)
    Arrow3D(q.id)
    if API.PinChanged then API.PinChanged() end
  end
  QuestMatesTracker_Refresh()
end

local function IsPinned(q, who)
  local key, hold = API.Pinned()
  if who then return key == (who .. ":" .. q.id) end
  return hold and pinnedOwn == q.id or false
end

------------------------------------------------------------------------
-- Lines
------------------------------------------------------------------------
local pool, n, y = {}, 0, 0

local function GetLine()
  n = n + 1
  local l = pool[n]
  if not l then
    l = CreateFrame("Button", nil, f)
    l:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    l.fs = l:CreateFontString(nil, "OVERLAY")
    l.fs:SetJustifyH("LEFT"); l.fs:SetWordWrap(true)
    l.icon = CreateFrame("Button", nil, l)
    l.icon:SetSize(16, 16); l.icon:SetPoint("TOPLEFT", 0, 1)
    l.icon.tex = l.icon:CreateTexture(nil, "ARTWORK"); l.icon.tex:SetAllPoints()
    -- selected (marker) quest: small arrow in front + a fading highlight behind the row
    l.icon.glow = l.icon:CreateTexture(nil, "OVERLAY") -- kept for compatibility, never shown
    l.icon.glow:Hide()
    l.sel = l:CreateTexture(nil, "BACKGROUND", nil, -1)
    l.sel:SetTexture("Interface\\Buttons\\WHITE8X8")
    l.sel:SetPoint("TOPLEFT", -6, 2); l.sel:SetPoint("BOTTOMRIGHT", 0, -2)
    l.sel:Hide()
    l.arrow = l:CreateTexture(nil, "OVERLAY")
    l.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    l.arrow:SetSize(12, 12); l.arrow:SetPoint("RIGHT", l, "TOPLEFT", -1, -8)
    l.arrow:Hide()
    -- style C: the icon sits on a gold-rimmed disc
    local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    l.rim = l.icon:CreateTexture(nil, "BACKGROUND", nil, 1)
    l.rim:SetTexture(CIRCLE); l.rim:SetSize(21, 21); l.rim:SetPoint("CENTER")
    l.disc = l.icon:CreateTexture(nil, "BACKGROUND", nil, 2)
    l.disc:SetTexture(CIRCLE); l.disc:SetSize(18, 18); l.disc:SetPoint("CENTER")
    l.rim:Hide(); l.disc:Hide()
    l.icon:SetScript("OnClick", function(b)
      local d = b:GetParent().data
      if d and d.q then TogglePin(d.q, d.who) elseif d and d.recipe then b:GetParent():Click("LeftButton") end
    end)
    l.icon:SetScript("OnEnter", function(b)
      if not (b:GetParent().data and b:GetParent().data.q) then return end
      GameTooltip:SetOwner(b, "ANCHOR_LEFT")
      GameTooltip:AddLine(IsPinned(b:GetParent().data.q, b:GetParent().data.who) and "Click to remove the marker" or "Click to point the marker here", 1, 1, 1)
      GameTooltip:Show()
    end)
    l.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    l:SetScript("OnClick", function(b, button)
      local d = b.data; if not d then return end
      if d.kind == "friend" then collapsedFriend[d.who] = not collapsedFriend[d.who]; QuestMatesTracker_Refresh() return end
      if d.recipe then
        if IsShiftKeyDown() then
          local eb = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
          local link = C_TradeSkillUI and C_TradeSkillUI.GetRecipeLink and C_TradeSkillUI.GetRecipeLink(d.recipe.id)
          if eb and link then ChatEdit_InsertLink(link) return end
          if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked then pcall(C_TradeSkillUI.SetRecipeTracked, d.recipe.id, false, d.recipe.recraft) end
          QuestMatesTracker_Refresh()
        elseif C_TradeSkillUI and C_TradeSkillUI.OpenRecipe then
          pcall(C_TradeSkillUI.OpenRecipe, d.recipe.id)
        end
        return
      end
      if not d.q then return end
      if IsShiftKeyDown() then
        -- chat box open: link the quest; otherwise Shift-click untracks my own quest (like the default tracker)
        local eb = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
        if eb or d.who then API.OpenQuest(d.q, d.who) return end
        Untrack(d.q.id)
        return
      end
      if button == "RightButton" then
        -- my quest: my quest log (Quest Ledger Forever); friend's quest: the QuestMates reader
        API.OpenQuest(d.q, d.who, d.who ~= nil)
      else
        if IsControlKeyDown() then ShowOnMap(d.q, d.who)  -- Ctrl-click: the map
        else TogglePin(d.q, d.who) end                     -- click: track (diamond + 3D arrow), click again: untrack
      end
    end)
    l:SetScript("OnEnter", function(b)
      local d = b.data
      if d and d.recipe then
        b.fs:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(b, "ANCHOR_LEFT")
        local ok = d.recipe.link and pcall(GameTooltip.SetHyperlink, GameTooltip, d.recipe.link)
        if not ok then GameTooltip:AddLine(d.recipe.name, 1, 0.82, 0) end
        GameTooltip:AddLine("Click to open the profession - Shift-click to stop tracking", 0.5, 0.8, 1)
        GameTooltip:Show()
      elseif d and d.q then
        b.fs:SetTextColor(1, 1, 1)
        if d.who then API.QuestTooltip(b, d.q, d.who, "Click to track/untrack - right-click to read it - Ctrl-click for the map")
        else
          GameTooltip:SetOwner(b, "ANCHOR_LEFT")
          GameTooltip:AddLine(string.format("[%d] %s", d.q.level or 0, d.q.title), 1, 0.82, 0)
          for _, fr in ipairs(API.FriendsOnQuest(d.q.id)) do
            local c = fr.color
            local prog = {}
            for _, o in ipairs(fr.objs) do if o.need and o.need > 0 then prog[#prog + 1] = o.have .. "/" .. o.need end end
            GameTooltip:AddLine(fr.who .. ": " .. (fr.complete and "done" or table.concat(prog, " ")), c[1], c[2], c[3])
          end
          GameTooltip:AddLine("Click to track/untrack - right-click for the quest log - Ctrl-click for the map", 0.5, 0.8, 1)
          GameTooltip:AddLine("Shift-click to stop tracking", 0.5, 0.8, 1)
          GameTooltip:Show()
        end
      end
    end)
    l:SetScript("OnLeave", function(b) if b.r then b.fs:SetTextColor(b.r, b.g, b.b) end; GameTooltip:Hide() end)
    l.flash = l:CreateTexture(nil, "BACKGROUND")
    l.flash:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight"); l.flash:SetBlendMode("ADD")
    l.flash:SetPoint("TOPLEFT", -6, 2); l.flash:SetPoint("BOTTOMRIGHT", 4, -2); l.flash:SetAlpha(0)
    l.flashEnd = 0
    l:SetScript("OnUpdate", function(b)
      if b.slideStart then
        local t = (GetTime() - b.slideStart) / 0.3
        if t >= 1 then
          b.slideStart = nil
          b:SetPoint("TOPLEFT", f, "TOPLEFT", b.baseX, b.baseY)
        else
          local e = 1 - (1 - t) * (1 - t) -- ease out
          b:SetPoint("TOPLEFT", f, "TOPLEFT", b.baseX, b.baseY + b.slideFrom * (1 - e))
        end
      end
      local left = (b.flashEnd or 0) - GetTime()
      if left > 0 then b.flash:SetAlpha(math.min(1, left / 0.8)) elseif b.flash:GetAlpha() > 0 then b.flash:SetAlpha(0) end
    end)
    local ok, ag = pcall(l.fs.CreateAnimationGroup, l.fs)
    if ok and ag then
      local up = ag:CreateAnimation("Scale"); up:SetScale(1.12, 1.12); up:SetDuration(0.12); up:SetOrder(1)
      if up.SetOrigin then up:SetOrigin("LEFT", 0, 0) end
      local down = ag:CreateAnimation("Scale"); down:SetScale(1 / 1.12, 1 / 1.12); down:SetDuration(0.18); down:SetOrder(2)
      if down.SetOrigin then down:SetOrigin("LEFT", 0, 0) end
      l.pop = ag
    end
    pool[n] = l
  end
  return l
end

local prevY, newY, slideNext = {}, {}, false -- content positions per line key, for the slide animation
local function Line(font, text, indent, r, g, b, data, icon, pinned, flashEnd, pop, key)
  local l = GetLine()
  l.flashEnd = flashEnd or 0
  if not flashEnd then l.flash:SetAlpha(0) end
  if pop and l.pop then l.pop:Stop(); l.pop:Play() end
  l.data = data
  l.fs:SetFontObject(font); l.fs:SetText(text)
  l.r, l.g, l.b = r, g, b; l.fs:SetTextColor(r, g, b)
  l.fs:ClearAllPoints()
  l.fs:SetPoint("TOPLEFT", icon and 20 or 0, 0); l.fs:SetPoint("RIGHT", l, "RIGHT", 0, 0)
  -- selected look: gold for my quests, the friend's color for party quests
  if pinned then
    local c = (data and data.who) and API.Color(data.who) or { 1, 0.82, 0 }
    if l.sel.SetGradient and CreateColor then
      l.sel:SetVertexColor(1, 1, 1, 1)
      l.sel:SetGradient("HORIZONTAL", CreateColor(c[1], c[2], c[3], 0.35), CreateColor(c[1], c[2], c[3], 0))
    else
      l.sel:SetVertexColor(c[1], c[2], c[3], 0.25)
    end
    l.rim:SetVertexColor(c[1], c[2], c[3], 1)
    l.disc:SetVertexColor(c[1] * 0.45, c[2] * 0.45, c[3] * 0.45, 1)
    l.rim:Show(); l.disc:Show()
  else
    l.rim:Hide(); l.disc:Hide()
  end
  l.sel:Hide(); l.arrow:Hide() -- style D (arrow + row highlight) is off
  if icon then
    l.icon.tex:SetTexture(icon); l.icon.tex:SetTexCoord(0, 1, 0, 1)
    if data and data.recipe then l.icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    l.icon:Show()
  else l.icon:Hide() end
  l:ClearAllPoints()
  l:SetPoint("TOPLEFT", f, "TOPLEFT", indent, y + scrollOff); l:SetPoint("RIGHT", f, "RIGHT", -10, 0)
  -- slide from the old spot when the list was reordered by new progress
  l.baseX, l.baseY, l.slideStart = indent, y + scrollOff, nil
  if key then
    if slideNext and prevY[key] and prevY[key] ~= y then
      l.slideFrom = prevY[key] - y; l.slideStart = GetTime()
      l:SetPoint("TOPLEFT", f, "TOPLEFT", indent, y + scrollOff + l.slideFrom)
    end
    newY[key] = y
  end
  local h = math.max(icon and 16 or 12, l.fs:GetStringHeight() or 12)
  l:SetHeight(h); l:EnableMouse(data ~= nil)
  -- only the text itself catches clicks; the empty rest of the row clicks through to the world
  local rowW = WIDTH - indent - 10
  local used = (icon and 20 or 0) + math.min(l.fs:GetStringWidth() or rowW, rowW - (icon and 20 or 0))
  l:SetHitRectInsets(0, math.max(0, rowW - used), 0, 0)
  -- scrolled list: only lines fully inside the visible area (below the header) are shown
  local top = -(y + scrollOff)
  l:SetShown(top >= HEADH and top + h <= HEADH + viewH)
  y = y - h - 2
  return true
end

------------------------------------------------------------------------
-- Tracked recipes (the game's own profession tracking)
------------------------------------------------------------------------
local function ItemCount(id)
  if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id, true, false, true, true) or 0 end
  return GetItemCount and GetItemCount(id, true) or 0
end
local function ItemName(id)
  local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
  if not name and GetItemInfo then name = GetItemInfo(id) end
  return name
end
local function TrackedRecipes()
  local out = {}
  if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipesTracked and C_TradeSkillUI.GetRecipeSchematic) then return out end
  for _, recraft in ipairs({ false, true }) do
    local ok, ids = pcall(C_TradeSkillUI.GetRecipesTracked, recraft)
    if ok and type(ids) == "table" then
      for _, id in ipairs(ids) do
        local ok2, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, id, recraft)
        if ok2 and sch then
          local r = { id = id, recraft = recraft, name = sch.name or ("Recipe " .. id), icon = sch.icon, objs = {} }
          if C_TradeSkillUI.GetRecipeLink then r.link = C_TradeSkillUI.GetRecipeLink(id) end
          for _, slot in ipairs(sch.reagentSlotSchematics or {}) do
            local rg = slot.reagents and slot.reagents[1]
            local need = slot.quantityRequired or 0
            if rg and rg.itemID and need > 0 and slot.required ~= false then
              local have = 0
              for _, alt in ipairs(slot.reagents) do if alt.itemID then have = have + ItemCount(alt.itemID) end end
              local nm = ItemName(rg.itemID) or ("item " .. rg.itemID)
              r.objs[#r.objs + 1] = { text = string.format("%s %d/%d", nm, math.min(have, need), need),
                have = math.min(have, need), need = need, done = have >= need }
            end
          end
          out[#out + 1] = r
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- "Professions" section bar, laid out inside the scrolling list
local pbar = CreateFrame("Button", nil, f)
pbar:SetHeight(24)
local pbg = HeaderArt(pbar, { "UI-QuestTracker-Secondary-Objective-Header", "Objective-Header" })
pbg:SetPoint("TOPLEFT", -12, 3); pbg:SetPoint("BOTTOMRIGHT", 12, -3)
local pMin = MinButton(pbar, 16, 15, "UI-QuestTrackerButton-Secondary-Collapse", "UI-QuestTrackerButton-Secondary-Expand", "UI-QuestTrackerButton-Yellow-Highlight")
pMin:SetPoint("RIGHT", -2, 0)
local pText = pbar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pText:SetPoint("LEFT", 6, 0); pText:SetText("Professions")
local function ToggleProf() db.utProfMin = not db.utProfMin; QuestMatesTracker_Refresh() end
pbar:SetScript("OnClick", ToggleProf); pMin:SetScript("OnClick", ToggleProf)
pbar:Hide()

local function ProfessionSection()
  local list = TrackedRecipes()
  if #list == 0 then pbar:Hide() return end
  y = y - 8
  pbar:ClearAllPoints()
  pbar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y + scrollOff); pbar:SetPoint("RIGHT", f, "RIGHT", -10, 0)
  local top = -(y + scrollOff)
  pbar:SetShown(top >= HEADH and top + 24 <= HEADH + viewH)
  pMin:SetCollapsed(db.utProfMin)
  y = y - 28
  if db.utProfMin then return end
  for _, r in ipairs(list) do
    Line("GameFontNormal", r.name, 4, 1, 0.82, 0, { recipe = r }, r.icon)
    for _, o in ipairs(r.objs) do
      local r2, g2, b2 = ProgressColor(o)
      Line("GameFontHighlightSmall", (o.done and CHECK or "- ") .. o.text, 24, r2, g2, b2)
    end
    y = y - 4
  end
end

-- progress memory: [who or "me"][qid][objective index] = have; flashes when it goes up
local seen, flashUntil = {}, {}
CHECK = "|A:UI-QuestTracker-Tracker-Check:12:12|a "
local function Lerp(a, b, t) return a + (b - a) * t end
ProgressColor = function(o, who)
  if o.done then
    if who then local c = API.Color(who); return c[1], c[2], c[3] end
    return 0.3, 1, 0.3
  end
  local t = (o.need and o.need > 0) and math.min(1, (o.have or 0) / o.need) or 0
  if who then -- white -> friend's color
    local c = API.Color(who)
    return Lerp(0.9, c[1], t), Lerp(0.9, c[2], t), Lerp(0.9, c[3], t)
  end
  if t < 0.5 then -- white -> yellow -> green
    local u = t / 0.5; return Lerp(0.9, 1, u), Lerp(0.9, 0.82, u), Lerp(0.9, 0.1, u)
  end
  local u = (t - 0.5) / 0.5; return Lerp(1, 0.45, u), Lerp(0.82, 1, u), Lerp(0.1, 0.3, u)
end

-- newest progress first: the quest that last got a kill/item jumps to the top (per owner: "me" or a friend)
local topQuest = {}
local function NoteProgress(owner, list)
  local s = seen[owner]
  if not s then return end
  for _, q in ipairs(list) do
    local prev = s[q.id]
    if prev then
      local up = q.complete and not prev.done
      for i, o in ipairs(q.objs or {}) do
        if prev[i] and o.have and o.have > prev[i] then up = true end
      end
      if up and topQuest[owner] ~= q.id then topQuest[owner] = q.id; slideNext = true end
    end
  end
end
local function TopFirst(owner, list)
  local id = topQuest[owner]
  if not id then return list end
  for i, q in ipairs(list) do
    if q.id == id then table.remove(list, i); table.insert(list, 1, q); break end
  end
  return list
end

local function QuestBlock(q, who, extra)
  local r, g, b = LevelColor(q.level)
  local lvl = tostring(q.level or 0) .. ((q.tag == ELITE or q.tag == "Elite") and "+" or "")
  local name = string.format("[%s] %s%s", lvl, q.title, q.tag and (" (" .. q.tag .. ")") or "")
  local owner = who or "me"
  local kb = owner .. ":" .. q.id .. ":"
  if not Line("GameFontNormal", name .. (extra or ""), 4, r, g, b, { q = q, who = who },
    q.complete and ICON_DONE or ICON_PROGRESS, IsPinned(q, who), nil, nil, kb .. "t") then return false end
  seen[owner] = seen[owner] or {}
  if q.timeEnd then
    local left = math.max(0, q.timeEnd - GetTime())
    local txt = string.format("|TInterface\\Icons\\INV_Misc_PocketWatch_01:12:12:0:0:64:64:6:58:6:58|t %d:%02d", math.floor(left / 60), math.floor(left % 60))
    local tr, tg, tb = 1, 1, 1
    if left < 15 then
      if math.floor(GetTime() * 2) % 2 == 0 then tr, tg, tb = 1, 0.15, 0.15 else tr, tg, tb = 0.6, 0.05, 0.05 end
    elseif left < 60 then tr, tg, tb = 1, 0.55, 0.1 end
    Line("GameFontHighlightSmall", txt, 24, tr, tg, tb, nil, nil, nil, nil, nil, kb .. "timer")
  end
  if q.complete then
    Line("GameFontHighlightSmall", "- Ready for turn-in", 24, 0.3, 1, 0.3, nil, nil, nil, nil, nil, kb .. "d")
    local now = { done = true }
    for i, o in ipairs(q.objs or {}) do now[i] = o.have end
    seen[owner][q.id] = now
  elseif q.desc and q.desc ~= "" then
    Line("GameFontHighlightSmall", q.desc, 24, 0.85, 0.85, 0.85, nil, nil, nil, nil, nil, kb .. "d")
    seen[owner][q.id] = { done = false }
  else
    local prev = seen[owner][q.id]
    local now = { done = false }
    for i, o in ipairs(q.objs or {}) do
      local key = owner .. ":" .. q.id .. ":" .. i
      now[i] = o.have
      local pop = false
      if prev and prev[i] and o.have and o.have > prev[i] then
        flashUntil[key] = GetTime() + 1.2; pop = true
      end
      local fe = flashUntil[key]
      if fe and fe <= GetTime() then flashUntil[key] = nil; fe = nil end
      local r2, g2, b2 = ProgressColor(o, who)
      Line("GameFontHighlightSmall", (o.done and CHECK or "- ") .. (o.text or ""), 24, r2, g2, b2, nil, nil, nil, fe, pop, kb .. i)
    end
    seen[owner][q.id] = now
  end
  y = y - 4
  return true
end

------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------
local function Enabled() return db and db.unifiedTracker ~= false end
local anyTimer = false

function QuestMatesTracker_Refresh()
  if not Enabled() then f:Hide() return end
  for _, l in ipairs(pool) do l:Hide() end
  n, y = 0, -HEADH
  -- room from the tracker's top down to just above the bottom action bars
  local ftop = f:GetTop()
  local fs = f:GetScale() or 1
  viewH = ftop and math.max(120, ftop - 150 / fs - HEADH) or 600

  local friends = API.Friends()
  local inParty = #friends > 0
  if not inParty then tab = "mine" end
  partyBtn:SetShown(inParty)
  partyBtn.count:SetText(inParty and #friends or "")
  partyBtn.ring:SetShown(tab == "party")
  secText:SetText(tab == "party" and "Party Quests" or "Quests")
  minBtn:SetCollapsed(db.utMin); secMin:SetCollapsed(db.utSecMin)
  sec:SetShown(not db.utMin)
  f:SetScale(db.utScale or 1)
  Place()

  if db.utMin then y = -26 end
  if not db.utMin and not db.utSecMin then
    if tab == "mine" then
      anyTimer = false
      local qs = MyQuests()
      NoteProgress("me", qs); TopFirst("me", qs)
      -- running timers always on top
      local timed, rest = {}, {}
      for _, q in ipairs(qs) do if q.timeEnd and not q.complete then timed[#timed + 1] = q else rest[#rest + 1] = q end end
      if #timed > 0 then
        table.sort(timed, function(a, b) return a.timeEnd < b.timeEnd end)
        for _, q in ipairs(rest) do timed[#timed + 1] = q end
        qs = timed
      end
      anyTimer = #timed > 0
      if #qs == 0 then Line("GameFontHighlightSmall", "No tracked quests", 4, 0.6, 0.6, 0.6) end
      for i, q in ipairs(qs) do
        local shared = inParty and #API.FriendsOnQuest(q.id) or 0
        local extra = shared > 0 and string.format(" |cff5dcaa5shared %d|r", shared) or nil
        if not QuestBlock(q, nil, extra) then
          break
        end
      end
    else
      for _, who in ipairs(friends) do
        local fq = API.FriendQuests(who)
        NoteProgress(who, fq); TopFirst(who, fq)
        local c = API.Color(who)
        local count = #fq
        y = y - 2
        if not Line("GameFontNormal", who .. " |cff888888- " .. count .. (count == 1 and " quest|r" or " quests|r")
          .. (collapsedFriend[who] and " |cff888888(+)|r" or ""), 4, c[1], c[2], c[3], { kind = "friend", who = who }) then break end
        if not collapsedFriend[who] then
          if count == 0 then Line("GameFontHighlightSmall", "No quests", 24, 0.6, 0.6, 0.6) end
          for _, q in ipairs(fq) do
            local extra = API.MyQuest(q.id) and " |cff5dcaa5you have this|r" or nil
            local view = { id = q.id, title = q.title, level = q.level, complete = q.complete, objs = q.objs }
            if not QuestBlock(view, who, extra) then break end
          end
        end
      end
    end
  end
  if not db.utMin and tab == "mine" then ProfessionSection() else pbar:Hide() end
  prevY, newY, slideNext = newY, {}, false
  local total = math.max(0, -y - HEADH)
  local maxOff = math.max(0, total - viewH)
  if scrollOff > maxOff then scrollOff = maxOff; QuestMatesTracker_Refresh() return end
  f.maxOff = maxOff
  f:EnableMouseWheel(maxOff > 0 and not db.utMin)
  f:SetHeight((db.utMin and 26 or HEADH) + math.min(total, viewH) + 4)
  local shownH = math.min(total, viewH)
  if maxOff > 0 and not db.utMin then
    bar:ClearAllPoints()
    bar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -HEADH)
    bar:SetHeight(shownH)
    local th = math.max(20, shownH * shownH / total)
    thumb:SetHeight(th)
    thumb:ClearAllPoints()
    thumb:SetPoint("TOP", bar, "TOP", 0, -(shownH - th) * scrollOff / maxOff)
    bar:Show()
  else
    bar:Hide()
  end
  f:Show()
end

------------------------------------------------------------------------
-- Hiding / restoring Blizzard's tracker
------------------------------------------------------------------------
local function BlizzFrames()
  local out = {}
  for _, name in ipairs({ "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame", "QuestTimerFrame" }) do
    if _G[name] then out[#out + 1] = _G[name] end
  end
  return out
end

-- right edge that keeps clear of the side action bars (and anything else docked on the right)
local SIDE_BARS = { "MultiBarRight", "MultiBarLeft" } -- action bar 4 and bar 5 only
local function RightEdge()
  local edge = UIParent:GetRight() or 0
  local us = UIParent:GetEffectiveScale() or 1
  local half = (UIParent:GetWidth() or 0) / 2
  local function check(fr)
    if fr and fr:IsVisible() and fr:GetLeft() then
      local left = fr:GetLeft() * (fr:GetEffectiveScale() or 1) / us
      if left > half and left < edge then edge = left end
    end
  end
  for _, name in ipairs(SIDE_BARS) do
    check(_G[name])
    for i = 1, 12 do check(_G[name .. "Button" .. i]) end
  end
  return edge - 8
end

-- saved spot for the current Edit Mode layout (false = reset to the automatic spot)
local function SavedPos()
  -- the old single position moves into the layout that's active the first time; layouts with nothing saved use the automatic spot
  if db.utPos then
    db.utPosL = db.utPosL or {}
    local L = EM.Layout()
    if db.utPosL[L] == nil then db.utPosL[L] = db.utPos end
    db.utPos = nil
  end
  local v = db.utPosL and db.utPosL[EM.Layout()]
  return v or nil
end

Place = function()
  if f.moving or f.emMoving then return end
  f:ClearAllPoints()
  local scale = f:GetScale() or 1
  local edge = RightEdge()
  local sp = SavedPos()
  if sp then
    f:SetPoint(sp[1], UIParent, sp[2], sp[3], sp[4])
    -- older saves were anchored at the bottom: re-anchor by the top so minimizing doesn't move it
    if not tostring(sp[1]):find("TOP") and f:GetTop() then
      EM.TopAnchor(f)
      local p, _, rp, x, y = f:GetPoint()
      db.utPosL = db.utPosL or {}; db.utPosL[EM.Layout()] = { p, rp, x, y }
    end
    -- even a saved spot never sits on top of the side bars
    local right, top = f:GetRight(), f:GetTop()
    if right and top and right * scale > edge then
      f:ClearAllPoints()
      f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", edge / scale, top)
    end
    return
  end
  local x = edge - (UIParent:GetRight() or 0)
  -- start right under the minimap (higher than Blizzard's spot)
  local y
  local mm = MinimapCluster or Minimap
  local bottom = mm and mm:IsShown() and mm:GetBottom()
  if bottom then
    y = bottom * (mm:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1) - (UIParent:GetTop() or 0) - 2
  end
  y = y or db.utTop or -200
  f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", x / scale, y / scale)
end

-- watch the right edge (bar 4 / bar 5 switched on or off in settings, bars moved) and follow it
local lastEdge, watchT = nil, 0
f:SetScript("OnUpdate", function(_, el)
  watchT = watchT + el
  if watchT < 0.5 then return end
  watchT = 0
  if not db then return end
  local e = math.floor(RightEdge() + 0.5)
  if e ~= lastEdge then lastEdge = e; Place() end
end)

local pendingApply = false
local hooked = {}
local function GuardShow(bf)
  if hooked[bf] then return end
  hooked[bf] = true
  bf:HookScript("OnShow", function(self)
    if Enabled() and self:GetParent() ~= hider then C_Timer.After(0, function() QuestMatesTracker_Apply() end) end
  end)
end
function QuestMatesTracker_Apply()
  if not db then return end
  if InCombatLockdown and InCombatLockdown() then pendingApply = true return end
  pendingApply = false
  for _, bf in ipairs(BlizzFrames()) do
    GuardShow(bf)
    if Enabled() then
      if bf:GetParent() ~= hider then
        local top = bf:GetTop()
        if top and not db.utTop then
          db.utTop = top * (bf:GetEffectiveScale() or 1) / (UIParent:GetEffectiveScale() or 1) - (UIParent:GetTop() or 0)
        end
        blizzParent[bf] = bf:GetParent(); bf:SetParent(hider)
      end
    elseif bf:GetParent() == hider then
      bf:SetParent(blizzParent[bf] or UIParent)
    end
  end
  QuestMatesTracker_Refresh()
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local tickT = 0
local ticker = CreateFrame("Frame")
ticker:SetScript("OnUpdate", function(_, el)
  if not anyTimer then return end
  tickT = tickT + el
  if tickT < 0.5 then return end
  tickT = 0
  QuestMatesTracker_Refresh()
end)

local pending = false
local function Soon()
  if pending then return end
  pending = true
  C_Timer.After(0.2, function() pending = false; QuestMatesTracker_Refresh() end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
ev:RegisterEvent("QUEST_WATCH_UPDATE")
ev:RegisterEvent("SUPER_TRACKING_CHANGED")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
for _, e in ipairs({ "QUEST_TIMER_STARTED", "TRACKED_RECIPE_UPDATE", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED" }) do pcall(ev.RegisterEvent, ev, e) end
for _, e in ipairs({ "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED", "CVAR_UPDATE" }) do pcall(ev.RegisterEvent, ev, e) end
ev:SetScript("OnEvent", function(_, e)
  if e == "PLAYER_LOGIN" then
    ObjectiveForeverDB = ObjectiveForeverDB or {}
    db = ObjectiveForeverDB
    -- first run: take over the tracker settings that used to live in QuestMates
    if not db.migrated then
      local old = QuestMatesDB
      if type(old) == "table" then
        for k, v in pairs(old) do
          if k:match("^ut") or k == "unifiedTracker" then db[k] = v end
        end
      end
      db.migrated = true
    end
    if db.unifiedTracker == nil then db.unifiedTracker = true end
    -- older build saved a spot on any drag (even without Shift); forget that once
    if not db.utPosFixed then db.utPos = nil; db.utPosFixed = true end
    for _, name in ipairs(SIDE_BARS) do
      local bar = _G[name]
      if bar then
        bar:HookScript("OnShow", function() C_Timer.After(0, function() if not SavedPos() then Place() end end) end)
        bar:HookScript("OnHide", function() C_Timer.After(0, function() if not SavedPos() then Place() end end) end)
      end
    end
    QuestMatesTracker_Apply()
    Place()
    C_Timer.After(1, function() if not SavedPos() then Place() end end)
    C_Timer.After(4, function() if not SavedPos() then Place() end end)
    return
  end
  if not db then return end
  if e == "UI_SCALE_CHANGED" or e == "DISPLAY_SIZE_CHANGED" or e == "ACTIONBAR_SHOWGRID" or e == "ACTIONBAR_HIDEGRID" or e == "CVAR_UPDATE" then
    C_Timer.After(0.1, function() if db and not SavedPos() then Place() end end)
    return
  end
  if e == "SUPER_TRACKING_CHANGED" and pinnedOwn then
    local _, hold = API.Pinned()
    local cur = STGet()
    if cur ~= nil and cur ~= pinnedOwn then
      if hold then API.Unpin() end
      pinnedOwn = nil
    end
  end
  if e == "PLAYER_REGEN_ENABLED" then
    if pendingApply then QuestMatesTracker_Apply() end
    return
  end
  Soon()
end)

function ObjectiveForeverIsOn() return db and db.unifiedTracker ~= false end
SLASH_QUESTMATESTRACKER1 = "/objf"
SLASH_QUESTMATESTRACKER2 = "/qmt"
SlashCmdList.QUESTMATESTRACKER = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "icons" then
    -- lists the art Blizzard's own tracker uses, so QuestMates can copy it exactly
    local bf = _G.ObjectiveTrackerFrame
    if not bf then print(P .. "No ObjectiveTrackerFrame in this client.") return end
    local seen, count = {}, 0
    local function walk(fr, depth)
      if depth > 8 then return end
      for _, r in ipairs({ fr:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "Texture" then
          local atlas = r.GetAtlas and r:GetAtlas()
          local tex = r:GetTexture()
          local key = tostring(atlas or tex)
          if key ~= "nil" and not seen[key] then
            seen[key] = true; count = count + 1
            print(("  %s  %dx%d  (%s)"):format(atlas and ("atlas " .. atlas) or ("file " .. tostring(tex)),
              r:GetWidth() or 0, r:GetHeight() or 0, (fr:GetDebugName() or "?"):match("[^%.]+%.?[^%.]*$") or "?"))
          end
        end
      end
      for _, c in ipairs({ fr:GetChildren() }) do walk(c, depth + 1) end
    end
    print(P .. "Blizzard tracker art:")
    walk(bf, 0)
    if count == 0 then print("  (nothing found - track a quest and try again)") end
    return
  end
  if msg == "debug" then
    local st = STGet()
    local wp = C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint and C_SuperTrack.IsSuperTrackingUserWaypoint()
    local key, hold = API.Pinned()
    print((P .. "api: C_SuperTrack %s, C get %s, C set %s, old get %s, old set %s"):format(tostring(C_SuperTrack ~= nil),
      tostring(C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID ~= nil), tostring(C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID ~= nil),
      tostring(GetSuperTrackedQuestID ~= nil), tostring(SetSuperTrackedQuestID ~= nil)))
    print((P .. "marker: quest %s, waypoint %s, nav %s, pinned %s/%s, frame %s"):format(tostring(st), tostring(wp),
      tostring(GetCVar and GetCVar("showInGameNavigation")), tostring(key), tostring(hold),
      tostring(SuperTrackedFrame and SuperTrackedFrame:IsShown())))
    local us = UIParent:GetEffectiveScale() or 1
    print((P .. "screen right %.0f, tracker right %.0f, bar edge %.0f, saved spot: %s"):format(
      UIParent:GetRight() or 0, (f:GetRight() or 0) * (f:GetEffectiveScale() or 1) / us, RightEdge(), SavedPos() and "yes" or "no"))
    for _, name in ipairs(SIDE_BARS) do
      local bar, b1 = _G[name], _G[name .. "Button1"]
      print(("  %s: %s, visible %s, left %s"):format(name, bar and "found" or "missing", tostring(bar and bar:IsVisible()),
        tostring(b1 and b1:GetLeft() and math.floor(b1:GetLeft() * (b1:GetEffectiveScale() or 1) / us))))
    end
    return
  end
  if msg == "reset" then
    db.utPosL = db.utPosL or {}; db.utPosL[EM.Layout()] = false; Place(); print(P .. "Tracker moved back to the default spot.")
  elseif msg:match("^scale") then
    local v = tonumber(msg:match("^scale%s+([%d%.]+)"))
    if v and v >= 0.5 and v <= 2 then db.utScale = v; QuestMatesTracker_Refresh()
    else print(P .. "Use /objf scale 0.5 - 2") end
  else
    db.unifiedTracker = (db.unifiedTracker == false)
    QuestMatesTracker_Apply()
    print(P .. "Tracker " .. (db.unifiedTracker and "on" or "off (default tracker back)"))
  end
end

-- Edit Mode: the tracker shows as "Objective Forever" with Blizzard's highlight
EM.Attach(f, "Objective Forever", {
  save = function(pos, layout) db.utPosL = db.utPosL or {}; db.utPosL[layout] = pos end,
  apply = function() if db then Place() end end,
  enter = function() if db and Enabled() then QuestMatesTracker_Apply() end end,
  -- leaving Edit Mode puts Blizzard's tracker back: hide it again
  exit = function()
    if not db then return end
    QuestMatesTracker_Apply(); Place()
    C_Timer.After(0.2, function() QuestMatesTracker_Apply() end)
    C_Timer.After(1, function() QuestMatesTracker_Apply() end)
  end,
  panel = function(p, y)
    y = EM.Slider(p, y, "Size", 0.5, 2, 0.05, function() return db.utScale or 1 end,
      function(v) db.utScale = v; QuestMatesTracker_Refresh() end)
    y = EM.Button(p, y - 4, "Reset position", function()
      db.utPosL = db.utPosL or {}; db.utPosL[EM.Layout()] = false; Place()
    end)
    return y
  end,
})
