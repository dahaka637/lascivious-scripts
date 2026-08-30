TacHold.options = {
    PoseNormal = nil,
    PoseHighReady = nil,
    PoseLowReady = nil,
    PoseGunResting = nil,
    PoseVanilla = nil,
    CycleKey = nil
}

TacHold.initOptions = function()
    local options = PZAPI.ModOptions:create("TacHold", "TacHold")

    TacHold.options.PoseNormal =
        options:addTickBox("Tactical hold", "Tactical hold", true)

    TacHold.options.PoseHighReady =
        options:addTickBox("HighReady", "HighReady", false)

    TacHold.options.PoseLowReady =
        options:addTickBox("LowReady", "LowReady", false)

    TacHold.options.PoseGunResting =
        options:addTickBox("GunResting", "GunResting", false)

    TacHold.options.PoseVanilla =
        options:addTickBox("Vanilla", "Vanilla", false)

    TacHold.options.CycleKey =
        options:addKeyBind(
            "Cycle animation Key",
            "Cycle animation Key",
            Keyboard.KEY_U
        )
end

TacHold.initOptions()