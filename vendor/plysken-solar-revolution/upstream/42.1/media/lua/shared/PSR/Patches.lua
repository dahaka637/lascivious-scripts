---@class PSR
local PSR = require "PSR/Utilities"

PSR.Patches = {}

-- Server-only: ISPlugGenerator and ISActivateGenerator are shared TimedActions
-- that run on the server; patch them to update the PSR powerbank state.
--
-- 🔴 GARDE 3-CONTEXTES (audit 2026-08-04). Valait `if not isClient() then`.
-- Sur un HOTE COOP, `isClient()` est vrai ⇒ la condition etait fausse ⇒ les deux patchs n'etaient
-- JAMAIS enregistres. Consequence joueur : brancher un groupe electrogene APRES avoir pose la bank
-- ne l'enregistrait pas comme secours (il ne restait que `autoConnectBackup`, joue a la pose seule)
-- ⇒ le Failsafe ne demarrait jamais, la base tombait la nuit. Solo et client de dedie n'etaient pas
-- touches, d'ou l'invisibilite du defaut.
-- ⚠️ Corrige OBLIGATOIREMENT avec `WorldUtil.getPowerBanksInArea` (meme audit) : sans ca on
-- reactive un appelant qui recupere des objets CLIENT depourvus de `connectBackupGenerator`,
-- et on remplace une fonction muette par un crash.
if not (isClient() and not isServer()) then
    PSR.Patches["ISPlugGenerator.complete"] = function ()
        local original = ISPlugGenerator.complete
        ISPlugGenerator.complete = function (self)
            local r = original(self)

            if self.plug then
                PSR.PBSystem_Server:onPlugGenerator(self.character, self.generator)
            else
                PSR.PBSystem_Server:onUnPlugGenerator(self.character, self.generator)
            end

            return r
        end
    end

    PSR.Patches["ISActivateGenerator.complete"] = function ()
        local original = ISActivateGenerator.complete
        ISActivateGenerator.complete = function (self)
            local result = original(self)

            if result and self.activate == self.generator:isActivated() then
                PSR.PBSystem_Server:onActivateGenerator(self.character, self.generator, self.activate)
            end

            return result
        end
    end
end

-- ISTransferAction is a client-side TimedAction.
-- SP:        runs on the unified process → direct server-side update.
-- MP client: ISTransferAction runs here → send moveBattery command to server.
-- MP server: ISTransferAction is not loaded → guard returns early.
PSR.Patches["ISTransferAction.transferItem"] = function ()
    if not ISTransferAction then return end
    local original = ISTransferAction.transferItem
    ISTransferAction.transferItem = function (self, character, item, srcContainer, destContainer, dropSquare)
        local result = original(self, character, item, srcContainer, destContainer, dropSquare)

        if result ~= nil then
            local maxCapacity = item:getModData().PSR_maxCapacity
            if not isClient() then
                -- SP: direct server-side logic
                PSR.PBSystem_Server:onTransferItem(self, character, item, srcContainer, destContainer, dropSquare)
            elseif maxCapacity and PSR.PBSystem_Client then
                -- MP client: notify server to update charge via moveBattery command
                local condition = item:getCondition()
                local capacity = maxCapacity * (1 - math.pow((1 - (condition / 100)), 6))
                local charge = capacity * item:getCurrentUsesFloat()
                local src = srcContainer:getParent()
                local dst = destContainer:getParent()
                if src and PSR.WorldUtil.objectIsType(src, "PowerBank") then
                    PSR.PBSystem_Client:sendCommand(character, "moveBattery", {
                        { x = src:getX(), y = src:getY(), z = src:getZ() }, "take", charge, capacity
                    })
                    -- Immediate client-side sprite update (server reply arrives later)
                    local pb = PSR.PBSystem_Client:getLuaObjectAt(src:getX(), src:getY(), src:getZ())
                    if pb then
                        pb:updateFromIsoObject()
                        pb.batteries = (pb.batteries or 1) - 1
                        if pb.batteries > 0 then
                            pb.charge    = (pb.charge    or 0) - charge
                            pb.maxcapacity = (pb.maxcapacity or 0) - capacity
                        else
                            pb.charge = 0
                            pb.maxcapacity = 0
                        end
                        pb:updateSprite()
                    end
                end
                if dst and PSR.WorldUtil.objectIsType(dst, "PowerBank") then
                    PSR.PBSystem_Client:sendCommand(character, "moveBattery", {
                        { x = dst:getX(), y = dst:getY(), z = dst:getZ() }, "put", charge, capacity
                    })
                    -- Immediate client-side sprite update
                    local pb = PSR.PBSystem_Client:getLuaObjectAt(dst:getX(), dst:getY(), dst:getZ())
                    if pb then
                        pb:updateFromIsoObject()
                        pb.batteries = (pb.batteries or 0) + 1
                        pb.charge    = (pb.charge    or 0) + charge
                        pb.maxcapacity = (pb.maxcapacity or 0) + capacity
                        pb:updateSprite()
                    end
                end
            end
        end

        return result
    end
end

PSR.queueFunction("OnTick", function (tick)
    for _, patch in pairs(PSR.Patches) do
        patch()
    end
    PSR.Patches = nil
end)
