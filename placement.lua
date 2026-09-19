local function getPreviewAlpha()
    local alpha = Config and Config.PreviewAlpha
    if type(alpha) ~= 'number' then return 255 end
    return math.floor(math.max(0, math.min(255, alpha)))
end

local gizmoEnabled = false
local gizmoCancelled = false
local currentEntity
local gizmoSessionId = 0

local MOVE_SPEED = (Config and tonumber(Config.MoveSpeed)) or 1.35
local MOVE_SPEED_FINE = (Config and tonumber(Config.MoveSpeedFine)) or 0.35
local ROTATE_SPEED = (Config and tonumber(Config.RotateSpeed)) or 90.0
local ROTATE_SPEED_FINE = (Config and tonumber(Config.RotateSpeedFine)) or 25.0
local SCROLL_ROTATE = (Config and tonumber(Config.ScrollRotateDegrees)) or 5.0

local DEFAULT_KEYBINDS = {
    moveForward = 32,
    moveBack = 33,
    moveLeft = 34,
    moveRight = 35,
    moveDown = 44,
    moveUp = 38,
    rotateLeft = 174,
    rotateRight = 175,
    scrollUp = 241,
    scrollDown = 242,
    snapToGround = 19,
    fineModifier = 21,
    confirm = 191,
    confirmAlt = 201,
    cancel = { 200, 202, 177 },
}

local function resolveKey(name)
    local val = Config and Config.Keybinds and Config.Keybinds[name]
    if type(val) == 'number' then return val end
    return DEFAULT_KEYBINDS[name]
end

