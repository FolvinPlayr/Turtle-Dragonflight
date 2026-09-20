--[[ Bar Layout ----------------------------------------------------------------

  FFXIV style bar shaping: how many buttons a bar shows, how many of them fit
  per row, and whether it grows sideways or downwards. Driven from the Edit Mode
  panel (see mods\tEditMode.lua), stored per character.

  Three things bite here, all of them learned the hard way:

  * A bar is only ever touched once the user changes something about it, and
    button 1 is never moved at all. Everything else hangs off button 1, so the
    block always starts exactly where this addon's own layout put it. Deriving
    positions from the bar frame instead means guessing at insets nobody wrote
    down - and tReducedActionBar.lua re-anchors MainMenuBar itself from a
    UIParent_ManageFramePositions hook, so the frame is not a fixed reference.

  * A button that is moved, hidden or re-shown must be repainted with
    ActionButton_Update. Vanilla only paints empty slots from its own events,
    so without this they render as nothing at all and you see through them.

  * Buttons past the chosen count get their Show method stubbed out, not just
    Hide(). Blizzard re-shows action buttons from MultiActionBar_Update and from
    action bar paging, so a plain Hide() reappears the moment you swap pages.
    The original method is kept on the button so Reset can put it back.

--]]

local _G = tDFUI.GetGlobalEnv()
local T = tDFUI.T
local mod = math.mod or mod

-- `hidden` keeps this out of the options list and always on. There is nothing
-- to toggle: a bar with no saved shape is untouched, so the module does nothing
-- until Edit Mode asks it to, and a checkbox for that is just noise.
local module = tDFUI:register({
  title = T["Bar Layout"],
  description = T["barlayout_desc"],
  expansions = { ["vanilla"] = true, ["tbc"] = true },
  category = T["Action Bar"],
  enabled = true,
  hidden = true,
})

-- Every bar that can be reshaped.
--
--   pattern    string.format template for numbered buttons
--   names      explicit button list instead, where they are not numbered
--   max        button count for `pattern` bars (`names` bars count themselves)
--   gap        pixels between buttons
--   refresh    repaint buttons after moving them - action bars only
--   mirror     a parallel set of buttons that must take the same shape
--   nocount    the button count is fixed; only the shape is editable
--   nobounds   do not report a footprint to Edit Mode (see Bounds)
--   dirx       -1 for bars that run right to left from their first button
--
-- Bar frames are never resized. They were, briefly, to stop a reshaped bar
-- leaving a full width ghost behind - but half the bottom of the UI anchors to
-- MainMenuBar, and every bar's first button anchors to its own frame, so
-- resizing moved things that had no business moving. The ghost is dealt with by
-- rebuilding the artwork around the buttons (see the art section below) and by
-- reporting Bounds() to Edit Mode, so the overlay hugs the buttons rather than
-- the untouched frame.
local bars = {
  ["MainMenuBar"] = {
    label = "Main Action Bar",
    pattern = "ActionButton%d", max = 12, gap = 6, refresh = true,
    -- the bonus bar (stealth, druid forms) replaces the main bar in place, so
    -- it has to take the same shape or it reverts to 12 across when you shift
    mirror = "BonusActionButton%d",
  },
  ["MultiBarBottomLeft"] = {
    label = "Bottom Left Bar",
    pattern = "MultiBarBottomLeftButton%d", max = 12, gap = 6, refresh = true,
  },
  ["MultiBarBottomRight"] = {
    label = "Bottom Right Bar",
    pattern = "MultiBarBottomRightButton%d", max = 12, gap = 6, refresh = true,
  },
  ["MultiBarRight"] = {
    label = "Right Bar",
    pattern = "MultiBarRightButton%d", max = 12, gap = 6, refresh = true,
    vertical = true,
  },
  ["MultiBarLeft"] = {
    label = "Right Bar 2",
    pattern = "MultiBarLeftButton%d", max = 12, gap = 6, refresh = true,
    vertical = true,
  },
  -- The bag bar is a special shape: tDFbagMain is the backpack button itself,
  -- not a container, and the bag buttons are its children running leftwards
  -- from it. So it lays out from the BOTTOMRIGHT going left, with the offsets
  -- that reproduce tBagIcons.lua's own spacing.
  --
  -- Both of the dirx = -1 bars are `nobounds`. Bounds() describes a block
  -- measured rightwards from a frame's left edge, which is the wrong end for a
  -- bar that grows leftwards - Edit Mode would draw the overlay a frame's width
  -- away from the buttons the moment either one was reshaped.
  ["tDFbagMain"] = {
    label = "Bag Bar",
    names = { "tDFbag1", "tDFbag2", "tDFbag3", "tDFbag4", "tDFbagKeys" },
    gap = 0, nocount = true, nobounds = true, dirx = -1,
  },
  ["tDFmicrobutton"] = {
    label = "Micro Menu",
    -- right to left on screen, so the list runs in reverse visual order
    names = {
      "mbHelp", "mbMainMenu", "mbPvP", "mbShop", "mbLFT", "mbEBC",
      "mbWorldMap", "mbSocials", "mbQuestLog", "mbTalent", "mbSpellBook",
      "mbCharacter",
    },
    gap = 2, nocount = true, nobounds = true, dirx = -1,
  },
}

