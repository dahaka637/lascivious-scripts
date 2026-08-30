if not getActivatedMods():contains("VFExpansion1") then
	return
end

local contextLoaded = pcall(require, "VFE_ContextMenu")
if not contextLoaded or not VFEContext or not VFEAttachmentParity then
	print("Improvised Silencers: VFE context-menu compatibility could not be loaded")
	return
end

local function predicateNotBroken(item)
	return not item:isBroken()
end

local improvisedSilencers = {
	["Base.Silencer"] = true,
	["Base.MetalPipeSilencer"] = true,
	["Base.TorchSilencer"] = true,
	["Base.WaterBottleSilencer"] = true,
	["Base.PotatoSilencer"] = true,
}

local function upgradeImprovisedSilencer(weapon, part, player, ...)
	if ISILWeaponStateCompatibility and ISILWeaponStateCompatibility.rememberWeaponState then
		ISILWeaponStateCompatibility.rememberWeaponState(player, weapon, part)
	end

	-- Resolve the active handler at click time. This preserves handler changes
	-- made by Build 42 or another weapon framework without globally wrapping it.
	return ISInventoryPaneContextMenu.onUpgradeWeapon(weapon, part, player, ...)
end

-- VFE normally checks attachment parity against a related base weapon. That is
-- useful for most VFE parts, but can show our suppressors on blocked variants
-- such as the integrally suppressed CAR-15 Delta. For our parts only, check the
-- exact weapon selected by the player instead.
function VFEContext:Upgrade(item, index, player, context)
	local hasScrewdriver = player:getInventory():containsTagEvalRecurse(ItemTag.SCREWDRIVER, predicateNotBroken)
	if item and instanceof(item, "HandWeapon") then
		local weaponParts = player:getInventory():getItemsFromCategory("WeaponPart")
		if weaponParts and not weaponParts:isEmpty() then
			local subMenuUp = context:getNew(context)
			local doIt = false
			local addOption = false
			local alreadyDoneList = {}
			for i = 0, weaponParts:size() - 1 do
				local part = weaponParts:get(i)
				local canAttachWithCurrentTools = hasScrewdriver
					or part:getFullType() == "Base.PotatoSilencer"
				local mountOn = part:getMountOn()
				local mountTarget = VFEAttachmentParity[index + 1]
				if improvisedSilencers[part:getFullType()] then
					mountTarget = item:getFullType()
				end

				if canAttachWithCurrentTools and mountOn and mountOn:contains(mountTarget)
					and not alreadyDoneList[part:getName()] then
					if part:getPartType() == "Scope" and not item:getWeaponPart("Scope") then
						addOption = true
					elseif part:getPartType() == "Clip" and not item:getWeaponPart("Clip") then
						addOption = true
					elseif part:getPartType() == "Sling" and not item:getWeaponPart("Sling") then
						addOption = true
					elseif part:getPartType() == "Stock" and not item:getWeaponPart("Stock") then
						addOption = true
					elseif part:getPartType() == "Canon" and not item:getWeaponPart("Canon") then
						addOption = true
					elseif part:getPartType() == "RecoilPad" and not item:getWeaponPart("RecoilPad") then
						addOption = true
					end
				end

				if addOption then
					doIt = true
					local upgradeHandler = ISInventoryPaneContextMenu.onUpgradeWeapon
					if improvisedSilencers[part:getFullType()] then
						upgradeHandler = upgradeImprovisedSilencer
					end
					subMenuUp:addOption(part:getName(), item, upgradeHandler, part, player)
					addOption = false
					alreadyDoneList[part:getName()] = true
				end
			end

			if doIt then
				local upgradeOption = context:addOption(getText("ContextMenu_Add_Weapon_Upgrade"), items, nil)
				context:addSubMenu(upgradeOption, subMenuUp)
			end
		end
	end
end

print("Improvised Silencers: VFE context-menu compatibility loaded")
