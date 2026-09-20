-- Minimal WoW 1.12 API stub, enough to load and exercise tEditMode / tBarLayout.
-- Run with lua55; shims the 5.0-isms the addon relies on.

table.getn = function(t) return #t end
table.insert = table.insert
math.mod = function(a, b) return a % b end
if not unpack then unpack = table.unpack end
strlower = string.lower
tinsert = table.insert
date = os.date

local frames = {}

local FrameMT = {}

local function noop() end

local geometry = {
  GetLeft = function(f) return f._x end,
  GetRight = function(f) return f._x + f._w end,
  GetTop = function(f) return f._y end,
  GetBottom = function(f) return f._y - f._h end,
  GetWidth = function(f) return f._w end,
  GetHeight = function(f) return f._h end,
  SetWidth = function(f, v) f._w = v end,
  SetHeight = function(f, v) f._h = v end,
  GetScale = function(f) return f._scale end,
  SetScale = function(f, v) f._scale = v end,
  GetEffectiveScale = function(f)
    local s, p = f._scale, f._parent
    while p do
      if type(p) ~= "table" then
        error("bad parent: frame " .. tostring(f._name) .. " (" ..
          tostring(f._kind) .. ") has a " .. type(p) .. " parent")
      end
      s = s * p._scale
      p = p._parent
    end
    return s
  end,
  GetAlpha = function(f) return f._alpha end,
  SetAlpha = function(f, v) f._alpha = v end,
  GetParent = function(f) return f._parent end,
  GetName = function(f) return f._name end,
  IsShown = function(f) return f._shown end,
  IsVisible = function(f) return f._shown end,
  Show = function(f)
    if f._shown then return end
    f._shown = true
    local h = f._scripts.OnShow
    if h then local prev = this; this = f; h(); this = prev end
  end,
  Hide = function(f)
    if not f._shown then return end
    f._shown = nil
    local h = f._scripts.OnHide
    if h then local prev = this; this = f; h(); this = prev end
  end,
  GetPoint = function(f) local p = f._point; if not p then return nil end
    return p[1], p[2], p[3], p[4], p[5] end,
  SetPoint = function(f, a, b, c, d, e) f._point = { a, b, c, d, e } end,
  ClearAllPoints = function(f) f._point = nil end,
  GetText = function(f) return f._text or "" end,
  SetText = function(f, v) f._text = v end,
  GetValue = function(f) return f._value or 0 end,
  SetValue = function(f, v)
    f._value = v
    local h = f._scripts and f._scripts.OnValueChanged
    if h then local prev = this; this = f; h(); this = prev end
  end,
  GetChecked = function(f) return f._checked end,
  SetChecked = function(f, v) f._checked = v end,
  SetScript = function(f, k, v) f._scripts[k] = v end,
  GetScript = function(f, k) return f._scripts[k] end,
  RegisterEvent = function(f, e) f._events[e] = true end,
  GetRegions = function(f) return unpack(f._regions) end,
  GetNormalTexture = function(f) return f._normal end,
}

-- Widget methods the addon calls whose behaviour does not matter here. Listed
-- explicitly rather than caught by a wildcard, so that an ARBITRARY field the
-- addon parks on a frame (o.item, grid.lines, slider.caption) still reads back
-- as nil when unset instead of as a stray no-op function.
for _, name in ipairs({
  "ClearFocus", "EnableKeyboard", "EnableMouse", "EnableMouseWheel",
  "RegisterForClicks", "RegisterForDrag", "SetAllPoints", "SetAutoFocus",
  "SetBackdrop", "SetBackdropBorderColor", "SetBackdropColor",
  "SetFrameStrata", "SetJustifyH", "SetMinMaxValues", "SetMovable",
  "SetOwner", "SetTexCoord", "SetTexture", "SetUserPlaced", "SetValueStep",
  "StartMoving", "StopMovingOrSizing", "AddLine", "SetID", "SetFont",
  "UnregisterAllEvents", "SetNormalTexture", "GetVertexColor",
  "SetVertexColor", "GetObjectType", "SetFrameLevel", "SetHitRectInsets",
}) do
  geometry[name] = noop
