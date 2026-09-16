-- Placeable deposits and anomalies - V4
-- Surviving Mars: Relaunched
--
-- V4 follows the current Relaunched sample-mod layout:
--   * items.lua only contains the Code item + ModItemRef entries.
--   * Building Template presets live in Data/BuildingTemplate/.
--   * Generated buildable classes live in Code/BuildingTemplate/.
--
-- The buildable objects are zero-cost, instant-build placement proxies.
-- Immediately after one is placed, it creates the requested native map
-- marker/deposit/anomaly/effect at that position and removes itself.

local MOD_TAG = "[Placeable deposits and anomalies] "
local CATEGORY_ID = "MPT_MapPlacement"

local function Log(msg)
	if ModLog then
		ModLog(MOD_TAG .. tostring(msg))
	end
end

local function SafeCall(label, fn, ...)
	local ok, a, b, c = pcall(fn, ...)
	if not ok then
		Log(label .. " ERROR: " .. tostring(a))
		return false
	end
	return true, a, b, c
end

local RESOURCE_SCALE = (const and const.ResourceScale) or 1000
local DEPOSIT_AMOUNT = 5000 * RESOURCE_SCALE

local definitions = {
	MPT_Place_Concrete = {
		kind = "terrain_resource",
		resource = "Concrete",
	},
	MPT_Place_Water = {
		kind = "subsurface_resource",
		resource = "Water",
	},
	MPT_Place_Metals = {
		kind = "subsurface_resource",
		resource = "Metals",
	},
	MPT_Place_RareMetals = {
		kind = "subsurface_resource",
		resource = "PreciousMetals",
	},
	MPT_Place_ExoticMinerals = {
		kind = "subsurface_resource",
		resource = "PreciousMinerals",
	},

	MPT_Place_ResearchAnomaly = {
		kind = "anomaly",
		tech_action = "complete",
	},
	MPT_Place_TechAnomaly = {
		kind = "anomaly",
		tech_action = "unlock",
	},
	MPT_Place_BreakthroughAnomaly = {
		kind = "anomaly",
		tech_action = "breakthrough",
	},
	MPT_Place_ResourceAnomaly = {
		kind = "anomaly",
		tech_action = "resources",
	},

	MPT_Place_Vista = {
		kind = "effect",
		deposit_type = "BeautyEffectDeposit",
	},
	MPT_Place_ResearchSite = {
		kind = "effect",
		deposit_type = "ResearchEffectDeposit",
	},
}

local function CurrentMapId(obj)
	if obj and obj.GetMapID then
		local ok, id = pcall(obj.GetMapID, obj)
		if ok and id then
			return id
		end
	end
	return ActiveMapID
end

local function NewOnMap(class_name, map_id)
	if PlaceObjectIn and map_id then
		local ok, obj = pcall(PlaceObjectIn, class_name, map_id)
		if ok and obj then
			return obj
		end
	end
	if PlaceObject then
		local ok, obj = pcall(PlaceObject, class_name)
		if ok then
			return obj
		end
	end
end

local function Reveal(obj)
	if not IsValid(obj) then
		return
	end

	if obj.SetRevealed then
		pcall(obj.SetRevealed, obj, true)
	else
		obj.revealed = true
	end

	if obj.PickVisibilityState then
		pcall(obj.PickVisibilityState, obj)
	end
end

local function PlaceResource(pos, map_id, resource, terrain_resource)
	local marker_class = terrain_resource and "TerrainDepositMarker" or "SubsurfaceDepositMarker"
	local marker = NewOnMap(marker_class, map_id)

	if not IsValid(marker) then
		Log("Could not create " .. marker_class)
		return
	end

	marker:SetPos(pos)
	marker.resource = resource
	marker.grade = "Very High"
	marker.max_amount = DEPOSIT_AMOUNT
	marker.revealed = true

	if not terrain_resource then
		marker.depth_layer = 1
	end

	-- This is the native marker sequence used by the game/modding examples:
	-- SpawnDeposit -> PlaceDeposit -> PickVisibilityState.
	if marker.SpawnDeposit then
		local ok, err = pcall(marker.SpawnDeposit, marker)
		if not ok then
			Log(marker_class .. ":SpawnDeposit ERROR: " .. tostring(err))
		end
	end

	local deposit
	if marker.PlaceDeposit then
		local ok, result = pcall(marker.PlaceDeposit, marker)
		if ok then
			deposit = result
		else
			Log(marker_class .. ":PlaceDeposit ERROR: " .. tostring(result))
		end
	end

	Reveal(deposit)
	Reveal(marker)
	Log("Placement attempted: " .. tostring(resource))
end