local db
local repaint            -- one-shot frame, repaints a bar the frame after it moves
local originals = {}     -- button name -> its anchor and Show before we touched it
local bounds = {}        -- bar name -> the size its buttons actually occupy now


-- Make the game repaint an action button.
--
-- Vanilla paints a button's empty-slot art inside ActionButton_Update, which
-- only ever runs from its own events. A button that we move, hide or re-show
-- keeps whatever paint state it was left in - so empty slots rendered as
-- nothing at all and you saw through them to the bar art behind, which read as
-- the buttons having gone black. Dragging a spell onto the bar fixed it because
-- that made the game run this function itself.
--
-- ActionButton_Update takes its button from the global `this`, so it has to be
-- set and put back, the same trick tRadio.lua uses to drive the client's radio
-- widgets.
local function RefreshButton(button)
  if not button or not ActionButton_Update then return end

  local previous = this
  this = button
  pcall(ActionButton_Update)
  this = previous
end


--[[ helpers ----------------------------------------------------------------]]

local function ButtonName(def, index)
  if def.names then return def.names[index] end
  return string.format(def.pattern, index)
end

local function ButtonCount(def)
  if def.names then return table.getn(def.names) end
  return def.max
end

-- remember a button's original anchor and Show method exactly once
local function Remember(name, button)
  if originals[name] then return end

  local point, relativeTo, relativePoint, x, y = button:GetPoint(1)
  originals[name] = {
    point = point, relativeTo = relativeTo, relativePoint = relativePoint,
    x = x, y = y,
    show = button.Show,
  }
end

local function Defaults(key)
  local def = bars[key]
  local max = ButtonCount(def)
  -- columns defaults to the full count, which reads as one row when horizontal
  -- and one tall column when vertical - i.e. exactly how the bar ships
  return {
    count = max,
    columns = max,
    vertical = def.vertical and 1 or 0,
  }
end

-- Is this bar in the shape it ships in?
--
-- Exactly one predicate, deliberately. This decides which artwork the main bar
-- shows, and it is asked from two places - once while laying the bar out and
-- once while asserting the art state afterwards. Two hand written spellings of
-- it is how the bar ended up with both layers of art on screen at once.
local function IsDefaultShape(key)
  local saved = db and db[key]
  if not saved then return true end

  local base = Defaults(key)

  return (saved.count or base.count) == base.count
    and (saved.columns or base.columns) == base.columns
    and (saved.vertical or base.vertical) == base.vertical
