-- Hide the original gryphons
MainMenuBarLeftEndCap:Hide()
MainMenuBarRightEndCap:Hide()

-- Create new frames
leftGryphonFrame = CreateFrame("Frame", nil, MainMenuBar)
rightGryphonFrame = CreateFrame("Frame", nil, MainMenuBar)

-- Set the new frames to a higher strata
leftGryphonFrame:SetFrameStrata("HIGH")
rightGryphonFrame:SetFrameStrata("HIGH")

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
