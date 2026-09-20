-- Radio panel for the micro menu.
--
-- READ THIS BEFORE CHANGING ANYTHING HERE
--
-- The radio is the CLIENT's. It ships inside a patch MPQ, so there is no
-- source to read -- everything below was dumped from a running session with
-- /tdf radio probe. An addon cannot play the stream itself: 1.12 Lua has no
-- networking, and PlayMusic()/PlaySoundFile() resolve paths through the
-- client's file/MPQ layer, so neither can take a URL.
--
-- What the client exposes:
--
--   EBCMinimapDropdown                 its own panel, 205x130
--     EBCMinimapDropdownCheckButton    station 1, has an OnClick
--     EBCMinimapDropdownCheckButton2   station 2, has an OnClick
--     EBCMinimapDropdownSlider         volume 0..100, has an OnValueChanged
--     EBCMinimapDropdownMuteButton     mute, a Frame with an OnMouseDown
--   EBC_TITLE, EBC_STATION1/2, EBC_STOPPED, EBC_TUNEDINTO  -- plain strings
--
-- The client's own panel CANNOT be shown from here. Ten logged attempts all
-- ended "still hidden": the frame has no OnShow/OnUpdate/OnHide of its own to
-- park, every call in the show path succeeded, and IsVisible() was still nil
-- straight after Show() -- so the client overrides its visibility somewhere
-- we cannot reach. Don't spend another evening on it.
--
-- Its child widgets, though, respond to code perfectly: clicking a station
-- checkbutton from a script tunes the radio and the music plays. So this file
-- draws its own panel and drives those widgets. The client keeps ownership of
-- stations, volume and playback; we own nothing but the buttons you see.
--
-- Two stations is all the client has -- they are hardcoded, one checkbutton
-- each, so there is no third station to add.
--
-- We do not touch WoW's sound CVars. An earlier version pointed its own
-- slider at "MusicVolume", set it to 0 and silenced the client radio along
-- with the game. The slider here drives EBCMinimapDropdownSlider -- the
-- radio's volume, not the game's. Don't reintroduce the old behaviour.

local _G = tDFUI.GetGlobalEnv()

local Print = tDFUI.Print

local function Now()
  local ok, stamp = pcall(date, "%Y-%m-%d %H:%M:%S")
  if ok and stamp then return stamp end
  return "uptime " .. tostring(GetTime())
end

-- --------------------------------------------------------------- rebranding
--
-- This client is a Turtle fork, so its radio still ships under Turtle's name
-- and Turtle's tower names. Renaming the globals covers both our panel and
-- the client's own chat lines, because those are formatted from these values
-- at the moment they are printed ("You stop listening to %s for now.").

local renames = {
  EBC_TITLE    = "Booty Bay Pirate Radio",
  EBC_STATION1 = "BBPR Music Tower",
  EBC_STATION2 = "BBPR Thematic Tower",
}

local function ApplyRenames()
  for name, value in pairs(renames) do
    if type(getglobal(name)) == "string" then setglobal(name, value) end
  end
end

-- The safety net for anything the rename can't reach: a client that copied a
-- string into a local at load time would still print the old name. Rewriting
-- on the way into the chat frame catches those too, which is what "any and
-- all mentions" needs. Both plain finds run before any gsub, so ordinary
-- chat traffic costs two string searches and nothing else.
local chat_rewrites = {
  { "Everlook Broadcasting Co%.", "Booty Bay Pirate Radio" },
  { "Everlook Broadcasting", "Booty Bay Pirate Radio" },
  { "Everlook Radio", "Booty Bay Pirate Radio" },
  { "Broadcasting Tower NX78", "BBPR Music Tower" },
  { "Broadcasting Tower LG87", "BBPR Thematic Tower" },
}

local function RewriteRadioText(text)
  if type(text) ~= "string" then return text end
  if not (strfind(text, "Everlook", 1, true) or
          strfind(text, "Broadcasting Tower", 1, true)) then
    return text
  end
  for i = 1, table.getn(chat_rewrites) do
    text = string.gsub(text, chat_rewrites[i][1], chat_rewrites[i][2])
  end
  return text
end

local function HookChatFrames()
  local count = NUM_CHAT_WINDOWS or 7
  for i = 1, count do
    local frame = getglobal("ChatFrame" .. i)
    if frame and not frame.tDF_radio_hooked then
      frame.tDF_radio_hooked = true
      local original = frame.AddMessage
      frame.AddMessage = function(self, text, r, g, b, id)
        return original(self, RewriteRadioText(text), r, g, b, id)
      end
    end
  end
