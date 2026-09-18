local _G = tDFUI.GetGlobalEnv()
local T = tDFUI.T

local module = tDFUI:register({
  title = T["Opposite Faction Gryphons"],
  description = T["Wyverns for Alliance and Gryphons for the Horde."],
  expansions = { ["vanilla"] = true, ["tbc"] = true },
  category = T["Action Bar"],
  enabled = nil,
})

module.enable = function(self)
  tDFGryphons.SetOpposite(true)
end
