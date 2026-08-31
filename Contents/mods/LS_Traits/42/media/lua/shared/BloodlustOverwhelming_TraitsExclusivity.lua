local Compat = require("bloodlusto/Compat")

local bloodlustOverwhelming = Compat.getBloodlustOverwhelmingTrait()

Compat.setMutualExclusive(bloodlustOverwhelming, Compat.getETWBloodlustTrait())
Compat.setMutualExclusive(bloodlustOverwhelming, Compat.getRegretNothingTrait())
Compat.setMutualExclusive(bloodlustOverwhelming, Compat.getPacifistTrait())
Compat.setMutualExclusive(bloodlustOverwhelming, Compat.getHemophobicTrait())
