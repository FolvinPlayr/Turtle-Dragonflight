local _G = _G or getfenv(0)

SLASH_RELOAD1 = '/rl'
function SlashCmdList.RELOAD(msg, editbox) ReloadUI() end

message = function(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffffff00" .. ( msg or "nil" ))
end
print = message

-- route runtime lua errors to the chat frame. this used to overwrite the
-- global error() function, which silently turned every raised error into a
-- chat message and made real failures impossible to notice.
tDFUI_OnError = function(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000".. (msg or "nil" ))
end
seterrorhandler(tDFUI_OnError)

tDFUI = CreateFrame("Frame")
tDFUI.mods = {}
tDFUI.errors = {}

 -- load translation tables
 tDFUI.L = (tDFUI_locale[GetLocale()] or tDFUI_locale["enUS"])
 tDFUI.T = (tDFUI_translation[GetLocale()] or tDFUI_translation["enUS"])

 -- use table index key as translation fallback
 tDFUI.T = setmetatable(tDFUI.T, { __index = function(tab,key)
   local value = tostring(key)
   rawset(tab, key, value)
   return value
 end})

 tDFUI:RegisterEvent("VARIABLES_LOADED")
 tDFUI:SetScript("OnEvent", function()

   -- load current expansion
  local expansion = tDFUI:GetExpansion()

  -- initialize empty config
  if not tDFUI_config then tDFUI_config = {} end

  -- first pass: write the default config for every registered mod.
  -- this has to complete before anything is enabled. when defaults and
  -- enabling shared one loop, a single failing mod aborted the loop and
  -- every mod after it lost both its config entry and its options-menu
  -- checkbox, so it looked like those features had vanished entirely.
  for title, mod in pairs(tDFUI.mods) do
    if mod.hidden then
      -- infrastructure modules have no checkbox and are always on
      tDFUI_config[title] = 1
    elseif not tDFUI_config[title] then
      tDFUI_config[title] = mod.enabled and 1 or 0
    end
  end

  -- second pass: load enabled mods, each one isolated. a mod that errors
  -- now only disables itself and gets reported through /tdf.
  for title, mod in pairs(tDFUI.mods) do
    if mod.expansions[expansion] and tDFUI_config[title] == 1 then
      local ok, err = pcall(mod.enable, mod)
      if not ok then
        table.insert(tDFUI.errors, { title = title, err = err or "unknown error" })
      end
    end
  end

  local failed = table.getn(tDFUI.errors)
  if failed > 0 then
    tDFUI.Print(failed .. " module(s) failed to load. Type |cffffff00/tdf|r for details.")
  end
end)

tDFUI.register = function(self, mod)
  tDFUI.mods[mod.title] = mod
  return tDFUI.mods[mod.title]
end

-- /tdf - report which modules failed and why
SLASH_TDFUI1 = '/tdf'
SlashCmdList.TDFUI = function(msg)
  local _, _, subcommand, args = string.find(msg or "", "^%s*(%a+)%s*(.*)$")
  if subcommand and strlower(subcommand) == "radio" then
    tDF_RadioCommand(args)
    return
  end

  if subcommand and strlower(subcommand) == "edit" then
    if tDF_EditModeCommand then
      tDF_EditModeCommand(args)
    else
      tDFUI.Print("Edit Mode is not enabled.")
    end
    return
  end

  if subcommand and strlower(subcommand) == "dict" then
    if tDF_SpellcheckCommand then
      tDF_SpellcheckCommand(args)
    else
      tDFUI.Print("Chat Spellcheck is not loaded.")
    end
    return
  end

  local failed = table.getn(tDFUI.errors)

  DEFAULT_CHAT_FRAME:AddMessage("|cff008000Turtle |cff1974d2Dragonflight|r status:")

  if failed == 0 then
    DEFAULT_CHAT_FRAME:AddMessage("  |cff55ff55All enabled modules loaded successfully.|r")
  else
    for i = 1, failed do
      DEFAULT_CHAT_FRAME:AddMessage("  |cffff5555" .. tDFUI.errors[i].title .. "|r")
      DEFAULT_CHAT_FRAME:AddMessage("    |cffaaaaaa" .. tDFUI.errors[i].err .. "|r")
    end
  end

  local on, off = 0, 0
  for title, mod in pairs(tDFUI.mods) do
    if tDFUI_config and tDFUI_config[title] == 1 then on = on + 1 else off = off + 1 end
  end
  DEFAULT_CHAT_FRAME:AddMessage("  |cffaaaaaa" .. on .. " enabled, " .. off ..
    " disabled. Options: Esc -> tDF Options|r")
end
