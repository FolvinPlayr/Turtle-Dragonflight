local _G = tDFUI.GetGlobalEnv()
local T = tDFUI.T

local module = tDFUI:register({
  title = T["Whisper Tabs"],
  description = T["Gives every player who whispers you their own docked chat tab, WIM style, holding that one conversation plus system messages. Vanilla only has room for five; anyone past that stays in normal chat with their name in blue."],
  expansions = { ["vanilla"] = true, ["tbc"] = true },
  category = T["Social & Chat"],
  enabled = true,
})

-- every one of these carries the conversation partner in arg2: the sender for
-- an incoming whisper, the recipient for everything else
local whisper_events = {
  ["CHAT_MSG_WHISPER"] = true,
  ["CHAT_MSG_WHISPER_INFORM"] = true,
  ["CHAT_MSG_AFK"] = true,
  ["CHAT_MSG_DND"] = true,
  ["CHAT_MSG_IGNORED"] = true,
}

local windows = NUM_CHAT_WINDOWS or 7

-- name of whoever is whispering from normal chat because no tab was free,
-- set only for the length of one message
local overflow_color = "|cff40c0ff"

-- lowercased player name -> chat frame
local tabs = {}

local original_OnEvent
local tinting

local function IsSpokenFor(frame)
  -- never touch the general or combat log windows
  return frame == DEFAULT_CHAT_FRAME or frame == _G["ChatFrame2"]
end

-- a docked tab that simply is not the selected one is hidden but very much
-- still in use, so isDocked has to be part of the answer. anything else is a
-- window the player has closed, and a closed window is free again no matter
-- what name is still hanging off it.
local function InUse(frame)
  return frame.isDocked or frame:IsShown()
end

-- a chat window a previous session already named after this player. chat
-- layout is saved between sessions, so conversations keep their old tab.
local function FindWindow(player)
  local wanted = strlower(player)
  for i = 1, windows do
    local frame = _G["ChatFrame" .. i]
    local name = GetChatWindowInfo(i)
    if frame and not IsSpokenFor(frame) and InUse(frame)
      and name and strlower(name) == wanted then
      return frame
    end
  end
end

local function FreeWindow()
  for i = 1, windows do
    local frame = _G["ChatFrame" .. i]
    if frame and not IsSpokenFor(frame) and not InUse(frame) then
      return frame
    end
  end
end

-- strip the tab down to one conversation: no channels, no message groups
-- except the system messages we deliberately want alongside the whispers.
-- WHISPER goes back on so the tab counts as a whisper window as far as the
-- default UI is concerned; the filtering to a single player is ours, and the
-- suppression below stops the tab printing the message a second time.
local function Prepare(frame)
  if ChatFrame_RemoveAllMessageGroups then ChatFrame_RemoveAllMessageGroups(frame) end
  if ChatFrame_RemoveAllChannels then ChatFrame_RemoveAllChannels(frame) end
  ChatFrame_AddMessageGroup(frame, "SYSTEM")
  ChatFrame_AddMessageGroup(frame, "WHISPER")
end

-- returns nil when every window is spoken for. vanilla has NUM_CHAT_WINDOWS
-- frames and two of those are General and the combat log, so five whisper
-- tabs is the ceiling; past that the caller falls back to normal chat rather
-- than stealing a tab out from under a conversation that is still going.
-- FCF_OpenNewWindow will only take a window it regards as untouched, so a
-- slot the player has closed and freed up can still be refused. bring one
-- back by hand when that happens, using the calls the chat UI uses itself.
local function Revive(frame, player)
  local id = frame:GetID()

  FCF_SetWindowName(frame, player)
  frame:Clear()

  if FCF_DockFrame then
    local index = 2
    if FCF_GetNumActiveChatFrames then index = FCF_GetNumActiveChatFrames() + 1 end
    FCF_DockFrame(frame, index)
  end

  frame:Show()

  local tab = _G["ChatFrame" .. id .. "Tab"]
  if tab then tab:Show() end

  if SetChatWindowShown then SetChatWindowShown(id, 1) end
end

local function OpenTab(player)
  local frame = FindWindow(player)
  if frame then
    Prepare(frame)
    return frame
  end

  local free = FreeWindow()
  if not free then return end

  -- remember which tab the player was reading, opening a window selects it
  local selected = SELECTED_DOCK_FRAME

  if FCF_OpenNewWindow then FCF_OpenNewWindow(player) end

  frame = FindWindow(player)
  if not frame then
    Revive(free, player)
    frame = FindWindow(player)
  end

  if selected and FCF_SelectDockFrame then FCF_SelectDockFrame(selected) end

  if frame then
    Prepare(frame)
    return frame
  end
