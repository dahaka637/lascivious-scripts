-- Lascivious Factions System - client side.
-- Sends player intents to the server, shows server notifications, and gives
-- enter/leave-claim feedback. Until a proper UI exists, a small "/ff ..." chat
-- command set (mirroring the DiscordLink command hook in this repo) drives the
-- whole framework for testing.

require "LFS_Shared"
require "LFS_Claims"
require "LFS_TileToolAPI"
require "LFS_Permissions"
require "LFS_UI"
require "LFS_Localization"
require "LFS_PhunZonesUI"
require "LFS_TerritoryOverlay"
local ChatRouter = require "LasciviousSystems_ChatRouter"

local FF = LasciviousFactionsSystem
local Claims = FF.Claims
local UI = FF.UI

print("[LFS] client lua loaded")

-- ---------------------------------------------------------------------------
-- Idempotent tribute request ownership
-- ---------------------------------------------------------------------------
-- Keep the exact payload until the server correlates a definitive reply. Losing
-- only a notify packet must not turn the next click (or reconnect) into a second
-- deposit/withdraw with a fresh id. A small player-modData record survives a
-- reconnect; it contains only the three scalar fields the server already accepts.
FF._tributeClient = type(FF._tributeClient) == "table" and FF._tributeClient or {}
local TributeClient = FF._tributeClient
if TributeClient.retryHook and Events.OnTick then Events.OnTick.Remove(TributeClient.retryHook) end
TributeClient.retryHook = nil
TributeClient.awaiting = false
TributeClient.ambiguous = TributeClient.pending ~= nil
TributeClient.sequence = math.max(0, math.floor(tonumber(TributeClient.sequence) or 0))

function FF._tributeNowMs()
    if getTimestampMs then return tonumber(getTimestampMs()) or 0 end
    return (getTimestamp and (tonumber(getTimestamp()) or 0) or 0) * 1000
end

function FF._normalisePendingTribute(record)
    if type(record) ~= "table" then return nil end
    local requestId = record.requestId
    local command = record.command
    local amount = tonumber(record.amount)
    if type(requestId) ~= "string" or requestId == "" or #requestId > 80 then return nil end
    if command ~= "depositTribute" and command ~= "donateTribute"
        and command ~= "withdrawTribute" then return nil end
    if not amount or amount ~= amount or amount == math.huge or amount == -math.huge
        or amount <= 0 or amount > 1000000 then return nil end
    return {
        requestId = requestId,
        command = command,
        amount = amount,
        automaticRetries = 0,
        payload = { requestId = requestId, amount = amount },
    }
end

-- A hot reload preserves the namespace table. Re-validate that retained record
-- just like reconnect data instead of trusting a partial/corrupt table.
TributeClient.pending = FF._normalisePendingTribute(TributeClient.pending)
TributeClient.ambiguous = TributeClient.pending ~= nil

function FF._persistPendingTribute(player)
    player = player or (getPlayer and getPlayer() or nil)
    if not player or not player.getModData then return end
    local ok, modData = pcall(function() return player:getModData() end)
    if not ok or type(modData) ~= "table" then return end
    local pending = TributeClient.pending
    if pending then
        modData.LFS_TributePendingV1 = {
            requestId = pending.requestId,
            command = pending.command,
            amount = pending.amount,
        }
    else
        modData.LFS_TributePendingV1 = nil
    end
    -- Persist before the money-moving command is sent. Failure to transmit is
    -- non-fatal (the in-memory id still protects this session), hence the pcall.
    if player.transmitModData then pcall(function() player:transmitModData() end) end
end

function FF._restorePendingTribute(player)
    if not player or not player.getModData then return false end
    if TributeClient.pending then return true end
    local ok, modData = pcall(function() return player:getModData() end)
    local restored = ok and type(modData) == "table"
        and FF._normalisePendingTribute(modData.LFS_TributePendingV1) or nil
    TributeClient.pending = restored
    TributeClient.ambiguous = restored ~= nil
    if ok and type(modData) == "table" and modData.LFS_TributePendingV1 ~= nil and not restored then
        modData.LFS_TributePendingV1 = nil
        if player.transmitModData then pcall(function() player:transmitModData() end) end
    end
    return restored ~= nil
end

function FF._setTributeRetryActive(active)
    if TributeClient.retryHook and Events.OnTick then Events.OnTick.Remove(TributeClient.retryHook) end
    TributeClient.retryHook = nil
    if active and Events.OnTick then
        TributeClient.retryHook = FF._tributeRetryTick
        Events.OnTick.Add(TributeClient.retryHook)
    end
end

function FF._sendPendingTribute(automatic)
    local pending = TributeClient.pending
    local player = getPlayer and getPlayer() or nil
    if not player or type(pending) ~= "table" then return false end
    if automatic then
        pending.automaticRetries = math.max(0,
            math.floor(tonumber(pending.automaticRetries) or 0)) + 1
    end
    TributeClient.awaiting = true
    TributeClient.ambiguous = false
    TributeClient.sentAt = FF._tributeNowMs()
    TributeClient.nextCheckAt = TributeClient.sentAt + 250
    sendClientCommand(player, FF.MODULE, pending.command, pending.payload)
    FF._setTributeRetryActive(true)
    return true
end

-- Public client helper used by LFS_Panel. If a previous result is unknown, the
-- new form values are intentionally ignored and the exact old transaction is
-- queried instead.
function FF.requestTribute(command, amount)
    local player = getPlayer and getPlayer() or nil
    if not player then return false, "no_player" end
    FF._restorePendingTribute(player)
    if TributeClient.awaiting then return false, "awaiting" end
    if TributeClient.pending then
        return FF._sendPendingTribute(false), "retrying"
    end
    local pending = FF._normalisePendingTribute({
        requestId = tostring(FF._tributeNowMs()) .. ":f:" .. tostring(TributeClient.sequence + 1),
        command = command,
        amount = amount,
    })
    if not pending then return false, "invalid" end
    TributeClient.sequence = TributeClient.sequence + 1
    TributeClient.pending = pending
    -- Store/transmit the immutable id before the server can mutate either ledger.
    FF._persistPendingTribute(player)
    return FF._sendPendingTribute(false), nil
