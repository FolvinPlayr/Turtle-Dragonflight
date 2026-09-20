local _G = tDFUI.GetGlobalEnv()
local T = tDFUI.T
local gfind = string.gmatch or string.gfind

local module = tDFUI:register({
  title = T["Chat Spellcheck"],
  description = T["Spellchecks and shows suggestions below the chat-frame. Add words with /tdf dict add <word>"],
  expansions = { ["vanilla"] = true, ["tbc"] = true },
  category = T["Social & Chat"],
  enabled = true,
})

-- a word has to be this long before it is looked at, which is what keeps lfg,
-- wtb, ony, mc and the rest of chat shorthand quiet. drop it to 3 if you would
-- rather catch more and put up with more noise.
local MIN_LENGTH = 4

-- how many corrections fit on the hint line before it gets silly
local MAX_HINTS = 3

local suspect_color = "|cffffd100"
local fix_color = "|cff40c0ff"

-- plain English the web corpus behind the dictionary happens to lack. game
-- jargon is deliberately absent: druid, paladin, warlock, shaman and friends
-- are yours to add with /tdf dict add, so the list stays a dictionary.
local extra_words = [[
loot potion cloak enchant smelt thirst thirsty congratulate apologise rumour
dagger scabbard quiver satchel tabard trinket reagent summon dismount bandage
bribe barter haggle blacksmith alchemist jeweler herbalist innkeeper peasant
goblin ogre werewolf boar scorpion moth slime ooze golem pickpocket
]]

-- misspellings common enough that the corpus itself contains some of them.
-- these are struck out of the dictionary and always corrected, which also
-- catches the short ones MIN_LENGTH would otherwise skip.
local typos = {
  ["teh"] = "the", ["hte"] = "the", ["adn"] = "and", ["nad"] = "and",
  ["yuo"] = "you", ["taht"] = "that", ["thsi"] = "this", ["wiht"] = "with",
  ["alot"] = "a lot", ["thier"] = "their", ["wich"] = "which",
  ["recieve"] = "receive", ["reciept"] = "receipt", ["beleive"] = "believe",
  ["acheive"] = "achieve", ["seperate"] = "separate", ["definately"] = "definitely",
  ["occured"] = "occurred", ["occurance"] = "occurrence", ["becuase"] = "because",
  ["freind"] = "friend", ["wierd"] = "weird", ["arguement"] = "argument",
  ["calender"] = "calendar", ["comming"] = "coming", ["commited"] = "committed",
  ["concious"] = "conscious", ["embarass"] = "embarrass", ["enviroment"] = "environment",
  ["existance"] = "existence", ["familar"] = "familiar", ["finaly"] = "finally",
  ["foriegn"] = "foreign", ["goverment"] = "government", ["gaurd"] = "guard",
  ["happend"] = "happened", ["harrass"] = "harass", ["independant"] = "independent",
  ["knowlege"] = "knowledge", ["libary"] = "library", ["maintainance"] = "maintenance",
  ["neccessary"] = "necessary", ["noticable"] = "noticeable", ["occassion"] = "occasion",
  ["persistant"] = "persistent", ["posession"] = "possession", ["prefered"] = "preferred",
  ["priviledge"] = "privilege", ["publically"] = "publicly", ["recomend"] = "recommend",
  ["refered"] = "referred", ["relevent"] = "relevant", ["religous"] = "religious",
  ["remeber"] = "remember", ["resturant"] = "restaurant", ["rythm"] = "rhythm",
  ["seige"] = "siege", ["succesful"] = "successful", ["suprise"] = "surprise",
  ["tommorow"] = "tomorrow", ["tounge"] = "tongue", ["truely"] = "truly",
  ["unfortunatly"] = "unfortunately", ["untill"] = "until", ["usualy"] = "usually",
  ["vaccum"] = "vacuum", ["wether"] = "whether", ["writting"] = "writing",
  ["yeild"] = "yield",
}

