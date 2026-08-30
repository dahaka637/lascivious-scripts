local Antibodies = {}
Antibodies.__index = Antibodies
Antibodies.__name = "Antibodies"

Antibodies.info = {
	["version"] = "1.97",
	["optionsVersion"] = "194",
	["author"] = "lonegamedev.com",
	["modName"] = "Antibodies",
	["modId"] = "lgd_antibodies",
	["modWorkshopId"] = "",
}

function Antibodies.getNamespacedModData(player)
	local md = player:getModData()
	md.Antibodies = md.Antibodies or {}
	return md.Antibodies
end

return Antibodies