end

function FF._handleTributeReply(args)
    local pending = TributeClient.pending
    if type(args) ~= "table" or not pending or type(args.requestId) ~= "string"
        or args.requestId ~= pending.requestId then return end
    TributeClient.awaiting = false
    FF._setTributeRetryActive(false)
    if args.key == "tribute_request_processing" then
        -- The server has an ambiguous cross-ModData marker. Retain the id forever;
        -- a new id could duplicate money and the server will also reject it.
        TributeClient.ambiguous = true
        pending.automaticRetries = 2
    else
        TributeClient.pending = nil
        TributeClient.ambiguous = false
        FF._persistPendingTribute()
    end
end

function FF._tributeRetryTick()
    if not TributeClient.awaiting then return FF._setTributeRetryActive(false) end
    local now = FF._tributeNowMs()
    if now < (TributeClient.sentAt or 0) then
        TributeClient.sentAt = now
        TributeClient.nextCheckAt = now + 250
    end
    if now < (TributeClient.nextCheckAt or 0) then return end
    TributeClient.nextCheckAt = now + 250
    if now - (TributeClient.sentAt or 0) <= 10000 then return end
    local pending = TributeClient.pending
    local retries = pending and math.max(0,
        math.floor(tonumber(pending.automaticRetries) or 0)) or 0
    if pending and retries < 2 and FF._sendPendingTribute(true) then return end
    TributeClient.awaiting = false
    TributeClient.ambiguous = pending ~= nil
    FF._setTributeRetryActive(false)
    local player = getPlayer and getPlayer() or nil
    if player and pending then
        player:setHaloNote(FF.text("UI_LFS_TributeMsgTimeout",
            "Sem resposta do servidor. A próxima tentativa consultará a mesma operação com segurança."),
            255, 180, 80, 300)
    end
end

-- Pull the authoritative registry to this client.
--
-- We do NOT use ModData.request at OnGameStart: it fires before the client is
-- fully in-world, has no retry, and vanilla B42 never uses it -- on a joined
-- coop/dedicated client it silently races and the registry stays empty. Instead
-- we copy the pattern PhunZones/vanilla use reliably: a self-removing first-tick
-- handshake over the ordinary command channel (which delivers all our other
-- intents dependably). The server answers TARGETED with the full table inline
-- (Handlers.requestSync -> "syncData" below). Live updates thereafter arrive via
-- the server's FF.sync()/ModData.transmit + our OnReceiveGlobalModData handler.
local function requestInitialSync()
    -- Wait for the local player to exist before handshaking; retry next tick
    -- otherwise. Only self-remove once the request is actually sent.
    local player = getPlayer()
    if not player then return end
    Events.OnTick.Remove(requestInitialSync)
    -- Resume the exact same operation after reconnect before the player can create
    -- a new request id. Server replay protection makes this a status query.
    if FF._restorePendingTribute(player) then FF._sendPendingTribute(false) end
    -- Inlined rather than via the send() helper: send() is a local declared later
    -- in this file, so it is not in lexical scope here.
    sendClientCommand(player, FF.MODULE, "requestSync", {})
end
local function scheduleInitialSync()
    Events.OnTick.Remove(requestInitialSync)
    Events.OnTick.Add(requestInitialSync)
end
if FF._clientInitialSyncHook then Events.OnGameStart.Remove(FF._clientInitialSyncHook) end
FF._clientInitialSyncHook = scheduleInitialSync
Events.OnGameStart.Add(scheduleInitialSync)

-- Live structural pushes arrive through the server's coalesced
-- ModData.transmit(FF.MODDATA); high-frequency score/tribute changes use the compact
-- `stateDelta` server command below plus a sparse full checkpoint.
-- B42 quirk (per PhunZones): tableData may be false, and the data is already in
-- the local store by the time this fires -- only write it back when we actually
-- got a table.
-- Panel refresh (a role's permission checkboxes, tribute balance/history, the
-- Overview "no faction yet" state) does NOT hook this event -- it turned out
-- not to be a safe signal for it. See LasciviousFactionsSystemPanel:prerender/
-- liveRefreshFingerprint in LFS_Panel.lua for the per-frame check that replaced
-- that attempt, and its comment for why.
local function receiveLfsGlobalData(tableName, tableData)
    if tableName ~= FF.MODDATA then return end
    if type(tableData) == "table" then
        ModData.add(FF.MODDATA, tableData)
    end
end
if FF._clientGlobalDataHook then Events.OnReceiveGlobalModData.Remove(FF._clientGlobalDataHook) end
FF._clientGlobalDataHook = receiveLfsGlobalData
Events.OnReceiveGlobalModData.Add(receiveLfsGlobalData)

