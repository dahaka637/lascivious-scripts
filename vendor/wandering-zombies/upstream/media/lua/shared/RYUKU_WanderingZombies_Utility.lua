---@class WZUtility
WZUtility = {}

---@param obj Object
---@param fieldPath string
---@return integer|nil error
function WZUtility:getClassFieldIdx(obj, fieldPath)
    for i = 0, getNumClassFields(obj) - 1 do
        if tostring(getClassField(obj, i)) == fieldPath then return i end
    end

    return nil
end

---@param obj Object
---@param idx integer
---@return any
function WZUtility:getClassFieldVal(obj, idx)
    local field = getClassField(obj, idx)
    return (field ~= nil and getClassFieldVal(obj, field)) or nil
end