local function PlaceAnomaly(pos, map_id, tech_action)
	local marker = NewOnMap("SubsurfaceAnomalyMarker", map_id)

	if not IsValid(marker) then
		Log("Could not create SubsurfaceAnomalyMarker")
		return
	end

	marker:SetPos(pos)
	marker.sequence = "Static Dust Charge"
	marker.sequence_list = "Anomalies"
	marker.tech_action = tech_action
	marker.revealed = true

	if marker.PlaceDeposit then
		local ok, result = pcall(marker.PlaceDeposit, marker)
		if not ok then
			Log("SubsurfaceAnomalyMarker:PlaceDeposit ERROR: " .. tostring(result))
		else
			Reveal(result)
		end
	else
		Log("SubsurfaceAnomalyMarker has no PlaceDeposit method")
	end

	Reveal(marker)
	Log("Placement attempted: anomaly/" .. tostring(tech_action))
end

local function PlaceEffect(pos, map_id, deposit_type)
	local marker = NewOnMap("EffectDepositMarker", map_id)

	if not IsValid(marker) then
		Log("Could not create EffectDepositMarker")
		return
	end

	marker:SetPos(pos)
	marker.deposit_type = deposit_type
	marker.revealed = true

	if marker.SpawnDeposit then
		local ok, err = pcall(marker.SpawnDeposit, marker)
		if not ok then
			Log("EffectDepositMarker:SpawnDeposit ERROR: " .. tostring(err))
		end
	end

	local deposit
	if marker.PlaceDeposit then
		local ok, result = pcall(marker.PlaceDeposit, marker)
		if ok then
			deposit = result
		else
			Log("EffectDepositMarker:PlaceDeposit ERROR: " .. tostring(result))
		end
	end

	Reveal(deposit)
	Reveal(marker)
	Log("Placement attempted: " .. tostring(deposit_type))
end

local function FindDefinition(obj)
	local candidates = {
		obj.class,
		obj.template_name,
		obj.fx_actor_class,
	}

	for _, id in ipairs(candidates) do
		if id and definitions[id] then
			return id, definitions[id]
		end
	end
end

local function ConvertProxy(obj)
	if not IsValid(obj) then
		return
	end

	local id, def = FindDefinition(obj)
	if not def then
		Log(
			"Unknown placement proxy. class=" .. tostring(obj.class) ..
			" template_name=" .. tostring(obj.template_name) ..
			" fx_actor_class=" .. tostring(obj.fx_actor_class)
		)
		if IsValid(obj) then
			DoneObject(obj)
		end
		return
	end

	local pos = obj:GetVisualPos()
	local map_id = CurrentMapId(obj)

	Log("Converting " .. tostring(id))

	if def.kind == "terrain_resource" then
		PlaceResource(pos, map_id, def.resource, true)
	elseif def.kind == "subsurface_resource" then
		PlaceResource(pos, map_id, def.resource, false)
	elseif def.kind == "anomaly" then
		PlaceAnomaly(pos, map_id, def.tech_action)
	elseif def.kind == "effect" then
		PlaceEffect(pos, map_id, def.deposit_type)
	end

	if IsValid(obj) then
		DoneObject(obj)
	end
end

-- Same idea as the bundled Cemetery sample: custom gameplay class derives
-- from Building, while each Building Template generates a child class.
DefineClass.MPT_PlacementBuilding = {
	__parents = { "Building" },
}

function MPT_PlacementBuilding:GameInit()
	local obj = self

	-- Delay conversion until the instant-build placement has completely
	-- finished creating the object.
	if CreateGameTimeThread then
		CreateGameTimeThread(function()
			Sleep(1)
			ConvertProxy(obj)
		end)
	elseif DelayedCall then
		DelayedCall(0, ConvertProxy, obj)
	else
		ConvertProxy(obj)
	end
end

local function RegisterCategory()
	if not BuildMenuSubcategories then
		Log("BuildMenuSubcategories is not available yet")
		return false
	end

	if not BuildMenuSubcategories[CATEGORY_ID] then
		PlaceObj("BuildMenuSubcategory", {
			build_pos = 99,
			category = "Storages",
			description = T(0, "Place deposits, anomalies, Vistas, and Research Sites directly on the map."),
			display_name = T(0, "Map Placement"),
			group = "Default",
			icon = "UI/Icons/Buildings/res_all.tga",
			category_name = CATEGORY_ID,
			id = CATEGORY_ID,
		})
		Log("Registered Map Placement build-menu category")
	else
		Log("Map Placement build-menu category already exists")
	end

	if RefreshXBuildMenu then
		pcall(RefreshXBuildMenu)
	end

	return true
end

function OnMsg.ClassesPostprocess()
	RegisterCategory()
end

function OnMsg.ModsReloaded()
	RegisterCategory()
end

function OnMsg.CityStart()
	RegisterCategory()
end

function OnMsg.LoadGame()
	RegisterCategory()
end

RegisterCategory()
Log("V4 code loaded")