-- ---------------------------------------------------------------------------
-- Server notifications
-- ---------------------------------------------------------------------------
local MESSAGES = {
    name_required = "Usage: /ff create <name>",
    name_taken = "That faction name is taken.",
    invalid_faction_name = "Invalid faction name: %s",
    already_in_faction = "You are already in a faction.",
    create_score_too_low = "You need more personal character score to create a faction (%s points).",
    not_in_faction = "You are not in a faction.",
    no_such_faction = "No faction by that name.",
    not_owner = "Only the owner can do that.",
    owner_must_disband = "Owners must disband, not leave.",
    not_authorised = "You don't have permission to do that.",
    faction_created = "Faction created: %s",
    faction_updated = "Faction settings updated.",
    faction_disbanded = "Faction disbanded: %s",
    faction_renamed = "Your faction has been renamed (it was %s).",
    joined_faction = "Joined faction: %s",
    left_faction = "Left faction: %s",
    invite_sent = "Invite sent to %s.",
    invite_required = "That faction is invite-only. You need an invite to join.",
    member_cap_reached = "That faction is full.",
    decay_warning = "Your faction is inactive and will be disbanded soon unless a member logs in.",
    invite_revoked = "Invite for %s revoked.",
    invite_declined = "Invite declined.",
    already_member = "That player is already in your faction.",
    invite_player_offline = "That player is no longer online.",
    invite_target_has_faction = "That player already belongs to a faction.",
    invite_pending = "There is already a pending invitation for %s.",
    invite_cooldown = "That player declined recently. Wait %s before inviting again.",
    invite_declined_by = "%s declined your faction invitation.",

    ally_request_sent = "Alliance request sent to %s.",
    ally_requested = "%s wants to form an alliance.",
    ally_formed = "Now allied with %s.",
    ally_declined = "Alliance request declined.",
    ally_broken = "Alliance with %s ended.",
    enemy_declared = "%s marked as an enemy.",
    relation_cleared = "Relationship cleared.",
    claim_set = "Claim set (%s tiles).",
    claim_cleared = "Claim cleared.",
    claim_area_removed = "An admin removed one of your faction's claimed areas.",
    respawn_set = "Faction respawn point set.",
    respawn_must_be_in_claim = "Stand inside your claim to set the respawn point.",
    claim_rejected = "Claim rejected: %s",
    raid_declared = "Raid started on %s. Outnumber the defenders inside and hold to capture.",
    raid_incoming = "Your claim is under raid by %s! Get inside and defend it.",
    raid_won = "Raid succeeded -- %s's claim is burned and the land is freed.",
    raid_lost = "Your claim was captured and burned by %s. The land is now unclaimed.",
    raid_failed = "Your raid on %s failed -- they held the line.",
    raid_defended = "You defended your claim against %s's raid.",
    raid_abandoned_self = "You called off your raid on %s.",
    raid_abandoned = "%s has called off their raid on your claim.",
    raid_rejected = "Raid rejected: %s",
    no_such_member = "No member by that name.",
    cannot_change_owner = "You cannot change the owner's role.",
    cannot_transfer_self = "You already own this faction.",
    ownership_transferred = "Ownership transferred from %s to %s.",
    invalid_role = "That role doesn't exist in your faction.",
    member_role_changed = "%s is now in the %s role.",
    cannot_kick_owner = "You cannot kick the owner.",
    cannot_kick_self = "You cannot kick yourself -- use '/ff leave' instead.",
    member_kicked = "%s was removed from the faction.",
    role_created = "Role '%s' created.",
    role_deleted = "Role '%s' deleted.",
    role_renamed = "Role renamed to '%s'.",
    role_updated = "Role '%s' updated.",
    role_exists = "A role with that name already exists.",
    too_many_roles = "This faction has reached its role limit.",
    cannot_delete_role = "That role can't be renamed or deleted.",
    intrusion = "%s (hostile) has entered your territory!",
    wars_disabled = "Faction wars are disabled on this server.",
    war_rejected_ally = "You can't declare war on an ally.",
    war_rejected_active = "You are already at war with them.",
    war_rejected_ceasefire = "A ceasefire is in effect -- you can't re-declare war yet.",
    war_none = "You are not at war with them.",
    war_victory = "Victory! %s has surrendered the war.",
    war_defeat = "Your faction has lost the war against %s.",
    pacts_disabled = "Non-aggression pacts are disabled on this server.",
    pact_exists = "You already have a pact with them.",
    pact_rejected_hostile = "You can't pact a faction you're at war with or hold as an enemy.",
    pact_proposed = "Pact proposed to %s.",
    pact_incoming = "%s has proposed a non-aggression pact.",
    pact_formed = "Non-aggression pact formed with %s.",
    pact_declined = "Pact proposal declined.",
    pact_none = "You have no pact with them.",
    pact_broken_self = "You broke your pact with %s.",
    pact_broken_by = "%s has broken their pact with you!",
    pact_expired = "Your non-aggression pact with %s has expired.",
    war_rejected_pact = "A non-aggression pact is in effect -- break it first.",
    coalition_joined_self = "You have joined the war against %s.",
    coalition_no_war = "There's no active war to join against them.",
    coalition_already = "You're already in that war.",
    coalition_not_ally = "You can only join a war on an ally's side.",
    coalition_ally_target = "You can't join a war against your own ally.",
    coalition_pact = "A non-aggression pact stops you joining a war against them.",
    score_reset_death = "Your character score was reset after death.",
    score_preserved_death = "Your character score was preserved after death.",
}

local CLAIM_REASON = {
    empty = "no tiles selected",
    too_many_rects = "selection has too many pieces",
    faction_too_small = "not enough members to claim",
    too_large = "claim exceeds your faction's size limit",
    overlap = "overlaps another faction's claim",
    too_scattered = "areas are too far apart",
    too_many_public = "too many areas set to Public",
    too_close = "too close to another faction's claim",
    no_claim_zone = "the server blocks claiming in that area",
}

-- Tribute notify keys skip the generic MESSAGES/FF.tr path below: FF.tr's final
-- fallback for a template with no KEYS entry returns it unchanged, with no %s
-- substitution -- see the "notify" command handler further down, and FF.text
-- calls throughout this mod for the properly-substituting alternative. Each
-- entry is { UI_LFS_key, PT-BR fallback } for FF.text(key, fallback, extra).
local TRIBUTE_MESSAGES = {
    tribute_deposited = { "UI_LFS_TributeMsgDeposited", "Você contribuiu %s crédito(s) para o tesouro da facção." },
    tribute_withdrawn = { "UI_LFS_TributeMsgWithdrawn", "Você sacou %s crédito(s) do tesouro da facção." },
    tribute_invalid_request = { "UI_LFS_TributeMsgInvalidRequest", "Pedido de tributo inválido." },
    tribute_invalid_amount = { "UI_LFS_TributeMsgInvalidAmount", "Quantidade inválida." },
    tribute_insufficient_player_funds = { "UI_LFS_TributeMsgInsufficientPlayer", "Você não tem créditos suficientes." },
    tribute_insufficient_faction_funds = { "UI_LFS_TributeMsgInsufficientFaction",
        "O tesouro da facção não tem créditos suficientes." },
    tribute_withdraw_failed = { "UI_LFS_TributeMsgWithdrawFailed", "Não foi possível concluir o saque." },
    tribute_shop_unavailable = { "UI_LFS_TributeMsgShopUnavailable",
        "O serviço de créditos está indisponível no momento. Tente novamente em instantes." },
    tribute_request_processing = { "UI_LFS_TributeMsgProcessing",
        "A operação já foi iniciada, mas o resultado é incerto. Não tente novamente; contate um administrador." },
}

