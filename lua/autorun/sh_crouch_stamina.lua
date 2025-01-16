-- Global var for third-party scripts.
CrouchStamina = true

-- WORKAROUND: We cannot access m_flDucktime on clientside.
-- ISSUE: https://github.com/Facepunch/garrysmod-requests/issues/1403
local function GetDuckProgress(ply)
    local standingViewOffset, currentViewOffset = ply:GetViewOffset(), ply:GetCurrentViewOffset()
    local heightDifference = standingViewOffset.z - ply:GetViewOffsetDucked().z

    return (standingViewOffset.z - currentViewOffset.z) / heightDifference
end

local cf = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED)
local enabled = CreateConVar("sv_crouch_stamina", 1, cf, "Sets whether crouch stamina is enabled or not.", 0, 1)
local sv_timebetweenducks = CreateConVar("sv_crouch_stamina_cooldown", 0, cf, "Sets the minimum time players must wait before being allowed to crouch again.", 0)

local function DuckingEnabled(ply)
    if !enabled:GetBool() then
        return true
    end

    -- If mashing duck key too much, treat as unpressed to avoid being able to "camp" in half-ducked positions by pressing/releasing near a target height.
    -- HACK: Because of float imprecision(?) duckProgress == 0 seems to always return false and tolerance checks do nothing. Don't ask why.
    if ply:GetNW2Float("DuckSpeed") < 1.5 and math.abs(GetDuckProgress(ply)) <= 0.05 then
        return false
    end

    local cooldown = sv_timebetweenducks:GetFloat()

    -- After completing a duck/unduck, we can't re-duck for a minimum amount of time.
    -- This is to minimize ugly camera shaking due to immediate duck/un-duck in the air before the above anti-spam code kicks in.
    if cooldown != 0 and !ply:IsFlagSet(FL_DUCKING) and CurTime() < ply:GetNW2Float("DuckLastTime", 0) + cooldown then
        return false
    end

    return true
end

local vec2_origin = Vector(0, 0)
local CS_PLAYER_DUCK_SPEED_IDEAL = 8.0
local DEFAULT_DUCK_SPEED = 0.1

hook.Add("PlayerSpawn", "CrouchStamina.Init", function(ply)
    if !IsValid(ply) then
        return
    end

    ply:SetNW2Float("DuckSpeed", CS_PLAYER_DUCK_SPEED_IDEAL)
    ply:SetNW2Vector("DuckPos", vec2_origin)
end)

hook.Add("StartCommand", "CrouchStamina", function(ply, cmd)
    -- If mashing duck key too much, treat as unpressed to avoid being able to "camp" in half-ducked positions by pressing/releasing near a target height.
    if DuckingEnabled(ply) then
        return
    end

    cmd:RemoveKey(IN_DUCK)
end)

local DUCK_SPEED_MUL = 0.07
local slow_movement = CreateConVar("sv_crouch_stamina_slow_movement", 0, cf, "Slows movement by using crouch stamina.", 0, 1)
local get_sv_crouch_spam_penalty = CreateConVar("sv_crouch_spam_penalty", 2.0, cf, "Modifies how much stamina is lost when crouching.", 0)

-- HACK: IN_BULLRUSH isn't used anywhere.
-- We use it to store the "raw" value of whether IN_DUCK was held, before it is modified by code.
-- This way when m_nButtons is copied to m_nOldButtons we can tell if duck was pressed or released on the next frame.
local IN_RAWDUCK = IN_BULLRUSH
local moveRW = false
local rwSpeed = false

hook.Add("SetupMove", "CrouchStamina.Slow", function(ply, mv, cmd)
    if !slow_movement:GetBool() then
        return
    end

    local mul = math.max(ply:GetNW2Float("DuckSpeed") / CS_PLAYER_DUCK_SPEED_IDEAL, 0.5)

    if mul == 1 then
        return
    end

    cmd:SetForwardMove(cmd:GetForwardMove() * mul)
    cmd:SetSideMove(cmd:GetSideMove() * mul)

    mv:SetMaxClientSpeed(mv:GetMaxClientSpeed() * mul)
    mv:SetMaxSpeed(mv:GetMaxClientSpeed() * mul * (ply:Crouching() and ply:GetCrouchedWalkSpeed() or 1))
end)