end
--[[ main bar artwork ------------------------------------------------------

  The HD bar art that ships with tDF is drawn by tMainActionBar.lua as two
  256x256 frames pinned to MainMenuBar's centre at hardcoded -125 / +127 / -5
  offsets. That has two consequences:

  * it cannot follow a reshaped bar, and
  * it is 2px off centre even at the default shape, which is why the art and the
    buttons never quite lined up.

  So the art is rebuilt here instead, one strip per row of buttons, anchored to
  the first and last button of that row. It follows any shape, and it lines up
  by construction because it is measured from the buttons themselves.

  The texture is 512x512 with the bar occupying rows 208..303 - v 0.40625 to
  0.59375 - and it is uniform across its full width, so it has no end caps to
  distort when stretched. The gryphons are separate frames from tGryphons.lua.
  Each strip draws the texture twice, the right half mirrored, exactly as the
  original two frames did, so the pattern keeps its current scale.

--]]

local ART_TEXTURE = "Interface\\AddOns\\Turtle-Dragonflight\\img\\HDActionBar.tga"

-- Measured from the file. The bar occupies rows 208..303 of the 512px texture:
-- a top rim at 208..221, the interior fill at 222..291, and a bottom rim at
-- 292..303. Rows that touch another row use the interior bounds so the seam
-- between them has no rim, instead of two rims stacked on each other.
local ART_V_TOP      = 0.40625    -- y 208, outer edge of the top rim
local ART_V_INNERTOP = 0.43359    -- y 222, first row of interior fill
local ART_V_BOTTOM   = 0.59375    -- y 304, outer edge of the bottom rim

-- The texture was drawn 512 wide into a 256 wide frame, so one screen pixel is
-- two texture pixels. Slicing u by that ratio keeps the rivet pattern at its
-- native scale at any bar width; stretching the whole texture instead is what
-- turned a one-button-wide strip into a bundle of vertical lines.
local ART_U_PER_PIXEL = 1 / 256

local ART_PAD = 6          -- the strip stands proud of the buttons vertically
local ART_SEAM = 3         -- ...but only half that where another row adjoins,
                           -- so stacked rows tile exactly instead of overlapping
local ART_OVERHANG = 5     -- and it runs slightly past the end buttons

local artrows = {}

-- the two hardcoded copies from tMainActionBar.lua, which we replace wholesale
local function ShowOriginalArt(show)
  if not tDFActionBarArt then return end

  for _, art in pairs(tDFActionBarArt) do
    for _, frame in pairs(art) do
      if frame then
        if show then frame:Show() else frame:Hide() end
      end
    end
  end
end

local function ArtRow(index)
  if artrows[index] then return artrows[index] end

  local frame = CreateFrame("Frame", nil, MainMenuBar)
  frame:SetFrameStrata("LOW")

  -- two halves, the right one mirrored, so both ends of the strip are the
  -- texture's own finished edge however much of it is used
  frame.left = frame:CreateTexture(nil, "BACKGROUND")
  frame.left:SetTexture(ART_TEXTURE)
  frame.left:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
  frame.left:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", 0, 0)

  frame.right = frame:CreateTexture(nil, "BACKGROUND")
  frame.right:SetTexture(ART_TEXTURE)
  frame.right:SetPoint("TOPLEFT", frame, "TOP", 0, 0)
  frame.right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)

  artrows[index] = frame
  return frame
end

-- No tint is applied to these strips, deliberately. An earlier version dimmed
-- them to match Darkened UI and the result was far darker than the artwork they
-- replaced, so they are left at the texture's own brightness.

-- Where the gryphons were anchored before we moved them onto a strip
local gryphonanchors

