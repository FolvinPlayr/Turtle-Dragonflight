--[[ Edit Mode -----------------------------------------------------------------

  A Dragonflight style layout editor for Turtle-Dragonflight.

  Open it from Esc -> tDF Edit Mode, or with `/tdf edit` / `/tdfedit`.

  Design notes, because vanilla makes two of these non-obvious:

  * Nothing is dragged by its real frame. Each editable element gets a separate
    overlay frame, and the overlay is what receives the mouse. Enabling mouse
    input on the live frames (the older Movable Unit Frames approach) steals
    clicks from buff buttons and action bars and replaces their drag scripts.
    Overlays leave the real frames untouched.

  * Positions are stored in UIParent units, not in the frame's own coordinate
    space. GetLeft() reports coordinates scaled by the frame's own scale, while
    SetPoint offsets are interpreted in that same space, so a position saved
    before a scale change lands in the wrong spot once the scale differs. Every
    read multiplies by (frame effective scale / UIParent effective scale) and
    every write divides by it, which keeps a layout valid across UI scale and
    per-frame scale changes.

--]]

local _G = tDFUI.GetGlobalEnv()
local T = tDFUI.T
local mod = math.mod or mod

local module = tDFUI:register({
  title = T["Edit Mode"],
  description = T["editmode_desc"],
  expansions = { ["vanilla"] = true, ["tbc"] = true },
  category = T["General"],
  enabled = true,
})

local CENTER_SNAP = 12    -- px of magnetism towards the screen center lines
local EDGE_KEEP   = 24    -- px of a frame that must stay on screen when applying
local REFRESH     = 0.2   -- seconds between overlay refreshes while open

-- How far an element may drift before it counts as having been dragged along
-- by something else. Deliberately tiny: a drag runs this check on every frame,
-- and a tolerance large enough to ignore one frame of mouse movement is also
-- large enough to let a dependant creep the entire width of the screen a third
-- of a pixel at a time. See BeginIsolation for the rest of that story.
local PIN_EPSILON = 0.05

local Print = tDFUI.Print

-- Every element Edit Mode can move. `key` is the global name to look up, which
-- for a few tDF frames is the global variable name rather than the frame name
-- (xpbar, repbar). Anything missing on this client is skipped silently, so
-- entries for disabled modules and other expansions cost nothing.
local registry = {
  -- unit frames
  { key = "PlayerFrame",           label = "Player",            group = "Unit Frames" },
  { key = "TargetFrame",           label = "Target",            group = "Unit Frames" },
  { key = "TargetofTargetFrame",   label = "Target of Target",  group = "Unit Frames" },
  { key = "PetFrame",              label = "Pet",               group = "Unit Frames" },
  { key = "PartyMemberFrame1",     label = "Party 1",           group = "Unit Frames" },
  { key = "PartyMemberFrame2",     label = "Party 2",           group = "Unit Frames" },
  { key = "PartyMemberFrame3",     label = "Party 3",           group = "Unit Frames" },
  { key = "PartyMemberFrame4",     label = "Party 4",           group = "Unit Frames" },

  -- castbars
  { key = "tDFImprovedCastbar",    label = "Castbar",           group = "Castbars" },
  { key = "CastingBarFrame",       label = "Default Castbar",   group = "Castbars" },

  -- action bars
  --
  -- The main bar moves alone. It used to drag the XP bars along, back when the
  -- default XP bar could be stranded by moving it; the bars are separate
  -- elements with their own overlays, so moving one should not move the others.
  { key = "MainMenuBar",           label = "Main Action Bar",   group = "Action Bars" },
  { key = "MultiBarBottomLeft",    label = "Bottom Left Bar",   group = "Action Bars" },
  { key = "MultiBarBottomRight",   label = "Bottom Right Bar",  group = "Action Bars" },
  { key = "MultiBarRight",         label = "Right Bar",         group = "Action Bars" },
  { key = "MultiBarLeft",          label = "Right Bar 2",       group = "Action Bars" },
  -- These two frames are not the size of the buttons they hold, so the overlay
  -- is measured from the buttons themselves instead - otherwise the box and the
  -- stance button it is supposed to be around sit in different places.
  { key = "ShapeshiftBarFrame",    label = "Stance Bar",        group = "Action Bars",
    measure = { pattern = "ShapeshiftButton%d", count = 10 } },
  { key = "PetActionBarFrame",     label = "Pet Bar",           group = "Action Bars",
    measure = { pattern = "PetActionButton%d", count = 10 } },
  { key = "tDFbagMain",            label = "Bag Bar",           group = "Action Bars" },
  { key = "tDFmicrobutton",        label = "Micro Menu",        group = "Action Bars" },

  -- bars and trackers
  -- the custom XP bar carries the invisible default one (and its chrome, which
  -- is anchored to it) so the two can never drift apart and expose each other
  { key = "xpbar",                 label = "XP Bar",            group = "Bars & Trackers",
    attach = { "MainMenuExpBar" }, attachscale = true },
  -- moved and scaled only as a passenger of the two entries above; it has no
  -- overlay of its own because it is invisible and has nothing to grab
  { key = "MainMenuExpBar",        label = "Default XP Bar",    group = "Bars & Trackers",
    nooverlay = true },
  { key = "repbar",                label = "Reputation Bar",     group = "Bars & Trackers" },
  { key = "tDFquestwatchframe",    label = "Quest Tracker",     group = "Bars & Trackers" },
  { key = "QuestWatchFrame",       label = "Quest Objectives",  group = "Bars & Trackers" },
  { key = "BuffButton0",           label = "Buffs",             group = "Bars & Trackers" },
  { key = "BuffButton8",           label = "Buffs (row 2)",     group = "Bars & Trackers" },
  { key = "TempEnchant1",          label = "Weapon Buffs",      group = "Bars & Trackers" },
  { key = "tDFDurability",         label = "Durability",        group = "Bars & Trackers" },
  { key = "DurabilityFrame",       label = "Armored Man",       group = "Bars & Trackers" },

  -- minimap and world
  { key = "MyCustomMinimap",       label = "Minimap",           group = "Minimap & World" },
  { key = "MinimapCluster",        label = "Minimap Cluster",   group = "Minimap & World" },
  { key = "MinimapClock",          label = "Clock",             group = "Minimap & World" },
  { key = "tDF_RadioPanel",        label = "Radio Panel",       group = "Minimap & World" },

  -- chat
  { key = "ChatFrame1",            label = "Chat",              group = "Chat" },
  { key = "ChatFrame2",            label = "Combat Log",        group = "Chat" },
}

local items = {}        -- resolved registry entries, in registry order
local byKey = {}        -- key -> item
local db                -- tDFUI_config["EditModeDB"]

local selected, dragging
local isolation          -- positions recorded when the current drag started
local manager, panel, grid
local updating           -- guards slider/editbox handlers against feedback loops

-- forward declarations, for the handful of functions that genuinely are used
-- above where they are defined. Everything else is a plain `local function` at
-- its own definition site.
local Close, Teardown, Select, UpdatePanel, RefreshOverlay

--[[ position helpers -------------------------------------------------------]]

-- factor that converts the frame's own coordinate space to UIParent units
local function ScaleFactor(frame)
  local ui = UIParent:GetEffectiveScale()
  local fe = frame:GetEffectiveScale()
  if not ui or not fe or ui == 0 or fe == 0 then return 1 end
  return fe / ui
end