end

FrameMT.__index = function(f, key)
  return geometry[key]
end

local function NewFrame(kind, name, parent, template)
  local f = setmetatable({
    _name = name, _parent = parent, _kind = kind, _template = template,
    _x = 100, _y = 400, _w = 120, _h = 40,
    _scale = 1, _alpha = 1, _shown = true,
    _scripts = {}, _events = {}, _regions = {},
  }, FrameMT)

  if name then
    _G[name] = f
    -- OptionsSliderTemplate / OptionsCheckButtonTemplate fontstrings
    if template == "OptionsSliderTemplate" then
      _G[name .. "Text"] = NewFrame("FontString", nil, f)
      _G[name .. "Low"] = NewFrame("FontString", nil, f)
      _G[name .. "High"] = NewFrame("FontString", nil, f)
    elseif template == "OptionsCheckButtonTemplate" then
      _G[name .. "Text"] = NewFrame("FontString", nil, f)
    end
  end

  table.insert(frames, f)
  return f
end

function CreateFrame(kind, name, parent, template)
  return NewFrame(kind, name, parent, template)
end

geometry.CreateFontString = function(f) return NewFrame("FontString", nil, f) end
geometry.CreateTexture = function(f)
  local t = NewFrame("Texture", nil, f)
  table.insert(f._regions, t)
  return t
end

UIParent = NewFrame("Frame", "UIParent", nil)
UIParent._w, UIParent._h = 1920, 1080
UIParent._x, UIParent._y = 0, 1080
WorldFrame = NewFrame("Frame", "WorldFrame", nil)
GameTooltip = NewFrame("Frame", "GameTooltip", UIParent)
GameMenuFrame = NewFrame("Frame", "GameMenuFrame", UIParent)

DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) print("  [chat] " .. tostring(m)) end }
UISpecialFrames = {}
SlashCmdList = {}

function IsShiftKeyDown() return nil end
function GetLocale() return "enUS" end
function GetBuildInfo() return "1.12.1", "5875", "Jan 1 2006", 11200 end
function IsAddOnLoaded() return nil end
function UIParent_ManageFramePositions() end
function ActionButton_Update() end
function MultiActionBar_Update() end
TOOLTIP_UPDATE_TIME = 0.2

-- frames the registry and the bar tables look for
local wanted = {
  "PlayerFrame", "TargetFrame", "PetFrame", "MainMenuBar", "MultiBarBottomLeft",
  "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft", "ShapeshiftBarFrame",
  "PetActionBarFrame", "MainMenuExpBar", "QuestWatchFrame", "MinimapCluster",
  "ChatFrame1", "ChatFrame2", "CastingBarFrame", "DurabilityFrame",
  "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
  "CharacterBag3Slot", "KeyRingButton", "MainMenuBarBackpackButton",
  "MainMenuBarArtFrame", "MainMenuBarTexture0", "BuffButton0", "TempEnchant1",
}
for _, n in ipairs(wanted) do NewFrame("Frame", n, UIParent) end

-- tDF frames
for _, n in ipairs({ "tDFbagMain", "tDFmicrobutton", "xpbar", "repbar" }) do
  local f = NewFrame("Frame", n, UIParent)
  _G[n] = f
end
MainMenuBar._w, MainMenuBar._h = 512, 60

-- buttons the bar layout reshapes
for i = 1, 12 do
  for _, pat in ipairs({ "ActionButton%d", "BonusActionButton%d",
    "MultiBarBottomLeftButton%d", "MultiBarBottomRightButton%d",
    "MultiBarRightButton%d", "MultiBarLeftButton%d" }) do
    local b = NewFrame("Button", string.format(pat, i), MainMenuBar)
    b._w, b._h = 36, 36
    b._x, b._y = 100 + (i - 1) * 42, 80
  end
