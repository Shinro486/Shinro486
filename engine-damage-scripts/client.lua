-- Configuration
local Config = {
    SPEED_LIMIT = 140.0,    -- Vitesse limite en km/h
    IMPACTS_NEEDED = 5,     -- Nombre d'impacts nécessaires
    HEALTH_THRESHOLD = 500, -- Seuil de santé critique
    CHECK_DELAY = 100,      -- Délai entre les vérifications (ms)
    DAMAGE_COOLDOWN = 1000  -- Délai entre les impacts (ms)
}

-- Variables locales
local vehicleData = {}
local currentVehicle = nil
local lastDamageTime = 0
local ptfxAssetLoaded = false

-- Chargement anticipé des effets
Citizen.CreateThread(function()
    RequestNamedPtfxAsset("core")
    while not HasNamedPtfxAssetLoaded("core") do 
        Wait(0)
    end
    ptfxAssetLoaded = true
end)

-- Fonctions utilitaires
local function InitVehicle(vehicle)
    if not vehicle or not DoesEntityExist(vehicle) then return false end
    
    if not vehicleData[vehicle] then
        vehicleData[vehicle] = {
            impacts = 0,
            health = GetVehicleBodyHealth(vehicle),
            smoking = false,
            effect = nil
        }
        return true
    end
    return false
end

local function ApplySmoke(vehicle)
    local data = vehicleData[vehicle]
    if not data or data.smoking or not ptfxAssetLoaded then return end
    
    UseParticleFxAssetNextCall("core")
    data.effect = StartParticleFxLoopedOnEntity(
        "exp_grd_bzgas_smoke",
        vehicle,
        0.0, 1.0, 0.5,
        0.0, 0.0, 0.0,
        2.0,
        false, false, false
    )
    
    if data.effect then
        data.smoking = true
        SetVehicleEngineHealth(vehicle, 300.0)
        SetVehicleEngineOn(vehicle, false, true, true)
        SetVehicleUndriveable(vehicle, true)
        
        TriggerEvent('chat:addMessage', {
            color = {255, 0, 0},
            args = {'SYSTÈME', 'Le moteur est endommagé!'}
        })
    end
end

local function StopSmoke(vehicle)
    local data = vehicleData[vehicle]
    if not data or not data.smoking then return end
    
    if data.effect then
        StopParticleFxLooped(data.effect, false)
        RemoveParticleFx(data.effect, true)
        data.effect = nil
    end
    
    data.smoking = false
    data.impacts = 0
    SetVehicleEngineOn(vehicle, true, false, false)
    SetVehicleUndriveable(vehicle, false)
    SetVehicleEngineHealth(vehicle, 1000.0)
end

-- Boucle principale optimisée
Citizen.CreateThread(function()
    while true do
        Wait(Config.CHECK_DELAY)
        
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            local vehicle = GetVehiclePedIsIn(ped, false)
            
            if vehicle ~= currentVehicle then
                currentVehicle = vehicle
                InitVehicle(vehicle)
            end
            
            local data = vehicleData[vehicle]
            if data then
                local currentHealth = GetVehicleBodyHealth(vehicle)
                local engineHealth = GetVehicleEngineHealth(vehicle)
                local currentTime = GetGameTimer()
                
                -- Vérifie la réparation
                if data.smoking and engineHealth > 900.0 then
                    StopSmoke(vehicle)
                end
                
                -- Vérifie les dégâts critiques
                if currentHealth < Config.HEALTH_THRESHOLD and not data.smoking then
                    ApplySmoke(vehicle)
                -- Vérifie les impacts
                elseif currentHealth < data.health and (currentTime - lastDamageTime) > Config.DAMAGE_COOLDOWN then
                    local speed = GetEntitySpeed(vehicle) * 3.6
                    
                    if speed > Config.SPEED_LIMIT then
                        data.impacts = Config.IMPACTS_NEEDED
                    else
                        data.impacts = data.impacts + 1
                    end
                    
                    lastDamageTime = currentTime
                    
                    if data.impacts >= Config.IMPACTS_NEEDED then
                        ApplySmoke(vehicle)
                    end
                end
                
                data.health = currentHealth
            end
        end
    end
end)

-- Commande de reset
RegisterCommand('resetmotor', function()
    if currentVehicle and vehicleData[currentVehicle] then
        StopSmoke(currentVehicle)
        vehicleData[currentVehicle] = nil
    end
end)