-- TOPLEFT of `frame` relative to the bottom left of the screen, in UIParent units
local function ReadPosition(frame)
  local left, top = frame:GetLeft(), frame:GetTop()
  if not left or not top then return nil end
  local s = ScaleFactor(frame)
  return left * s, top * s
end

local function FrameSize(frame)
  local s = ScaleFactor(frame)
  local w = (frame:GetWidth() or 0) * s
  local h = (frame:GetHeight() or 0) * s
  if w < 8 then w = 8 end
  if h < 8 then h = 8 end
  return w, h
end

local function WritePosition(frame, x, y)
  local s = ScaleFactor(frame)
  if s == 0 then return end
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s, y / s)
end

-- Rescue a layout that a resolution change pushed off the screen entirely.
-- Deliberate partial-offscreen placement is left alone - only a frame with no
-- pixel left on screen gets dragged back, and only far enough to be grabbable.
local function Clamp(frame, x, y)
  local w, h = FrameSize(frame)
  local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()

  if x >= sw then x = sw - EDGE_KEEP end
  if x + w <= 0 then x = EDGE_KEEP - w end
  if y <= 0 then y = EDGE_KEEP end
  if y - h >= sh then y = sh + h - EDGE_KEEP end

  return x, y
end

local function Entry(key)
  db.frames[key] = db.frames[key] or {}
  return db.frames[key]
end

-- Frames that live inside another editable frame but should keep their own
-- on-screen size when that parent is scaled. In vanilla the stance bar, the pet
-- bar, the multibars and the bag slot buttons are all children of MainMenuBar,
-- so scaling the main bar silently resized all of them too.
local independents = {
  "ShapeshiftBarFrame", "PetActionBarFrame",
  "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft",
  "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
  "CharacterBag3Slot", "KeyRingButton", "MainMenuBarBackpackButton",
  "tDFbagMain", "tDFmicrobutton",
}

-- What an independent looked like before Edit Mode touched anything, used as
-- the fallback whenever it has no saved scale of its own.
--
-- A flat 1 here is wrong: the independents are re-asserted on every layout pass,
-- so a frame another module had deliberately scaled got flattened back a second
-- after it loaded. Registry elements already record this as item.default.scale;
-- half this list is not in the registry (the bag slots, the keyring, the
-- backpack button), so those are measured here instead.
local basescale = {}

local function BaseScale(key, frame)
  local item = byKey[key]
  if item and item.default then return item.default.scale or 1 end

  if basescale[key] == nil then basescale[key] = ScaleFactor(frame) end
  return basescale[key]
end

-- Take the measurement again.
--
-- Latching once at enable is too early to be trusted: main.lua enables modules
-- in pairs() order, so a module that scales one of these frames inside its own
-- enable may not have run yet, and we would have recorded a size that was never
-- really the default. Called from the post-login retry passes, by which point
-- everything has loaded - and only where the user has no scale of their own,
-- since a saved scale makes the fallback moot anyway.
local function RelatchPassengers()
  for i = 1, table.getn(independents) do
    local key = independents[i]
    local e = db.frames[key]

    if not (e and e.scale) then basescale[key] = nil end
  end
end

local function IsDescendant(frame, ancestor)
  if not frame or not ancestor then return nil end
  local parent = frame:GetParent()

  while parent do
    if parent == ancestor then return true end
    parent = parent:GetParent()
  end
end

-- Set a frame's scale so that its size ON SCREEN is `scale`, whatever its
-- parent is doing. ScaleFactor already reports exactly that ratio, so this is
-- its inverse.
local function SetVisualScale(frame, scale)
  local parent = frame:GetParent()
  local ratio = 1

  if parent and parent.GetEffectiveScale then
    local ui = UIParent:GetEffectiveScale()
    if ui and ui ~= 0 then ratio = parent:GetEffectiveScale() / ui end
  end

  if not ratio or ratio == 0 then ratio = 1 end
  pcall(frame.SetScale, frame, scale / ratio)
end

-- Hand a frame over to us for good: movable, user-placed, anchored to UIParent.
--
-- SetUserPlaced does layout bookkeeping inside Blizzard's frame code, and this
-- used to run from every WritePosition - sixty times a second for the whole of
-- a drag. It only has to be said once per frame, so it is remembered.
local claimed = {}

local function Anchor(frame, x, y)
  local name = frame:GetName()

  if not (name and claimed[name]) then
    pcall(frame.SetMovable, frame, true)
    pcall(frame.SetUserPlaced, frame, true)
    if name then claimed[name] = true end
  end

  WritePosition(frame, x, y)
end

-- ...and take it back, so a reset frame is Blizzard's to position again
local function Unclaim(frame)
  local name = frame:GetName()
  if name then claimed[name] = nil end
  pcall(frame.SetUserPlaced, frame, false)
end

-- Note where everything that could be dragged along currently sits.
--
-- Half this UI is anchored to the other half: tReducedActionBar.lua hangs
-- MultiBarBottomLeft off MainMenuBar, MultiBarBottomRight off that,
-- ReputationWatchBar off MainMenuExpBar and repbar off that again. Moving one
-- element therefore moves its dependants, which is not what "move this bar"
-- means in an editor.
--
-- Only elements with no saved position of their own can be affected, since a
-- placed element is anchored to UIParent and immune. The element being moved
-- and its declared passengers are excluded - those are supposed to travel.
--
-- This snapshot is taken ONCE PER GESTURE, not once per frame of a drag.
-- Comparing against the previous frame instead is what welded the UI together:
-- a slow, precise drag moves the frame well under a pixel per tick, every
-- dependant moves by that same sub-pixel amount, no single tick ever exceeds
-- the tolerance, and the dependant rides along for the entire drag while the
-- check reports that nothing happened. Measuring from the start of the gesture
-- means drift accumulates into the comparison instead of being thrown away.
local function BeginIsolation(item)
  local attached = {}
  if item.attach then
    for i = 1, table.getn(item.attach) do attached[item.attach[i]] = true end
  end

  local snapshot = {}
  for i = 1, table.getn(items) do
    local other = items[i]
    local oe = db.frames[other.key]

    if other ~= item and not attached[other.key] and not (oe and oe.x) then
      local px, py = ReadPosition(other.frame)
      if px then snapshot[i] = { x = px, y = py } end
    end
  end

  return snapshot
end

-- Put back anything that moved only because it was anchored to what we just
-- moved, which also makes it independent from here on.
--
-- A pinned element is dropped from the snapshot: it is anchored to UIParent now
-- and cannot be dragged along again, so re-reading its position on every frame
-- of the rest of the drag would tell us nothing. (Clearing a field of a table
-- being walked by pairs() is the one mutation Lua allows during traversal.)
local function ApplyIsolation(snapshot)
  if not snapshot then return end

  for i, prev in pairs(snapshot) do
    local other = items[i]
    local nx, ny = ReadPosition(other.frame)

    if nx and (math.abs(nx - prev.x) > PIN_EPSILON
      or math.abs(ny - prev.y) > PIN_EPSILON) then
      local oe = Entry(other.key)
      oe.x, oe.y = prev.x, prev.y
      Anchor(other.frame, prev.x, prev.y)
      snapshot[i] = nil
    end
  end
end