end

-- ------------------------------------------------------- the client's radio

-- 100 is a hard ceiling, not a conservative default. The client's volume
-- slider writes WoW's "MusicVolume" CVar: with the slider at 100, Config.wtf
-- reads SET MusicVolume "1", so the scale is value/100 into a CVar the engine
-- clamps at 1.0. A slider that went to 200 therefore moved, wrote 2.0, and
-- was clamped straight back to full scale -- motion with no extra loudness.
--
-- There is no amplification anywhere in the 1.12 Lua API to route around it:
-- MasterVolume is the same 0..1 scale, and the stream is decoded by the
-- client, out of reach. If the radio is too quiet the lever is MasterVolume
-- in the game's own sound options, not this slider. Don't try 200 again.
local VOLUME_MAX = 100

-- Every lookup below is guarded: these frames belong to the client UI and can
-- be renamed or dropped by a client patch, and a missing one must leave the
-- panel working rather than erroring on open.
local function StationButton(index)
  if index == 1 then return EBCMinimapDropdownCheckButton end
  if index == 2 then return EBCMinimapDropdownCheckButton2 end
  return nil
end

local function VolumeSlider()
  return EBCMinimapDropdownSlider
end

local function MuteButton()
  return EBCMinimapDropdownMuteButton
end

-- Undo the widening an earlier build applied, so a session that ran it is
-- not left with a slider promising a boost it cannot deliver. Only a range
-- wider than ours is touched: whatever else a client patch might ship is
-- left alone.
local function NormalizeVolumeRange()
  local slider = VolumeSlider()
  if not slider then return nil end
  local ok, low, high = pcall(slider.GetMinMaxValues, slider)
  if ok and high and high > VOLUME_MAX then
    return pcall(slider.SetMinMaxValues, slider, low or 0, VOLUME_MAX)
  end
  return true
end

local function StationName(index)
  local name = getglobal("EBC_STATION" .. index)
  if type(name) == "string" and name ~= "" then return name end
  return "Station " .. index
end

local function RadioTitle()
  if type(EBC_TITLE) == "string" and EBC_TITLE ~= "" then return EBC_TITLE end
  return "Radio"
end

local function StationCount()
  local count = 0
  for i = 1, 2 do
    if StationButton(i) then count = count + 1 end
  end
  return count
end

local function IsTuned(index)
  local button = StationButton(index)
  if not button then return nil end
  local ok, checked = pcall(button.GetChecked, button)
  if ok then return checked end
  return nil
end

-- Click the client's own checkbutton rather than calling EBC_TuneIn(): the
-- OnClick is the path the client itself uses, so whatever bookkeeping it does
-- around tuning happens too.
local function TuneStation(index)
  local button = StationButton(index)
  if not button then return nil end
  local ok = pcall(button.Click, button)
  return ok
end

-- The mute control is a Frame with an OnMouseDown, not a Button, so there is
-- no Click() to call. Invoke the handler the way the client would: `this` is
-- the global the 1.12 API sets before running a script, so it has to be
-- pointed at the frame for the duration of the call and put back afterwards.
local function ToggleMute()
  local frame = MuteButton()
  if not frame then return nil end

  local ok, script = pcall(frame.GetScript, frame, "OnMouseDown")
  if not ok or not script then return nil end

  local previous_this = this
  this = frame
  local called = pcall(script)
  this = previous_this

  return called
end

local function GetRadioVolume()
  local slider = VolumeSlider()
  if not slider then return nil end
  local ok, value = pcall(slider.GetValue, slider)
  if ok and value then return math.floor(value + 0.5) end
  return nil
end

local function SetRadioVolume(value)
  local slider = VolumeSlider()
  if not slider then return nil end
  return pcall(slider.SetValue, slider, value)
end

-- ------------------------------------------------------------------ panel

local panel
local applying_volume

-- panel geometry, all in one place
local PAD          = 10   -- frame edge to content
local ROW_HEIGHT   = 20   -- one station row
local BOX_SIZE     = 18   -- checkbox
local TITLE_HEIGHT = 16
local GAP          = 6    -- last row to the slider label
local LABEL_HEIGHT = 13
local SLIDER_H     = 16
local VALUE_WIDTH  = 34   -- room for "200%"

local function UpdatePanel()
  if not panel then return end

  for i = 1, table.getn(panel.checks) do
    panel.checks[i]:SetChecked(IsTuned(i) and true or nil)
  end

  local volume = GetRadioVolume()
  if volume and panel.slider then
    applying_volume = true
    panel.slider:SetValue(volume)
    applying_volume = nil
    panel.slider_value:SetText(volume .. "%")
  end
