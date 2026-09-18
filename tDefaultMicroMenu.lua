
tDFmicrobutton = CreateFrame("Frame", "tDFmicrobutton", UIParent)
tDFmicrobutton:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -10, 8)
tDFmicrobutton:SetHeight(30)
tDFmicrobutton:SetWidth(250)
tDFmicrobutton:SetFrameStrata("MEDIUM")

-- Hide blizzard's micro buttons.
--
-- This used to run at file scope, which meant the default buttons were gone
-- the moment the addon loaded, whether or not a replacement micro menu was
-- ever built. If the replacement failed, you were left with no spellbook,
-- character or talent button at all. It is now called by the micro menu
-- modules only after their own bar has been created successfully.
function tDF_HideDefaultMicroButtons()
  local buttons = {
    HelpMicroButton, MainMenuMicroButton, WorldMapMicroButton,
    SocialsMicroButton, QuestLogMicroButton, SpellbookMicroButton,
    CharacterMicroButton,
  }

  for _, button in pairs(buttons) do
    button:ClearAllPoints()
    button:Hide()
  end

  TalentMicroButton:ClearAllPoints()
  TalentMicroButton:SetPoint("BOTTOMLEFT", UIParent, -30, -30)
  TalentMicroButton:Hide()
end


function ShowTWBGQueueMenu()
  if not BuildTWBGQueueMenu then return end
  local TWBGQueueMinimapMenuFrame = CreateFrame('Frame', 'TWBGQueueMinimapMenuFrame', UIParent, 'UIDropDownMenuTemplate')
  UIDropDownMenu_Initialize(TWBGQueueMinimapMenuFrame, BuildTWBGQueueMenu, "MENU");
  ToggleDropDownMenu(1, nil, TWBGQueueMinimapMenuFrame, "cursor", -150, 25);
end