-- Single place every move goes through. Anything listed in the element's
-- `attach` travels by the same delta and gets its own saved position, which is
-- what keeps the two XP bars welded together however you grab them.
local function PlaceItem(item, x, y)
  local e = Entry(item.key)
  local ox, oy = ReadPosition(item.frame)
  local dx, dy = 0, 0
  if ox and oy then dx, dy = x - ox, y - oy end

  -- during a drag this is the snapshot taken when the mouse went down; a
  -- one-shot move (nudge, coordinate box, centre button) takes its own
  local snapshot = isolation or BeginIsolation(item)

  e.x, e.y = x, y
  Anchor(item.frame, x, y)

  if item.attach and (dx ~= 0 or dy ~= 0) then
    for i = 1, table.getn(item.attach) do
      local frame = _G[item.attach[i]]

      if frame and frame.SetPoint then
        local ax, ay = ReadPosition(frame)
        if ax and ay then
          local ae = Entry(item.attach[i])
          ae.x, ae.y = ax + dx, ay + dy
          Anchor(frame, ae.x, ae.y)
        end
      end
    end
  end

  ApplyIsolation(snapshot)
end

-- Scaling has to re-place the frame afterwards: the anchor offsets are read in
-- the frame's own coordinate space, so changing the scale moves it. It also has
-- to undo the scale it just inflicted on everything parented inside it.
local function ScaleItem(item, scale)
  local e = Entry(item.key)
  e.scale = scale

  -- Rescaling changes the frame's width and height, so anything anchored to an
  -- edge of it slides. That has to be undone for the same reason a move does,
  -- or wheeling over the main bar walks the stance bar, the pet bar and the
  -- rep bar up and down with it.
  local snapshot = BeginIsolation(item)

  -- note how big the passengers look right now
  local before = {}
  for i = 1, table.getn(independents) do
    local frame = _G[independents[i]]
    if frame and frame ~= item.frame and IsDescendant(frame, item.frame) then
      before[independents[i]] = ScaleFactor(frame)
    end
  end

  SetVisualScale(item.frame, scale)

  if item.attachscale and item.attach then
    for i = 1, table.getn(item.attach) do
      local frame = _G[item.attach[i]]
      if frame and frame.SetScale then
        local ae = Entry(item.attach[i])
        ae.scale = scale
        SetVisualScale(frame, scale)
        if ae.x and ae.y then WritePosition(frame, ae.x, ae.y) end
      end
    end
  end

  -- and put them back to the size they were
  for key, visual in pairs(before) do
    local frame = _G[key]
    SetVisualScale(frame, visual)

    local ce = db.frames[key]
    if ce and ce.x and ce.y then WritePosition(frame, ce.x, ce.y) end
  end

  if e.x and e.y then WritePosition(item.frame, e.x, e.y) end

  -- last, so it measures the frames after the passenger restore above has had
  -- its say rather than half way through
  ApplyIsolation(snapshot)
end

--[[ apply and reset --------------------------------------------------------]]

-- Blizzard positions its own frames in a layout pass that runs on various
-- events rather than continuously, so a frame we just handed back to it sits at
-- the anchor we recorded until that pass next happens to fire - which looked
-- like a reset landing slightly wrong and then correcting itself seconds later.
-- Running the pass immediately closes that gap.
local function SettleDefaults()
  if UIParent_ManageFramePositions then
    pcall(UIParent_ManageFramePositions)
  end
end

-- Put the whole saved layout back on screen.
--
-- Three passes, and the order is the whole point. Scaling a frame changes the
-- effective scale of everything inside it, and an anchor offset is read in the
-- frame's own coordinate space - so a position worked out before the scales
-- have settled lands somewhere else once they do. Every scale in the UI is
-- therefore decided first, and nothing is positioned until none of it will move
-- underneath the measurement.
--
-- This runs on every Blizzard layout pass, so it is worth keeping tight.
local function ApplyAll()
  -- 1. the scale and opacity the user chose
  for i = 1, table.getn(items) do
    local frame = items[i].frame
    local e = db.frames[items[i].key]

    if e then
      if e.scale then SetVisualScale(frame, e.scale) end
      if e.alpha then pcall(frame.SetAlpha, frame, e.alpha) end
    end
  end

  -- 2. the passengers keep the size they look now, whatever the frame they live
  -- inside has just done. Most have no saved scale of their own, so without
  -- this a scaled main bar shrinks the bag buttons, the stance bar and the pet
  -- bar again on every reload and every layout pass.
  for i = 1, table.getn(independents) do
    local key = independents[i]
    local frame = _G[key]

    if frame and frame.SetScale then
      local ce = db.frames[key]
      SetVisualScale(frame, (ce and ce.scale) or BaseScale(key, frame))
    end
  end

  -- 3. positions, each one through Clamp.
  --
  -- Only registry elements are placed here, and that is the complete set: the
  -- independents that are not in the registry are children nothing can give a
  -- saved position to. The eight that ARE in the registry used to be written a
  -- second time by the loop above, raw and unclamped, which quietly undid the
  -- offscreen rescue for exactly the frames most likely to need it.
  for i = 1, table.getn(items) do
    local frame = items[i].frame
    local e = db.frames[items[i].key]

    if e and e.x and e.y then Anchor(frame, Clamp(frame, e.x, e.y)) end
  end
end

-- `seen` guards the passenger recursion below against an attach cycle. The
-- registry has none today, but two elements listing each other would otherwise
-- reset each other until the stack ran out.
local function ResetItem(item, seen)
  if seen[item] then return end
  seen[item] = true

  local frame, d = item.frame, item.default
  db.frames[item.key] = nil

  -- a reset means the whole element, shape included, not just where it sits
  if tDF_BarLayout and tDF_BarLayout.Supports(item.key) then
    tDF_BarLayout.Reset(item.key)
  end

  -- anything that travels with this element goes home with it, or resetting the
  -- main bar would leave the XP bars stranded wherever it dragged them
  if item.attach then
    for i = 1, table.getn(item.attach) do
      local passenger = byKey[item.attach[i]]
      if passenger then ResetItem(passenger, seen) end
    end
  end

  if d then
    -- the captured default is a VISUAL scale, so it has to go back through
    -- SetVisualScale; a raw SetScale here would be wrong for anything living
    -- inside a bar the user has since scaled
    SetVisualScale(frame, d.scale or 1)
    pcall(frame.SetAlpha, frame, d.alpha or 1)
    Unclaim(frame)

    if d.point then
      frame:ClearAllPoints()
      frame:SetPoint(d.point, d.relativeTo or frame:GetParent() or UIParent,
        d.relativePoint or d.point, d.x or 0, d.y or 0)
    end
  end

  RefreshOverlay(item)
end

local function ResetFrame(item)
  ResetItem(item, {})
  UpdatePanel()
  SettleDefaults()
end

-- Every element back to its default. Silent, because loading a layout profile
-- starts from here and should not announce a reset the user did not ask for.
local function ResetEverything()
  local seen = {}

  for i = 1, table.getn(items) do
    ResetItem(items[i], seen)
  end

  UpdatePanel()

  -- one layout pass for the whole batch, not one per element
  SettleDefaults()
end

local function ResetAll()
  ResetEverything()
  Print("Edit Mode: every element restored to its default position.")
end

--[[ overlays ---------------------------------------------------------------]]

local overlay_backdrop = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 8, edgeSize = 12,
  insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

local function StyleOverlay(o)
  if o.item == selected then
    o:SetBackdropColor(.25, .45, .8, .45)
    o:SetBackdropBorderColor(1, .82, 0, 1)
  elseif o.item.frame:IsVisible() then
    o:SetBackdropColor(.1, .1, .1, .4)
    o:SetBackdropBorderColor(.4, .6, 1, .8)
  else
    o:SetBackdropColor(.1, .1, .1, .25)
    o:SetBackdropBorderColor(.45, .45, .45, .6)
  end