local function resolveCancelKeys()
    local val = Config and Config.Keybinds and Config.Keybinds.cancel
    if type(val) == 'table' then
        local out = {}
        for i = 1, #val do
            if type(val[i]) == 'number' then out[#out + 1] = val[i] end
        end
        if #out > 0 then return out end
    elseif type(val) == 'number' then
        return { val }
    end
    return DEFAULT_KEYBINDS.cancel
end

local KEYS = {
    moveForward = resolveKey('moveForward'),
    moveBack = resolveKey('moveBack'),
    moveLeft = resolveKey('moveLeft'),
    moveRight = resolveKey('moveRight'),
    moveDown = resolveKey('moveDown'),
    moveUp = resolveKey('moveUp'),
    rotateLeft = resolveKey('rotateLeft'),
    rotateRight = resolveKey('rotateRight'),
    scrollUp = resolveKey('scrollUp'),
    scrollDown = resolveKey('scrollDown'),
    snapToGround = resolveKey('snapToGround'),
    fineModifier = resolveKey('fineModifier'),
    confirm = resolveKey('confirm'),
    confirmAlt = resolveKey('confirmAlt'),
}

local CANCEL_KEYS = resolveCancelKeys()

local function getBridgeHelpText()
    local ok, mod = pcall(function()
        return exports['mst_bridge']['HelpText']()
    end)
    if ok and type(mod) == 'table' and mod.ShowHelpText and mod.HideHelpText then
        return mod
    end
    return nil
end

local function hideGizmoHelpText()
    local ht = getBridgeHelpText()
    if ht and ht.HideHelpText then
        pcall(ht.HideHelpText)
    elseif lib and lib.hideTextUI then
        pcall(lib.hideTextUI)
    end
end

local function buildHintText()
    local hint = MST_PlacementLocale('gizmo.keyboard_hint')
    if type(hint) == 'string' and hint ~= '' and hint ~= 'gizmo.keyboard_hint' then
        return hint
    end
    return '[WASD] Move  \n[Q/E] Up/Down  \n[Scroll / ← →] Rotate  \n[LALT] Snap  \n[Shift] Fine  \n[ENTER] Done  \n[ESC] Cancel'
end

local function showHint()
    local msg = buildHintText()
    local ht = getBridgeHelpText()
    if ht then
        pcall(ht.ShowHelpText, msg)
    elseif lib and lib.showTextUI then
        pcall(lib.showTextUI, msg)
    end
end

local function camRelativeAxes()
    local rot = GetGameplayCamRot(2)
    local z = math.rad(rot.z)
    local forward = vector3(-math.sin(z), math.cos(z), 0.0)
    local right = vector3(math.cos(z), math.sin(z), 0.0)
    local flen = #forward
    local rlen = #right
    if flen > 0.001 then forward = forward / flen end
    if rlen > 0.001 then right = right / rlen end
    return forward, right
end

local function disableGameplayConflicts()
    DisableControlAction(0, 24, true)
    DisableControlAction(0, 25, true)
    DisableControlAction(0, 140, true)
    DisableControlAction(0, 141, true)
    DisableControlAction(0, 142, true)
    DisableControlAction(0, 257, true)
    DisablePlayerFiring(PlayerId(), true)

    SetPauseMenuActive(false)
    DisableControlAction(0, 200, true)
    DisableControlAction(0, 199, true)
    DisableControlAction(0, 177, true)
    DisableControlAction(0, 202, true)

    DisableControlAction(0, 30, true)
    DisableControlAction(0, 31, true)
    DisableControlAction(0, KEYS.moveForward, true)
    DisableControlAction(0, KEYS.moveBack, true)
    DisableControlAction(0, KEYS.moveLeft, true)
    DisableControlAction(0, KEYS.moveRight, true)
    DisableControlAction(0, KEYS.moveDown, true)
    DisableControlAction(0, KEYS.moveUp, true)
    DisableControlAction(0, KEYS.fineModifier, true)
end

local function isFineMod()
    return IsDisabledControlPressed(0, KEYS.fineModifier) or IsControlPressed(0, KEYS.fineModifier)
end

local function pressed(control)
    return IsDisabledControlPressed(0, control) or IsControlPressed(0, control)
end

local function justPressed(control)
    return IsDisabledControlJustPressed(0, control) or IsControlJustPressed(0, control)
end

local function applyMove(entity, dt)
    local fine = isFineMod()
    local speed = (fine and MOVE_SPEED_FINE or MOVE_SPEED) * dt
    local forward, right = camRelativeAxes()
    local dx, dy, dz = 0.0, 0.0, 0.0

    if pressed(KEYS.moveForward) then
        dx = dx + forward.x * speed
        dy = dy + forward.y * speed
    end
    if pressed(KEYS.moveBack) then
        dx = dx - forward.x * speed
        dy = dy - forward.y * speed
    end
    if pressed(KEYS.moveLeft) then
        dx = dx - right.x * speed
        dy = dy - right.y * speed
    end
    if pressed(KEYS.moveRight) then
        dx = dx + right.x * speed
        dy = dy + right.y * speed
    end
    if pressed(KEYS.moveDown) then
        dz = dz - speed
    end
    if pressed(KEYS.moveUp) then
        dz = dz + speed
    end

    if dx == 0.0 and dy == 0.0 and dz == 0.0 then return end

    local c = GetEntityCoords(entity)
    SetEntityCoordsNoOffset(entity, c.x + dx, c.y + dy, c.z + dz, false, false, false)
end

local function applyRotate(entity, dt)
    local fine = isFineMod()
    local speed = (fine and ROTATE_SPEED_FINE or ROTATE_SPEED) * dt
    local heading = GetEntityHeading(entity)
    local delta = 0.0

    if pressed(KEYS.rotateLeft) then delta = delta + speed end
    if pressed(KEYS.rotateRight) then delta = delta - speed end

    if justPressed(KEYS.scrollUp) then
        delta = delta + SCROLL_ROTATE
    end
    if justPressed(KEYS.scrollDown) then
        delta = delta - SCROLL_ROTATE
    end

    if delta == 0.0 then return end
    SetEntityHeading(entity, heading + delta)
end

local function snapToGround(entity)
    if not entity or not DoesEntityExist(entity) then return end
    PlaceObjectOnGroundProperly_2(entity)
    Wait(0)
    local coords = GetEntityCoords(entity)
    SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z - 0.04, false, false, false)
end

local function clearPreviewFx(entity)
    if not entity or not DoesEntityExist(entity) then return end
    if SetEntityDrawOutline then
        SetEntityDrawOutline(entity, false)
    end
    ResetEntityAlpha(entity)
    SetEntityVisible(entity, true, false)
    SetEntityAlpha(entity, 255, false)
end