local function RememberGryphons()
  if gryphonanchors or not tDFGryphons then return end

  gryphonanchors = {}

  -- Measure the endcaps against the BUTTONS, not against the artwork or the
  -- strip. Button 1 never moves vertically whatever the shape is, so it is the
  -- only stable reference here - the strip's centre shifts with its padding,
  -- and the artwork's own position is what went stale last time.
  local artcentre = ActionButton1 and ActionButton1:GetTop()
    and (ActionButton1:GetTop() + ActionButton1:GetBottom()) / 2

  for _, side in pairs({ "left", "right" }) do
    local texture = tDFGryphons[side]

    if texture and texture.GetPoint then
      local point, relativeTo, relativePoint, x, y = texture:GetPoint(1)
      local centre = texture:GetTop()
        and (texture:GetTop() + texture:GetBottom()) / 2

      gryphonanchors[side] = {
        point = point, relativeTo = relativeTo, relativePoint = relativePoint,
        x = x, y = y,
        -- how high the endcap rides relative to the middle of a button
        dy = (centre and artcentre) and (centre - artcentre) or 0,
      }
    end
  end
end

-- Hand the bar back to the artwork that ships with the addon.
--
-- The generated strips are only used for shapes the original art cannot
-- express. At the default twelve-across the original is simply better: it is
-- what the addon was drawn for, and every attempt to reproduce it from slices
-- of the same texture came out wrong in some way - too dark, too short, or
-- sized from whichever buttons happened to be visible at the time.
local function RestoreOriginalArt()
  ShowOriginalArt(true)

  for i = 1, table.getn(artrows) do
    artrows[i]:Hide()
  end

  if gryphonanchors and tDFGryphons then
    for _, side in pairs({ "left", "right" }) do
      local texture, anchor = tDFGryphons[side], gryphonanchors[side]

      if texture and anchor and anchor.point then
        texture:ClearAllPoints()
        texture:SetPoint(anchor.point, anchor.relativeTo or MainMenuBarArtFrame,
          anchor.relativePoint or anchor.point, anchor.x or 0, anchor.y or 0)
      end
    end
  end
end

local function BuildMainBarArt(spans)
  if not spans or table.getn(spans) == 0 then return end

  RememberGryphons()
  ShowOriginalArt(false)

  local rows = table.getn(spans)

  for i = 1, rows do
    local span = spans[i]
    local frame = ArtRow(i)

    -- One rim per seam, not two and not none.
    --
    -- Every row keeps its bottom rim; only the top rim is dropped on rows that
    -- have another row above them. Two rims at a seam was the doubled border;
    -- zero rims made a stacked bar almost entirely the texture's interior fill,
    -- which is genuinely dark - measured luminance 20..47 against 80..97 for
    -- the rims - and that is what turned the bar black when rows were added.
    local padtop = (i == 1) and ART_PAD or ART_SEAM
    local padbottom = (i == rows) and ART_PAD or ART_SEAM
    local vtop = (i == 1) and ART_V_TOP or ART_V_INNERTOP
    local vbottom = ART_V_BOTTOM

    -- how much of the texture this row's width is worth, at native scale
    local width = (span.width or 0) + ART_OVERHANG * 2
    local u = width / 2 * ART_U_PER_PIXEL
    if u > 1 then u = 1 end
    if u <= 0 then u = 1 end

    frame.left:SetTexCoord(0, u, vtop, vbottom)
    frame.right:SetTexCoord(u, 0, vtop, vbottom)

    -- Centred on the row, full stop. This used to add a measured offset between
    -- the shipped art and the buttons, but that measurement gets cached the
    -- first time it succeeds and tReducedActionBar.lua moves MainMenuBar
    -- between y=13 and y=28 depending on whether the XP bar shows - so the
    -- cached value went stale and floated the strip 14px above its buttons.
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", span.first, "TOPLEFT", -ART_OVERHANG, padtop)
    frame:SetPoint("BOTTOMRIGHT", span.last, "BOTTOMRIGHT", ART_OVERHANG, -padbottom)
    frame:Show()
  end

  for i = table.getn(spans) + 1, table.getn(artrows) do
    artrows[i]:Hide()
  end

  -- The endcaps belong at the ends of the bottom row. Their visibility is left
  -- entirely alone so the Hide Gryphons module keeps working either way.
  --
  -- Hung off the bottom row's end BUTTONS rather than off the strip. The
  -- buttons never move vertically when the count changes, so with a fixed
  -- offset measured against them the endcaps cannot drift - anchoring to the
  -- strip put them at the strip's centre, which moves with its padding, and
  -- that is what lowered the wyverns below twelve buttons.
  local ends = spans[rows]

  if tDFGryphons and ends and gryphonanchors then
    local left = gryphonanchors.left and gryphonanchors.left.dy or 0
    local right = gryphonanchors.right and gryphonanchors.right.dy or 0

    tDFGryphons.left:ClearAllPoints()
    tDFGryphons.left:SetPoint("LEFT", ends.first, "LEFT", -105, left)
    tDFGryphons.right:ClearAllPoints()
    tDFGryphons.right:SetPoint("RIGHT", ends.last, "RIGHT", 108, right)
  end