end

-- Union of a set of buttons, in UIParent units. Used for frames whose own rect
-- says nothing useful about where their contents actually are.
local function MeasureButtons(spec)
  local left, top, right, bottom

  for i = 1, spec.count do
    local button = _G[string.format(spec.pattern, i)]

    if button and button.IsShown and button:IsShown() and button:GetLeft() then
      local s = ScaleFactor(button)
      local l, t = button:GetLeft() * s, button:GetTop() * s
      local r, b = button:GetRight() * s, button:GetBottom() * s

      if not left or l < left then left = l end
      if not top or t > top then top = t end
      if not right or r > right then right = r end
      if not bottom or b < bottom then bottom = b end
    end
  end

  return left, top, right, bottom
end

-- move the real frame to wherever the overlay currently sits, applying grid
-- and center snapping unless shift is held
local function SyncFromOverlay(o)
  local item = o.item
  local x, y = o:GetLeft(), o:GetTop()
  if not x or not y then return end

  local w, h = o:GetWidth(), o:GetHeight()
  local free = IsShiftKeyDown()

  if not free and db.snap == 1 then
    local g = db.grid or 32
    if g > 0 then
      x = math.floor(x / g + 0.5) * g
      y = math.floor(y / g + 0.5) * g
    end
  end

  local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
  local vguide, hguide

  if not free then
    if math.abs((x + w / 2) - sw / 2) <= CENTER_SNAP then
      x = sw / 2 - w / 2
      vguide = true
    end
    if math.abs((y - h / 2) - sh / 2) <= CENTER_SNAP then
      y = sh / 2 + h / 2
      hguide = true
    end
  end

  if vguide then manager.vguide:Show() else manager.vguide:Hide() end
  if hguide then manager.hguide:Show() else manager.hguide:Hide() end

  -- the overlay may sit away from its frame (see RefreshOverlay), so take that
  -- offset back off before telling the frame where to go
  PlaceItem(item, x - (o.dx or 0), y - (o.dy or 0))
end

local function OverlayTooltip(o)
  local item = o.item
  local x, y = ReadPosition(item.frame)
  GameTooltip:SetOwner(o, "ANCHOR_CURSOR")
  GameTooltip:SetText(item.label, 1, .82, 0)
  GameTooltip:AddLine(item.group, .7, .7, .7)
  if x then
    GameTooltip:AddLine(string.format("X %d  Y %d  Scale %.2f",
      math.floor(x + .5), math.floor(y + .5), ScaleFactor(item.frame)), 1, 1, 1)
  end
  if not item.frame:IsVisible() then
    GameTooltip:AddLine("Currently hidden - can still be placed.", .6, .6, .6)
  end
  GameTooltip:AddLine("Drag to move, shift-drag ignores snapping.", .4, .8, 1)
  GameTooltip:AddLine("Wheel scales, shift-wheel fades.", .4, .8, 1)
  GameTooltip:AddLine("Right-click resets this element.", .4, .8, 1)
  GameTooltip:Show()
end

local function CreateOverlay(item)
  local o = CreateFrame("Button", nil, manager)
  o:SetFrameStrata("FULLSCREEN")
  o:SetMovable(true)
  o:EnableMouse(true)
  o:EnableMouseWheel(true)
  o:RegisterForDrag("LeftButton")
  o:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  o:SetBackdrop(overlay_backdrop)

  o.item = item
  o.label = o:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  o.label:SetPoint("CENTER", o, "CENTER", 0, 0)
  o.label:SetText(item.label)

  o:SetScript("OnEnter", function() OverlayTooltip(this) end)
  o:SetScript("OnLeave", function() GameTooltip:Hide() end)

  o:SetScript("OnDragStart", function()
    Select(this.item)
    -- one snapshot for the whole drag; SyncFromOverlay runs every frame and
    -- must not re-measure against a picture the drag itself has already moved
    isolation = BeginIsolation(this.item)
    this:StartMoving()
    dragging = this
  end)

  o:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    dragging = nil
    isolation = nil
    manager.vguide:Hide()
    manager.hguide:Hide()
    RefreshOverlay(this.item)
    UpdatePanel()
  end)

  o:SetScript("OnClick", function()
    if arg1 == "RightButton" then
      ResetFrame(this.item)
    else
      Select(this.item)
    end
  end)

  o:SetScript("OnMouseWheel", function()
    local item = this.item
    Select(item)

    -- read through db.frames, not Entry: Entry creates the record, and this
    -- runs before anything is known to have changed
    local e = db.frames[item.key]

    if IsShiftKeyDown() then
      local a = ((e and e.alpha) or item.frame:GetAlpha() or 1) + arg1 * .1
      if a > 1 then a = 1 end
      if a < 0 then a = 0 end
      Entry(item.key).alpha = a
      pcall(item.frame.SetAlpha, item.frame, a)
    else
      local s = ((e and e.scale) or ScaleFactor(item.frame)) + arg1 * .05
      if s > 2 then s = 2 end
      if s < .5 then s = .5 end
      ScaleItem(item, s)
    end

    RefreshOverlay(item)
    UpdatePanel()
  end)

  return o
end

RefreshOverlay = function(item)
  local o = item.overlay
  if not o then return end

  local fx, fy = ReadPosition(item.frame)
  if not fx then
    o:Hide()
    return
  end

  local x, y = fx, fy
  local w, h = FrameSize(item.frame)

  -- A reshaped bar keeps its original frame size (resizing MainMenuBar drags
  -- everything anchored to it across the screen), so ask the layout module what
  -- the buttons really occupy and draw the overlay around that instead. The
  -- button block sits on the bar's BOTTOM edge, so the overlay's top is the
  -- frame's bottom plus the block's height, not the frame's own top.
  if tDF_BarLayout and tDF_BarLayout.Bounds then
    local bw, bh = tDF_BarLayout.Bounds(item.key)

    if bw and bh then
      local s = ScaleFactor(item.frame)
      local fh = (item.frame:GetHeight() or 0) * s
      w, h = bw * s, bh * s
      y = fy - (fh - h)
    end
  end

  -- frames whose rect says nothing about where their buttons are
  if item.measure then
    local left, top, right, bottom = MeasureButtons(item.measure)

    if left and right > left and top > bottom then
      x, y = left, top
      w, h = right - left, top - bottom
    end
  end

  -- Remember how far the overlay sits from the frame it drives, so dragging can
  -- convert back. Without this a bar whose overlay is offset from its frame
  -- jumps by that offset the moment you grab it.
  o.dx, o.dy = x - fx, y - fy

  o:SetWidth(w)
  o:SetHeight(h)
  o:ClearAllPoints()
  o:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
  StyleOverlay(o)
  o:Show()
end

local function RefreshAll()
  for i = 1, table.getn(items) do
    if items[i] ~= (dragging and dragging.item) then
      RefreshOverlay(items[i])
    end
  end
end

