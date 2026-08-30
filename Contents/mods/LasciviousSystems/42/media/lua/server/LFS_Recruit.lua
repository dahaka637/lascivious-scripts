-- Lascivious Factions System - legacy recruitment compatibility shim.
--
-- The public recruitment/listing/application system was retired in favour of the
-- manual online-player invitation flow implemented in LFS_Server.lua. Keeping this
-- empty server file avoids stale Workshop installations loading an older copy by name,
-- while deliberately registering no commands, timers or event handlers.

if isClient() and not isCoopHost() then return end

print("[LFS] legacy recruitment board disabled; manual invitations active")
