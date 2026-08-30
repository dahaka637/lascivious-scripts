
MF = MF or {}
MF.color = MF.color or {}
MF.key = "MoodleFramework"

function MF.overrideGray()
    local color = MF.color.grayPick and MF.color.grayPick.color
    if color then
        Color.gray:set(color.r,color.g,color.b,color.a)
    end
end

function MF.hasBorder()
    return MF.color.includeBorder:getValue()
end

function MF.hasBackground()
    return MF.color.includeBackground:getValue()
end

function MF.hasBGColor()
    return MF.color.includeBGColor:getValue()
end

function MF.loadConfig()
    local options = PZAPI.ModOptions:create(MF.key, "UI_options_MFColor_Title")
    --MF.color.grayPick = options:addColorPicker("0",  getText("UI_options_MFColor_grayPicker"), Color.gray:getRedFloat(), Color.gray:getGreenFloat(), Color.gray:getBlueFloat(), Color.gray:getAlphaFloat(),  getText("UI_options_MFColor_grayPicker_tooltip"))
    MF.color.grayPick = options:addColorPicker("0",  getText("UI_options_MFColor_grayPicker"), 1, 1, 1, Color.gray:getAlphaFloat(),  getText("UI_options_MFColor_grayPicker_tooltip"))
    MF.color.includeBGColor = options:addTickBox("1",  getText("UI_options_MFColor_BGColor"), true, getText("UI_options_MFColor_BGColor_tooltip"))
    MF.color.includeBackground = options:addTickBox("2",  getText("UI_options_MFColor_background"), true, getText("UI_options_MFColor_background_tooltip"))
    MF.color.includeBorder = options:addTickBox("3",  getText("UI_options_MFColor_border"), true, getText("UI_options_MFColor_border_tooltip"))

    local onApply = options.apply;
    options.apply = function(self,param2)
        onApply(self)
        if self.modOptionsID == MF.key then
            MF.overrideGray()
        end
    end
    
end

MF.loadConfig()

Events.OnMainMenuEnter.Add(MF.overrideGray)--maybe I should hook PZAPI.ModOptions:load() instead of that event