-- Match the registry against what actually exists right now, and give each new
-- element an overlay plus a record of where it started so Reset has a target.
--
-- This runs repeatedly rather than once at load. Several modules build their
-- frames inside their own enable function (tCastbar creates tDFImprovedCastbar
-- that way) and main.lua enables modules in pairs() order, so a single pass at
-- enable time would miss whatever happened to be enabled after us.
local function ResolveRegistry()
  for i = 1, table.getn(registry) do
    local entry = registry[i]

    if not byKey[entry.key] then
      local frame = _G[entry.key]

      if frame and type(frame) == "table" and frame.GetName and frame.SetPoint then
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)

        -- Copy the whole registry entry rather than naming fields one by one.
        -- The enumerated version silently dropped any option added later - a
        -- `measure` spec went missing exactly that way, and the feature simply
        -- never ran because item.measure was nil.
        local item = {}
        for field, value in pairs(entry) do item[field] = value end

        item.frame = frame
        item.default = {
          point = point, relativeTo = relativeTo, relativePoint = relativePoint,
          x = x, y = y,
          scale = ScaleFactor(frame),
          alpha = frame:GetAlpha() or 1,
        }

        table.insert(items, item)
        byKey[entry.key] = item

        if manager and not entry.nooverlay then item.overlay = CreateOverlay(item) end
      end
    end
  end
end

--[[ selection and nudging --------------------------------------------------]]

Select = function(item)
  selected = item
  for i = 1, table.getn(items) do
    if items[i].overlay then StyleOverlay(items[i].overlay) end
  end
  UpdatePanel()
end

local function SelectNext()
  local n = table.getn(items)
  if n == 0 then return end

  local start = 1
  for i = 1, n do
    if items[i] == selected then start = i + 1 break end
  end

  for i = 0, n - 1 do
    local index = mod(start - 1 + i, n) + 1
    if items[index].overlay and items[index].overlay:IsShown() then
      Select(items[index])
      return
    end
  end
end

local function Nudge(dx, dy)
  if not selected then return end

  local e = Entry(selected.key)
  if not e.x or not e.y then
    local x, y = ReadPosition(selected.frame)
    if not x then return end
    e.x, e.y = x, y
  end

  PlaceItem(selected, e.x + dx, e.y + dy)
  RefreshOverlay(selected)
  UpdatePanel()
end

local function CenterSelected(axis)
  if not selected then return end

  local w, h = FrameSize(selected.frame)
  local x, y = ReadPosition(selected.frame)
  if not x then return end

  if axis == "x" then
    x = UIParent:GetWidth() / 2 - w / 2
  else
    y = UIParent:GetHeight() / 2 + h / 2
  end

  PlaceItem(selected, x, y)
  RefreshOverlay(selected)
  UpdatePanel()
end

--[[ layout profiles --------------------------------------------------------]]

-- A profile is { frames = <positions>, bars = <shapes> }. Profiles written
-- before bar shapes were part of one are a bare position table, so anything
-- with no `frames` member is read as the position table itself.
local function ProfileFrames(profile)
  return profile.frames or profile
end

-- Entries with nothing in them are dropped. Reading an element's current scale
-- can create a blank record, and a profile full of empty tables is noise that
-- also makes IsPlaced-style checks harder to reason about later.
local function CopyFrames(source)
  local copy = {}

  for key, e in pairs(source or {}) do
    if e.x or e.y or e.scale or e.alpha then
      copy[key] = { x = e.x, y = e.y, scale = e.scale, alpha = e.alpha }
    end
  end

  return copy
end

local function SaveProfile(name)
  if not name or name == "" then
    Print("Edit Mode: type a profile name first.")
    return
  end

  tDF_editProfiles[name] = {
    frames = CopyFrames(db.frames),
    bars = tDF_BarLayout and tDF_BarLayout.Snapshot and tDF_BarLayout.Snapshot(),
  }

  Print("Edit Mode: saved layout |cffffff00" .. name .. "|r (shared by all characters).")
end

local function LoadProfile(name)
  local profile = name and tDF_editProfiles[name]

  if not profile then
    Print("Edit Mode: no profile named |cffffff00" .. (name or "?") .. "|r.")
    return
  end

  -- Reset to defaults first. A profile only lists what it has something to say
  -- about, so without this every element it does NOT mention silently kept
  -- whatever the previously loaded profile had done to it - and with no saved
  -- entry of its own left to explain why it was sitting there.
  ResetEverything()

  db.frames = CopyFrames(ProfileFrames(profile))

  if tDF_BarLayout and tDF_BarLayout.Restore then
    tDF_BarLayout.Restore(profile.bars)
  end

  ApplyAll()
  RefreshAll()
  UpdatePanel()
  Print("Edit Mode: loaded layout |cffffff00" .. name .. "|r.")
end

local function DeleteProfile(name)
  if not name or not tDF_editProfiles[name] then
    Print("Edit Mode: no profile named |cffffff00" .. (name or "?") .. "|r.")
    return
  end
  tDF_editProfiles[name] = nil
  Print("Edit Mode: deleted layout |cffffff00" .. name .. "|r.")
end

-- chat listing, kept for `/tdf edit list`; the panel uses the dropdown below
local function ListProfiles()
  local found
  Print("Edit Mode saved layouts:")
  for name in pairs(tDF_editProfiles) do
    DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00" .. name .. "|r")
    found = true
  end
  if not found then
    DEFAULT_CHAT_FRAME:AddMessage("  |cffaaaaaanone saved yet|r")
  end
end

--[[ profile dropdown ------------------------------------------------------]]

-- A hand rolled list rather than UIDropDownMenu: vanilla's
-- UIDropDownMenu_SetWidth takes (width, frame) where every later client takes
-- (frame, width), and this addon claims tbc support too. Twelve lines of
-- buttons beat an API whose argument order moves under you.
local profilelist

local function HideProfileList()
  if profilelist then profilelist:Hide() end
end

local function BuildProfileList(parent, anchor)
  profilelist = CreateFrame("Frame", "tDFEditModeProfileList", parent)
  profilelist:SetFrameStrata("TOOLTIP")
  profilelist:SetWidth(230)
  profilelist:SetHeight(24)
  profilelist:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
  profilelist:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  profilelist:SetBackdropColor(0, 0, 0, .9)
  profilelist.rows = {}
  profilelist:Hide()

  return profilelist
end

local function Row(index)
  if profilelist.rows[index] then return profilelist.rows[index] end

  local row = CreateFrame("Button", nil, profilelist)
  row:SetWidth(216)
  row:SetHeight(16)
  row:SetPoint("TOPLEFT", profilelist, "TOPLEFT", 7, -6 - (index - 1) * 17)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.text:SetPoint("LEFT", row, "LEFT", 2, 0)
  row.text:SetJustifyH("LEFT")

  row.highlight = row:CreateTexture(nil, "BACKGROUND")
  row.highlight:SetAllPoints(row)
  row.highlight:SetTexture(1, .82, 0, .25)
  row.highlight:Hide()

  row:SetScript("OnEnter", function() this.highlight:Show() end)
  row:SetScript("OnLeave", function() this.highlight:Hide() end)

  profilelist.rows[index] = row
  return row
end

-- `load` and `remove` are passed in so this block does not have to be moved
-- below the profile functions it drives
local function ToggleProfileList(parent, anchor, box, load, remove)
  if not profilelist then BuildProfileList(parent, anchor) end

  if profilelist:IsShown() then
    profilelist:Hide()
    return
  end

  -- plain pairs plus a sort, not tDFUI.spairs: spairs parks an __orderedIndex
  -- key on the table it walks, and this table is a saved variable
  local names = {}
  for name in pairs(tDF_editProfiles) do
    table.insert(names, name)
  end
  table.sort(names)

  local count = table.getn(names)

  for i = 1, count do
    local row = Row(i)
    local name = names[i]

    row.text:SetText(name)
    row:SetScript("OnClick", function()
      if arg1 == "RightButton" then
        remove(name)
      else
        box:SetText(name)
        load(name)
      end
      profilelist:Hide()
    end)
    row:Show()
  end

  for i = count + 1, table.getn(profilelist.rows) do
    profilelist.rows[i]:Hide()
  end

  if count == 0 then
    local row = Row(1)
    row.text:SetText("|cffaaaaaano layouts saved yet|r")
    row:SetScript("OnClick", function() profilelist:Hide() end)
    row:Show()
    count = 1
  end

  profilelist:SetHeight(count * 17 + 12)
  profilelist:Show()