end

-- The main bar ends every layout pass in exactly one art state: the shipped
-- artwork at its default shape, generated strips otherwise. This is asserted on
-- every pass rather than only when a shape changes, because a bar that ends up
-- with NO art - which is what a default shaped bar was doing after a reload -
-- is indistinguishable from a broken one, and because it makes two layers at
-- once impossible. The shipped art is full twelve-button width and pinned to
-- the bar's centre, so surviving alongside a strip shows two bars at once.
--
-- `spans` is the row breakdown LayoutBar just worked out. Callers that have not
-- laid the bar out leave it off: the shipped art is still hidden for a reshaped
-- bar, and whatever strips are already up stay as they are.
local function SyncMainBarArt(spans)
  if not MainMenuBar then return end

  if IsDefaultShape("MainMenuBar") then
    RestoreOriginalArt()
  elseif spans then
    BuildMainBarArt(spans)
  else
    ShowOriginalArt(false)
  end
end

--[[ public config ----------------------------------------------------------]]

local BarLayout = {}

BarLayout.Supports = function(key)
  return bars[key]
end

BarLayout.Get = function(key)
  local def = bars[key]
  if not def then return nil end

  local saved = db and db[key]
  local base = Defaults(key)

  if not saved then return base end

  return {
    count = saved.count or base.count,
    columns = saved.columns or base.columns,
    vertical = saved.vertical or base.vertical,
  }
end

-- Size the reshaped buttons occupy, so Edit Mode can draw an overlay that
-- matches what is on screen rather than the bar's untouched frame. Returns
-- nothing for a bar that has not been reshaped.
BarLayout.Bounds = function(key)
  local b = bounds[key]
  if not b then return nil end
  return b.width, b.height
end

BarLayout.Max = function(key)
  local def = bars[key]
  if not def then return 0 end
  return ButtonCount(def)
end

--[[ layout ---------------------------------------------------------------]]

