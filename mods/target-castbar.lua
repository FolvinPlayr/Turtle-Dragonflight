local _G = tDFUI.GetGlobalEnv()
local T = tDFUI.T
local GetExpansion = tDFUI.GetExpansion
local create_castbar = tDF.utils.create_castbar

local module = tDFUI:register({
    title = T["Enemy Castbars"],
    description = T["Shows an enemy castbar on target unit frame."],
    expansions = { ["vanilla"] = true, ["tbc"] = nil },
    category = T["Unit Frames"],
    enabled = true,
})

-- horizontal offset from the bottom-center of TargetFrame.
-- more negative moves the castbar (and its spell icon) further left.
local offset_x = -32
local offset_y = -10

module.enable = function(self)
    local castbar = create_castbar("target", "tDFTargetCastbar", TargetFrame, "BOTTOM", offset_x, offset_y, 140, 10, 2)
	-- Set the frame strata and level to ensure it's in front
    castbar:SetFrameStrata("HIGH")  -- Set the frame strata to 'HIGH' to ensure it appears above most UI elements.

    -- The shared factory stacks the spell name below the bar and the timer on
    -- top of it, which collides on a bar this short. Split them onto opposite
    -- ends of the bar instead, the way the Dragonflight castbar does it.
    castbar.text:ClearAllPoints()
    castbar.text:SetPoint("LEFT", castbar, "LEFT", 4, 0)
    castbar.text:SetJustifyH("LEFT")

    castbar.timerText:ClearAllPoints()
    castbar.timerText:SetPoint("RIGHT", castbar, "RIGHT", -4, 0)
    castbar.timerText:SetJustifyH("RIGHT")
end
