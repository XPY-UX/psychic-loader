-- Wait for the game to fully load before executing
repeat task.wait() until game:IsLoaded()
assert(hookmetamethod, "[Kitty]: Your executor doesn't support this.")

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Wait for character initialization
local function waitForCharacter()
    if not LocalPlayer.Character then
        LocalPlayer.CharacterAdded:Wait()
    end
    task.wait(2)
end
waitForCharacter()

-- Locate core game script folders safely (with timeouts)
local PlayerScripts
local attempts = 0
repeat 
    task.wait(1)
    PlayerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
    attempts = attempts + 1
    if attempts > 20 then return end
until PlayerScripts

local Controllers
attempts = 0
repeat 
    task.wait(1)
    Controllers = PlayerScripts:FindFirstChild("Controllers")
    attempts = attempts + 1
    if attempts > 20 then return end
until Controllers

local Modules
attempts = 0
repeat 
    task.wait(1)
    Modules = ReplicatedStorage:FindFirstChild("Modules")
    attempts = attempts + 1
    if attempts > 20 then return end
until Modules

-- Helper function to yield for a specific child object
local function waitForChildWithTimeout(parent, childName, timeout)
    local elapsed = 0
    while not parent:FindFirstChild(childName) and (elapsed < timeout) do
        task.wait(0.5)
        elapsed = elapsed + 0.5
    end
    return parent:FindFirstChild(childName)
end

-- Fetch Game Libraries
local CosmeticLibrary = waitForChildWithTimeout(Modules, "CosmeticLibrary", 10)
local ItemLibrary = waitForChildWithTimeout(Modules, "ItemLibrary", 10)
local PlayerDataController = waitForChildWithTimeout(Controllers, "PlayerDataController", 10)
local PlayerDataUtility = waitForChildWithTimeout(Modules, "PlayerDataUtility", 10)

if not CosmeticLibrary or not ItemLibrary or not PlayerDataController then return end

local EnumLibrary, RequiredCosmetics, RequiredItems, RequiredPlayerData, RequiredDataUtility
local setupSuccess = pcall(function()
    RequiredCosmetics = require(CosmeticLibrary)
    RequiredItems = require(ItemLibrary)
    RequiredPlayerData = require(PlayerDataController)
    RequiredDataUtility = require(PlayerDataUtility)
    
    local enumLibObj = Modules:FindFirstChild("EnumLibrary")
    if enumLibObj then
        EnumLibrary = require(enumLibObj)
        if EnumLibrary and EnumLibrary.WaitForEnumBuilder then
            task.spawn(function()
                pcall(function() EnumLibrary:WaitForEnumBuilder() end)
            end)
        end
    end
end)

-- Spoof Weapon Ownership
local function generateItemsTable(value)
    local items = {}
    if RequiredItems and RequiredItems.Items then
        for itemName, _ in pairs(RequiredItems.Items) do
            if not itemName:find("MISSING_") then
                items[itemName] = value
            end
        end
    end
    return items
end

RequiredPlayerData.OwnsAllWeapons = function() return true end
RequiredPlayerData.GetUnlockedWeapons = function() return generateItemsTable(true) end

if not setupSuccess or not RequiredCosmetics or not RequiredItems or not RequiredPlayerData then return end

-- Global tracking tables for spoofed gear
local EquippedSkins = {}
local FavoriteCosmetics = {}
local CurrentActiveFighterName
local SelectedFighterName

-- Helper function to construct structured cosmetic data
local function createCosmeticObject(cosmeticName, expectedType, extraConfig)
    if not RequiredCosmetics or not RequiredCosmetics.Cosmetics then return nil end
    local baseCosmetic = RequiredCosmetics.Cosmetics[cosmeticName]
    if not baseCosmetic then return nil end
    
    local cosmeticObj = {}
    for key, value in pairs(baseCosmetic) do
        cosmeticObj[key] = value
    end
    
    cosmeticObj.Name = cosmeticName
    cosmeticObj.Type = cosmeticObj.Type or expectedType
    cosmeticObj.Seed = math.random(1, 1000000)
    
    if EnumLibrary then
        pcall(function()
            local enumVal = EnumLibrary:ToEnum(cosmeticName)
            if enumVal then
                cosmeticObj.Enum = enumVal
                cosmeticObj.ObjectID = enumVal
            end
        end)
    end
    
    if extraConfig then
        if extraConfig.inverted then cosmeticObj.Inverted = true end
        if extraConfig.favoritesOnly then cosmeticObj.OnlyUseFavorites = true end
    end
    return cosmeticObj
end

local ConfigPath = "unlockall/config.json"

