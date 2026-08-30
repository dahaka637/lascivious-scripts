# Module: Time Vote

| Field | Value |
|---|---|
| `module_key` | `time-vote` |
| Bundled location | `Contents/mods/LasciviousScripts/42/media/lua/{shared,client,server}/LasciviousScripts/TimeVote/` |
| Origin | own code (not derived from any upstream mod) |
| Namespace | `LasciviousScripts.TimeVote` |
| Sandbox option table | `LasciviousScriptsTimeVote` |
| Current version | 2.2.0 (`Core.VERSION`) |

This is a module of LasciviousScripts (`LasciviousScripts.TimeVote`), not a standalone mod.

## Production compatibility note (2026-08-27)

The dedicated-server Kahlua environment used in production had no callable global `next`, causing
`refreshElectorate` to throw every periodic resync while the roster was empty. The empty-roster
check now reuses `sameOnlineSet(lastOnline, current)` (implemented with `pairs`), preserving the
same state transition without depending on that global. See `review/09_PRODUCTION_FINDINGS.md`
PROD-001; dedicated post-patch retest is still required.

## Correct architecture for B42.20.x

The custom panel only collects multiplayer votes. The server owns consensus. When consensus grants
5x or 20x, the multiplier is applied once. There is no `enforceLocalSpeed()` loop and nothing runs
on `OnTickEvenPaused` to restore a fast speed after the game has returned to 1x.

B42.20.2 deliberately makes `SpeedControls:getCurrentGameSpeed()` return `1` while running as a
multiplayer client. Because of that, several single-player interruption gates never execute in MP.
The client mirrors only those disabled vanilla gates:

- `IsoPlayer:isJustMoved()` while not following/pathfinding -> 1x;
- falling / on fire -> 1x;
- a spotted zombie on the same floor within the vanilla 4-tile radius, or 7 tiles when more than
  four zombies are visible -> 1x;
- when the native `TimedActionGameSpeedReset` option is enabled, transition from doing a timed
  action to no longer doing one -> 1x.

Other vanilla systems that still reset `GameTime` in multiplayer are not duplicated. The client
simply observes that the multiplier became lower than the granted speed and sends a cancellation
to the server. This includes attack-state code that still calls `SetCurrentGameSpeed(1)` directly.
Any one client's vanilla interruption cancels fast-forward for every player.

## Speeds and voting

All four native levels are exposed: 1x / 5x / 20x / 40x (Wait).

- 5x or 20x starts only when every online player selected the same level.
- A lone player is unanimity by definition, so one click applies immediately.
- A lone player can switch directly 5x <-> 20x in one click.
- With multiple players, changing an active fast speed invalidates the old consensus and returns
  to 1x while the new vote is collected.
- Clicking 1x while fast-forward is active immediately returns the local client to 1x and asks
  the server to cancel the consensus globally.
- Join/leave, player death, SoloOnly gating, disabling the feature and an empty server reset 1x.

Votes and online participants are keyed by multiplayer online ID, with username fallback only when
an ID is unavailable. Sync packets carry a monotonically increasing revision. A same-revision
periodic resync cannot resurrect 5x/20x after a native interruption has already requested 1x.

## UI

The speed icons (`SpeedPanel.lua`) are drawn at 50% of their source dimensions. `tv_user.png`, the
vote-intention indicator, remains at its original size. The outer panel and every child speed
button have their background and border disabled, leaving only the icons/counter visible. No
player-facing text is drawn by this panel (icon + vote-count only), which sidesteps PT-BR
localization entirely for this UI.

## Timed actions

B42 multiplayer `NetTimedAction` completion is based on server real time. The server therefore
keeps the existing duration bridge so reading/crafting/washing/eating can follow 5x/20x. Unlike
the old implementation, duration is also restored/rebased when speed decreases or returns to 1x.

The client-side `setJobDelta()` and manual read-page synchronization were removed. B42's
server-side `ISReadABook` derives page progress from the authoritative timed-action progress.

## Important invariants

1. Never recreate a per-tick `GameTime:setMultiplier(expected)` enforcement loop.
2. Never re-add `OnTickEvenPaused` multiplier enforcement.
3. Never re-add client-side `setJobDelta()` acceleration.
4. Never use `SpeedControls:getCurrentGameSpeed()` as the MP truth; B42.20.2 returns 1 on clients.
5. A native/local reset to 1x wins over fast-forward and is propagated globally.
6. Never bridge back to the native `zombie.ui.SpeedControls` widget — already tried and dropped
   (unreliable solo-vote application in MP, and no localization hook). The custom `SpeedPanel` +
   server-authoritative consensus is the design going forward.

## Sandbox options

| Option | Type | Default | Purpose |
|---|---|---|---|
| `LasciviousScriptsTimeVote.Enabled` | boolean | `true` | Master on/off switch. |
| `LasciviousScriptsTimeVote.SoloOnly` | boolean | `false` | Fast-forward only while exactly one player is online. |
| `LasciviousScriptsTimeVote.DebugLogging` | boolean | `false` | Console logging of `NetTimedAction` acceleration details. |
