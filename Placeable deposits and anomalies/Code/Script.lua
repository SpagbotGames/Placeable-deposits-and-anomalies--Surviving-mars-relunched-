-- Placeable deposits and anomalies - V3
-- Surviving Mars: Relaunched
--
-- IMPORTANT:
-- The build-menu entries themselves are real ModItemBuildingTemplate objects
-- defined in items.lua.  This file only provides the Building-derived class
-- that those templates instantiate and converts it into the requested map
-- object after placement.

local MOD_TAG = "[Placeable deposits and anomalies] "
local DEPOSIT_AMOUNT = 5000 * (const.ResourceScale or 1000)

local function Log(text)
	if ModLog then
		ModLog(MOD_TAG .. tostring(text))
	end
end

local tools = {
	MPT_Place_Concrete = {
		kind = "resource",
		marker = "TerrainDepositMarker",
		resource = "Concrete",
	},
	MPT_Place_Water = {
		kind = "resource",
		marker = "SubsurfaceDepositMarker",
		resource = "Water",
		depth_layer = 1,
	},
	MPT_Place_Metals = {
		kind = "resource",
		marker = "SubsurfaceDepositMarker",
		resource = "Metals",
		depth_layer = 1,
	},
	MPT_Place_RareMetals = {
		kind = "resource",
		marker = "SubsurfaceDepositMarker",
		resource = "PreciousMetals",
		depth_layer = 1,
	},
	MPT_Place_ExoticMinerals = {
		kind = "resource",
		marker = "SubsurfaceDepositMarker",
		resource = "PreciousMinerals",
		depth_layer = 1,
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

local function RevealObject(obj)
	if not IsValid(obj) then
		return
	end
	if obj.SetRevealed then
		obj:SetRevealed(true)
	else
		obj.revealed = true
	end
	if obj.PickVisibilityState then
		obj:PickVisibilityState()
	end
end

local function GetMapId(obj)
	-- Placement happens on the active map.  GetMapID is used when available
	-- so this also behaves correctly on non-surface maps.
	if obj and obj.GetMapID then
		local id = obj:GetMapID()
		if id then
			return id
		end
	end
	return ActiveMapID
end

local function NewMarker(class_name, map_id)
	if not class_name then
		return
	end
	if g_Classes and not g_Classes[class_name] then
		Log("Missing game class: " .. class_name)
		return
	end

	if PlaceObjectIn and map_id then
		return PlaceObjectIn(class_name, map_id)
	end
	if PlaceObject then
		return PlaceObject(class_name)
	end
end

local function PlaceResource(tool, pos, map_id)
	local marker = NewMarker(tool.marker, map_id)
	if not IsValid(marker) then
		Log("Could not create " .. tostring(tool.marker))
		return false
	end

	marker:SetPos(pos)
	marker.resource = tool.resource
	marker.grade = "Very High"
	marker.max_amount = DEPOSIT_AMOUNT
	marker.revealed = true

	if tool.depth_layer then
		marker.depth_layer = tool.depth_layer
	end

	-- This follows the native marker workflow used by the game.  Some marker
	-- revisions need SpawnDeposit before PlaceDeposit, while others can use
	-- PlaceDeposit directly, so support both.
	local spawned
	if marker.SpawnDeposit then
		spawned = marker:SpawnDeposit()
	end

	local deposit
	if marker.PlaceDeposit then
		deposit = marker:PlaceDeposit()
	end
	deposit = deposit or spawned

	if IsValid(deposit) then
		RevealObject(deposit)
		Log("Placed resource deposit: " .. tostring(tool.resource))
		return true
	end

	-- A few marker implementations keep/manage the resulting deposit
	-- internally and return nil. If the marker survived, still count this as
	-- a successful native placement attempt and let the game own it.
	if IsValid(marker) then
		RevealObject(marker)
		Log("Placed resource marker: " .. tostring(tool.resource))
		return true
	end

	Log("Resource placement returned no deposit: " .. tostring(tool.resource))
	return false
end

local function PlaceAnomaly(tool, pos, map_id)
	local marker = NewMarker("SubsurfaceAnomalyMarker", map_id)
	if not IsValid(marker) then
		Log("Could not create SubsurfaceAnomalyMarker")
		return false
	end

	marker:SetPos(pos)
	marker.sequence = "Static Dust Charge"
	marker.sequence_list = "Anomalies"
	marker.tech_action = tool.tech_action
	marker.revealed = true

	local deposit
	if marker.PlaceDeposit then
		deposit = marker:PlaceDeposit()
	end

	if IsValid(deposit) then
		RevealObject(deposit)
	else
		-- The official anomaly example relies on PlaceDeposit and does not
		-- require the return value, so do not treat nil as a hard failure.
		RevealObject(marker)
	end

	Log("Placed anomaly: " .. tostring(tool.tech_action))
	return true
end

local function PlaceEffect(tool, pos, map_id)
	local marker = NewMarker("EffectDepositMarker", map_id)
	if not IsValid(marker) then
		Log("Could not create EffectDepositMarker")
		return false
	end

	marker:SetPos(pos)
	marker.deposit_type = tool.deposit_type
	marker.revealed = true

	local spawned
	if marker.SpawnDeposit then
		spawned = marker:SpawnDeposit()
	end

	local deposit
	if marker.PlaceDeposit then
		deposit = marker:PlaceDeposit()
	end
	deposit = deposit or spawned

	if IsValid(deposit) then
		RevealObject(deposit)
		Log("Placed map effect: " .. tostring(tool.deposit_type))
		return true
	end

	if IsValid(marker) then
		RevealObject(marker)
		Log("Placed map effect marker: " .. tostring(tool.deposit_type))
		return true
	end

	Log("Effect placement returned no object: " .. tostring(tool.deposit_type))
	return false
end

local function ConvertPlacementBuilding(obj)
	if not IsValid(obj) then
		return
	end

	local template = obj.template_name
	if not template or template == "" then
		template = obj.fx_actor_class
	end

	local tool = tools[template]
	if not tool then
		Log("Unknown placement template. template_name=" ..
			tostring(obj.template_name) .. " fx_actor_class=" ..
			tostring(obj.fx_actor_class))
		DoneObject(obj)
		return
	end

	local pos = obj:GetVisualPos()
	local map_id = GetMapId(obj)

	Log("Converting placement tool: " .. tostring(template))

	if tool.kind == "resource" then
		PlaceResource(tool, pos, map_id)
	elseif tool.kind == "anomaly" then
		PlaceAnomaly(tool, pos, map_id)
	elseif tool.kind == "effect" then
		PlaceEffect(tool, pos, map_id)
	end

	if IsValid(obj) then
		DoneObject(obj)
	end
end

DefineClass.MPT_PlacementBuilding = {
	__parents = { "Building" },
}

function MPT_PlacementBuilding:GameInit()
	-- Let the ordinary Building class finish its normal instant-build setup,
	-- then convert this temporary object on the next game-time tick.
	Building.GameInit(self)

	CreateGameTimeThread(function(obj)
		Sleep(1)
		ConvertPlacementBuilding(obj)
	end, self)
end

function OnMsg.ClassesBuilt()
	Log("MPT_PlacementBuilding finalized")
end

function OnMsg.CityStart()
	Log("V3 loaded in colony")
end

function OnMsg.LoadGame()
	Log("V3 loaded with save")
end

Log("V3 code loaded")
