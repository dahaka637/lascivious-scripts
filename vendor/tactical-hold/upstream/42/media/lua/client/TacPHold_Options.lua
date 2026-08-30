TacPHold = TacPHold or {}

TacPHold.options = {
    PoseNormal = nil,
    PoseHighReady = nil,
	PoseLowReady = nil,
	PoseVanilla = nil
}

TacPHold.initOptions = function()

    local options = PZAPI.ModOptions:create("TacPHold", "TacPHold")

    TacPHold.options.PoseNormal =
        options:addTickBox(
            "Tactical hold",
            "Tactical hold",
            true
        )

    TacPHold.options.PoseHighReady =
        options:addTickBox(
            "HighReady",
            "HighReady",
            false
        )
		
	TacPHold.options.PoseLowReady =
        options:addTickBox(
            "Low Ready",
            "Low Ready",
            false
        )
		
	TacPHold.options.PoseVanilla =
        options:addTickBox(
            "Vanilla",
            "Vanilla",
            false
        )
		    

end

TacPHold.initOptions()