end

--[[ grid -------------------------------------------------------------------]]

local function BuildGrid()
  local size = db.grid or 32
  if size < 8 then size = 8 end

  grid.lines = grid.lines or {}
  local width, height = UIParent:GetWidth(), UIParent:GetHeight()
  local used = 0

  local function line()
    used = used + 1
    if not grid.lines[used] then
      grid.lines[used] = grid:CreateTexture(nil, "BACKGROUND")
    end
    return grid.lines[used]
  end

  -- vertical
  local i = 0
  while i * size <= width do
    local tex = line()
    local center = math.abs(i * size - width / 2) < size / 2
    if center then tex:SetTexture(.8, .6, 0, .8) else tex:SetTexture(0, 0, 0, .35) end
    tex:SetPoint("TOPLEFT", grid, "TOPLEFT", i * size - .5, 0)
    tex:SetPoint("BOTTOMRIGHT", grid, "BOTTOMLEFT", i * size + .5, 0)
    tex:Show()
    i = i + 1
  end

  -- horizontal
  i = 0
  while i * size <= height do
    local tex = line()
    local center = math.abs(i * size - height / 2) < size / 2
    if center then tex:SetTexture(.8, .6, 0, .8) else tex:SetTexture(0, 0, 0, .35) end
    tex:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, -(i * size) + .5)
    tex:SetPoint("BOTTOMRIGHT", grid, "TOPRIGHT", 0, -(i * size) - .5)
    tex:Show()
    i = i + 1
  end

  -- hide whatever a coarser grid left behind
  for n = used + 1, table.getn(grid.lines) do
    grid.lines[n]:Hide()
  end
end

--[[ panel ------------------------------------------------------------------]]

local function Button(parent, text, width, x, y, onclick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetWidth(width)
  b:SetHeight(21)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:SetText(text)
  b:SetScript("OnClick", onclick)
  return b
end

-- OptionsSliderTemplate hangs its three fontstrings off the slider's global
-- name. They are grabbed once here and kept on the slider as .caption, .low and
-- .high; every caller uses those rather than rebuilding the global name and
-- looking it up again, which the panel was doing a dozen times per refresh.
local function Slider(parent, name, label, min, max, step, x, y, onchange)
  local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
  s:SetWidth(240)
  s:SetHeight(16)
  s:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  s:SetMinMaxValues(min, max)
  s:SetValueStep(step)
  s:SetValue(min)

  s.caption = _G[name .. "Text"]
  s.low = _G[name .. "Low"]
  s.high = _G[name .. "High"]

  if s.low then s.low:SetText(tostring(min)) end
  if s.high then s.high:SetText(tostring(max)) end
  if s.caption then s.caption:SetText(label) end

  s:SetScript("OnValueChanged", function()
    if updating then return end
    onchange(this:GetValue())
  end)

  return s
end

-- Slider captions are set from several places and always have to cope with a
-- template that may not have given us the fontstring.
local function SetCaption(slider, text)
  if slider.caption then slider.caption:SetText(text) end
end

local function CheckBox(parent, name, label, x, y, onclick)
  local c = CreateFrame("CheckButton", name, parent, "OptionsCheckButtonTemplate")
  c:SetWidth(22)
  c:SetHeight(22)
  c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  if _G[name .. "Text"] then _G[name .. "Text"]:SetText(label) end
  c:SetScript("OnClick", function()
    if updating then return end
    onclick(this:GetChecked() and 1 or 0)
  end)
  return c
end

local function CoordBox(parent, name, label, x, y, apply)
  local e = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
  e:SetWidth(54)
  e:SetHeight(18)
  e:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  e:SetAutoFocus(false)

  e.text = e:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  e.text:SetPoint("BOTTOMLEFT", e, "TOPLEFT", -4, 2)
  e.text:SetText(label)

  e:SetScript("OnEnterPressed", function()
    apply(tonumber(this:GetText()))
    this:ClearFocus()
  end)
  e:SetScript("OnEscapePressed", function() this:ClearFocus() UpdatePanel() end)

  return e
end

local function BuildPanel()
  panel = CreateFrame("Frame", "tDFEditModePanel", UIParent)
  panel:SetWidth(280)
  panel:SetHeight(614)
  panel:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
  panel:SetFrameStrata("FULLSCREEN_DIALOG")
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function() this:StartMoving() end)
  panel:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  panel:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })

  panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.title:SetPoint("TOP", panel, "TOP", 0, -16)
  panel.title:SetText(T["|cff008000t|cff1974d2DF"] .. " |cffffffffEdit Mode")

  panel.selection = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  panel.selection:SetPoint("TOP", panel, "TOP", 0, -36)
  panel.selection:SetText("|cffaaaaaanothing selected|r")

  panel.x = CoordBox(panel, "tDFEditModeX", "X", 24, -78, function(value)
    if value and selected then
      local _, cy = ReadPosition(selected.frame)
      local e = db.frames[selected.key]
      PlaceItem(selected, value, (e and e.y) or cy)
      RefreshOverlay(selected)
    end
    UpdatePanel()
  end)

  panel.y = CoordBox(panel, "tDFEditModeY", "Y", 104, -78, function(value)
    if value and selected then
      local cx = ReadPosition(selected.frame)
      local e = db.frames[selected.key]
      PlaceItem(selected, (e and e.x) or cx, value)
      RefreshOverlay(selected)
    end
    UpdatePanel()
  end)

  panel.nudgehint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  panel.nudgehint:SetPoint("TOPLEFT", panel, "TOPLEFT", 176, -80)
  panel.nudgehint:SetText("arrows nudge\nshift = 10px")
  panel.nudgehint:SetJustifyH("LEFT")

  panel.scale = Slider(panel, "tDFEditModeScale", "Scale", .5, 2, .05, 22, -122, function(value)
    if not selected then return end
    ScaleItem(selected, value)
    RefreshOverlay(selected)
    UpdatePanel()
  end)

  panel.alpha = Slider(panel, "tDFEditModeAlpha", "Opacity", 0, 1, .05, 22, -166, function(value)
    if not selected then return end
    local e = Entry(selected.key)
    e.alpha = value
    pcall(selected.frame.SetAlpha, selected.frame, value)
    UpdatePanel()
  end)

  panel.centerx = Button(panel, "Center X", 116, 22, -196, function() CenterSelected("x") end)
  panel.centery = Button(panel, "Center Y", 116, 142, -196, function() CenterSelected("y") end)
  panel.resetone = Button(panel, "Reset Element", 116, 22, -220, function()
    if selected then ResetFrame(selected) end
  end)
  panel.resetall = Button(panel, "Reset All", 116, 142, -220, function() ResetAll() end)

  --[[ bar shaping, provided by mods\tBarLayout.lua when it is loaded ]]--

  panel.shapelabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.shapelabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -252)
  panel.shapelabel:SetText("|cffffd100Bar shape|r")

  panel.count = Slider(panel, "tDFEditModeCount", "Buttons", 1, 12, 1, 22, -288, function(value)
    if selected and tDF_BarLayout then
      tDF_BarLayout.Set(selected.key, "count", math.floor(value))
      RefreshOverlay(selected)
      UpdatePanel()
    end
  end)

  panel.columns = Slider(panel, "tDFEditModeColumns", "Per row", 1, 12, 1, 22, -332, function(value)
    if selected and tDF_BarLayout then
      tDF_BarLayout.Set(selected.key, "columns", math.floor(value))
      RefreshOverlay(selected)
      UpdatePanel()
    end
  end)

  panel.vertical = CheckBox(panel, "tDFEditModeVertical", "Vertical", 22, -358, function(value)
    if selected and tDF_BarLayout then
      tDF_BarLayout.Set(selected.key, "vertical", value)
      RefreshOverlay(selected)
      UpdatePanel()
    end
  end)

  panel.resetshape = Button(panel, "Reset shape", 104, 152, -360, function()
    if selected and tDF_BarLayout then
      tDF_BarLayout.Reset(selected.key)
      RefreshOverlay(selected)
      UpdatePanel()
    end
  end)

  --[[ grid ]]--

  panel.snap = CheckBox(panel, "tDFEditModeSnap", "Snap to grid", 22, -392, function(value)
    db.snap = value
  end)

  panel.showgrid = CheckBox(panel, "tDFEditModeShowGrid", "Show grid", 152, -392, function(value)
    db.showgrid = value
    if value == 1 then BuildGrid() grid:Show() else grid:Hide() end
  end)

  -- The caption tracks the slider immediately; the grid itself is rebuilt when
  -- the handle is let go. Rebuilding on every 8px step meant dragging from one
  -- end to the other re-laid several hundred line textures fifteen times over.
  panel.gridsize = Slider(panel, "tDFEditModeGrid", "Grid size", 8, 128, 8, 22, -436, function(value)
    db.grid = value
    SetCaption(panel.gridsize, "Grid size: " .. math.floor(value))
    if db.showgrid == 1 and not panel.gridsize.held then BuildGrid() end
  end)

  -- hooked, not set: OptionsSliderTemplate brings its own mouse handlers and
  -- replacing them stops the handle responding
  tDFUI.HookScript(panel.gridsize, "OnMouseDown", function()
    panel.gridsize.held = true
  end)

  tDFUI.HookScript(panel.gridsize, "OnMouseUp", function()
    panel.gridsize.held = nil
    if db.showgrid == 1 then BuildGrid() end
  end)

  --[[ layout profiles ]]--

  panel.profilelabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.profilelabel:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -466)
  panel.profilelabel:SetText("|cffffd100Layout profiles|r |cffaaaaaa(all characters)|r")

  panel.profile = CreateFrame("EditBox", "tDFEditModeProfile", panel, "InputBoxTemplate")
  panel.profile:SetWidth(228)
  panel.profile:SetHeight(18)
  panel.profile:SetPoint("TOPLEFT", panel, "TOPLEFT", 28, -484)
  panel.profile:SetAutoFocus(false)
  panel.profile:SetScript("OnEnterPressed", function()
    SaveProfile(this:GetText())
    this:ClearFocus()
  end)
  panel.profile:SetScript("OnEscapePressed", function() this:ClearFocus() end)

  panel.save = Button(panel, "Save", 74, 22, -512, function()
    SaveProfile(panel.profile:GetText())
    HideProfileList()
  end)
  panel.load = Button(panel, "Load", 74, 100, -512, function()
    LoadProfile(panel.profile:GetText())
  end)
  panel.delete = Button(panel, "Delete", 74, 178, -512, function()
    DeleteProfile(panel.profile:GetText())
    HideProfileList()
  end)
  panel.list = Button(panel, "Saved layouts", 230, 22, -536, function()
    ToggleProfileList(panel, panel.list, panel.profile, LoadProfile, DeleteProfile)
  end)

  panel.hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  panel.hint:SetPoint("TOPLEFT", panel, "TOPLEFT", 24, -562)
  panel.hint:SetWidth(232)
  panel.hint:SetJustifyH("LEFT")
  panel.hint:SetText("Click an element to select it. Wheel scales, shift-wheel fades, right-click resets. Tab cycles.")

  panel.done = Button(panel, "Done", 100, 90, -586, function() Close() end)

  panel:EnableKeyboard(true)
  panel:SetScript("OnKeyDown", function()
    local step = IsShiftKeyDown() and 10 or 1
    if arg1 == "ESCAPE" then
      Close()
    elseif arg1 == "UP" then
      Nudge(0, step)
    elseif arg1 == "DOWN" then
      Nudge(0, -step)
    elseif arg1 == "LEFT" then
      Nudge(-step, 0)
    elseif arg1 == "RIGHT" then
      Nudge(step, 0)
    elseif arg1 == "TAB" then
      SelectNext()
    end
  end)

  -- Hiding the panel IS closing Edit Mode, whoever does the hiding. The panel
  -- is in UISpecialFrames, so Escape can hide it without going anywhere near
  -- Close() - and if the teardown lived only in Close(), that left a fullscreen
  -- sheet of mouse-enabled overlays over the whole UI with nothing visible to
  -- explain why nothing was clickable.
  panel:SetScript("OnHide", function() Teardown() end)