-- word -> frequency rank, so a suggestion can prefer the commoner spelling
local dict = {}
-- lowercased word -> true, the player's own additions
local personal = {}
-- lowercased word -> correction string, or false for "this one is fine"
local verdict = {}

local hint

local alphabet = "abcdefghijklmnopqrstuvwxyz"

-- suffix, and what to put in its place. tried in order against a word that is
-- not in the dictionary verbatim, so looting finds loot and funnier finds funny
-- without the dictionary having to carry every inflection.
local stem_rules = {
  { "ies$", "y" }, { "ied$", "y" }, { "ier$", "y" }, { "iest$", "y" }, { "ily$", "y" },
  { "es$", "" }, { "es$", "e" }, { "s$", "" },
  { "ed$", "" }, { "ed$", "e" },
  { "ing$", "" }, { "ing$", "e" },
  { "er$", "" }, { "er$", "e" },
  { "est$", "" }, { "est$", "e" },
  { "ly$", "" },
}

local function StemKnown(stem)
  if stem == "" or dict[stem] then return dict[stem] end

  -- stopped lost its ed and came out stopp, running came out runn
  if strfind(stem, "(%a)%1$") then
    return dict[strsub(stem, 1, strlen(stem) - 1)]
  end
end

local function Known(word)
  if dict[word] then return true end

  -- don't, player's, we're
  local bare = gsub(word, "'.*$", "")
  if bare ~= word and bare ~= "" and dict[bare] then return true end

  for i = 1, table.getn(stem_rules) do
    local stem = gsub(word, stem_rules[i][1], stem_rules[i][2])
    if stem ~= word and StemKnown(stem) then return true end
  end
end

-- every string one edit away from the word, kept only when it is a real word.
-- far cheaper than measuring the distance to all nineteen thousand entries.
local function Suggest(word)
  local length = strlen(word)
  if length < 3 or length > 16 then return end

  local best, best_rank

  local function consider(candidate)
    local rank = dict[candidate]
    if rank and (not best_rank or rank < best_rank) then
      best, best_rank = candidate, rank
    end
  end

  for i = 1, length do
    local head = strsub(word, 1, i - 1)
    local tail = strsub(word, i + 1)

    consider(head .. tail)

    if i < length then
      consider(head .. strsub(word, i + 1, i + 1) .. strsub(word, i, i) .. strsub(word, i + 2))
    end

    for j = 1, 26 do
      consider(head .. strsub(alphabet, j, j) .. tail)
    end
  end

  for i = 1, length + 1 do
    local head = strsub(word, 1, i - 1)
    local tail = strsub(word, i)
    for j = 1, 26 do
      consider(head .. strsub(alphabet, j, j) .. tail)
    end
  end

  return best
end

-- nil when the word is fine, otherwise what it probably should have been
local function Check(word)
  local cached = verdict[word]
  if cached ~= nil then return cached or nil end

  local result
  if typos[word] then
    result = typos[word]
  elseif personal[word] or Known(word) then
    result = false
  else
    result = Suggest(word) or ""
  end

  verdict[word] = result
  return result or nil
end

-- index is the word's position in the line, because a capital only means a
-- name once something has come before it
local function Worth(word, index)
  local lower = strlower(word)

  if typos[lower] then return true end
  if personal[lower] then return end
  if strlen(word) < MIN_LENGTH then return end
  if strfind(word, "^%u+$") then return end
  if index > 1 and strfind(word, "^%u") then return end

  return true
end