local function LayoutBar(key)
  local def = bars[key]
  local bar = _G[key]
  if not def or not bar then return end

  local settings = db[key]
  if not settings then return end          -- untouched bars stay untouched

  local base = Defaults(key)
  local count = settings.count or base.count
  local columns = settings.columns or base.columns
  local vertical = (settings.vertical or base.vertical) == 1
  local total = ButtonCount(def)

  if def.nocount then count = total end
  if count < 1 then count = 1 end
  if count > total then count = total end
  if columns < 1 then columns = 1 end
  if columns > count then columns = count end

  local first = _G[ButtonName(def, 1)]
  if not first then return end

  local bw, bh = first:GetWidth(), first:GetHeight()
  local gap = def.gap or 6
  local sx, sy = bw + gap, bh + gap

  -- Which way the block runs from its first button. Button 1 is never moved -
  -- see the loop below - so everything is expressed relative to it.
  local dirx = def.dirx or 1

  -- Work the grid out up front so the block can be anchored to the bar's BOTTOM
  -- edge and grow upwards. Anchoring at the top and growing down sent a tall
  -- vertical bar straight off the bottom of the screen, because the bars that
  -- matter already sit at the bottom. Button 1 still lands top left of the
  -- block; only the block's own anchor changes.
  local maxcol, maxrow

  if vertical then
    maxrow = columns < count and columns or count
    maxcol = math.ceil(count / columns)
  else
    maxcol = columns < count and columns or count
    maxrow = math.ceil(count / columns)
  end

  local spans = {}

  for i = 1, total do
    local name = ButtonName(def, i)
    local button = _G[name]

    if button then
      Remember(name, button)

      if i <= count then
        local col, row

        if vertical then
          -- fill downwards first: `columns` is how many fit in one column
          col = math.floor((i - 1) / columns)
          row = mod(i - 1, columns)
        else
          row = math.floor((i - 1) / columns)
          col = mod(i - 1, columns)
        end

        button.Show = originals[name].show

        -- Button 1 is left exactly where the addon's own layout put it, and
        -- every other button hangs off it. Deriving positions from the bar's
        -- corner instead meant guessing at insets the addon never told us
        -- about - tReducedActionBar.lua re-anchors MainMenuBar itself from a
        -- UIParent_ManageFramePositions hook, so the bar is not a fixed
        -- reference, but the first button always is. Row 0 is button 1's own
        -- row and further rows stack above it.
        if i > 1 then
          button:ClearAllPoints()
          button:SetPoint("BOTTOMLEFT", first, "BOTTOMLEFT",
            dirx * col * sx, row * sy)
        end

        button:Show()

        -- Track each row's end buttons so the artwork can hang off them.
        -- Row 0 is the bottom row now that the block grows upward from button
        -- 1, but the art wants spans[1] to be the TOP row, so the index is
        -- flipped here rather than in the art code.
        local index = maxrow - row
        local span = spans[index]

        if not span then
          span = { first = button, last = button, firstcol = col, lastcol = col }
          spans[index] = span
        else
          if col < span.firstcol then span.first, span.firstcol = button, col end
          if col > span.lastcol then span.last, span.lastcol = button, col end
        end

        span.width = (span.lastcol - span.firstcol + 1) * sx - gap

        -- repaint it, or an empty slot stays invisible where we put it
        if def.refresh then RefreshButton(button) end

        if def.mirror then
          local mname = string.format(def.mirror, i)
          local mirror = _G[mname]

          if mirror then
            Remember(mname, mirror)
            mirror.Show = originals[mname].show
            mirror:ClearAllPoints()
            mirror:SetPoint("BOTTOMLEFT", first, "BOTTOMLEFT",
              dirx * col * sx, row * sy)
          end
        end
      else
        -- stub Show before hiding, or Blizzard puts it straight back
        button.Show = function() return end
        button:Hide()

        if def.mirror then
          local mname = string.format(def.mirror, i)
          local mirror = _G[mname]

          if mirror then
            Remember(mname, mirror)
            mirror.Show = function() return end
            mirror:Hide()
          end
        end
      end
    end
  end

  -- what the buttons actually occupy, for bars whose frame we cannot resize.
  -- Skipped where the block does not start at the frame's own corner, or Edit
  -- Mode would draw the overlay in the wrong place.
  if not def.nobounds then
    bounds[key] = { width = maxcol * sx - gap, height = maxrow * sy - gap }
  end

  -- Repaint again next frame. Restoring a button's Show, showing it and
  -- repainting it all inside one frame is not enough for a button the game had
  -- hidden - which is why an ability on slot 12 vanished after 12 -> 11 -> 12.
  if repaint then repaint:Show() end

  if key == "MainMenuBar" then SyncMainBarArt(spans) end
end

BarLayout.ApplyAll = function()
  if not db then return end

  for key in pairs(bars) do
    LayoutBar(key)
  end

  -- LayoutBar leaves an untouched bar alone and so never reaches its own art
  -- call, which is how a default shaped bar ended up with no art at all after a
  -- reload. Assert the state once more for the pass as a whole.
  SyncMainBarArt()
