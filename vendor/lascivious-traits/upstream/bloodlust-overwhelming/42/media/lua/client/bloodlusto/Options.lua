
local SECTION = PZAPI.ModOptions:create('BloodlustO', 'Bloodlust Overwhelming')

SECTION:addSlider('bloodiness_moodle_at', 'Show Bloodiness Moodle At',
        0, 100, 1,
        30,
        'At what level of overall bloodiness to show an informational moodle with it (also indicates freshness)')

SECTION:addTickBox('bloodiness_exact', 'Exact Bloodiness and Freshness', false,
        'Show exact bloodiness and freshness percentages in moodle tooltip')

SECTION:addTickBox('debug', 'Show Debug Panel', false,
        'Display a panel with the numbers behind bloodlust mechanics')

SECTION:addSeparator()

SECTION:addDescription('Phrases')

SECTION:addTickBox('craving_instakill_phrase', 'Phrase on Kill Craving Instakill', true,
        "Whether to display a phrase when you instakill a zombie due to high bloodlust while craving for kill.")

SECTION:addTickBox('frenzy_instakill_phrase', 'Phrase on Frenzy Instakill', true,
        "Whether to display a phrase when you instakill a zombie in frenzy.")

SECTION:addTickBox('revenge_instakill_phrase', 'Phrase on Frenzy Instakill', true,
        "Whether to display a phrase when you instakill a zombie after it hit you.")

SECTION:addTickBox('frenzy_hurt_phrase', 'Phrase when Hurt in Frenzy', true,
        "Whether to display a phrase when you get hit by a zombie in frenzy.")

SECTION:addTickBox('pre_frenzy_phrase', 'Pre-Frenzy Phrase', true,
        "Whether to display a phrase when you're about to enter bloody frenzy if you keep killing.")

SECTION:addTickBox('tracking_outburst_phrase', 'Tracking Outburst Phrase', true,
        "Whether to display a phrase when you're losing control to track a zombie.")




local MO = {}

SECTION.apply = function(self)
    for k,v in pairs(self.dict) do
        if v.type == "multipletickbox" then
            for i=1, #v.values do
                MO[(k.."_"..tostring(i))] = v:getValue(i)
            end
        elseif v.type == "button" then
            -- not a value
        else
            MO[k] = v:getValue()
        end
    end
end

Events.OnMainMenuEnter.Add(function() SECTION:apply() end)

SECTION:apply()

return MO