function create_microbutton_eye(parent_frame, x, y)
  -- LFT is turtle's "looking for turtles" frame set. bail out instead of
  -- erroring when the client doesn't ship it.
  if not LFTMinimapButton or not LFTFrameMainButton or not LFT then return end

  --LFT:SetPoint("CENTER", tDFmicrobutton, x, y)
  local overlay = CreateFrame("Frame", nil, LFTMinimapButton:GetParent())

  -- Set the frame strata to be higher than LFT_Minimap
  overlay:SetFrameStrata("DIALOG")

  -- Set the size and position of the overlay to match LFT_Minimap
  overlay:SetWidth(LFTMinimapButton:GetWidth()+2)
  overlay:SetHeight(LFTMinimapButton:GetHeight()+2)
  overlay:SetPoint("CENTER", LFTMinimapButton, "CENTER")

  -- Set the texture for the overlay
  overlay.texture = overlay:CreateTexture()
  overlay.texture:SetAllPoints()
  overlay.texture:SetTexture("Interface\\AddOns\\Turtle-Dragonflight\\img\\uigroupfinderflipbookeye.tga")
  overlay.texture:SetTexCoord(10/512, 55/512, 8/256, 55/256)

  ----------------ANIMATION----------------
  -- Define the TexCoords for each frame of the animation
  local texCoords = {
    --512 is left and right, 256 is up and down
    {10/512, 55/512, 8/256, 55/256}, -- 1st row
    {74/512, 119/512, 8/256, 55/256}, --256 will stay the same as we are going right down the row
    {138/512, 183/512, 8/256, 55/256}, -- Add 64 to all of 512
    {202/512, 247/512, 8/256, 55/256}, -- Add 64 to all of 256
    {266/512, 311/512, 8/256, 55/256},
    {330/512, 375/512, 8/256, 55/256},
    {394/512, 439/512, 8/256, 55/256},
    {458/512, 503/512, 8/256, 55/256},

    {10/512, 55/512, 72/256, 119/256}, --2nd row
    {74/512, 119/512, 72/256, 119/256}, 
    {138/512, 183/512, 72/256, 119/256},
    {202/512, 247/512, 72/256, 119/256},
    {266/512, 311/512, 72/256, 119/256},
    {330/512, 375/512, 72/256, 119/256},
    {394/512, 439/512, 72/256, 119/256},
    {458/512, 503/512, 72/256, 119/256},

    {10/512, 55/512, 136/256, 183/256}, -- 3rd row
    {74/512, 119/512, 136/256, 183/256},
    {138/512, 183/512, 136/256, 183/256},
    {202/512, 247/512, 136/256, 183/256},
    {266/512, 311/512, 136/256, 183/256},
    {330/512, 375/512, 136/256, 183/256},
    {394/512, 439/512, 136/256, 183/256},
    {458/512, 503/512, 136/256, 183/256},

    {10/512, 55/512, 200/256, 247/256},--4th row
    {74/512, 119/512, 200/256, 247/256},
    {138/512, 183/512, 200/256, 247/256},
    {202/512, 247/512, 200/256, 247/256},
    {266/512, 311/512, 200/256, 247/256}
  }

  -- Function to update the texture coordinates
  local currentFrame = 1
  local function UpdateTexCoords()
    local coords = texCoords[currentFrame]
    overlay.texture:SetTexCoord(unpack(coords))
    currentFrame = currentFrame + 1
    if currentFrame > table.getn(texCoords) then
        currentFrame = 1
    end
  end

  -- OnUpdate script to change the TexCoords every 0.1 seconds
  local timeSinceLastUpdate = 0
  local updateInterval = .1 -- Adjust this to change the speed of the animation
  overlay:SetScript("OnUpdate", function(self, elapsed)
    local elapsed = arg1 or 0
    timeSinceLastUpdate = timeSinceLastUpdate + elapsed
    if timeSinceLastUpdate > updateInterval then
        timeSinceLastUpdate = 0
        UpdateTexCoords()
    end
  end)

  --when group is formed
  local frame = CreateFrame("Frame")
  frame:RegisterEvent("PARTY_MEMBERS_CHANGED")

  frame:SetScript("OnEvent", function(self, event, ...)
    if GetNumPartyMembers() > 0 then
      --DEFAULT_CHAT_FRAME:AddMessage("The group has been formed!")
      --code here to stop the animation
      overlay:SetScript("OnUpdate", nil)
      overlay.texture:SetTexCoord(10/512, 55/512, 8/256, 55/256)
    else
      -- Reattach the OnUpdate script to restart the animation
      overlay:SetScript("OnUpdate", function(self, elapsed)
        local elapsed = arg1 or 0
        timeSinceLastUpdate = timeSinceLastUpdate + elapsed
        if timeSinceLastUpdate > updateInterval then
            timeSinceLastUpdate = 0
            UpdateTexCoords()
        end
      end)  
      UpdateTexCoords()
      LFT:Hide()
    end
  end)
  ----------------ANIMATION----------------

  -- Function to execute different code based on the button text
  local function ExecuteBasedOnButtonText()
    local buttonText = LFTFrameMainButton:GetText()
    if buttonText then
        if buttonText == "Find Group" then
            -- Code to execute when the button text is "Find Group"
            --print("Executing code for Find Group")
            LFTMinimapButton:Show()
            overlay.texture:Show()
            -- Insert your specific code here
        elseif buttonText == "Leave Queue" then
            -- Code to execute when the button text is "Leave Queue"
            --print("Executing code for Leave Queue")
            LFTMinimapButton:Hide()
            overlay.texture:Hide()
            -- Insert your specific code here
        else
            --print("Button text is empty?: " .. buttonText)
            --LFTMinimapButton:Show()
            --overlay.texture:Show()
        end
    else
        print("LFTFrameMainButton has no text.")
    end
  end

  -- call the helper directly; don't leave a HookScript method behind on a
  -- shared frame, see the note in mods/equip-compare.lua
  tDFUI.HookScript(LFTFrameMainButton, "OnClick", function()
    -- Call the function to check the button text and execute the corresponding code
    ExecuteBasedOnButtonText()
  end)

  LFTMinimapButton:Hide()
  overlay.texture:Hide()

  return overlay