end

-- show or hide the bar shaping controls for whatever is selected
local function UpdateShapeSection()
  local def = selected and tDF_BarLayout and tDF_BarLayout.Supports(selected.key)

  if not def then
    panel.count:Hide()
    panel.columns:Hide()
    panel.vertical:Hide()
    panel.resetshape:Hide()
    panel.shapelabel:SetText("|cff808080Bar shape|r |cff808080- not a bar|r")
    return
  end

  local layout = tDF_BarLayout.Get(selected.key)
  local max = tDF_BarLayout.Max(selected.key)
  local vertical = layout.vertical == 1

  panel.shapelabel:SetText("|cffffd100Bar shape|r |cffaaaaaa" .. (def.label or selected.label) .. "|r")

  -- the micro menu has a fixed set of buttons, so only its shape is editable
  if def.nocount then
    panel.count:Hide()
  else
    panel.count:Show()
    panel.count:SetMinMaxValues(1, max)
    panel.count:SetValue(layout.count)
    SetCaption(panel.count, "Buttons: " .. layout.count .. " of " .. max)
    if panel.count.high then panel.count.high:SetText(tostring(max)) end
  end

  panel.columns:Show()
  panel.columns:SetMinMaxValues(1, max)
  panel.columns:SetValue(layout.columns)
  SetCaption(panel.columns,
    (vertical and "Per column: " or "Per row: ") .. layout.columns)
  if panel.columns.high then panel.columns.high:SetText(tostring(max)) end

  panel.vertical:Show()
  panel.vertical:SetChecked(vertical and true or nil)
  panel.resetshape:Show()
end

-- `light` redraws only what a drag can change, and is what the drag loop calls.
-- The full refresh rewrites every control in the panel - including two sliders'
-- min/max and the whole bar shape section - which is far too much to redo on
-- every frame for sixty frames a second while the mouse is down.
UpdatePanel = function(light)
  if not panel or not panel:IsShown() then return end

  local x, y
  if selected then x, y = ReadPosition(selected.frame) end

  panel.x:SetText(x and tostring(math.floor(x + .5)) or "")
  panel.y:SetText(y and tostring(math.floor(y + .5)) or "")

  if light then return end

  updating = true

  panel.snap:SetChecked(db.snap == 1 and true or nil)
  panel.showgrid:SetChecked(db.showgrid == 1 and true or nil)
  panel.gridsize:SetValue(db.grid or 32)
  SetCaption(panel.gridsize, "Grid size: " .. math.floor(db.grid or 32))

  if selected then
    local frame = selected.frame
    local scale, alpha = ScaleFactor(frame), frame:GetAlpha() or 1

    panel.selection:SetText("|cffffd100" .. selected.label ..
      "|r |cffaaaaaa" .. selected.group .. "|r")
    panel.scale:SetValue(scale)
    panel.alpha:SetValue(alpha)
    SetCaption(panel.scale, string.format("Scale: %.2f", scale))
    SetCaption(panel.alpha, string.format("Opacity: %d%%", math.floor(alpha * 100 + .5)))
  else
    panel.selection:SetText("|cffaaaaaanothing selected|r")
    SetCaption(panel.scale, "Scale")
    SetCaption(panel.alpha, "Opacity")
  end

  UpdateShapeSection()

  updating = nil