-- Save settings to file
local function saveConfig()
    if not writefile then return end
    task.spawn(function()
        pcall(function()
            local configData = {equipped = {}, favorites = FavoriteCosmetics}
            for weapon, categories in pairs(EquippedSkins) do
                configData.equipped[weapon] = {}
                for category, item in pairs(categories) do
                    if item and item.Name then
                        configData.equipped[weapon][category] = {
                            name = item.Name,
                            seed = item.Seed,
                            inverted = item.Inverted
                        }
                    end
                end
            end
            if not isfolder("unlockall") then makefolder("unlockall") end
            writefile(ConfigPath, HttpService:JSONEncode(configData))
        end)
    end)
end

-- Load settings from file
local function loadConfig()
    if not readfile or not isfile or not isfile(ConfigPath) then return end
    pcall(function()
        local configData = HttpService:JSONDecode(readfile(ConfigPath))
        if configData.equipped then
            for weapon, categories in pairs(configData.equipped) do
                EquippedSkins[weapon] = {}
                for category, item in pairs(categories) do
                    local cosmeticObj = createCosmeticObject(item.name, category, {inverted = item.inverted})
                    if cosmeticObj then
                        cosmeticObj.Seed = item.seed
                        EquippedSkins[weapon][category] = cosmeticObj
                    end
                end
            end
        end
        FavoriteCosmetics = configData.favorites or {}
    end)
end

-- Intercept Cosmetic Validation Methods
local AllowedTypes = {Skin = true, Wrap = true}
local oldOwnsCosmetic = RequiredCosmetics.OwnsCosmetic
local oldOwnsCosmeticForWeapon = RequiredCosmetics.OwnsCosmeticForWeapon
local oldOwnsCosmeticNormally = RequiredCosmetics.OwnsCosmeticNormally
local oldOwnsCosmeticUniversally = RequiredCosmetics.OwnsCosmeticUniversally
local oldOwnsCosmeticForSomething = RequiredCosmetics.OwnsCosmeticForSomething

local function isValidCosmetic(name, variant)
    if not name or type(name) ~= "string" or name:find("MISSING_") then return false end
    local cosmetic = RequiredCosmetics.Cosmetics[name]
    if not cosmetic then return false end
    return AllowedTypes[cosmetic.Type] or false
end

RequiredCosmetics.OwnsCosmetic = function(self, weapon, cosmeticName, variant)
    if isValidCosmetic(cosmeticName, variant) then return true end
    return oldOwnsCosmetic(self, weapon, cosmeticName, variant)
end

RequiredCosmetics.OwnsCosmeticForWeapon = function(self, slot, weapon, cosmeticName)
    if isValidCosmetic(cosmeticName, weapon) then return true end
    return oldOwnsCosmeticForWeapon(self, slot, weapon, cosmeticName)
end

RequiredCosmetics.OwnsCosmeticNormally = function(self, cosmeticName, ...)
    if isValidCosmetic(cosmeticName, nil) then return true end
    return oldOwnsCosmeticNormally(self, cosmeticName, ...)
end

RequiredCosmetics.OwnsCosmeticUniversally = oldOwnsCosmeticUniversally
RequiredCosmetics.OwnsCosmeticForSomething = oldOwnsCosmeticForSomething

-- Hook Player Data Queries
local oldGet = RequiredPlayerData.Get
RequiredPlayerData.Get = function(self, property)
    local result = oldGet(self, property)
    if property == "CosmeticInventory" then return result end
    if property == "FavoritedCosmetics" then
        local favoritesMap = {}
        if result then
            for k, v in pairs(result) do favoritesMap[k] = v end
        end
        for category, items in pairs(FavoriteCosmetics) do
            favoritesMap[category] = favoritesMap[category] or {}
            for item, state in pairs(items) do
                favoritesMap[category][item] = state
            end
        end
        return favoritesMap
    end
    return result
end

local oldGetWeaponData = RequiredPlayerData.GetWeaponData
RequiredPlayerData.GetWeaponData = function(self, weaponName)
    local weaponData = {Unlocked = true, Level = 100, XP = 99999}
    local actualData = oldGetWeaponData(self, weaponName)
    if actualData then
        for k, v in pairs(actualData) do weaponData[k] = v end
    end
    if EquippedSkins and EquippedSkins[weaponName] then
        for category, cosmetic in pairs(EquippedSkins[weaponName]) do
            weaponData[category] = cosmetic
        end
    end
    return weaponData
end

-- Dynamically fetch Fighter Controllers
local FighterController
task.spawn(function()
    local fc = Controllers:FindFirstChild("FighterController")
    if fc then pcall(function() FighterController = require(fc) end) end
end)

