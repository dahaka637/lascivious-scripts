---@class WZUtility
WZUtility = {}

---@return boolean
function WZUtility:isReflectionEnabled()
    if self._reflectionState == nil then
        self._reflectionState = pcall(getReflectionVersion)
    end

    return self._reflectionState
end

---@param currentIdx integer?
---@param errorState boolean
---@param errorMsg string
---@param defaultVal any
---@param obj java.lang.Object
---@param fieldPath string
---@return integer?, boolean, any
function WZUtility:getClassFieldVal(currentIdx, errorState, errorMsg, defaultVal, obj, fieldPath)
    local field
    if currentIdx == nil then
        if errorState then return currentIdx, errorState, defaultVal end

        for i = 0, getNumClassFields(obj) - 1 do
            field = getClassField(obj, i)
            if tostring(field) == fieldPath then
                currentIdx = i
                break
            end
        end

        if currentIdx == nil then
            getPlayer():addLineChatElement(errorMsg)
            return nil, true, defaultVal
        end
    end

    if field == nil then field = getClassField(obj, currentIdx) end
    return currentIdx, errorState, getClassFieldVal(obj, field)
end