-- Same direct { UI_LFS_key, PT-BR fallback } shape as TRIBUTE_MESSAGES above, and
-- for the same reason: FF.tr's generic path never substitutes into a template with
-- no KEYS entry. upgrade_allocated is the one message here with two substitutions
-- (upgrade name, new level) -- see the "notify" command handler's directMsg branch.
local UPGRADE_MESSAGES = {
    upgrade_invalid_type = { "UI_LFS_UpgradeMsgInvalidType", "Tipo de aprimoramento inválido." },
    upgrade_maxed = { "UI_LFS_UpgradeMsgMaxed", "Esse aprimoramento já está no nível máximo." },
    upgrade_no_points = { "UI_LFS_UpgradeMsgNoPoints", "Sua facção não possui pontos de aprimoramento disponíveis." },
    upgrade_allocated = { "UI_LFS_UpgradeMsgAllocated", "%s aprimorado para o nível %s." },
    upgrade_milestone_reached = { "UI_LFS_UpgradeMsgMilestone",
        "Sua facção atingiu um novo marco de poder! +%s ponto(s) de aprimoramento." },
}

local DEBUG_MESSAGES = {
    debug_tools_disabled = { "UI_LFS_DebugMsgToolsDisabled",
        "As ferramentas de debug estão desativadas nas configurações do sandbox." },
    debug_power_added = { "UI_LFS_DebugMsgPowerAdded", "+%s de poder adicionado à sua facção (debug)." },
}

-- Same direct { UI_LFS_key, PT-BR fallback } shape as the tables above -- see
-- LFS_VehicleGuard.lua for the protect/lock data model these messages report on.
local VEHICLE_MESSAGES = {
    vehicle_not_found = { "UI_LFS_VehicleMsgNotFound", "Veículo não encontrado." },
    vehicle_not_in_territory = { "UI_LFS_VehicleMsgNotInTerritory",
        "Esse veículo não está dentro do território da sua facção." },
    vehicle_protect_occupant_blocked = { "UI_LFS_VehicleMsgOccupantBlocked",
        "Não é possível proteger: há alguém de fora da facção dentro do veículo." },
    vehicle_protect_limit = { "UI_LFS_VehicleMsgProtectLimit",
        "Sua facção já atingiu o limite de veículos protegidos (%s)." },
    vehicle_protect_requested = { "UI_LFS_VehicleMsgProtectRequested",
        "Proteção de '%s' iniciada -- será confirmada em 1 hora de jogo se o veículo continuar no território." },
    vehicle_protect_confirmed = { "UI_LFS_VehicleMsgProtectConfirmed",
        "'%s' agora está protegido pela facção." },
    vehicle_protect_failed = { "UI_LFS_VehicleMsgProtectFailed",
        "A proteção de '%s' falhou -- o veículo saiu do território ou teve alguém de fora entrando nele." },
    vehicle_kicked_locked = { "UI_LFS_VehicleMsgKickedLocked",
        "Você foi removido do veículo -- ele está trancado pela facção %s." },
    vehicle_tow_detached = { "UI_LFS_VehicleMsgTowDetached",
        "O reboque de um veículo trancado de sua facção foi desfeito automaticamente." },
    vehicle_lock_needs_protect = { "UI_LFS_VehicleMsgLockNeedsProtect",
        "Só é possível trancar um veículo que já esteja protegido pela facção." },
}

local function formatInviteWait(seconds)
    local n = math.max(0, math.ceil(tonumber(seconds) or 0))
    if n < 60 then return FF.text("UI_LFS_WaitSeconds", "%d segundos", n) end
    if n < 3600 then return FF.text("UI_LFS_WaitMinutes", "%d minutos", math.ceil(n / 60)) end
    if n < 86400 then
        local h = math.floor(n / 3600)
        local m = math.ceil((n % 3600) / 60)
        if m > 0 then return FF.text("UI_LFS_WaitHoursMinutes", "%dh %dmin", h, m) end
        return FF.text("UI_LFS_WaitHours", "%d horas", h)
    end
    local d = math.floor(n / 86400)
    local h = math.ceil((n % 86400) / 3600)
    if h > 0 then return FF.text("UI_LFS_WaitDaysHours", "%dd %dh", d, h) end
    return FF.text("UI_LFS_WaitDays", "%d dias", d)
end

local inviteDialogs = {}

local function answerFactionInvite(_, button, factionName)
    inviteDialogs[factionName] = nil
    if button.internal == "YES" then
        sendClientCommand(getPlayer(), FF.MODULE, "acceptInvite", { name = factionName })
    else
        sendClientCommand(getPlayer(), FF.MODULE, "declineInvite", { name = factionName })
    end
end

local function showFactionInvite(args)
    local player = getPlayer()
    local factionName = args and args.faction
    if not (player and factionName and factionName ~= "") then return end
    if FF.getFactionOfPlayer(player:getUsername()) then return end
    local old = inviteDialogs[factionName]
    if old and old.isReallyVisible and old:isReallyVisible() then return end
    inviteDialogs[factionName] = nil

    local inviter = (args.inviter and args.inviter ~= "") and args.inviter
        or FF.text("UI_LFS_UnknownInviter", "a member")
    local text = FF.text("UI_LFS_FactionInvitePopup",
        "%s invited you to join faction %s.\n\nDo you want to accept the invitation?",
        inviter, factionName)
    local modal = ISModalDialog:new(
        math.floor(getCore():getScreenWidth() / 2 - 200),
        math.floor(getCore():getScreenHeight() / 2 - 85),
        400, 170, text, true, nil, answerFactionInvite, nil, factionName)
    modal:initialise(); modal:addToUIManager()
    modal.moveWithMouse = true
    modal:setAlwaysOnTop(true); modal:bringToTop()
    -- Do not inherit English Yes/No from the game's active locale: this server build
    -- intentionally presents every LFS-facing control in Brazilian Portuguese.
    if modal.yes then modal.yes:setTitle(FF.text("UI_LFS_AcceptAction", "Accept")) end
    if modal.no then modal.no:setTitle(FF.text("UI_LFS_DeclineAction", "Decline")) end
    inviteDialogs[factionName] = modal
end