-- Metatable Hooking for Remotes (Equipping / Intercepting network traffic)
task.spawn(function()
    task.wait(1)
    if not hookmetamethod then return end
    
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if not remotes then return end
    
    local dataRemoteFolder = remotes:FindFirstChild("Data")
    local replicationRemoteFolder = remotes:FindFirstChild("Replication")
    
    local equipCosmeticRemote = dataRemoteFolder and dataRemoteFolder:FindFirstChild("EquipCosmetic")
    local favoriteCosmeticRemote = dataRemoteFolder and dataRemoteFolder:FindFirstChild("FavoriteCosmetic")
    local fighterRemote = replicationRemoteFolder and replicationRemoteFolder:FindFirstChild("Fighter")
    local useItemRemote = fighterRemote and fighterRemote:FindFirstChild("UseItem")
    
    if not equipCosmeticRemote then return end
    
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        if getnamecallmethod() ~= "FireServer" then return oldNamecall(self, ...) end
        
        local args = {...}
        if useItemRemote and (self == useItemRemote) and FighterController then
            task.spawn(function()
                pcall(function()
                    local fighter = FighterController:GetFighter(LocalPlayer)
                    if fighter and fighter.Items then
                        for _, item in pairs(fighter.Items) do
                            if item:Get("ObjectID") == args[1] then
                                CurrentActiveFighterName = item.Name
                                break
                            end
                        end
                    end
                end)
            end)
        end
        
        if self == equipCosmeticRemote then
            local weapon, slot, cosmetic = args[1], args[2], args[3]
            local config = args[4] or {}
            
            EquippedSkins[weapon] = EquippedSkins[weapon] or {}
            if not cosmetic or cosmetic == "None" or cosmetic == "" then
                EquippedSkins[weapon][slot] = nil
                if not next(EquippedSkins[weapon]) then EquippedSkins[weapon] = nil end
            else
                local cosmeticObj = createCosmeticObject(cosmetic, slot, {inverted = config.IsInverted, favoritesOnly = config.OnlyUseFavorites})
                if cosmeticObj then EquippedSkins[weapon][slot] = cosmeticObj end
            end
            
            task.spawn(function()
                task.wait(0.1)
                pcall(function() RequiredPlayerData.CurrentData:Replicate("WeaponInventory") end)
                saveConfig()
            end)
            return
        end
        
        if favoriteCosmeticRemote and (self == favoriteCosmeticRemote) then
            FavoriteCosmetics[args[1]] = FavoriteCosmetics[args[1]] or {}
            FavoriteCosmetics[args[1]][args[2]] = args[3] or nil
            saveConfig()
            return
        end
        
        return oldNamecall(self, ...)
    end)
end)

-- Visual Hooking for viewmodels and rendering skins locally
local oldGetViewModelImage = RequiredItems.GetViewModelImageFromWeaponData
RequiredItems.GetViewModelImageFromWeaponData = function(self, weaponData, resolutionFlag)
    if not weaponData then return oldGetViewModelImage(self, weaponData, resolutionFlag) end
    local weaponName = weaponData.Name
    local matchesEquipped = (weaponData.Skin and EquippedSkins[weaponName] and (weaponData.Skin == EquippedSkins[weaponName].Skin)) or ((SelectedFighterName == LocalPlayer) and EquippedSkins[weaponName] and EquippedSkins[weaponName].Skin)
    
    if matchesEquipped and EquippedSkins[weaponName] and EquippedSkins[weaponName].Skin then
        local visualModel = self.ViewModels[EquippedSkins[weaponName].Skin.Name]
        if visualModel then
            return visualModel[resolutionFlag and "ImageHighResolution" or "Image"] or visualModel.Image
        end
    end
    return oldGetViewModelImage(self, weaponData, resolutionFlag)
end

