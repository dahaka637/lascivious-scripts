require "ISUI/ISPostDeathUI"

EvilMortyDeathScreen = EvilMortyDeathScreen or {}
local EMDS = EvilMortyDeathScreen

EMDS.SOUND_NAME   = "EvilMortyDeathTheme"

EMDS.RESET_TIME   = 5.0
EMDS.DEFAULT_ZOOM = 1.0
EMDS.ZOOM_DELAY   = 10.0
EMDS.FADE_DELAY   = 85.0
EMDS.FADE_TIME    = 5.0
EMDS.MAX_ZOOM     = 2.5
EMDS.COARSE_STEP  = 9.0

EMDS.LEVELS       = { 2.5, 2.25, 2.0, 1.75, 1.5, 1.25, 1.0, 0.75, 0.5, 0.25 }
EMDS.PROBE        = { 1.0 }

EMDS.state = nil

function EMDS.installLevels(levels)
	if setZoomLevels == nil then return false end
	if pcall(setZoomLevels, unpack(levels)) then return true end
	return pcall(setZoomLevels, levels)
end

function EMDS.readZoom(st)
	if not EMDS.installLevels(EMDS.PROBE) then return nil end
	local core = getCore()
	local a = core:getNextZoom(st.playerNum, 1)
	local b = core:getNextZoom(st.playerNum, -1)
	if a ~= b then return nil end
	st.levelsChanged = true
	return a
end

function EMDS.applyZoom(st, value)
	local cur = EMDS.readZoom(st)
	if cur == nil then return false end

	if value > cur + 0.0001 then
		if not EMDS.installLevels({ value, cur }) then return false end
		getCore():doZoomScroll(st.playerNum, 1)
	elseif value < cur - 0.0001 then
		if not EMDS.installLevels({ cur, value }) then return false end
		getCore():doZoomScroll(st.playerNum, -1)
	end
	return true
end

function EMDS.beginZoom(st)
	local core = getCore()
	st.zoomStarted = true

	st.zoomWasEnabled = core:isZoomEnabled()
	if not st.zoomWasEnabled then core:setZoomEnalbed(true) end

	local cur = EMDS.readZoom(st)
	if cur == nil then
		EMDS.fallBackToCoarse(st)
		return
	end
	st.rawStart = cur
	st.mode = "smooth"
end

function EMDS.fallBackToCoarse(st)
	EMDS.installLevels(EMDS.LEVELS)
	st.mode = "coarse"
	st.coarseSteps = 0
	st.zoomDir = nil
end

function EMDS.desiredZoom(st, elapsed)
	local target = EMDS.MAX_ZOOM
	if target < EMDS.DEFAULT_ZOOM then target = EMDS.DEFAULT_ZOOM end

	if elapsed < EMDS.RESET_TIME then
		local p = elapsed / EMDS.RESET_TIME
		return st.rawStart + (EMDS.DEFAULT_ZOOM - st.rawStart) * p
	elseif elapsed < EMDS.ZOOM_DELAY then
		return EMDS.DEFAULT_ZOOM
	end

	local p = (elapsed - EMDS.ZOOM_DELAY) / (EMDS.FADE_DELAY - EMDS.ZOOM_DELAY)
	if p > 1 then p = 1 end
	return EMDS.DEFAULT_ZOOM + (target - EMDS.DEFAULT_ZOOM) * p
end

function EMDS.updateSmoothZoom(st, elapsed)
	if not EMDS.applyZoom(st, EMDS.desiredZoom(st, elapsed)) then
		EMDS.fallBackToCoarse(st)
	end
end

function EMDS.updateCoarseZoom(st, elapsed)
	if st.coarseMaxed then return end
	local due = EMDS.ZOOM_DELAY + st.coarseSteps * EMDS.COARSE_STEP
	if elapsed < due then return end
	st.coarseSteps = st.coarseSteps + 1

	local core = getCore()
	if st.zoomDir == nil then
		local a = core:getNextZoom(st.playerNum, 1)
		local b = core:getNextZoom(st.playerNum, -1)
		st.zoomDir = (a >= b) and 1 or -1
	end

	local nextLevel = core:getNextZoom(st.playerNum, st.zoomDir)
	if st.coarseLast and nextLevel <= st.coarseLast + 0.0001 then
		st.coarseMaxed = true
		return
	end
	st.coarseLast = nextLevel
	core:doZoomScroll(st.playerNum, st.zoomDir)
	st.coarseDone = (st.coarseDone or 0) + 1
end

function EMDS.restoreZoom(st)
	local core = getCore()
	if not core then return end

	if st.mode == "smooth" and st.rawStart then
		EMDS.applyZoom(st, st.rawStart)
	elseif st.mode == "coarse" and st.zoomDir and st.coarseDone then
		for _ = 1, st.coarseDone do
			core:doZoomScroll(st.playerNum, -st.zoomDir)
		end
	end

	if st.levelsChanged then
		pcall(function() core:zoomLevelsChanged() end)
	end
	if st.zoomWasEnabled == false then core:setZoomEnalbed(false) end
	if st.autoZoom then core:setAutoZoom(st.playerNum, true) end