local function Scan()
  if not hint then return end

  local text = ChatFrameEditBox:GetText()
  if not text or text == "" then
    hint:Hide()
    return
  end

  local body, index = text, 0

  -- whatever follows a slash command is never the opening of a sentence, so
  -- starting the count at 1 lets the capital rule swallow a whisper target
  if strfind(body, "^/") then
    body = gsub(body, "^/%S*%s*", "")
    index = 1
  end

  -- item and player links are not prose
  body = gsub(body, "|H.-|h.-|h", " ")
  body = gsub(body, "|c%x%x%x%x%x%x%x%x", "")
  body = gsub(body, "|r", "")

  local found, shown = "", 0

  for word in gfind(body, "[%a][%a']*") do
    index = index + 1

    if Worth(word, index) then
      local fix = Check(strlower(word))

      -- an opening capital with no near miss is a name far more often than a
      -- typo, and names are the one thing no dictionary can hold
      if fix == "" and index == 1 and strfind(word, "^%u") then fix = nil end

      if fix then
        shown = shown + 1
        if shown <= MAX_HINTS then
          if found ~= "" then found = found .. "   " end
          found = found .. suspect_color .. word .. "|r"
          -- "" means it is not a word we know but we have no better guess
          if fix ~= "" then found = found .. " > " .. fix_color .. fix .. "|r" end
        end
      end
    end
  end

  if shown == 0 then
    hint:Hide()
    return
  end

  if shown > MAX_HINTS then
    found = found .. "   |cff808080+" .. (shown - MAX_HINTS) .. "|r"
  end

  hint.text:SetText(found)
  hint:Show()
end

-- /tdf dict add|remove|list
function tDF_SpellcheckCommand(args)
  if not tDF_dictionary then tDF_dictionary = {} end

  local _, _, action, word = strfind(args or "", "^%s*(%a*)%s*(%S*)")
  action = strlower(action or "")
  word = strlower(word or "")

  if action == "add" and word ~= "" then
    tDF_dictionary[word] = true
    personal[word] = true
    verdict[word] = false
    tDFUI.Print("added |cffffff00" .. word .. "|r to your dictionary.")

  elseif action == "remove" and word ~= "" then
    tDF_dictionary[word] = nil
    personal[word] = nil
    verdict[word] = nil
    tDFUI.Print("removed |cffffff00" .. word .. "|r from your dictionary.")

  elseif action == "list" then
    local list, count = "", 0
    for entry in pairs(tDF_dictionary) do
      count = count + 1
      list = (list == "" and entry) or (list .. ", " .. entry)
    end
    tDFUI.Print(count ..
      " word(s) in your dictionary. |cffaaaaaa" .. list .. "|r")

  else
    tDFUI.Print("|cffffff00/tdf dict add|remove <word>|r, or |cffffff00/tdf dict list|r")
  end
end

module.enable = function(self)
  assert(tDF_spellcheck_words, "the spellcheck word list failed to load")

  -- build the lookup once. the generated file is frequency ordered, so the
  -- running count doubles as "how common is this word".
  local rank = 0
  for i = 1, table.getn(tDF_spellcheck_words) do
    for word in gfind(tDF_spellcheck_words[i], "%a+") do
      rank = rank + 1
      if not dict[word] then dict[word] = rank end
    end
  end

  for word in gfind(extra_words, "%a+") do
    rank = rank + 1
    if not dict[word] then dict[word] = rank end
  end

  -- the corpus was scraped from the web and picked up a few misspellings on
  -- the way. a dictionary that contains teh cannot correct teh.
  for word in pairs(typos) do
    dict[word] = nil
  end

  if not tDF_dictionary then tDF_dictionary = {} end
  for word in pairs(tDF_dictionary) do
    personal[word] = true
  end

  -- parented to the edit box so it appears and disappears along with it
  hint = CreateFrame("Frame", "tDFSpellcheckHint", ChatFrameEditBox)
  hint:SetHeight(14)
  hint:SetPoint("TOPLEFT", ChatFrameEditBox, "BOTTOMLEFT", 0, -1)
  hint:SetPoint("TOPRIGHT", ChatFrameEditBox, "BOTTOMRIGHT", 0, -1)
  hint:Hide()

  hint.text = hint:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hint.text:SetPoint("LEFT", hint, "LEFT", 6, 0)
  hint.text:SetJustifyH("LEFT")

  local previous = ChatFrameEditBox:GetScript("OnTextChanged")
  ChatFrameEditBox:SetScript("OnTextChanged", function()
    if previous then previous() end
    Scan()
  end)
end