end
for i = 1, 10 do
  NewFrame("Button", "ShapeshiftButton" .. i, ShapeshiftBarFrame)
  NewFrame("Button", "PetActionButton" .. i, PetActionBarFrame)
end
for _, n in ipairs({ "tDFbag1", "tDFbag2", "tDFbag3", "tDFbag4", "tDFbagKeys" }) do
  NewFrame("Button", n, tDFbagMain)
end
for _, n in ipairs({ "mbHelp", "mbMainMenu", "mbPvP", "mbShop", "mbLFT", "mbEBC",
  "mbWorldMap", "mbSocials", "mbQuestLog", "mbTalent", "mbSpellBook",
  "mbCharacter" }) do
  NewFrame("Button", n, tDFmicrobutton)
end

tDFActionBarArt = { MainMenuBar = { left = NewFrame("Frame", nil, MainMenuBar),
  right = NewFrame("Frame", nil, MainMenuBar) } }
tDFGryphons = { left = NewFrame("Texture", nil, MainMenuBar),
  right = NewFrame("Texture", nil, MainMenuBar) }

-- the addon's own bootstrap, condensed from main.lua / helpers.lua
tDFUI = setmetatable({}, { __index = function() return function() end end })
tDFUI.mods = {}
tDFUI.errors = {}
tDFUI.T = setmetatable({}, { __index = function(t, k) rawset(t, k, k); return k end })
tDFUI.GetGlobalEnv = function() return _G end
tDFUI.GetExpansion = function() return "vanilla" end
tDFUI.register = function(self, mod) tDFUI.mods[mod.title] = mod; return mod end
tDFUI.Print = function(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff008000t|cff1974d2DF|r: " .. tostring(msg))
end
tDFUI.HookScript = function(f, script, func)
  local ok, prev = pcall(f.GetScript, f, script)
  if not ok then return end
  f:SetScript(script, function(...)
    if prev then prev(...) end
    func(...)
  end)
end

retries = {}
tDFUI.RetryAfterLogin = function(passes, func)
  table.insert(retries, { passes = passes, func = func })
end

local hooked = {}
tDFUI.hooksecurefunc = function(name, func, append)
  local old = _G[name]
  if not old then return end
  _G[name] = function(...)
    if append then old(...); func(...) else func(...); old(...) end
  end
  table.insert(hooked, name)
end

tDFUI.IsPlaced = function(name)
  if tDF_EditMode and tDF_EditMode.IsPlaced then return tDF_EditMode.IsPlaced(name) end
end

tDFUI_config = {}
this, event, arg1 = nil, nil, nil

--[[ run ]]--

-- the addon folder, resolved from this script's own path so the harness runs
-- from anywhere:  lua tests-editmode.lua
local root = (arg and arg[0] and string.match(arg[0], "^(.*[/\\])")) or ""

local function load(path)
  local chunk, err = loadfile(root .. path)
  if not chunk then error("load " .. path .. ": " .. tostring(err)) end
  chunk()
end

local function step(label, fn)
  local ok, err = pcall(fn)
  print((ok and "  ok   " or "  FAIL ") .. label .. (ok and "" or "  ->  " .. tostring(err)))
  if not ok then FAILED = true end
end

print("== load ==")
step("tBarLayout.lua parses and registers", function() load("mods/tBarLayout.lua") end)
step("tEditMode.lua parses and registers", function() load("mods/tEditMode.lua") end)

print("== enable ==")
step("Bar Layout enable", function() tDFUI.mods["Bar Layout"].enable() end)
step("Edit Mode enable", function() tDFUI.mods["Edit Mode"].enable() end)

print("== retry loop (the post-login passes) ==")
step("retry passes run", function()
  for _, r in ipairs(retries) do
    for _ = 1, r.passes do r.func() end
  end
end)

print("== open / edit / close ==")
step("Open", function() tDF_EditMode.Open() end)
step("Apply", function() tDF_EditMode.Apply() end)

step("select + move an element", function()
  local o
  for _, f in ipairs(frames) do
    if f.item and f.item.key == "MainMenuBar" then o = f break end
  end
  if not o then error("no overlay for MainMenuBar") end

  local prev = this
  this = o
  o._scripts.OnDragStart()
  this = prev

  -- the real drag runs through the manager's OnUpdate, a frame at a time
  for _ = 1, 10 do
    o._x, o._y = o._x + 6, o._y + 2
    this, arg1 = tDFEditModeManager, 0.016
    tDFEditModeManager._scripts.OnUpdate()
    this, arg1 = prev, nil
  end

  this = o
  o._scripts.OnDragStop()
  this = prev
end)

step("MainMenuBar is now placed", function()
  if not tDF_EditMode.IsPlaced("MainMenuBar") then error("IsPlaced false after drag") end
end)

step("clamp rescues an offscreen frame", function()
  local db = tDFUI_config["EditModeDB"]
  db.frames["MultiBarBottomLeft"] = { x = 9000, y = 9000 }
  tDF_EditMode.Apply()
  local f = MultiBarBottomLeft
  if f:GetLeft() >= UIParent:GetWidth() then
    error("left still offscreen: " .. f:GetLeft())
  end
end)

step("reshape a bar", function()
  tDF_BarLayout.Set("MainMenuBar", "count", 6)
  tDF_BarLayout.Set("MainMenuBar", "columns", 3)
end)

step("bar shape survives ApplyAll", function()
  tDF_BarLayout.ApplyAll()
  local l = tDF_BarLayout.Get("MainMenuBar")
  if l.count ~= 6 or l.columns ~= 3 then
    error("shape lost: " .. l.count .. "/" .. l.columns)
  end
end)

step("save profile", function() tDF_EditModeCommand("") ; tDF_editProfiles = tDF_editProfiles or {} end)

step("profile round trip carries bar shape", function()
  local SaveLoad = tDF_EditMode
  -- drive through the slash verbs the panel also uses
  local db = tDFUI_config["EditModeDB"]
  tDF_editProfiles["test"] = {
    frames = { MainMenuBar = { x = 300, y = 500 } },
    bars = { MainMenuBar = { count = 4, columns = 2, vertical = 0 } },
  }
  tDF_EditModeCommand("load test")
  local l = tDF_BarLayout.Get("MainMenuBar")
  if l.count ~= 4 or l.columns ~= 2 then
    error("profile did not restore shape: " .. l.count .. "/" .. l.columns)
  end
  if not db.frames["MainMenuBar"] or db.frames["MainMenuBar"].x ~= 300 then
    error("profile did not restore position")
  end
end)

step("loading a profile clears what it omits", function()
  local db = tDFUI_config["EditModeDB"]
  db.frames["ChatFrame1"] = { x = 700, y = 700 }
  tDF_EditModeCommand("load test")
  if db.frames["ChatFrame1"] then error("stale entry survived profile load") end
end)

step("old format profile still loads", function()
  tDF_editProfiles["legacy"] = { ChatFrame1 = { x = 222, y = 333 } }
  tDF_EditModeCommand("load legacy")
  local db = tDFUI_config["EditModeDB"]
  if not db.frames["ChatFrame1"] or db.frames["ChatFrame1"].x ~= 222 then
    error("legacy profile not read")
  end
end)

step("reset all", function() tDF_EditModeCommand("reset") end)

step("reset really cleared the db", function()
  local db = tDFUI_config["EditModeDB"]
  for k, e in pairs(db.frames) do
    if e.x then error("entry survived reset: " .. k) end
  end
end)

step("Close", function() tDF_EditMode.Close() end)

step("closing took the overlays down", function()
  if tDFEditModeManager:IsShown() then error("manager still shown after Close") end
end)

step("hiding the panel alone also tears down", function()
  tDF_EditMode.Open()
  tDFEditModePanel:Hide()          -- what UISpecialFrames does
  if tDFEditModeManager:IsShown() then
    error("manager stranded when the panel was hidden directly")
  end
end)

step("toggle back open and closed", function()
  tDF_EditMode_Toggle()
  tDF_EditMode_Toggle()
end)

step("layout hook re-entry is safe", function()
  UIParent_ManageFramePositions()
  UIParent_ManageFramePositions()
end)

print("== regressions for the specific bugs fixed ==")

local function visual(f)
  return f:GetEffectiveScale() / UIParent:GetEffectiveScale()
end

step("a passenger keeps its size when its parent is scaled", function()
  tDF_EditModeCommand("reset")

  local child = MainMenuBarBackpackButton      -- NOT in the registry
  local before = visual(child)

  local db = tDFUI_config["EditModeDB"]
  db.frames["MainMenuBar"] = { scale = 1.5 }
  tDF_EditMode.Apply()

  local after = visual(child)
  if math.abs(after - before) > 0.001 then
    error(string.format("passenger visual scale drifted %.3f -> %.3f", before, after))
  end
end)

step("...and a module's own scale is not flattened to 1", function()
  tDF_EditModeCommand("reset")

  -- another module scales this during login, after Edit Mode's enable ran
  local child = CharacterBag0Slot
  child._scale = 0.8
  local before = visual(child)

  -- the post-login retry passes are where that gets noticed
  for _, r in ipairs(retries) do
    for _ = 1, r.passes do r.func() end
  end

  if math.abs(visual(child) - before) > 0.001 then
    error(string.format("passenger scale stomped %.3f -> %.3f", before, visual(child)))
  end
end)

step("clamp still applies to a registry+independent frame", function()
  local db = tDFUI_config["EditModeDB"]
  db.frames["ShapeshiftBarFrame"] = { x = -9000, y = -9000 }
  tDF_EditMode.Apply()

  local f = ShapeshiftBarFrame
  if f:GetRight() <= 0 then error("still off the left edge: " .. f:GetRight()) end
  if f:GetTop() <= 0 then error("still below the screen: " .. f:GetTop()) end
end)

step("right-to-left bars report no bounds", function()
  tDF_BarLayout.Set("tDFmicrobutton", "columns", 6)
  if tDF_BarLayout.Bounds("tDFmicrobutton") then
    error("micro menu reported bounds; its overlay would be drawn at the wrong end")
  end
  tDF_BarLayout.Set("tDFbagMain", "columns", 2)
  if tDF_BarLayout.Bounds("tDFbagMain") then error("bag bar reported bounds") end
end)

step("a reshaped bar DOES report bounds", function()
  tDF_BarLayout.Set("MultiBarBottomLeft", "columns", 6)
  local w, h = tDF_BarLayout.Bounds("MultiBarBottomLeft")
  if not w or not h then error("no bounds for a reshaped left-to-right bar") end
end)

step("attach cycle does not recurse forever", function()
  -- force one, the way a future registry edit might
  local xp = nil
  for _, f in ipairs(frames) do
    if f.item and f.item.key == "xpbar" then xp = f.item end
  end
  if xp then
    local exp = nil
    for _, f in ipairs(frames) do
      if f.item and f.item.key == "MainMenuExpBar" then exp = f.item end
    end
    if exp then exp.attach = { "xpbar" } end
  end
  tDF_EditModeCommand("reset")
end)

step("bar shapes survive a Blizzard layout pass", function()
  tDF_BarLayout.Set("MainMenuBar", "count", 8)
  tDF_BarLayout.Set("MainMenuBar", "columns", 4)
  UIParent_ManageFramePositions()
  tDF_BarLayout.ApplyAll()

  local l = tDF_BarLayout.Get("MainMenuBar")
  if l.count ~= 8 or l.columns ~= 4 then
    error("shape lost across a layout pass: " .. l.count .. "/" .. l.columns)
  end
end)

step("slash verbs all run", function()
  for _, verb in ipairs({ "list", "close", "reset", "lock", "", "load nope" }) do
    tDF_EditModeCommand(verb)
  end
end)

print(FAILED and "\nRESULT: failures above" or "\nRESULT: all steps passed")