end

BarLayout.Set = function(key, field, value)
  if not bars[key] or not db then return end

  db[key] = db[key] or Defaults(key)
  db[key][field] = value

  LayoutBar(key)

  -- the bar's footprint changed, so let Edit Mode re-measure its overlay
  if tDF_EditMode and tDF_EditMode.Apply then tDF_EditMode.Apply() end
end

BarLayout.Reset = function(key)
  local def = bars[key]
  if not def or not db then return end

  db[key] = nil
  local total = ButtonCount(def)

  local function restore(name)
    local button, o = _G[name], originals[name]
    if not button or not o then return end

    button.Show = o.show
    button:ClearAllPoints()

    if o.point then
      button:SetPoint(o.point, o.relativeTo or button:GetParent() or UIParent,
        o.relativePoint or o.point, o.x or 0, o.y or 0)
    end

    button:Show()
    if def.refresh then RefreshButton(button) end
  end

  for i = 1, total do
    restore(ButtonName(def, i))
    if def.mirror then restore(string.format(def.mirror, i)) end
  end

  bounds[key] = nil

  -- db[key] is gone, so this resolves to the shipped artwork
  if key == "MainMenuBar" then SyncMainBarArt() end
end

--[[ profiles ---------------------------------------------------------------]]

-- Bar shapes as an Edit Mode layout profile stores them. Only bars that have
-- actually been reshaped appear; one left at its shipped shape has no entry, so
-- a profile says nothing about it and Restore puts it back to default.
BarLayout.Snapshot = function()
  local copy = {}
  if not db then return copy end

  for key, saved in pairs(db) do
    if bars[key] then
      copy[key] = {
        count = saved.count,
        columns = saved.columns,
        vertical = saved.vertical,
      }
    end
  end

  return copy
end

-- Replace every bar shape at once. Bars absent from `shapes` go back to the
-- shape they ship in - a profile that does not mention a bar means "default",
-- not "leave whatever the last profile did to it".
BarLayout.Restore = function(shapes)
  if not db then return end

  for key in pairs(bars) do
    if not (shapes and shapes[key]) then BarLayout.Reset(key) end
  end

  if shapes then
    for key, saved in pairs(shapes) do
      if bars[key] then
        db[key] = {
          count = saved.count,
          columns = saved.columns,
          vertical = saved.vertical,
        }
      end
    end
  end

  BarLayout.ApplyAll()
end

--[[ module enable ----------------------------------------------------------]]

module.enable = function(self)
  tDFUI_config = tDFUI_config or {}
  tDFUI_config["BarLayoutDB"] = tDFUI_config["BarLayoutDB"] or {}
  db = tDFUI_config["BarLayoutDB"]

  tDF_BarLayout = BarLayout

  -- Repaints every shaped bar's buttons one frame after a layout change, then
  -- hides itself again. A button the game had hidden does not always take its
  -- new paint in the same frame it is shown in.
  repaint = CreateFrame("Frame", nil, UIParent)
  repaint:Hide()
  repaint:SetScript("OnUpdate", function()
    this:Hide()

    for key, def in pairs(bars) do
      if def.refresh and db[key] then
        for i = 1, ButtonCount(def) do
          local button = _G[ButtonName(def, i)]
          if button and button:IsShown() then RefreshButton(button) end
        end
      end
    end
  end)

  -- The micro menu builds its buttons inside its own module's enable, and
  -- main.lua enables modules in pairs() order, so the buttons may not exist
  -- yet. Retry a few times after login rather than assuming they are there.
  tDFUI.RetryAfterLogin(3, BarLayout.ApplyAll)

  -- Blizzard re-shows the multibar buttons whenever bar visibility changes
  tDFUI.hooksecurefunc("MultiActionBar_Update", function()
    BarLayout.ApplyAll()
  end, true)

  BarLayout.ApplyAll()
end