-- Hook Viewmodel Generation Classes
task.spawn(function()
    task.wait(3)
    pcall(function()
        local clientItemClass = PlayerScripts.Modules.ClientReplicatedClasses.ClientFighter.ClientItem
        local clientItem = require(clientItemClass)
        
        if clientItem._CreateViewModel then
            local oldCreateViewModel = clientItem._CreateViewModel
            clientItem._CreateViewModel = function(self, renderData)
                local itemName = self.Name
                local owner = self.ClientFighter and self.ClientFighter.Player
                v25 = (owner == LocalPlayer) and itemName or nil
                
                if (owner == LocalPlayer) and EquippedSkins[itemName] and EquippedSkins[itemName].Skin and renderData then
                    pcall(function()
                        local keyData = self:ToEnum("Data")
                        local keySkin = self:ToEnum("Skin")
                        local keyName = self:ToEnum("Name")
                        if renderData[keyData] then
                            renderData[keyData][keySkin] = EquippedSkins[itemName].Skin
                            renderData[keyData][keyName] = EquippedSkins[itemName].Skin.Name
                        elseif renderData.Data then
                            renderData.Data.Skin = EquippedSkins[itemName].Skin
                            renderData.Data.Name = EquippedSkins[itemName].Skin.Name
                        end
                    end)
                end
                local vmResult = oldCreateViewModel(self, renderData)
                v25 = nil
                return vmResult
            end
        end
    end)

    pcall(function()
        local viewModelClass = PlayerScripts.Modules.ClientReplicatedClasses.ClientFighter.ClientItem:FindFirstChild("ClientViewModel")
        if viewModelClass then
            local vm = require(viewModelClass)
            if vm.GetWrap then
                local oldGetWrap = vm.GetWrap
                vm.GetWrap = function(self)
                    local itemName = self.ClientItem and self.ClientItem.Name
                    local owner = self.ClientItem and self.ClientItem.ClientFighter and self.ClientItem.ClientFighter.Player
                    if itemName and (owner == LocalPlayer) and EquippedSkins[itemName] and EquippedSkins[itemName].Wrap then
                        return EquippedSkins[itemName].Wrap
                    end
                    return oldGetWrap(self)
                end
            end
            
            local oldVmNew = vm.new
            vm.new = function(self, context)
                local owner = context.ClientFighter and context.ClientFighter.Player
                local itemName = v25 or context.Name
                if (owner == LocalPlayer) and EquippedSkins[itemName] then
                    pcall(function()
                        local repClass = require(ReplicatedStorage.Modules.ReplicatedClass)
                        local dataEnum = repClass:ToEnum("Data")
                        self[dataEnum] = self[dataEnum] or {}
                        local currentSkinConfig = EquippedSkins[itemName]
                        if currentSkinConfig.Skin then self[dataEnum][repClass:ToEnum("Skin")] = currentSkinConfig.Skin end
                        if currentSkinConfig.Wrap then self[dataEnum][repClass:ToEnum("Wrap")] = currentSkinConfig.Wrap end
                        if currentSkinConfig.Charm then self[dataEnum][repClass:ToEnum("Charm")] = currentSkinConfig.Charm end
                    end)
                end
                local vmInstance = oldVmNew(self, context)
                if (owner == LocalPlayer) and EquippedSkins[itemName] and EquippedSkins[itemName].Wrap and vmInstance._UpdateWrap then
                    task.spawn(function()
                        vmInstance:_UpdateWrap()
                        task.wait(0.1)
                        if not vmInstance._destroyed then vmInstance:_UpdateWrap() end
                    end)
                end
                return vmInstance
            end
        end
    end)

    -- Hook Profile Inspector
    pcall(function()
        local viewProfile = require(PlayerScripts.Modules.Pages.ViewProfile)
        if viewProfile and viewProfile.Fetch then
            local oldFetch = viewProfile.Fetch
            viewProfile.Fetch = function(self, targetPlayer)
                SelectedFighterName = targetPlayer
                return oldFetch(self, targetPlayer)
            end
        end
    end)

    -- Hook Finisher Replication Effects
    pcall(function()
        local clientEntity = require(PlayerScripts.Modules.ClientReplicatedClasses.ClientEntity)
        if clientEntity.ReplicateFromServer then
            local oldReplicate = clientEntity.ReplicateFromServer
            clientEntity.ReplicateFromServer = function(self, actionType, ...)
                if actionType == "FinisherEffect" then
                    local args = {...}
                    local targetUser = args[3]
                    local processedUser = targetUser
                    if (type(targetUser) == "userdata") and EnumLibrary and EnumLibrary.FromEnum then
                        pcall(function() processedUser = EnumLibrary:FromEnum(targetUser) end)
                    end
                    
                    local isSelf = (tostring(processedUser) == LocalPlayer.Name) or (tostring(processedUser):lower() == LocalPlayer.Name:lower())
                    if isSelf and CurrentActiveFighterName and EquippedSkins[CurrentActiveFighterName] and EquippedSkins[CurrentActiveFighterName].Finisher then
                        local customFinisher = EquippedSkins[CurrentActiveFighterName].Finisher
                        local finisherEnum = customFinisher.Enum
                        if not finisherEnum and EnumLibrary then
                            pcall(function() finisherEnum = EnumLibrary:ToEnum(customFinisher.Name) end)
                        end
                        if finisherEnum then
                            args[1] = finisherEnum
                            return oldReplicate(self, actionType, unpack(args))
                        end
                    end
                end
                return oldReplicate(self, actionType, ...)
            end
        end
    end)
end)