hook.Add("Move", "CrouchStamina", function(ply, mv)
    if !enabled:GetBool() then
        return
    end

    local speedMul = math.Remap(ply:GetNW2Float("DuckSpeed"), CS_PLAYER_DUCK_SPEED_IDEAL, 0, 0, CS_PLAYER_DUCK_SPEED_IDEAL)

    if moveRW == false then
        moveRW = GetConVar("sv_kait_enabled") or GetConVar("kait_movement_enabled")
        rwSpeed = GetConVar("sv_kait_crouching_speed") or GetConVar("kait_crouching_speed")
    end

    local curDuckSpeed = DEFAULT_DUCK_SPEED

    if moveRW and moveRW:GetBool() then
        curDuckSpeed = rwSpeed:GetFloat()
    end

    local duckSpeed = curDuckSpeed + (speedMul * DUCK_SPEED_MUL)

    if mv:KeyPressed(IN_DUCK) then
        ply:SetDuckSpeed(duckSpeed)
    end

    if mv:KeyReleased(IN_DUCK) then
        ply:SetUnDuckSpeed(duckSpeed)
    end

    local buttons = mv:GetButtons()

    -- REFERENCE: https://github.com/SwagSoftware/Kisak-Strike/blob/master/game/shared/cstrike15/cs_gamemovement.cpp#L169
    -- Save off state of IN_DUCK before we set/unset it from gameplay effects
    if bit.band(buttons, IN_DUCK) != 0 then
        mv:SetButtons(bit.bor(buttons, IN_RAWDUCK))
    end

    -- Add duck-spam speed penalty when we press or release the duck key.
    -- (this is the only place that IN_RAWDUCK is checked)
    if bit.band(mv:GetButtons(), IN_RAWDUCK) != bit.band(mv:GetOldButtons(), IN_RAWDUCK) then
        ply:SetNW2Float("DuckSpeed", math.max(0, ply:GetNW2Float("DuckSpeed") - get_sv_crouch_spam_penalty:GetFloat()))
    end

    -- REFERENCE: https://github.com/SwagSoftware/Kisak-Strike/blob/master/game/shared/cstrike15/cs_gamemovement.cpp#L1069
    -- Reduce duck-spam penalty over time.
    ply:SetNW2Float("DuckSpeed", math.Approach(ply:GetNW2Float("DuckSpeed"), CS_PLAYER_DUCK_SPEED_IDEAL, engine.TickInterval() * 3.0))

    local duckAmount = GetDuckProgress(ply)

    -- Use the last-known position of full crouch speed to restore crouch speed.
    -- The goal is that moving a sufficient distance should reset crouch speed in an intuitive manner.
    if ply:GetNW2Float("DuckSpeed") >= CS_PLAYER_DUCK_SPEED_IDEAL then
        local origin = mv:GetOrigin()
        origin.z = 0

        ply:SetNW2Vector("DuckPos", origin)
    elseif duckAmount <= 0 or duckAmount >= 1 then
        local duckPos = ply:GetNW2Vector("DuckPos", vec2_origin)
        local flDistToLastPositionAtFullCrouchSpeed = duckPos:Distance2DSqr(mv:GetOrigin())

        -- if we're sufficiently far from the last full crouch speed location, we can safely restore crouch speed faster.
        if flDistToLastPositionAtFullCrouchSpeed > 128 ^ 2 then
            ply:SetNW2Float("DuckSpeed", math.Approach(ply:GetNW2Float("DuckSpeed"), CS_PLAYER_DUCK_SPEED_IDEAL, engine.TickInterval() * 6.0))
        end
    end

    -- REFERENCE: https://github.com/SwagSoftware/Kisak-Strike/blob/master/game/shared/cstrike15/cs_gamemovement.cpp#L949
    if !ply:IsFlagSet(FL_DUCKING) and ply:GetNW2Bool("WasDucking", false) then
        ply:SetNW2Float("DuckLastTime", CurTime())
    end

    ply:SetNW2Bool("WasDucking", ply:IsFlagSet(FL_DUCKING))
end)