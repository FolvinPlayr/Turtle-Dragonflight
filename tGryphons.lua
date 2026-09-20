-- Hide the original gryphons
MainMenuBarLeftEndCap:Hide()
MainMenuBarRightEndCap:Hide()

-- Create new frames
leftGryphonFrame = CreateFrame("Frame", nil, MainMenuBar)
rightGryphonFrame = CreateFrame("Frame", nil, MainMenuBar)

-- The endcaps need to draw over the action bar art and the buttons, but NOT
-- over the game's panels. "HIGH" put them above the bag, character, escape and
-- tDF options frames, so a gryphon moved up the screen covered whatever window
-- was open underneath it. "MEDIUM" is where tMainActionBar.lua puts the action
-- buttons, so a frame level above those keeps the art on top of the bar while
-- every panel still draws over it.
leftGryphonFrame:SetFrameStrata("MEDIUM")
rightGryphonFrame:SetFrameStrata("MEDIUM")

local buttonlevel = ActionButton1 and ActionButton1:GetFrameLevel() or 5
leftGryphonFrame:SetFrameLevel(buttonlevel + 5)
rightGryphonFrame:SetFrameLevel(buttonlevel + 5)

-- Create new textures
local leftGryphon = leftGryphonFrame:CreateTexture(nil, "OVERLAY")
local rightGryphon = rightGryphonFrame:CreateTexture(nil, "OVERLAY")

--Checking Horde vs. Alliance wouldn't work, so using races
local race = UnitRace("player")
--DEFAULT_CHAT_FRAME:AddMessage("Your race is " .. race .. ".")

-- Set common properties
leftGryphon:SetPoint("LEFT", MainMenuBarArtFrame, "LEFT", -100, -2)
rightGryphon:SetPoint("RIGHT", MainMenuBarArtFrame, "RIGHT", 103, -2)

-- the endcap art for either faction
local GRYPHON_TEXTURE = "Interface\\Addons\\Turtle-Dragonflight\\img\\GryphonNew.tga"
local WYVERN_TEXTURE = "Interface\\Addons\\Turtle-Dragonflight\\img\\WyvernNew.tga"

local isAlliance
if race == "Night Elf" then
    isAlliance = true
elseif race == "Human" or race == "Gnome" or race == "Dwarf" or race == "High Elf" then
    isAlliance = true
else
    isAlliance = false
end

-- shared handle so other modules (see mods\opposite-faction-gryphons.lua)
-- can swap the endcap art after this file has run
tDFGryphons = {
  left = leftGryphon,
  right = rightGryphon,
  isAlliance = isAlliance,
  gryphon = GRYPHON_TEXTURE,
  wyvern = WYVERN_TEXTURE,
}

-- opposite = show the other faction's endcaps instead of your own
tDFGryphons.SetOpposite = function(opposite)
  local alliance = tDFGryphons.isAlliance
  if opposite then alliance = not alliance end

  local texturePath = alliance and tDFGryphons.gryphon or tDFGryphons.wyvern
  tDFGryphons.left:SetTexture(texturePath)
  tDFGryphons.right:SetTexture(texturePath)
end

tDFGryphons.SetOpposite(nil)

--Size the endcaps
leftGryphon:SetWidth(150)
leftGryphon:SetHeight(150)
rightGryphon:SetWidth(150)
rightGryphon:SetHeight(150)

-- Flip the right texture
rightGryphon:SetTexCoord(1, 0, 0, 1)