end

--[[ open and close ---------------------------------------------------------]]

local function Open()
  if not manager then return end
  if panel and panel:IsShown() then return end

  if tDFUI_config and tDFUI_config[T["Movable Unit Frames Extended"]] == 1 then
    Print("|cffff9900Movable Unit Frames Extended is also enabled|r - its shift+ctrl dragging fights Edit Mode over the same frames. Turn it off in tDF Options.")
  end

  if db.showgrid == 1 then
    BuildGrid()
    grid:Show()
  else
    grid:Hide()
  end

  ResolveRegistry()

  manager:Show()
  panel:Show()
  RefreshAll()
  UpdatePanel()
end

-- Everything that comes down when Edit Mode ends. Driven from the panel's
-- OnHide, so it runs however the panel was hidden - the Done button, Escape
-- through UISpecialFrames, or another addon. Safe to run twice.
Teardown = function()
  if dragging then
    dragging:StopMovingOrSizing()
    dragging = nil
  end
  isolation = nil

  HideProfileList()

  if grid then grid:Hide() end
  if manager then manager:Hide() end

  GameTooltip:Hide()
  selected = nil
end

Close = function()
  if panel and panel:IsShown() then panel:Hide() else Teardown() end
end

local function Toggle()
  if panel and panel:IsShown() then Close() else Open() end
end

--[[ module enable ----------------------------------------------------------]]

module.enable = function(self)
  tDFUI_config = tDFUI_config or {}
  tDFUI_config["EditModeDB"] = tDFUI_config["EditModeDB"] or {}
  db = tDFUI_config["EditModeDB"]
  db.frames = db.frames or {}
  if db.grid == nil then db.grid = 32 end
  if db.snap == nil then db.snap = 1 end
  if db.showgrid == nil then db.showgrid = 1 end

  tDF_editProfiles = tDF_editProfiles or {}

  -- overlays live one strata below the panel so the controls are never buried
  manager = CreateFrame("Frame", "tDFEditModeManager", UIParent)
  manager:SetAllPoints(UIParent)
  manager:SetFrameStrata("FULLSCREEN")
  manager:Hide()

  -- The grid is parented to UIParent, not WorldFrame. WorldFrame is in raw
  -- screen pixels while every position here is in UIParent units, so a
  -- WorldFrame grid drifts out of alignment with the snapping at any UI scale
  -- other than 1.0 - the lines would point at the wrong place.
  grid = CreateFrame("Frame", nil, UIParent)
  grid:SetAllPoints(UIParent)
  grid:SetFrameStrata("BACKGROUND")
  grid:Hide()

  -- center guides, shown while a drag is magnetised to an axis
  manager.vguide = manager:CreateTexture(nil, "OVERLAY")
  manager.vguide:SetTexture(1, .82, 0, .7)
  manager.vguide:SetPoint("TOP", UIParent, "TOP", 0, 0)
  manager.vguide:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 0)
  manager.vguide:SetWidth(1)
  manager.vguide:Hide()

  manager.hguide = manager:CreateTexture(nil, "OVERLAY")
  manager.hguide:SetTexture(1, .82, 0, .7)
  manager.hguide:SetPoint("LEFT", UIParent, "LEFT", 0, 0)
  manager.hguide:SetPoint("RIGHT", UIParent, "RIGHT", 0, 0)
  manager.hguide:SetHeight(1)
  manager.hguide:Hide()

  BuildPanel()
  panel:Hide()
  table.insert(UISpecialFrames, "tDFEditModePanel")

  ResolveRegistry()

  manager:SetScript("OnUpdate", function()
    if dragging then
      SyncFromOverlay(dragging)
      -- coordinates only; the full panel refresh is far too much per frame
      UpdatePanel(true)
    end

    this.elapsed = (this.elapsed or 0) + arg1
    if this.elapsed > REFRESH then
      this.elapsed = 0
      RefreshAll()
    end
  end)

  -- apply the stored layout once the rest of the UI has settled, then again a
  -- little later: several tDF modules and Blizzard's own layout pass move these
  -- frames after VARIABLES_LOADED, and whoever writes last wins
  tDFUI.RetryAfterLogin(3, function()
    ResolveRegistry()
    RelatchPassengers()
    ApplyAll()
  end)

  local combat = CreateFrame("Frame", nil, UIParent)
  combat:RegisterEvent("PLAYER_REGEN_DISABLED")
  combat:SetScript("OnEvent", function()
    if panel and panel:IsShown() then
      Close()
      Print("Edit Mode closed - you are in combat.")
    end
  end)

  -- Blizzard's layout pass re-places the action bars and the minimap cluster on
  -- zone changes and whenever a bar is toggled, so our positions have to be
  -- re-asserted right after it runs.
  --
  -- This has to happen synchronously, inside the hook. Deferring it by a frame
  -- or two - which is what handing the work to the retry loop above did - meant
  -- the frames were visibly drawn at Blizzard's defaults, down at the bottom of
  -- the screen, for a tick before snapping back. That was the flicker during
  -- and after editing: not our position being wrong, just our correction
  -- arriving one frame late.
  local reapplying
  tDFUI.hooksecurefunc("UIParent_ManageFramePositions", function()
    if dragging or reapplying then return end
    reapplying = true
    ApplyAll()
    reapplying = nil
  end, true)

  ApplyAll()

  -- public entry points
  tDF_EditMode = {
    Open = Open, Close = Close, Toggle = Toggle,
    ResetAll = ResetAll, Apply = ApplyAll,

    -- Has the user placed this frame by hand? tReducedActionBar.lua re-anchors
    -- half the bottom of the UI from a layout hook and an OnUpdate, so it asks
    -- this before overriding a position someone chose deliberately.
    IsPlaced = function(key)
      local e = db and db.frames and db.frames[key]
      return (e and e.x and e.y) and true or nil
    end,
  }
  tDF_EditMode_Toggle = Toggle

  tDF_EditModeCommand = function(args)
    -- only the verb is case folded; profile names keep the case they were
    -- saved with, or `load MyLayout` would never match anything
    local _, _, verb, rest = string.find(args or "", "^%s*(%a*)%s*(.*)$")
    verb = string.lower(verb or "")
    rest = string.gsub(rest or "", "%s+$", "")

    if verb == "reset" then
      ResetAll()
    elseif verb == "lock" or verb == "close" then
      Close()
    elseif verb == "list" then
      ListProfiles()
    elseif verb == "load" and rest and rest ~= "" then
      LoadProfile(rest)
    else
      Toggle()
    end
  end

  SLASH_TDFEDITMODE1 = "/tdfedit"
  SlashCmdList["TDFEDITMODE"] = function(msg) tDF_EditModeCommand(msg) end
end
