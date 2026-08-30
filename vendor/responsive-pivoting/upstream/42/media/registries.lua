-- B42 requires custom trait TYPES to be registered here, before the
-- character_trait_definition scripts (media/scripts/characters/PivotMod_traits.txt)
-- are loaded. Without this, the definition's "CharacterTrait = pivotmod:..."
-- lookup returns nil and the script throws on load.
PivotMod = PivotMod or {}
PivotMod.CharacterTrait = PivotMod.CharacterTrait or {}

PivotMod.CharacterTrait.ONYOURTOES = CharacterTrait.register("pivotmod:onyourtoes")
PivotMod.CharacterTrait.PODSHOFE = CharacterTrait.register("pivotmod:podshofe")