local RAID_REASON = {
    raids_disabled = "raids are disabled on this server",
    no_target = "no such faction to raid",
    self_target = "you cannot raid your own faction",
    target_no_claim = "that faction has no claim to raid",
    already_under_raid = "that faction is already under raid",
    attempts_exceeded = "your faction is out of raids for today",
    ally_target = "you can't raid an ally",
    pact_target = "a non-aggression pact protects that faction",
    outside_window = "raids aren't allowed at this hour",
    defenders_offline = "that faction has no members online to defend",
    no_active_raid = "your faction has no raid to call off",
}

-- Server-wide faction-event feed templates (see the server's broadcastEvent). Each
-- takes an ordered list of substitution strings; %s slots are filled from args in
-- order. Rendered as a distinct "[Factions]" chat line.
local EVENT_MESSAGES = {
    faction_new = "A new faction has formed: %s.",
    faction_disbanded_global = "The %s faction has disbanded.",
    faction_renamed_global = "The %s faction is now known as %s.",
    faction_decayed = "The %s faction has faded away from inactivity.",
    alliance_formed = "%s and %s have formed an alliance.",
    war_declared = "%s has declared war on %s!",
    war_won = "%s has won its war against %s!",
    war_dissolved = "The war between %s and %s has ended.",
    season_ended = "Season %s is over -- %s takes the crown!",
    pact_formed_global = "%s and %s have signed a non-aggression pact.",
    pact_broken_global = "%s has broken its pact with %s.",
    coalition_joined = "%s has joined %s's war against %s!",
    coalition_left = "%s has withdrawn from the war against %s.",
}

-- Push a local-only line into the chat panel (not networked). ISChat.addLineInChat
-- expects a ChatMessage-like object; only getTextWithPrefix/getAuthor/setText are
-- ever called on it (verified against the B42 ISChat source), so a small duck-typed
-- table is enough. Best-effort: wrapped in pcall so any chat-internal change just
-- falls back to the console print the caller already did. `prefix` defaults to
-- "[Faction]" (the framework notice tag); callers pass their own (e.g. "[Factions]"
-- for the event feed) or "" to suppress it entirely (faction chat builds its own).
local function addChat(text, prefix)
    if not (ISChat and ISChat.instance and ISChat.addLineInChat) then return end
    pcall(function()
        local inst = ISChat.instance
        local tabID = 1
        if inst.chatText and inst.chatText.tabID then
            tabID = inst.chatText.tabID
        elseif inst.tabs and inst.tabs[1] then
            tabID = inst.tabs[1].tabID
        end
        if prefix == nil then prefix = "[Faction]" end
        local prefixed = (prefix ~= "" and (prefix .. " ") or "") .. text
        local msg = {
            getTextWithPrefix = function() return prefixed end,
            getText = function() return text end,
            getAuthor = function() return nil end,
            setText = function() end,
        }
        ISChat.addLineInChat(msg, tabID)
    end)
end

-- Exported so other client files have a real fallback when HaloTextHelper is absent.
-- Without this, input complaints degrade to a console print the player never sees.
FF.addChat = addChat

-- ---------------------------------------------------------------------------
-- Recent-events log (the panel's notification bell)
-- ---------------------------------------------------------------------------
-- Chat is the wrong and only home for faction events today: a player who was looting
-- when their ally declared war has no way back to that line. This keeps the last few,
-- newest first, purely client-side and purely in memory -- it is a convenience view of
-- things the server already told us, not state, so it is deliberately not persisted.
FF.EVENT_LOG_MAX = 20
FF.eventLog = FF.eventLog or {}
FF.eventLogUnread = FF.eventLogUnread or 0

-- `line` is the already-formatted, already-localized text -- formatting once at
-- receive time keeps the template substitution in exactly one place.
function FF.pushEvent(key, line)
    if not line or line == "" then return end
    table.insert(FF.eventLog, 1, { key = key, text = line, at = getTimestamp() })
    while #FF.eventLog > FF.EVENT_LOG_MAX do table.remove(FF.eventLog) end
    FF.eventLogUnread = math.min(FF.eventLogUnread + 1, FF.EVENT_LOG_MAX)
end

-- Wrap `text` in a PZ rich-text colour tag using a {r,g,b} colour (0-1 floats).
-- ISChat lines are rendered by ISRichTextPanel, which parses <RGB:r,g,b> markup;
-- the trailing <RGB:1,1,1> resets so the rest of the line stays default-coloured.
local function colorize(c, text)
    if not c then return text end
    return string.format(" <RGB:%.3f,%.3f,%.3f> %s <RGB:1,1,1> ", c.r or 1, c.g or 1, c.b or 1, text)
end

local function richTextSafe(value, maximum)
    return FF.truncateUtf8(tostring(value or ""):gsub("[%c<>]", ""), maximum or 256)
end

-- Show the faction's message-of-the-day once, shortly after login. Copies the
-- requestInitialSync self-removing-tick pattern: on a joined client the registry lands
-- via the syncData handshake a few ticks after spawn, so we poll until the local player
-- resolves to a faction (then show its MOTD) or give up if they are simply factionless.
local motdTicks = 0
local function showMotdOnce()
    local player = getPlayer()
    if not player then return end          -- not in world yet; retry next tick
    motdTicks = motdTicks + 1
    local _, faction = FF.getFactionOfPlayer(player:getUsername())
    if faction then
        Events.OnTick.Remove(showMotdOnce)
        local motd = faction.motd
        if type(motd) == "string" and motd ~= "" then
            addChat("[MOTD] " .. motd, "")
        end
    elseif motdTicks > 600 then
        -- No faction after a generous window: factionless, so nothing to show.
        Events.OnTick.Remove(showMotdOnce)
    end
end
local function scheduleMotd()
    motdTicks = 0
    Events.OnTick.Remove(showMotdOnce)
    Events.OnTick.Add(showMotdOnce)
end
if FF._clientMotdHook then Events.OnGameStart.Remove(FF._clientMotdHook) end
FF._clientMotdHook = scheduleMotd
Events.OnGameStart.Add(scheduleMotd)

-- Format whole seconds as m:ss for the raid HUD.
local function fmtMMSS(sec)
    sec = math.max(0, math.floor(sec or 0))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- Throttle the raid progress line: the server pings ~1s, but we only surface it
-- to the player every few seconds (or the moment the held count resets to 0).
local lastRaidHudAt = 0
local lastRaidHeld = -1

-- ---------------------------------------------------------------------------
-- Client-side safehouse mirror
-- ---------------------------------------------------------------------------
-- The engine only hands a client the safehouse list when it CONNECTS, and B42 has no
-- server-side "sync this safehouse" call (SafeHouse has no syncSafehouse method; the
-- sendSafehouse* globals are client->server request senders). So a player who is already
-- online never sees a new claim or a membership change -- which is why a second member
-- accepting an invite stayed locked out until they relogged.
--
-- The server therefore broadcasts the authoritative rect + roster to everyone, and we
-- reproduce it in the local SafeHouse list. This is presentation of server state only;
-- the server remains authoritative. Same approach as JeevesClaims, which documents the
-- identical problem ("Java's native sync may not have delivered it yet").
--
-- Everything is pcall-guarded: if a B42 update moves this API the worst case is the
-- stale behaviour we already had, not an error on every sync.

local function findLocalSafehouse(x, y, w, h)
    if not (SafeHouse and SafeHouse.getSafehouseList) then return nil end
    local list = SafeHouse.getSafehouseList()
    if not list then return nil end
    for i = list:size() - 1, 0, -1 do
        local sh = list:get(i)
        if sh:getX() == x and sh:getY() == y and sh:getW() == w and sh:getH() == h then
            return sh
        end
    end
    return nil
end

local function applySafehouseSync(args)
    local x, y = math.floor(args.x or 0), math.floor(args.y or 0)
    local w, h = math.floor(args.w or 0), math.floor(args.h or 0)
    if w <= 0 or h <= 0 then return end

    local sh = findLocalSafehouse(x, y, w, h)
    if not sh then
        sh = SafeHouse.addSafeHouse(x, y, w, h, args.owner)
        if not sh then return end
    end
    if args.owner and sh.setOwner then sh:setOwner(args.owner) end

    -- Rebuild the roster wholesale: the payload is the complete membership, so clearing
    -- first is what makes a kick take effect without a relog.
    local players = sh:getPlayers()
    if not players then return end
    players:clear()
    if type(args.members) == "table" then
        for _, user in ipairs(args.members) do
            if user ~= args.owner then sh:addPlayer(user) end
        end
    else
        -- Rolling-update compatibility with the old comma-delimited payload.
        for user in string.gmatch(args.members or "", "([^,]+)") do
            if user ~= args.owner then sh:addPlayer(user) end
        end
    end
end

local function applySafehouseDrop(args)
    local sh = findLocalSafehouse(math.floor(args.x or 0), math.floor(args.y or 0),
        math.floor(args.w or 0), math.floor(args.h or 0))
    if sh and SafeHouse.removeSafeHouse then SafeHouse.removeSafeHouse(sh) end
end

local function onLfsServerCommand(module, command, args)
    if module ~= FF.MODULE then return end
    if type(command) ~= "string" then return end
    if type(args) ~= "table" then args = {} end

    if command == "notify" then
        -- Money-moving tribute replies carry their request id. Clear (or retain,
        -- for an ambiguous processing marker) the immutable client transaction
        -- before presenting the ordinary halo/chat notification.
        if args.requestId ~= nil then
            local ok, err = pcall(FF._handleTributeReply, args)
            if not ok then FF.warn("tribute reply correlation failed: " .. tostring(err)) end
        end
        local player = getPlayer()
        if not player then return end
        local template = MESSAGES[args.key] or args.key
        local extra = args.extra
        if args.key == "claim_rejected" and extra then
            extra = FF.tr(CLAIM_REASON[extra] or extra)
        elseif args.key == "raid_rejected" and extra then
            extra = FF.tr(RAID_REASON[extra] or extra)
        elseif args.key == "invite_cooldown" and extra then
            extra = formatInviteWait(extra)
        end
        local extra2 = args.extra2
        if args.key == "member_role_changed" and extra2 then extra2 = FF.tr(extra2) end
        local msg
        local directMsg = TRIBUTE_MESSAGES[args.key] or UPGRADE_MESSAGES[args.key] or DEBUG_MESSAGES[args.key]
            or VEHICLE_MESSAGES[args.key]
        if directMsg then
            if extra ~= nil and extra2 ~= nil then
                msg = FF.text(directMsg[1], directMsg[2], tostring(extra), tostring(extra2))
            elseif extra ~= nil then
                msg = FF.text(directMsg[1], directMsg[2], tostring(extra))
            else
                msg = FF.text(directMsg[1], directMsg[2])
            end
        elseif extra2 ~= nil then
            msg = FF.tr(template, tostring(extra), tostring(extra2))
        elseif extra ~= nil then
            msg = FF.tr(template, tostring(extra))
        else
            msg = FF.tr(template)
        end
        -- Red instead of the default white specifically for the locked-vehicle
        -- eject -- this is the one notify() message that means "something was
        -- just forcibly done to you", not a passive status update, so it
        -- reads as a warning above the player's own head, not a neutral note.
        if args.key == "vehicle_kicked_locked" then
            player:setHaloNote(msg, 255, 60, 60, 300)
        else
            player:setHaloNote(msg, 255, 255, 255, 300)
        end
        print("[LFS] " .. msg)
        addChat(msg)

    elseif command == "factionInvitePopup" then
        showFactionInvite(args or {})

    elseif command == "syncData" then
        -- Targeted handshake reply (see requestInitialSync): store the full
        -- registry so FF.getData()/FF.getFaction() work on this client. This is
        -- the guaranteed initial-load path for joined clients.
        ModData.add(FF.MODDATA, type(args.data) == "table" and args.data or {})
        FF.log("received registry via syncData handshake")

    elseif command == "stateDelta" then
        -- Frequent score/hour and passive-tribute changes are deliberately sent as
        -- a small patch rather than retransmitting the entire faction registry.
        local data = FF.getData()
        local scores = type(args.scores) == "table" and args.scores or {}
        local tributes = type(args.tributes) == "table" and args.tributes or {}
        for username, rec in pairs(scores) do
            if type(username) == "string" and type(rec) == "table" then
                data.playerScore[username] = rec
            end
        end
        for name, state in pairs(tributes) do
            local faction = data.factions[name]
            if faction and type(state) == "table" then
                FF.ensureTribute(faction)
                local balance = tonumber(state.balance)
                if balance and balance == balance and balance ~= math.huge and balance ~= -math.huge then
                    faction.tribute.balance = math.max(0, balance)
                end
            end
        end

    elseif command == "syncSafehouse" then
        local ok, err = pcall(applySafehouseSync, args or {})
        if not ok then
            FF.warn("safehouse sync failed: " .. tostring(err)
                .. " (claim access may need a relog)")
        end

    elseif command == "dropSafehouse" then
        local ok, err = pcall(applySafehouseDrop, args or {})
        if not ok then
            FF.warn("safehouse drop failed: " .. tostring(err))
        end

    elseif command == "report" then
        -- Multi-line diagnostic dump from /ff status or /ff selfcheck.
        print("[LFS] ---- report ----")
        for _, line in ipairs(type(args.lines) == "table" and args.lines or {}) do
            print("[LFS] " .. tostring(line))
            addChat(FF.tr(tostring(line)))
        end
        print("[LFS] ----------------")

    elseif command == "raidprogress" then
        -- Live siege HUD for members of both factions. Throttled so it does not
        -- spam every second; always surface a reset (held dropped back to 0).
        local player = getPlayer()
        if not player then return end
        local held = args.held or 0
        local now = getTimestamp()
        local reset = (held == 0 and lastRaidHeld > 0)
        if now - lastRaidHudAt >= 5 or reset then
            lastRaidHudAt = now
            local msg = FF.text("UI_LFS_RaidProgress",
                "Raid on %s -- %s / %s held (%d vs %d)", tostring(args.defender),
                fmtMMSS(held), fmtMMSS(args.need), args.attackers or 0, args.defenders or 0)
            player:setHaloNote(msg, 255, 180, 120, 250)
            print("[LFS] " .. msg)
        end
        lastRaidHeld = held

    elseif command == "factionChatMsg" then
        -- Live faction chat: (Faction) [TAG] Author: text. The "(Faction)" channel tag is a
        -- fixed colour (independent of the per-faction colour) so the channel is unmistakable
        -- next to local say -- distinct from the accent used by the event feed below. The
        -- [TAG] Author head keeps the per-faction colour for identity.
        local channel = colorize(UI and UI.color and UI.color.good, FF.tr("(Faction)"))
        local col = UI and UI.factionColor and UI.factionColor(args.faction)
        local head = colorize(col, "[" .. richTextSafe(args.tag, 24) .. "] "
            .. richTextSafe(args.author, 64) .. ":")
        addChat(channel .. " " .. head .. " " .. richTextSafe(args.text, 256), "")

    elseif command == "factionEvent" then
        -- Server-wide event feed. Format the localized template from the ordered
        -- args; colour the whole line in accent so it reads as a system notice.
        local template = EVENT_MESSAGES[args.key] or args.key
        local a = type(args.args) == "table" and args.args or {}
        local values = {}
        for i = 1, #a do values[i] = tostring(a[i] or "") end
        local line = FF.tr(template, unpack(values))
        addChat(colorize(UI and UI.color and UI.color.accent, line),
            FF.text("UI_LFS_FactionsPrefix", "[Factions]"))
        FF.pushEvent(args.key, line)
    end

    if command == "positions" then
        -- Periodic member-position payload (see the server's positionsTick).
        -- Stored on the shared FF namespace so LFS_MapOverlay can
        -- read it without a file dependency; `at` drives its staleness cutoff.
        FF.memberPositions = {
            at = getTimestamp(),
            factions = type(args.factions) == "table" and args.factions or {},
        }
    end
end
if FF._clientServerCommandHook then Events.OnServerCommand.Remove(FF._clientServerCommandHook) end
FF._clientServerCommandHook = onLfsServerCommand
Events.OnServerCommand.Add(onLfsServerCommand)

-- ---------------------------------------------------------------------------
-- Intent senders
-- ---------------------------------------------------------------------------
local function send(command, args)
    sendClientCommand(getPlayer(), FF.MODULE, command, args or {})
end

-- ---------------------------------------------------------------------------
-- Test/debug chat commands: /ff <sub> [arg]
-- ---------------------------------------------------------------------------
-- Emit a line to both the console and the chat panel.
local function output(text)
    text = FF.tr(text)
    print("[LFS] " .. text)
    addChat(text)
end

local function printInfo()
    local player = getPlayer()
    local name, faction = FF.getFactionOfPlayer(player:getUsername())
    if not faction then
        output("You are not in a faction.")
        return
    end
    local score = FF.factionScore(faction)
    output(FF.text("UI_LFS_InfoLine",
        "Faction '%s' | members=%d | claims=%d | score=%d | maxTiles=%d",
        name, FF.memberCount(faction), #(faction.claims or {}),
        math.floor(score + 0.5), math.floor(FF.maxClaimTiles(score) + 0.5)))
end

local function handleFFCommand(rest)
    local sub, arg = rest:match("^(%S+)%s*(.-)$")
    sub = sub and string.lower(sub) or ""
    local player = getPlayer()

    if sub == "panel" or sub == "ui" or sub == "open" then
        -- The Help tab advertises "/ff panel"; it is also the recovery path when the
        -- on-screen button is unavailable. Guarded so a panel error prints instead of
        -- silently eating the command.
        local ok, err = pcall(function() LasciviousFactionsSystemPanel.toggle() end)
        if not ok then output(FF.text("UI_LFS_OpenPanelFailed",
            "Could not open the faction panel: %s", tostring(err))) end
    elseif sub == "create" then
        send("createFaction", { name = arg, tag = arg })
    elseif sub == "leave" then
        send("leave")
    elseif sub == "disband" then
        send("disband")
    elseif sub == "claim" then
        FF.debugClaimAroundPlayer(player, tonumber(arg) or 20)
    elseif sub == "unclaim" then
        send("unclaim")
    elseif sub == "respawn" then
        send("setRespawn")
    elseif sub == "info" then
        printInfo()
    elseif sub == "status" then
        send("status")
    elseif sub == "selfcheck" then
        send("selfcheck")
    elseif sub == "raid" then
        if arg == "" then
            output("Usage: /ff raid <faction>")
        else
            send("startRaid", { target = arg })
        end
    elseif sub == "war" then
        if arg == "" then
            output("Usage: /ff war <faction>")
        else
            send("declareWar", { target = arg })
        end
    elseif sub == "pact" then
        if arg == "" then
            output("Usage: /ff pact <faction>  (proposes, or accepts a pending offer)")
        else
            send("proposePact", { target = arg })
        end
    elseif sub == "admin" then
        FF.adminCommand(arg)
    else
        output(FF.text("UI_LFS_CommandHelp",
            "/ff panel | create <name> | leave | disband | claim [size] | unclaim | respawn | raid <faction> | war <faction> | pact <faction> | info | status | selfcheck | admin <...>"))
        output(FF.text("UI_LFS_FactionChatHelp",
            "faction chat: /f <message>  (or /faction <message>)"))
    end
end

-- Slash commands are registered in the all-in-one chat router. It owns the one
-- ISChat wrapper and replaces this named handler on reload, so /ff, /kit and
-- /shop cannot overwrite or recursively wrap one another.

-- Replicate the two bookkeeping steps vanilla ISChat:onCommandEntered runs for every
-- native stream, so intercepted faction commands behave like /say, /all, etc.:
--   * lastChatCommand -> re-injected into the entry by ISChat:focus() on reopen (pre-fill)
--   * logChatCommand  -> pushes the full line into the per-tab up-arrow history buffer
-- We do this because our handlers `return` before vanilla runs, which would otherwise skip
-- both. `prefix` is the command the reopened entry should pre-fill (e.g. "/f "); `original`
-- is the exact text typed, stored in the up-arrow log. Best-effort: chat internals are
-- guarded elsewhere in this file too.
local function rememberChatCommand(instance, prefix, original)
    pcall(function()
        if instance.chatText then instance.chatText.lastChatCommand = prefix end
        if instance.logChatCommand then instance:logChatCommand(original) end
    end)
end

-- Vanilla ISChat:onCommandEntered ends with `doKeyPress(false)` + `timerTextEntry = 20`.
-- That swallows the Enter that was just pressed for ~20 ticks (see ISChat.ontick) so it
-- does NOT immediately pop a second KeyPressed -> onToggleChatBox -> focus(), which would
-- re-open the chat box. Our /f and /ff intercepts `return` before that tail, so without
-- this the chat stays open after sending a faction message. Best-effort (guarded).
local function closeChatAfterCommand(instance)
    pcall(function()
        if doKeyPress then doKeyPress(false) end
        instance.timerTextEntry = 20
    end)
end

ChatRouter.register("factions", function(instance, text)
    if text then
        local rest = text:match("^%s*/ff%s+(.-)%s*$")
        if rest then
            rememberChatCommand(instance, "/ff ", text)
            instance.textEntry:setText("")
            instance:unfocus()
            closeChatAfterCommand(instance)
            handleFFCommand(rest)
            return true
        end
        -- Faction chat: "/f <msg>" or "/faction <msg>". Routed to the server, which
        -- fans it out to online faction members only (Handlers.factionChat).
        local isFaction = text:match("^%s*/faction%s+.-%s*$")
        local chat = text:match("^%s*/faction%s+(.-)%s*$") or text:match("^%s*/f%s+(.-)%s*$")
        if chat and chat ~= "" then
            rememberChatCommand(instance, isFaction and "/faction " or "/f ", text)
            instance.textEntry:setText("")
            instance:unfocus()
            closeChatAfterCommand(instance)
            sendClientCommand(getPlayer(), FF.MODULE, "factionChat", { text = chat })
            return true
        end
    end
    return false
end)

-- ---------------------------------------------------------------------------
-- Raid PVP auto-enable (spike -- best-effort, RaidForcePvp)
-- ---------------------------------------------------------------------------
-- Vanilla has no server-side force-PVP: safety is the client-side, self-toggled
-- player:getSafety() manager. So while the local player stands inside a claim that
-- is under active raid, we drop their safety here (enabling PVP) and let normal
-- control return once the raid ends or they leave. This is inherently best-effort;
-- the whole thing is pcall-guarded and self-disables after one failure so a B42 API
-- change degrades to "toggle PVP manually" instead of erroring every tick. The
-- capture logic is entirely server-side and does not depend on this working.
local pvpForceBroken = false          -- set true after a failure; stop trying
local nextPvpCheck = 0

-- Is the given tile inside a claim whose faction currently has an active raid?
local function tileIsUnderRaid(x, y)
    local factionName = Claims.factionAt(x, y)
    if not factionName then return false end
    local faction = FF.getFaction(factionName)
    return faction ~= nil and faction.raid ~= nil
end

local function raidPvpTick()
    if pvpForceBroken then return end
    if not FF.getOptions().raidForcePvp then return end

    local now = getTimestamp()
    if now < nextPvpCheck then return end
    nextPvpCheck = now + 1

    -- Only meaningful when the server safety system gates PVP.
    if not (getServerOptions and getServerOptions():getBoolean("SafetySystem")) then return end

    local player = getPlayer()
    if not player then return end

    local ok, err = pcall(function()
        if not tileIsUnderRaid(math.floor(player:getX()), math.floor(player:getY())) then
            return
        end
        local safety = player:getSafety()
        -- isCurrent() == true means safety is ON (PVP disabled); drop it if allowed.
        if safety and safety:isCurrent() and safety:isToggleAllowed() then
            safety:toggleSafety()
            print("[LFS] raid: auto-enabled PVP (dropped safety) inside contested claim")
        end
    end)
    if not ok then
        pvpForceBroken = true
        FF.warn("raid PVP auto-enable failed: " .. tostring(err)
            .. " (falling back to manual PVP toggle; capture logic is unaffected)")
    end
end
if FF._clientRaidPvpTickHook then Events.OnTick.Remove(FF._clientRaidPvpTickHook) end
FF._clientRaidPvpTickHook = raidPvpTick
Events.OnTick.Add(raidPvpTick)