end

local function CreatePanel()
  local count = StationCount()

  -- deliberately shadows the upvalue: the panel is only published to it once
  -- construction has finished, so a failure part way through can't leave a
  -- half-built frame behind for the next click to trip over
  local panel = CreateFrame("Frame", "tDF_RadioPanel", UIParent)
  if tDFmicrobutton then
    panel:SetPoint("BOTTOM", tDFmicrobutton, "TOP", 0, 8)
  else
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
  panel:SetFrameStrata("DIALOG")
  panel:EnableMouse(true)
  panel:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16,
    insets = { left = 5, right = 5, top = 5, bottom = 5 }
  })
  panel:Hide()
  table.insert(UISpecialFrames, "tDF_RadioPanel")

  panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + 2, -PAD)
  panel.title:SetText(RadioTitle())

  local top = PAD + TITLE_HEIGHT

  -- build the rows first and measure them, so the panel is sized to the text
  -- it actually holds instead of a hardcoded width with dead space in it
  local widest = panel.title:GetStringWidth() or 0

  panel.checks = {}
  for i = 1, count do
    local check = CreateFrame("CheckButton", "tDF_RadioCheck" .. i, panel, "OptionsCheckButtonTemplate")
    check:SetWidth(BOX_SIZE)
    check:SetHeight(BOX_SIZE)
    check:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -top - (i - 1) * ROW_HEIGHT)
    check.index = i
    check:SetScript("OnClick", function()
      TuneStation(this.index)
      UpdatePanel()
    end)

    local label = getglobal("tDF_RadioCheck" .. i .. "Text")
    label:SetFontObject("GameFontHighlightSmall")
    label:SetText(StationName(i))

    local width = BOX_SIZE + 4 + (label:GetStringWidth() or 0)
    if width > widest then widest = width end

    panel.checks[i] = check
  end

  local rows_bottom = top + count * ROW_HEIGHT

  -- the mute row, only when the client actually has one
  local mute_bottom = rows_bottom
  if MuteButton() then
    local mute = CreateFrame("Button", "tDF_RadioMute", panel, "UIPanelButtonTemplate")
    mute:SetHeight(ROW_HEIGHT - 2)
    mute:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -rows_bottom - 2)
    mute:SetText((type(EBC_MUTE) == "string" and EBC_MUTE) or "Mute")
    mute:SetScript("OnClick", function()
      ToggleMute()
      UpdatePanel()
    end)
    panel.mute = mute
    mute_bottom = rows_bottom + ROW_HEIGHT + 2
  end

  local panel_width = widest + PAD * 2 + 4
  if panel_width < 170 then panel_width = 170 end

  local slider_label_top = mute_bottom + GAP
  local slider_top       = slider_label_top + LABEL_HEIGHT

  panel:SetWidth(panel_width)
  panel:SetHeight(slider_top + SLIDER_H + PAD)
  if panel.mute then panel.mute:SetWidth(panel_width - PAD * 2) end

  local slider_label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  slider_label:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + 2, -slider_label_top)
  slider_label:SetText("Volume")

  local slider = CreateFrame("Slider", "tDF_RadioVolume", panel, "OptionsSliderTemplate")
  slider:SetWidth(panel_width - PAD * 2 - VALUE_WIDTH)
  slider:SetHeight(SLIDER_H)
  slider:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + 2, -slider_top)
  slider:SetMinMaxValues(0, VOLUME_MAX)
  slider:SetValueStep(1)
  getglobal("tDF_RadioVolumeLow"):SetText("")
  getglobal("tDF_RadioVolumeHigh"):SetText("")
  getglobal("tDF_RadioVolumeText"):SetText("")

  local slider_value = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  slider_value:SetPoint("LEFT", slider, "RIGHT", 8, 0)

  slider:SetScript("OnValueChanged", function()
    local value = math.floor(this:GetValue() + 0.5)
    slider_value:SetText(value .. "%")
    -- don't push the value back at the client when we are only syncing the
    -- slider's position to what the client already reports
    if not applying_volume then SetRadioVolume(value) end
  end)

  panel.slider_label = slider_label
  panel.slider = slider
  panel.slider_value = slider_value
  return panel
end

function tDF_ShowRadioMenu()
  if not StationButton(1) then
    Print("this client has no radio. |cffaaaaaaRun |cffffff00/tdf radio probe|r" ..
      "|cffaaaaaa then |cffffff00/rl|r|cffaaaaaa to log what it does have.|r")
    return
  end

  -- re-applied on every open: the client owns these and may reset them
  ApplyRenames()
  NormalizeVolumeRange()

  if not panel then panel = CreatePanel() end

  if panel:IsVisible() then
    panel:Hide()
    return
  end

  UpdatePanel()
  panel:Show()