local function applyPreviewFx(entity)
    if not entity or not DoesEntityExist(entity) then return end
    SetEntityAlpha(entity, getPreviewAlpha(), false)

    if not SetEntityDrawOutline or IsEntityAPed(entity) then return end
    if SetEntityDrawOutlineShader then
        SetEntityDrawOutlineShader(1)
    end
    if SetEntityDrawOutlineColor then
        SetEntityDrawOutlineColor(80, 220, 120, 200)
    end
    SetEntityDrawOutline(entity, true)
end

local function placementLoop(entity)
    if not gizmoEnabled or not DoesEntityExist(entity) then
        gizmoEnabled = false
        return
    end

    -- Outline + soft alpha during gizmo. Cleared on confirm/cancel; mst_crypto
    -- also forces solid visible after place so the outline shader cannot stick.
    applyPreviewFx(entity)

    showHint()
    local lastHint = GetGameTimer()

    while gizmoEnabled and DoesEntityExist(entity) do
        local dt = GetFrameTime()
        if dt <= 0.0 or dt > 0.1 then dt = 0.016 end

        disableGameplayConflicts()
        applyMove(entity, dt)
        applyRotate(entity, dt)

        if justPressed(KEYS.snapToGround) then
            snapToGround(entity)
        end

        if justPressed(KEYS.confirm) or justPressed(KEYS.confirmAlt) then
            gizmoCancelled = false
            gizmoEnabled = false
            break
        end

        local cancelled = false
        for i = 1, #CANCEL_KEYS do
            local control = CANCEL_KEYS[i]
            if IsDisabledControlJustReleased(0, control) or IsControlJustReleased(0, control) then
                cancelled = true
                break
            end
        end
        if cancelled then
            gizmoCancelled = true
            gizmoEnabled = false
            break
        end

        if (GetGameTimer() - lastHint) > 2000 then
            showHint()
            lastHint = GetGameTimer()
        end

        Wait(0)
    end

    clearPreviewFx(entity)

    SetPauseMenuActive(true)
    hideGizmoHelpText()
    gizmoEnabled = false
    currentEntity = nil
end

local function releaseGizmoInput()
    if currentEntity and DoesEntityExist(currentEntity) then
        clearPreviewFx(currentEntity)
    end
    gizmoEnabled = false
    currentEntity = nil
    SetPauseMenuActive(true)
    hideGizmoHelpText()
    SetNuiFocus(false, false)
    if SetNuiFocusKeepInput then
        pcall(SetNuiFocusKeepInput, false)
    end
end

local function getNetworkIdIfNetworked(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return 0 end
    if type(NetworkGetEntityIsNetworked) == 'function' then
        local ok, wired = pcall(NetworkGetEntityIsNetworked, entity)
        if ok and not wired then return 0 end
    end
    local n = NetworkGetNetworkIdFromEntity(entity) or 0
    if n >= 65533 then return 0 end
    return n
end

local function useGizmo(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return nil
    end

    local netId = getNetworkIdIfNetworked(entity)
    if netId and netId > 0 then
        NetworkRequestControlOfEntity(entity)
        local timeout = 0
        while not NetworkHasControlOfEntity(entity) and timeout < 50 do
            Wait(10)
            NetworkRequestControlOfEntity(entity)
            timeout = timeout + 1
        end
    end

    gizmoEnabled = true
    gizmoCancelled = false
    currentEntity = entity
    gizmoSessionId = gizmoSessionId + 1

    pcall(placementLoop, entity)

    releaseGizmoInput()

    if gizmoCancelled then
        return nil
    end

    return {
        handle = entity,
        position = GetEntityCoords(entity),
        rotation = GetEntityRotation(entity),
    }
end

exports('useGizmo', useGizmo)

local function isGizmoActive()
    return gizmoEnabled
end

exports('isGizmoActive', isGizmoActive)
exports('isAvailable', function() return true end)
exports('getPreviewAlpha', getPreviewAlpha)
exports('releaseInput', releaseGizmoInput)

RegisterCommand('mstplacement_release', function()
    releaseGizmoInput()
    print('[mst_placement] Input released (keyboard placement — no EnterCursorMode).')
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    gizmoEnabled = false
    releaseGizmoInput()
end)