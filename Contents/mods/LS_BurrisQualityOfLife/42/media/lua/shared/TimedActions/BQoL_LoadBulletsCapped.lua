--[[
    Burris Quality of Life -- ISLoadBulletsInMagazine with a working ammo cap.

    Vanilla's ISLoadBulletsInMagazine ignores the ammoCount it is constructed
    with: that number only drives the job-progress tooltip. Its real stop
    condition (isLoadFinished, ISLoadBulletsInMagazine.lua:57-62) is "magazine
    full OR the character has no matching bullets left", with no per-action
    cap. Queue it for several magazines sharing one ammo pool and the first
    one drains every bullet before the next gets a turn.

    Lives in shared/TimedActions/ rather than beside the menu code that queues
    it, and that placement is load-bearing: this class inherits serverStart()
    and animEvent() from its parent, so a dedicated server needs the
    definition too. 51 of the 52 vanilla timed actions that define serverStart
    live in shared/, as do this mod's other four action classes.
]]

require "TimedActions/ISLoadBulletsInMagazine"

BQoL_LoadBulletsCapped = ISLoadBulletsInMagazine:derive("BQoL_LoadBulletsCapped")

--[[
    The baseline is captured here, not read from self.ammoCountStart.

    Vanilla sets ammoCountStart in start() only (:19). On a dedicated server
    the entry point is serverStart() (:70), which never sets it -- yet
    isLoadFinished() is reached from animEvent (:95, :107, :134), which the
    server does run, and the server is what actually inserts each bullet (the
    `if not isClient()` branch at :112). So reading ammoCountStart server-side
    is both an arithmetic-on-nil error and, if nil-guarded naively, a cap that
    silently stops applying on exactly the side that enforces it.
]]
function BQoL_LoadBulletsCapped:new(character, magazine, ammoCount)
    local o = ISLoadBulletsInMagazine.new(self, character, magazine, ammoCount)
    o.bqolStartCount = magazine:getCurrentAmmoCount()
    return o
end

function BQoL_LoadBulletsCapped:isLoadFinished()
    local base = self.ammoCountStart or self.bqolStartCount
    if base and self.ammoCount
        and (self.magazine:getCurrentAmmoCount() - base) >= self.ammoCount then
        return true
    end
    return ISLoadBulletsInMagazine.isLoadFinished(self)
end