end

-- Kept because tDefaultMicroMenu.lua and older macros call it.
function tDF_StopRadio()
  if panel then panel:Hide() end
end

-- --------------------------------------------------------------- the probe
--
-- Writes into tDF_radioProbe, a SavedVariable declared in the .toc. WoW
-- writes SavedVariables to
--   WTF/Account/<account>/SavedVariables/Turtle-Dragonflight.lua
-- on logout and on /rl, so it can be read off disk afterwards -- the chat
-- frame cannot be copied from, so printing is no use. Keep the contents to
-- plain strings, numbers and tables; the serialiser drops anything else.

local function EnsureProbe()
  if type(tDF_radioProbe) ~= "table" then tDF_radioProbe = {} end
  if type(tDF_radioProbe.lines) ~= "table" then tDF_radioProbe.lines = {} end
  -- experiment output lives in its own key. It used to go into `lines`, which
  -- the probe clears -- and the probe re-runs on every /rl, so flushing the
  -- log to disk was wiping the very thing it was flushing.
  if type(tDF_radioProbe.experiment) ~= "table" then tDF_radioProbe.experiment = {} end
end

local function Add(line)
  table.insert(tDF_radioProbe.lines, line)
end

local function AddExperiment(line)
  table.insert(tDF_radioProbe.experiment, line)
end

local function ObjectType(value)
  if type(value) ~= "table" then return nil end
  if type(value.GetObjectType) ~= "function" then return nil end
  local ok, kind = pcall(value.GetObjectType, value)
  if ok then return kind end
  return nil
end

local function ScriptList(widget)
  local names = { "OnClick", "OnShow", "OnHide", "OnUpdate", "OnMouseDown", "OnMouseUp", "OnValueChanged" }
  local found = {}
  for i = 1, table.getn(names) do
    if type(widget.GetScript) == "function" then
      local ok, script = pcall(widget.GetScript, widget, names[i])
      if ok and script then table.insert(found, names[i]) end
    end
  end
  if table.getn(found) == 0 then return "" end
  return " scripts=" .. table.concat(found, ",")
end

local function Describe(widget, indent, index)
  local name
  local ok, value = pcall(widget.GetName, widget)
  if ok and value then name = value else name = "<unnamed #" .. index .. ">" end

  local line = indent .. name .. " (" .. (ObjectType(widget) or "?") .. ")"

  if type(widget.GetText) == "function" then
    local ok2, text = pcall(widget.GetText, widget)
    if ok2 and text and text ~= "" then line = line .. " text=[" .. text .. "]" end
  end

  if ObjectType(widget) == "Slider" then
    local ok3, low, high = pcall(widget.GetMinMaxValues, widget)
    local ok4, current = pcall(widget.GetValue, widget)
    if ok3 then line = line .. " range=" .. tostring(low) .. ".." .. tostring(high) end
    if ok4 then line = line .. " value=" .. tostring(current) end
  end

  if type(widget.GetChecked) == "function" then
    local ok5, checked = pcall(widget.GetChecked, widget)
    if ok5 then line = line .. " checked=" .. tostring(checked) end
  end

  local ok6, shown = pcall(widget.IsVisible, widget)
  if ok6 then line = line .. " visible=" .. tostring(shown) end

  return line .. ScriptList(widget)
end

local function DescribeTree(frame, indent, depth)
  local ok, kids = pcall(function() return { frame:GetChildren() } end)
  if ok then
    for i = 1, table.getn(kids) do
      Add(Describe(kids[i], indent, i))
      if depth > 1 then DescribeTree(kids[i], indent .. "  ", depth - 1) end
    end
  end

  local okr, regions = pcall(function() return { frame:GetRegions() } end)
  if okr then
    for i = 1, table.getn(regions) do
      local region = regions[i]
      if type(region.GetText) == "function" then
        local okt, text = pcall(region.GetText, region)
        if okt and text and text ~= "" then
          local okn, rname = pcall(region.GetName, region)
          Add(indent .. "* " .. ((okn and rname) or "<unnamed>") .. " = [" .. text .. "]")
        end
      end
    end
  end
end

