local Antibodies = {}
Antibodies.__index = Antibodies
Antibodies.__name = "Antibodies"

Antibodies.info = {
	["version"] = "0.1.0",
	["optionsVersion"] = "194",
	["targetBuild"] = "42.20",
	["author"] = "lonegamedev.com",
	["modName"] = "Antibodies B42.20 Community",
	["modId"] = "AntibodiesB4220Community",
	["modWorkshopId"] = "",
}

function Antibodies.getNamespacedModData(player)
	local md = player:getModData()
	md.Antibodies = md.Antibodies or {}
	return md.Antibodies
end

return Antibodies