end

function ShowEBCMinimapDropdown()
  if not EBCMinimapDropdown then return end
  if EBCMinimapDropdown:IsVisible() then
    EBCMinimapDropdown:Hide()
  else
    EBCMinimapDropdown:Show()
  end
end

function create_microbutton_latency(wow_latency_button, offset_x, offset_y)
  local latency = wow_latency_button
  if not latency then return end

  -- Set the normal texture and store a reference to it
  latency.texture = latency:CreateTexture(nil, "BACKGROUND")
  latency:SetNormalTexture("Interface\\AddOns\\Turtle-Dragonflight\\img\\Latency.tga")
  latency:ClearAllPoints()
  latency:SetPoint("BOTTOMRIGHT", tDFmicrobutton, offset_x, offset_y)
  latency:SetWidth(20)
  latency:SetHeight(15)

  -- Add this to update each frame
  latency:SetScript("OnUpdate", function(self, elapsed)
    local _, _, latencyHome = GetNetStats()
    -- Change the color based on latency
    if latencyHome < 200 then
      latency:SetNormalTexture("Interface\\AddOns\\Turtle-Dragonflight\\img\\LatencyGreen.tga")
    elseif latencyHome < 300 then
        latency:SetNormalTexture("Interface\\AddOns\\Turtle-Dragonflight\\img\\LatencyYellow.tga")
    else
        latency:SetNormalTexture("Interface\\AddOns\\Turtle-Dragonflight\\img\\LatencyRed.tga")
    end
  end)

  return latency
end

-- Move turtle's own minimap buttons out of the way. Every frame touched here
-- is turtle-specific and can disappear between client patches, so each one is
-- guarded individually -- a missing frame used to abort the whole micro menu.
function microbutton_removemi()
  -- The radio's minimap button. Parked off screen rather than hidden, and
  -- deliberately left shown: this is the state the client's radio was proven
  -- to work in -- with the button shown but out of the way, clicking its
  -- station checkbuttons from tRadio.lua tunes in and the music plays.
  -- Hiding it may well be harmless, but that is untested, and the radio is
  -- the client's code, so leave the known-good configuration alone.
  -- Belt and braces: unclamped, off screen AND transparent. Alpha is safe to
  -- use now -- it is inherited by the panel this button owns, but that panel
  -- is never displayed; tRadio.lua drives its widgets without showing it.
  if EBC_Minimap then
    EBC_Minimap:SetParent(UIParent)
    EBC_Minimap:ClearAllPoints()
    -- unclamp before moving: the client clamps this button to the screen, so
    -- an off-screen anchor alone just pinned it to the bottom-left corner
    if type(EBC_Minimap.SetClampedToScreen) == "function" then
      EBC_Minimap:SetClampedToScreen(false)
    end
    EBC_Minimap:SetPoint("CENTER", UIParent, "CENTER", -2000, -2000)
    EBC_Minimap:SetAlpha(0)
    EBC_Minimap:EnableMouse(false)
    EBC_Minimap:Show()
  end

  --LFT:SetParent(UIParent)
  --LFT:ClearAllPoints()
  --LFT:Hide()

  if MinimapShopFrame then
    MinimapShopFrame:SetParent(UIParent)
    MinimapShopFrame:ClearAllPoints()
    MinimapShopFrame:SetPoint("TOPRIGHT", 5000, 5000)
    MinimapShopFrame:SetAlpha(0)
    MinimapShopFrame:SetHeight(0)
    MinimapShopFrame:SetWidth(0)
  end

  if TWMiniMapBattlefieldFrame then TWMiniMapBattlefieldFrame:Hide() end
end