function tDF_ProbeRadio(quiet)
  EnsureProbe()

  tDF_radioProbe.lines = {}
  tDF_radioProbe.at = Now()

  Add("stations: " .. StationCount())
  for i = 1, 2 do
    if StationButton(i) then
      Add("  " .. i .. ". " .. StationName(i) .. " tuned=" .. tostring(IsTuned(i)))
    end
  end
  Add("volume: " .. tostring(GetRadioVolume()))
  local slider = VolumeSlider()
  if slider then
    local ok, low, high = pcall(slider.GetMinMaxValues, slider)
    if ok then Add("volume range: " .. tostring(low) .. ".." .. tostring(high)) end
  end
  Add("mute button: " .. (MuteButton() and "present" or "missing"))

  if EBCMinimapDropdown then
    Add("client panel tree:")
    DescribeTree(EBCMinimapDropdown, "  ", 4)
  end

  local names = {}
  for name, value in pairs(_G) do
    if type(name) == "string" and strfind(name, "EBC", 1, true) then
      local kind = type(value)
      if kind == "string" or kind == "number" or kind == "boolean" then
        table.insert(names, name .. " = [" .. tostring(value) .. "]")
      elseif kind == "function" then
        table.insert(names, name .. " = <function>")
      end
    end
  end
  table.sort(names)
  Add("EBC globals:")
  for i = 1, table.getn(names) do Add("  " .. names[i]) end

  if not quiet then
    Print("probe written (" .. table.getn(tDF_radioProbe.lines) .. " lines). " ..
      "|cffaaaaaaType |cffffff00/rl|r|cffaaaaaa to flush it to disk.|r")
  end
end

-- Opt-in, because it changes what the radio is doing.
function tDF_TestRadio()
  EnsureProbe()
  AddExperiment("experiment at " .. Now() .. ":")
  AddExperiment("  tuned before: 1=" .. tostring(IsTuned(1)) .. " 2=" .. tostring(IsTuned(2)))

  AddExperiment("  station1 click -> " .. tostring(TuneStation(1)))
  AddExperiment("  tuned after click: 1=" .. tostring(IsTuned(1)) .. " 2=" .. tostring(IsTuned(2)))

  if type(EBC_TuneIn) == "function" then
    local ok, err = pcall(EBC_TuneIn, "https://radio.turtle-music.org/stream")
    AddExperiment("  EBC_TuneIn(url) -> " .. (ok and "accepted" or ("rejected: " .. tostring(err))))
    local ok2, err2 = pcall(EBC_TuneIn, 1)
    AddExperiment("  EBC_TuneIn(1) -> " .. (ok2 and "accepted" or ("rejected: " .. tostring(err2))))
  else
    AddExperiment("  EBC_TuneIn is not a function")
  end

  AddExperiment("  tuned at end: 1=" .. tostring(IsTuned(1)) .. " 2=" .. tostring(IsTuned(2)))
  Print("experiment logged. |cffaaaaaaType |cffffff00/rl|r|cffaaaaaa to flush it to disk.|r")
end

-- Rename and widen as soon as the client's UI is up, so the new names are in
-- place before anything can print the old ones -- and probe once per session,
-- so a dump exists on disk even if nothing is typed.
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_ENTERING_WORLD")
loader:SetScript("OnEvent", function()
  loader:UnregisterEvent("PLAYER_ENTERING_WORLD")
  pcall(ApplyRenames)
  pcall(HookChatFrames)
  pcall(NormalizeVolumeRange)
  pcall(tDF_ProbeRadio, true)
end)

-- ---------------------------------------------------------------- commands

function tDF_RadioCommand(args)
  args = args or ""

  if strfind(args, "^test") then
    tDF_TestRadio()
    return
  end

  if strfind(args, "^probe") then
    tDF_ProbeRadio()
    return
  end

  DEFAULT_CHAT_FRAME:AddMessage("|cff008000Turtle |cff1974d2Dragonflight|r radio:")

  if StationButton(1) then
    for i = 1, 2 do
      if StationButton(i) then
        DEFAULT_CHAT_FRAME:AddMessage("  " .. i .. ". " .. StationName(i) ..
          (IsTuned(i) and "  |cffaaaaaa(tuned in)|r" or ""))
      end
    end
    DEFAULT_CHAT_FRAME:AddMessage("  Volume " .. tostring(GetRadioVolume()) ..
      "%. |cffaaaaaaOpen it with the radio button on the micro menu.|r")
  else
    DEFAULT_CHAT_FRAME:AddMessage("  |cffff5555No radio found on this client.|r")
  end

  DEFAULT_CHAT_FRAME:AddMessage("  |cffaaaaaa/tdf radio probe  |  /tdf radio test  " ..
    "-- both write to SavedVariables, flush with /rl|r")
end
