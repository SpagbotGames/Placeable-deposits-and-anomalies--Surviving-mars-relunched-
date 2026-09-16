-- Placeable deposits and anomalies - V5
-- Surviving Mars: Relaunched
--
-- Fixes from V4:
--   1. Relaunched uses CurrentMap (a map object), not ActiveMapID.
--   2. Do NOT call SpawnDeposit() manually. DepositMarker:PlaceDeposit()
--      already calls SpawnDeposit(), registers the deposit, and positions it.
--   3. Remove the temporary placement building BEFORE spawning the marker,
--      so the proxy itself cannot obstruct a Vista / Research Site / deposit.

local MOD_TAG = "[Placeable deposits and anomalies] "
local CATEGORY_ID = "MPT_MapPlacement"

local function Log(msg)
	if ModLog then
		ModLog(MOD_TAG .. tostring(msg))
	end
end

local RESOURCE_SCALE = (const and const.ResourceScale) or 1000
local DEPOSIT_AMOUNT = 5000 * RESOURCE_SCALE

local definitions = {
	MPT_Place_Concrete = {
		kind = "terrain_resource",
		resource = "Concrete",
		amount = 2500 * RESOURCE_SCALE,
	},
	MPT_Place_Water = {
		kind = "subsurface_resource",
		resource = "Water",
		amount = 5000 * RESOURCE_SCALE,
	},
	MPT_Place_Metals = {
		kind = "subsurface_resource",
		resource = "Metals",
		amount = 5000 * RESOURCE_SCALE,
	},
	MPT_Place_RareMetals = {
		kind = "subsurface_resource",
		resource = "PreciousMetals",
		amount = 5000 * RESOURCE_SCALE,
	},
	MPT_Place_ExoticMinerals = {
		kind = "subsurface_resource",
		resource = "PreciousMinerals",
		amount = 5000 * RESOURCE_SCALE,
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

local function CurrentPlacementMap()
	-- Relaunched's documented map global. PlaceObjectIn now expects the
	-- actual map object rather than the old ActiveMapID value.
	if CurrentMap and CurrentMap.IsValid and CurrentMap:IsValid() then
		return CurrentMap
	end

	Log("CurrentMap is missing or invalid")
end

local function NewOnCurrentMap(class_name)
	local map = CurrentPlacementMap()
	if not map then
		return
	end

	local ok, obj = pcall(PlaceObjectIn, class_name, map)
	if not ok then
		Log("PlaceObjectIn(" .. tostring(class_name) .. ") ERROR: " .. tostring(obj))
		return
	end

	return obj
end

local function Reveal(obj)
	if not IsValid(obj) then
		return
	end

	if obj.SetRevealed then
		local ok, err = pcall(obj.SetRevealed, obj, true)
		if not ok then
			Log("SetRevealed ERROR: " .. tostring(err))
		end
	else
		obj.revealed = true
	end

	if obj.PickVisibilityState then
		local ok, err = pcall(obj.PickVisibilityState, obj)
		if not ok then
			Log("PickVisibilityState ERROR: " .. tostring(err))
		end
	end
end

local function PlaceResource(pos, resource, terrain_resource, amount)
	local marker_class = terrain_resource and "TerrainDepositMarker" or "SubsurfaceDepositMarker"
	local marker = NewOnCurrentMap(marker_class)

	if not IsValid(marker) then
		Log("Could not create " .. marker_class)
		return
	end

	marker:SetPos(pos)
	marker.resource = resource
	marker.grade = "Very High"
	marker.max_amount = amount or DEPOSIT_AMOUNT
	marker.revealed = true

	if not terrain_resource then
		marker.depth_layer = 1
	end

	-- IMPORTANT: PlaceDeposit() performs SpawnDeposit() itself, then assigns
	-- the final map position and registers the deposit with its sector.
	local ok, deposit = pcall(marker.PlaceDeposit, marker, true)
	if not ok then
		Log(marker_class .. ":PlaceDeposit ERROR: " .. tostring(deposit))
		return
	end

	if IsValid(deposit) then
		Reveal(deposit)
		Log("Placed resource deposit: " .. tostring(resource))
	else
		Log("No resource deposit was returned for " .. tostring(resource))
	end
end

local function PlaceAnomaly(pos, tech_action)
	local marker = NewOnCurrentMap("SubsurfaceAnomalyMarker")

	if not IsValid(marker) then
		Log("Could not create SubsurfaceAnomalyMarker")
		return
	end

	marker:SetPos(pos)
	marker.sequence = "Static Dust Charge"
	marker.sequence_list = "Anomalies"
	marker.tech_action = tech_action
	marker.revealed = true

	local ok, deposit = pcall(marker.PlaceDeposit, marker, true)
	if not ok then
		Log("SubsurfaceAnomalyMarker:PlaceDeposit ERROR: " .. tostring(deposit))
		return
	end

	Reveal(deposit)
	Log("Placed anomaly: " .. tostring(tech_action))
end

local function PlaceEffect(pos, deposit_type)
	local marker = NewOnCurrentMap("EffectDepositMarker")

	if not IsValid(marker) then
		Log("Could not create EffectDepositMarker")
		return
	end

	marker:SetPos(pos)
	marker.deposit_type = deposit_type
	marker.revealed = true

	-- EffectDepositMarker inherits the normal DepositMarker placement path.
	-- Do not call SpawnDeposit() ourselves.
	local ok, deposit = pcall(marker.PlaceDeposit, marker, true)
	if not ok then
		Log("EffectDepositMarker:PlaceDeposit ERROR (" ..
			tostring(deposit_type) .. "): " .. tostring(deposit))
		return
	end

	if IsValid(deposit) then
		Reveal(deposit)

		-- Effect deposits override GameInit in the reference implementation,
		-- so refreshing their visuals once AFTER PlaceDeposit has assigned a
		-- valid position is safe and avoids initializing visuals at InvalidPos.
		if deposit.AdjustVisuals then
			local vok, verr = pcall(deposit.AdjustVisuals, deposit)
			if not vok then
				Log(tostring(deposit_type) .. ":AdjustVisuals ERROR: " .. tostring(verr))
			end
		end

		Log("Placed map effect: " .. tostring(deposit_type))
	else
		Log("No map effect was returned for " .. tostring(deposit_type))
	end
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
		DoneObject(obj)
		return
	end

	local pos = obj:GetVisualPos()

	Log("Converting " .. tostring(id))

	-- Remove the zero-cost proxy first. EffectDepositMarker does not search
	-- for an alternate position when obstructed, so leaving the proxy here
	-- can prevent Vistas/Research Sites from spawning.
	DoneObject(obj)

	-- Give the construction/obstruction grids one game-time tick to clear
	-- the removed proxy before creating the real marker.
	Sleep(1)

	if def.kind == "terrain_resource" then
		PlaceResource(pos, def.resource, true, def.amount)
	elseif def.kind == "subsurface_resource" then
		PlaceResource(pos, def.resource, false, def.amount)
	elseif def.kind == "anomaly" then
		PlaceAnomaly(pos, def.tech_action)
	elseif def.kind == "effect" then
		PlaceEffect(pos, def.deposit_type)
	end
end

DefineClass.MPT_PlacementBuilding = {
	__parents = { "Building" },
}

function MPT_PlacementBuilding:GameInit()
	local obj = self

	CreateGameTimeThread(function()
		-- Let instant-build placement finish completely first.
		Sleep(1)
		ConvertProxy(obj)
	end)
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
Log("V5 code loaded")
