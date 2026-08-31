
--- @sandbox BloodlustO "Bloodlust Overwhelming"
--- @class BloodlustSandboxOptions
---
---
--- @field KillCravingMaxHours number (0.5 to 8760.0) = 36
--- How many in-game hours without killing it takes to reach maximum bloodlust.
---
--- @field KillCravingMaxHoursExponent number (0.1 to 10) = 3
--- Determines when most of the bloodlust is added.
---
--- 1 = linear increase, >1 higher increase the more time passes, <1 lower increase the more time passes.
---
--- For 36 hours until max bloodlust and exponent 3, first 1% bloodlust is reached at 7th hour, 50% at 29th hour and 100% at 36th hour.
---
--- @field KillCravingBloodinessFactor number (0.0 to 10.0) = 0.5
--- How much your bloodiness reduces the time it takes to reach 100% bloodlust.
---
--- 0.5 means 50% less time at 100% bloodiness.
---
--- @field KillCravingStaleBloodinessMultiplier number (0.0 to 10.0) = 1.0
--- How much staleness multiplies kill craving bloodiness factor.
---
--- 1.0 means 100% stale bloodiness makes your 50% bloodiness count as 100% bloodiness.
---
--- @field KillCravingHealthExponent number (0.0 to 10.0) = 2
--- How much low health increases the time it takes to reach 100% bloodlust.
---
--- 2.0 means on 50% health it takes ~3 times longer to reach 100% bloodlust.
---
---
--- @field FightlessCombatAfterMinutes number (0 to 60) = 5
--- Spending this much time in combat without hitting anyone will start increasing your bloodlust (If not in frenzy).
---
--- @field FightlessCombatBloodlustPerMinute number (0.0 to 100.0) = 3
--- How much bloodlust to add every minute you aren't hitting anyone in combat.
---
--- With 3, it'll take 33 minutes to reach 100 bloodlust.
---
--- @field ConsiderShovesAndStompsAsHits boolean = false
--- Whether shoving and stomping are considered as hits (Used for fightless combat bloodlust increase).
---
--- @field ConsiderCarDriveOverAsCombat boolean = false
--- Whether killing zombies by driving over them is considered as hits (Used for fightless combat bloodlust increase).
---
--- @field FightlessCombatBloodlustWhileDriving boolean = true
--- Whether your bloodlust will increase without fighting while driving.
---
---
--- @field GettingBloodyBloodlustChange number (-10.0 to 10.0) = 0.25
--- How much bloodlust to add (positive) or remove (negative) proportional to you getting bloodier.
---
--- With 0.25, +100% bloodiness on any individual body part, clothing or weapon will add 25 bloodlust.
---
--- @field GettingBloodyStressChange number (-100.0 to 100.0) = -0.5
--- How much stress to add (positive) or remove (negative) proportional to you getting bloodier.
---
--- With -0.5, +100% bloodiness on any individual body part, clothing or weapon will remove 50% stress.
---
--- @field GettingBloodyUnhappinessChange number (-100.0 to 100.0) = -0.3
--- How much happiness to add (positive) or remove (negative) proportional to you getting bloodier.
---
--- With -0.3, +100% bloodiness on any individual body part, clothing or weapon will remove 30% happiness.
---
---
---
--- @field BloodlustLevelForMoodDebuffs number (0.0 to 100.0) = 50
--- Bloodlust after which unhappiness, stress and boredom starts to increase if you aren't fighting.
---
--- The increase starts small, and reaches its maximum at 100% bloodlust.
---
--- @field MoodDebuffBloodlustExponent number (0.0 to 10.0) = 2
--- Determines when most of the mood debuffs are applied depending on bloodlust.
---
--- 1 = linear increase, >1 higher increase the higher the bloodlust, <1 lower increase the higher the bloodlust.
---
--- @field BloodinessImpactOnMoodDebuffs number (0.0 to 10.0) = 0.5
--- How much your bloodiness reduces the time it takes to reach 100% unhappiness/stress/boredom.
---
--- 0.5 means 50% quicker worst mood if 100% bloody.
---
--- @field MaxBloodlustDepressionAfterHours number (0.5 to 8760.0) = 24
--- At 100% bloodlust, it will take this in-game hours to reach 100% unhappiness.
---
--- Note: Because boredom is also added, and boredom increases unhappiness, the actual depression time will be lower.
---
--- @field MaxBloodlustFullStressAfterHours number (0.5 to 8760.0) = 36
--- At 100% bloodlust, it will take this in-game hours to reach 100% stress.
---
--- Note: Idle stress reduction is negated once mood debuffs kick in, so this is pretty accurate.
---
--- @field MaxBloodlustFullBoredomAfterHours number (0.5 to 8760.0) = 8
--- At 100% bloodlust, it will take this in-game hours to reach 100% boredom.
---
---
---
--- @field KillBloodlustReduction number (0.0 to 10000.0) = 10
--- Every generic kill reduces this much bloodlust.
--- @field SharpKillBloodlustReduction number (0.0 to 10000.0) = 12
--- Every kill with sharp weapons (spears, axes, blades) reduces this much bloodlust.
--- @field KnifeKillBloodlustReduction number (0.0 to 10000.0) = 15
--- Every kill with knives reduces this much bloodlust.
--- @field RangedKillBloodlustReduction number (0.0 to 10000.0) = 5
--- Every ranged kill (with firearms) reduces this much bloodlust.
---
---
--- @field HitBloodlustReduction number (0.0 to 10000.0) = 0.1
--- Every generic hit reduces this much bloodlust.
--- @field SharpHitBloodlustReduction number (0.0 to 10000.0) = 0.25
--- Every hit with sharp weapons (spears, axes, blades) reduces this much bloodlust.
--- @field KnifeHitBloodlustReduction number (0.0 to 10000.0) = 0.5
--- Every hit with knives reduces this much bloodlust.
--- @field RangedHitBloodlustReduction number (0.0 to 10000.0) = 0.05
--- Every ranged hit (with firearms) reduces this much bloodlust.
---
--- @field HurtBloodlustChange number (-100.0 to 100.0) = 100
--- How much bloodlust to increase/decrease when you get hit by a zombie.
---
---
---
--- @field BloodinessForFrenzy number (0.0 to 1000.0) = 100
--- How bloody overall you must be to start progressing towards frenzy.
---
--- You may set this beyond 100% if you intend to require at least some freshness.
---
--- @field BloodinessFreshnessMultiplierForFrenzy number (0.0 to 10000.0) = 0.5
--- How much bloodiness freshness makes bloodiness count as more.
---
--- 0.5 means 100% freshness counts like +50% more of bloodiness.
---
--- @field BloodinessFreshnessFrenzyProgressExponent number (0.0 to 100.0) = 4
--- Determines how strongly bloodiness freshness accelerates progress toward frenzy.
---
--- At 4, 50% freshness doubles the rate of frenzy progression, while 100% freshness quadruples it.
---
--- @field BloodlustOverreducedForFrenzy number (1.0 to 10000.0) = 50
--- You must reduce this much bloodlust (via hits/kills) while having no bloodlust to go into frenzy.
---
--- @field FrenzyPerMinuteDecayInCombat number (0.0 to 100.0) = 1
--- How much frenzy bloodlust to reduce in combat.
---
--- Note that this applies to progress towards frenzy (the bloodlust you reduced while at 0).
---
---@field FrenzyPerMinuteDecayOutOfCombat number (0.1 to 100.0) = 3
--- How much frenzy bloodlust to reduce out of combat.
---
--- Note that this applies to progress towards frenzy (the bloodlust you reduced while at 0).
---
---
---
--- @field FrenzyKillBloodlustIncrease number (0.0 to 10000.0) = 10
--- Every generic kill increases this much bloodlust in frenzy.
--- @field FrenzySharpKillBloodlustIncrease number (0.0 to 10000.0) = 12
--- Every kill with sharp weapons (spears, axes, blades) increases this much bloodlust in frenzy.
--- @field FrenzyKnifeKillBloodlustIncrease number (0.0 to 10000.0) = 15
--- Every kill with knives increases this much bloodlust in frenzy.
--- @field FrenzyRangedKillBloodlustIncrease number (0.0 to 10000.0) = 5
--- Every ranged kill (with firearms) increases this much bloodlust in frenzy.
---
--- @field FrenzyHitBloodlustIncrease number (0.0 to 10000.0) = 0.1
--- Every generic hit increases this much bloodlust in frenzy.
--- @field FrenzySharpHitBloodlustIncrease number (0.0 to 10000.0) = 0.25
--- Every hit with sharp weapons (spears, axes, blades) increases this much bloodlust in frenzy.
--- @field FrenzyKnifeHitBloodlustIncrease number (0.0 to 10000.0) = 0.5
--- Every hit with knives increases this much bloodlust in frenzy.
--- @field FrenzyRangedHitBloodlustIncrease number (0.0 to 10000.0) = 0.05
--- Every ranged hit (with firearms) increases this much bloodlust in frenzy.
---
--- @field FrenzyHurtBloodlustChange number (-100.0 to 100.0) = -50
--- How much bloodlust to increase/decrease when you get hit by a zombie in frenzy.
---
---
---
--- @field BloodlustChangeDestress number (0.0 to 100.0) = 5
--- Proportion of bloodlust change from hits/kills to add as stress reduction.
---
--- With 5, it'll take 20 bloodlust increased/decreased to go from 100% stress to absolute chill.
---
--- @field BloodlustChangeHappiness number (0.0 to 100.0) = 2
--- Proportion of bloodlust change from hits/kills to add as unhappiness reduction.
---
--- With 2, it'll take 50 bloodlust increased/decreased to go from depression to happiness.
---
---
---
--- @field BloodlustAdditionalDamage number (0.0 to 2.0) = 0.5
--- How much additional damage to deal at instakill bloodlust level.
---
--- The bonus increases smoothly as bloodlust rises, reaching the value you set at the bloodlust level required for instakill.
---
--- With bloodlust required for instakill set to 90 and default additional damage of 0.5,
--- you'll deal 0.5 bonus damage at 90 bloodlust, 0.25 at 45 bloodlust, etc.
---
--- Max zombie health is 2.0.
---
--- @field BloodlustAdditionalDamageInFrenzy number (0.0 to 2.0) = 0.75
--- How much additional damage to deal at instakill bloodlust level in frenzy.
---
--- The bonus increases smoothly as bloodlust rises, reaching the value you set at the bloodlust level required for instakill.
---
--- With bloodlust required for instakill set to 90 and default additional damage of 0.75,
--- you'll deal 0.75 bonus damage at 90 bloodlust, 0.375 at 45 bloodlust, etc.
---
--- Max zombie health is 2.0.
---
--- @field AdditionalDamageWithBareHands boolean = false
--- Whether to deal additional damage for hits with bare hands.
---
--- @field AdditionalDamageWorksForRanged boolean = false
--- Whether to deal additional damage for hits firearms.
---
---
---
--- @field InstakillAtBloodlust number (0.0 to 100.0) = 90
--- Bloodlust level above which your next hit will kill instantly.
---
--- @field InstakillWorksForRanged boolean = true
--- Whether instakilling is possible when shooting zombies.
---
--- Finally, your tiny lil' pistolittle can annihilate a zombie out of existence even when it barely touched its pinky.
---
--- @field InstakillDamage number (0.01 to 1000.0) = 2
--- How much damage is dealt on instakill.
---
--- You can reduce this to turn instakilling into massive damage dealing instead.
---
--- Max zombie health is 2.0.
---
---
--- @field InstakillBloodlustReduction number (0.0 to 10000.0) = 20
--- How much bloodlust is removed when an instakill is triggered.
--- @field InstakillBloodlustReductionInFrenzy number (0.0 to 10000.0) = 40
--- How much bloodlust is removed when an instakill is triggered in frenzy.
---
---
--- @field InstakillDueToCravingStrain number (0.0 to 10000.0) = 30
--- How much muscle strain is spread across your whole body when instakill is triggered.
---
--- One body part can hold 100 strain.
---
---
--- @field FrenzyInstakillBacklashStrain number (0.0 to 10000.0) = 20
--- How much muscle strain will be spread across your whole body for each instakill in frenzy.
---
--- One body part can hold 100 strain.
---
--- @field FrenzyInstakillBacklashFatigue number (0.0 to 100.0) = 2.5
--- How much fatigue will be added for each instakill in frenzy.
---
--- With 2.5 it'll take ~40 instakills for 100% fatigue.
---
--- @field FrenzyInstakillBacklashHunger number (0.0 to 100.0) = 3.33
--- How much hunger will be added for each instakill in frenzy.
---
--- With 3.33 it'll take ~30 instakills for 100% hunger.
---
--- @field FrenzyInstakillBacklashThirst number (0.0 to 100.0) = 5
--- How much thirst will be added for each instakill in frenzy.
---
--- With 5 it'll take ~20 instakills for 100% thirst.
---
--- @field FrenzyBacklashPerMinute number (0.0 to 10000.0) = 0.5
--- How much of backlash to apply every in-game minute once frenzy ends.
---
--- Each instakill in frenzy adds 1.0 to backlash.
---
--- With 0.5 it'll take ~3.3 in-game hours to apply backlash for 100 instakills.
---
---
---
--- @field FrenzyInstakillAreaDamage number (0.0 to 10000.0) = 1
--- How much damage to additionally spread evenly to nearby zombies while instakilling in frenzy.
---
--- Max zombie health is 2.0.
---
--- @field FrenzyInstakillAreaRadius number (0.1 to 100.0) = 1
--- Maximum tiles from instakilled zombie in which others will be affected.
---
--- @field FrenzyInstakillZombiesLimit number (1 to 10000) = 5
--- Maximum number of zombies affected by area damage.
---
--- @field InstakillSoundRadius number (0.0 to 10000.0) = 30
--- Zombies this many tiles away will be attracted to player on instakill.
---
--- For reference, shout sound radius is 30. See pzwiki.net/wiki/Noise
---
--- @field InstakillSoundRadiusInFrenzy number (0.0 to 10000.0) = 40
--- Zombies this many tiles away will be attracted to player on instakill in frenzy.
---
--- For reference, shout sound radius is 30. See pzwiki.net/wiki/Noise
---
--- @field RevengeInstakillSoundRadius number (0.0 to 10000.0) = 50
--- Zombies this many tiles away will be attracted to player on instakill triggered after getting hit.
---
--- For reference, shout sound radius is 30. See pzwiki.net/wiki/Noise
---
---
---
--- @field FrenzyHurtRevengeAtBloodlust number (0.0 to 100.0) = 50
--- In frenzy, getting hit with this much bloodlust will instakill the attacker and push back other zombies around.
---
--- @field FrenzyHurtRevengeDamage number (0.0 to 1000.0) = 2
--- How much damage to deal to an attacker when you get hit in frenzy.
---
--- Max zombie health is 2.0, so 2 damage will instakill whoever attacked you.
---
--- @field FrenzyHurtRevengePushTiles number (0.0 to 1000.0) = 4
--- Zombies within this many tiles to player will be pushed back on hit revenge.
---
--- @field FrenzyHurtRevengeZombiesPushed number (0 to 1000) = 20
--- Maximum number of zombies pushed back when on hit revenge.
---
--- @field FrenzyHurtRevengeKnockDownChance number (0.0 to 100.0) = 30
--- Percentage of zombies that will be knocked down on hit revenge.
---
--- @field FrenzyHurtSoundRadius number (0.0 to 1000.0) = 60
--- Zombies this many tiles away will be attracted to player in frenzy that just got hit.
---
--- For reference, shout sound radius is 30. See pzwiki.net/wiki/Noise
---
---
---
--- @field MaxBloodlustFrenzyWeaponSpeedIncrease number (0.0 to 10.0) = 0.25
--- How much faster you swing your weapon while in frenzy as you reach 100% bloodlust.
--- (The speed increases smoothly as bloodlust rises.)
---
--- 0.25 means 25% faster at 100% bloodlust. At 50% bloodlust you'll swing 12.5% faster.
---
--- @field MaxBloodlustFrenzyMoveSpeedIncrease number (0.0 to 1.0) = 0.25
--- How much faster you move while in frenzy as you reach 100% bloodlust.
--- (The speed increases smoothly as bloodlust rises.)
---
--- 0.25 means 25% faster at 100% bloodlust. At 50% bloodlust you'll be 12.5% faster.
---
---
---
--- @field BloodlustForExertionBuffering number (0.0 to 100.0) = 50
--- Minimum bloodlust to start buffering exertion at.
---
--- Note that in frenzy your exertion is always buffered.
---
--- @field BufferExertionAfter number (0.0 to 100.0) = 25
--- Once you reach this level of exertion, start storing it.
---
--- 25 if when first exertion moodle appears.
---
--- @field MaxBufferedExertion number (0.0 to 10000.0) = 100
--- How much exertion can be stored for later.
---
--- @field ExertionBufferingMultiplier number (0.1 to 10.0) = 1.0
--- How much of the removed exertion is stored for later.
---
--- 1.5 means you'll be later reliving 50% more exertion than you actually stored.
---
--- @field ExertionBufferedPerMinute number (0.1 to 100.0) = 2
--- How much of exertion to store every minute.
---
--- With 2 it'll take 50 minutes to store 100 exertion.
---
--- @field ExertionUnbufferedPerMinute number (0.1 to 100.0) = 3
--- How much of stored exertion to unleash back every minute.
---
--- With 3 it'll take ~30 minutes to unleash back 100 exertion.
---
--- @field ExertionUnbufferingHunger number (0.0 to 100.0) = 0.3
--- Proportion of hunger to add based on unleashed exertion.
---
--- 0.3 means every 100 of exertion unleashed adds 30% hunger.
---
--- @field ExertionUnbufferingThirst number (0.0 to 100.0) = 0.4
--- Proportion of thirst to add based on unleashed exertion.
---
--- 0.4 means every 100 of exertion unleashed adds 40% thirst.
---
--- @field ExertionUnbufferingStrain number (0.0 to 100.0) = 0.8
--- Proportion of muscle strain to spread across your whole body based on unleashed exertion.
---
--- 0.8 means every 100 of exertion unleashed adds 80 strain.
---
--- @field MinutesSinceCombatForUnbuffering number (0 to 525600) = 30
--- How many minutes must pass since combat before exertion unbuffering can start.
---
---
---
--- @field BloodlustForPanicImmunity number (0.0 to 100.0) = 80
--- You won't panic when above this bloodlust.
---
--- You'll also recover from panic significantly faster the closer you are to immunity.
---
---
---
--- @field FreshBloodinessDecayMode number 1|2 = 1
--- Defines how to decay bloodiness freshness.
---
--- 1. "Total" - remove *at most* per-minute freshness across the whole body and all equipped items.
--- 2. "Individual" - remove per-minute freshness from each body part and equipped item independently.
---
--- @field FreshBloodinessDecayPerMinute number (0.01 to 100.0) = 0.83
--- How much bloodiness freshness to remove every minute.
---
--- Bloodiness freshness is on 0 to 100 scale.
--- It acts more like "Fresh Bloodiness" - same as bloodiness, but decays with time.
--- It's tracked separately, and no actual bloodiness is removed.
---
--- With default 0.83 and "Total" decay mode, it would take ~24 hours for 100% overall bloodiness to go stale.
--- In "Individual" mode same bloodiness would decay in ~2 hours.
---
---
---
--- @field EarnIt boolean = true
--- Whether it's possible to earn the trait.
---
--- @field SendIntoFrenzyOnceEarned boolean = true
--- Whether to max out bloodlust and frenzy the moment you earn the trait.
---
--- @field BloodinessForBloodyKills number (0.0 to 100.0) = 90
--- Minimum overall bloodiness for a kill to be scored as bloody.
---
--- @field BloodyKillsToEarn number (1 to 100000) = 300
--- How many bloody kills it takes to earn the trait.
---
--- @field BloodyKillsDecayBelowBloodiness number (0.0 to 100.0) = 50
--- Bloody kills will decay every hour at this bloodiness.
---
--- @field BloodyKillsDecayPerHour number (0.0 to 100000.0) = 6
--- How many bloody kills are removed every hour if you're not bloody.
---
--- @field BloodyKillsDecayInSleep boolean = true
--- Whether to decay bloody kills while you're sleeping.
---
---
---
--- @field RearDangerIfNotSeenMinutes number (0 to 60) = 2
--- Consider zombie behind you as rear danger if you haven't seen it for this minutes.
---
--- @field RearDangerIfWithinTiles number (0 to 1000) = 8
--- Consider zombie behind you as rear danger if it's closer than this many tiles to you.
---
--- @field RearDangerMaxTiles number (16 to 1000) = 16
--- Don't consider zombies behind you as rear danger if they're further than this many tiles.
---
---
---
--- @field PreFrenzyPhraseCooldown number (0 to 43200) = 60
--- How many in-game minutes must pass before the character will say something when frenzy begins again.
---
--- @field TilesUntilZombieForInCombat number (0.1 to 1000.0) = 6
--- Tiles until closest zombie that is hidden behind something for player to be considered "in combat".
---
--- @field TilesUntilSeenZombieForInCombat number (0.1 to 1000.0) = 9
--- Tiles until closest zombie the player can see to be considered "in combat".
---
--- @field IgnoreZombiesWithFloorsDifference number (0.0 to 100.0) = 0.5
--- Zombies below/above this many floors to you are ignored in all features relying on distance.
---
--- @field ZombiesScanEveryTicks number (1 to 10000) = 30
--- Ticks between scanning closest zombies. Don't change if you don't know what you're doing.
---
local DEFAULTS = {
    KillCravingMaxHours = 36.0,
    KillCravingMaxHoursExponent = 3.0,
    KillCravingBloodinessFactor = 0.5,
    KillCravingStaleBloodinessMultiplier = 1.0,
    KillCravingHealthExponent = 2.0,
    FightlessCombatAfterMinutes = 5,
    FightlessCombatBloodlustPerMinute = 3.0,
    ConsiderShovesAndStompsAsHits = false,
    ConsiderCarDriveOverAsCombat = false,
    FightlessCombatBloodlustWhileDriving = true,
    GettingBloodyBloodlustChange = 0.25,
    GettingBloodyStressChange = -0.5,
    GettingBloodyUnhappinessChange = -0.3,
    BloodlustLevelForMoodDebuffs = 50.0,
    MoodDebuffBloodlustExponent = 2.0,
    BloodinessImpactOnMoodDebuffs = 0.5,
    MaxBloodlustDepressionAfterHours = 24.0,
    MaxBloodlustFullStressAfterHours = 36.0,
    MaxBloodlustFullBoredomAfterHours = 8.0,
    KillBloodlustReduction = 10.0,
    SharpKillBloodlustReduction = 12.0,
    KnifeKillBloodlustReduction = 15.0,
    RangedKillBloodlustReduction = 5.0,
    HitBloodlustReduction = 0.1,
    SharpHitBloodlustReduction = 0.25,
    KnifeHitBloodlustReduction = 0.5,
    RangedHitBloodlustReduction = 0.05,
    HurtBloodlustChange = 100.0,
    BloodinessForFrenzy = 100.0,
    BloodinessFreshnessMultiplierForFrenzy = 0.5,
    BloodinessFreshnessFrenzyProgressExponent = 4.0,
    BloodlustOverreducedForFrenzy = 50.0,
    FrenzyPerMinuteDecayInCombat = 1.0,
    FrenzyPerMinuteDecayOutOfCombat = 3.0,
    FrenzyKillBloodlustIncrease = 10.0,
    FrenzySharpKillBloodlustIncrease = 12.0,
    FrenzyKnifeKillBloodlustIncrease = 15.0,
    FrenzyRangedKillBloodlustIncrease = 5.0,
    FrenzyHitBloodlustIncrease = 0.1,
    FrenzySharpHitBloodlustIncrease = 0.25,
    FrenzyKnifeHitBloodlustIncrease = 0.5,
    FrenzyRangedHitBloodlustIncrease = 0.05,
    FrenzyHurtBloodlustChange = -50.0,
    BloodlustChangeDestress = 5.0,
    BloodlustChangeHappiness = 2.0,
    BloodlustAdditionalDamage = 0.5,
    BloodlustAdditionalDamageInFrenzy = 0.75,
    AdditionalDamageWithBareHands = false,
    AdditionalDamageWorksForRanged = false,
    InstakillAtBloodlust = 90.0,
    InstakillWorksForRanged = true,
    InstakillDamage = 2.0,
    InstakillBloodlustReduction = 20.0,
    InstakillBloodlustReductionInFrenzy = 40.0,
    InstakillDueToCravingStrain = 30.0,
    FrenzyInstakillBacklashStrain = 20.0,
    FrenzyInstakillBacklashFatigue = 2.5,
    FrenzyInstakillBacklashHunger = 3.33,
    FrenzyInstakillBacklashThirst = 5.0,
    FrenzyBacklashPerMinute = 0.5,
    FrenzyInstakillAreaDamage = 1.0,
    FrenzyInstakillAreaRadius = 1.0,
    FrenzyInstakillZombiesLimit = 5,
    InstakillSoundRadius = 30.0,
    InstakillSoundRadiusInFrenzy = 40.0,
    RevengeInstakillSoundRadius = 50.0,
    FrenzyHurtRevengeAtBloodlust = 50.0,
    FrenzyHurtRevengeDamage = 2.0,
    FrenzyHurtRevengePushTiles = 4.0,
    FrenzyHurtRevengeZombiesPushed = 20,
    FrenzyHurtRevengeKnockDownChance = 30.0,
    FrenzyHurtSoundRadius = 60.0,
    MaxBloodlustFrenzyWeaponSpeedIncrease = 0.25,
    MaxBloodlustFrenzyMoveSpeedIncrease = 0.25,
    BloodlustForExertionBuffering = 50.0,
    BufferExertionAfter = 25.0,
    MaxBufferedExertion = 100.0,
    ExertionBufferingMultiplier = 1.0,
    ExertionBufferedPerMinute = 2.0,
    ExertionUnbufferedPerMinute = 3.0,
    ExertionUnbufferingHunger = 0.3,
    ExertionUnbufferingThirst = 0.4,
    ExertionUnbufferingStrain = 0.8,
    MinutesSinceCombatForUnbuffering = 30,
    BloodlustForPanicImmunity = 80.0,
    FreshBloodinessDecayMode = 1,
    FreshBloodinessDecayPerMinute = 0.83,
    EarnIt = true,
    SendIntoFrenzyOnceEarned = true,
    BloodinessForBloodyKills = 90.0,
    BloodyKillsToEarn = 300,
    BloodyKillsDecayBelowBloodiness = 50.0,
    BloodyKillsDecayPerHour = 6.0,
    BloodyKillsDecayInSleep = true,
    RearDangerIfNotSeenMinutes = 2,
    RearDangerIfWithinTiles = 8,
    RearDangerMaxTiles = 16,
    PreFrenzyPhraseCooldown = 60,
    TilesUntilZombieForInCombat = 6.0,
    TilesUntilSeenZombieForInCombat = 9.0,
    IgnoreZombiesWithFloorsDifference = 0.5,
    ZombiesScanEveryTicks = 30,
}

SandboxVars = SandboxVars or {}
SandboxVars.BloodlustO = SandboxVars.BloodlustO or {}
local SB = SandboxVars.BloodlustO

setmetatable(SB, {
    __index = DEFAULTS,
})

return SB