end

function EMDS.onPlayerDeath(playerObj)
	if not playerObj then return end
	if EMDS.state then return end

	local playerNum = playerObj:getPlayerNum() or 0
	local core = getCore()
	local sm = getSoundManager()

	if sm then
		pcall(function() sm:StopMusic() end)
	end

	local st = {
		playerNum     = playerNum,
		startMs       = getTimestampMs(),
		sound         = nil,
		mode          = nil,
		zoomStarted   = false,
		zoomDir       = nil,
		coarseSteps   = 0,
		coarseMaxed   = false,
		levelsChanged = false,
		autoZoom      = core and core:getAutoZoom(playerNum) or false,
	}

	if core and st.autoZoom then
		core:setAutoZoom(playerNum, false)
	end

	if sm then
		st.sound = sm:playUISound(EMDS.SOUND_NAME)
	end

	EMDS.state = st
end

function EMDS.stop()
	local st = EMDS.state
	if not st then return end
	EMDS.state = nil

	local sm = getSoundManager()
	if sm and st.sound and st.sound ~= 0 then
		sm:stopUISound(st.sound)
	end

	if st.zoomStarted then
		EMDS.restoreZoom(st)
	end
end

function EMDS.onPanelPrerender(panel)
	local st = EMDS.state
	if not st then return end
	if panel.playerIndex ~= st.playerNum then return end

	local now = getTimestampMs()
	local elapsed = (now - st.startMs) / 1000

	-- Used to re-anchor a UI emitter to the corpse's world position every
	-- frame (EMDS.followSound/soundAnchor, removed 2026-08-30, explicit
	-- request) so the theme panned/attenuated like it came from the body as
	-- the death-cam zoomed out. That's exactly what made it feel louder in
	-- one ear than the other as the camera moved -- playUISound's own
	-- playback (already triggered in onPlayerDeath) is left flat/centered.

	if not st.zoomStarted then
		EMDS.beginZoom(st)
	end
	if st.mode == "smooth" then
		EMDS.updateSmoothZoom(st, elapsed)
	elseif st.mode == "coarse" and elapsed >= EMDS.ZOOM_DELAY then
		EMDS.updateCoarseZoom(st, elapsed)
	end

	if elapsed >= EMDS.FADE_DELAY then
		local a = (elapsed - EMDS.FADE_DELAY) / EMDS.FADE_TIME
		if a > 1 then a = 1 end
		panel:drawRect(panel.screenX - panel:getAbsoluteX(), panel.screenY - panel:getAbsoluteY(),
			panel.screenWidth, panel.screenHeight, a, 0, 0, 0)
		EMDS.highlightButtons(panel, a)
	end
end

function EMDS.highlightButton(button, a)
	if button and button.borderColor then
		button.borderColor.a = 0.3 + 0.7 * a
	end
end

function EMDS.highlightButtons(panel, a)
	EMDS.highlightButton(panel.buttonRespawn, a)
	EMDS.highlightButton(panel.buttonExit, a)
	EMDS.highlightButton(panel.buttonQuit, a)
end

if not EMDS._lsInstalled then
	EMDS._lsInstalled = true

	local ISPostDeathUI_prerender = ISPostDeathUI.prerender
	function ISPostDeathUI:prerender()
		ISPostDeathUI_prerender(self)
		EvilMortyDeathScreen.onPanelPrerender(self)
	end

	local ISPostDeathUI_onMouseWheel = ISPostDeathUI.onMouseWheel
	function ISPostDeathUI:onMouseWheel(del)
		if EvilMortyDeathScreen.state then return true end
		if ISPostDeathUI_onMouseWheel then
			return ISPostDeathUI_onMouseWheel(self, del)
		end
		return false
	end

	local ISPostDeathUI_onExit = ISPostDeathUI.onExit
	function ISPostDeathUI:onExit()
		EvilMortyDeathScreen.stop()
		ISPostDeathUI_onExit(self)
	end

	local ISPostDeathUI_onRespawn = ISPostDeathUI.onRespawn
	function ISPostDeathUI:onRespawn()
		EvilMortyDeathScreen.stop()
		ISPostDeathUI_onRespawn(self)
	end

	local ISPostDeathUI_onConfirmQuitToDesktop = ISPostDeathUI.onConfirmQuitToDesktop
	function ISPostDeathUI:onConfirmQuitToDesktop(button)
		if button and button.internal == "YES" then
			EvilMortyDeathScreen.stop()
		end
		ISPostDeathUI_onConfirmQuitToDesktop(self, button)
	end

	Events.OnPlayerDeath.Add(EvilMortyDeathScreen.onPlayerDeath)
	Events.OnCreatePlayer.Add(EvilMortyDeathScreen.stop)
	Events.OnMainMenuEnter.Add(EvilMortyDeathScreen.stop)
end