end

-- idempotent: the first caller in an event creates the tab, later callers in
-- the same event get the same one back. keeps returning nil while the windows
-- are full, and picks a tab up later if one is freed mid-session.
local function Resolve(player)
  if not player or player == "" then return end

  local key = strlower(player)
  local frame = tabs[key]

  -- the tab may have been closed since we last used it. hold on to it and
  -- every further whisper would be drawn into a window nobody can see.
  if frame and not InUse(frame) then
    tabs[key] = nil
    frame = nil
  end

  if not frame then
    frame = OpenTab(player)
    if not frame then return end
    tabs[key] = frame
  end

  return frame
end

-- recolours the [Name] label inside the player link the stock handler just
-- built, leaving the link itself intact so it still opens the whisper menu
local function TintAddMessage(frame, text, a1, a2, a3, a4, a5)
  if tinting and text then
    local link = "|Hplayer:" .. tinting .. "|h"
    text = gsub(text, link .. "%[" .. tinting .. "%]|h",
      link .. overflow_color .. "[" .. tinting .. "]|r|h")
  end
  return frame.tDFWhisperAddMessage(frame, text, a1, a2, a3, a4, a5)
end

-- run the stock handler against the frame we picked rather than the one the
-- event was dispatched to, so the message is formatted, coloured, hyperlinked
-- and flashed exactly the way the default UI would have done it. tint is the
-- player name to paint blue, set only for whispers that could not get a tab.
local function Deliver(frame, event, tint)
  local previous = this
  this = frame

  -- wrapping AddMessage for this one call keeps us outermost, whatever else
  -- has hooked it. the guard stops a frame ever chaining into itself.
  local restore
  if tint and frame.AddMessage and frame.AddMessage ~= TintAddMessage then
    restore = frame.AddMessage
    tinting = tint
    -- left in place on purpose. should the handler below ever error out
    -- before we restore, a still-wrapped frame keeps working off this instead
    -- of losing its AddMessage and taking the whole chat frame down with it.
    frame.tDFWhisperAddMessage = restore
    frame.AddMessage = TintAddMessage
  end

  original_OnEvent(event)

  if restore then
    frame.AddMessage = restore
    tinting = nil
  end
  this = previous
end

-- nobody could be given a tab, so put them in front of the player wherever
-- they happen to be looking: every chat window in use, tabs included. the
-- blue name is what keeps them apart from whoever owns the tab being read.
-- the combat log is left out, being a log rather than a conversation.
local function Broadcast(event, player)
  local delivered

  for i = 1, windows do
    local frame = _G["ChatFrame" .. i]
    if frame and frame ~= _G["ChatFrame2"]
      and (frame.isDocked or frame:IsShown()) then
      Deliver(frame, event, player)
      delivered = true
    end
  end

  -- nothing looked like it was in use, so fall back to the one window that
  -- always is rather than swallowing the message
  if not delivered then Deliver(DEFAULT_CHAT_FRAME, event, player) end
end

-- replaces ChatFrame_OnEvent. whisper traffic is dropped from every chat
-- frame here without exception, including our own tabs, and the listener
-- below is the single thing that decides where it actually goes. that keeps
-- one conversation out of another conversation's tab.
local function SuppressWhispers(event)
  if whisper_events[event] and arg2 and arg2 ~= "" then return end
  return original_OnEvent(event)
end

module.enable = function(self)
  -- fail here, where register() catches it and /tdf reports it, rather than
  -- erroring once per whisper for the rest of the session
  assert(GetChatWindowInfo and FCF_OpenNewWindow and FCF_SetWindowName
    and ChatFrame_AddMessageGroup, "chat window API is missing")

  original_OnEvent = ChatFrame_OnEvent
  ChatFrame_OnEvent = SuppressWhispers

  -- our own listener is the single point that prints a whisper. a chat frame
  -- would only be called when it happens to be registered for the event, and
  -- a tab created mid-dispatch would miss the very message that created it.
  local listener = CreateFrame("Frame")
  for name in pairs(whisper_events) do
    listener:RegisterEvent(name)
  end

  listener:SetScript("OnEvent", function()
    local player = arg2
    if not player or player == "" then return end

    local frame = Resolve(player)
    if frame then
      Deliver(frame, event)
    else
      Broadcast(event, player)
    end
  end)
end
