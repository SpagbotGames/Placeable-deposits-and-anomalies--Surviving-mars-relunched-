-- Placeable deposits and anomalies
-- Surviving Mars: Relaunched
--
-- Adds a Map Placement submenu under Storages and lets the player place
-- deposits, anomalies, Vistas, and Research Sites with the normal build cursor.

local CATEGORY_ID = "MPT_MapPlacement"
local CATEGORY_NAME = "Map Placement"

local DEPOSIT_AMOUNT = 5000 * (const.ResourceScale or 1000)
local VISTA_COMFORT = 25 * 1000
local RESEARCH_SITE_PERCENT = 50
local ANOMALY_RESOURCE_AMOUNT = 50 * (const.ResourceScale or 1000)

local function MPT_Log(text)
	if ModLog then
		ModLog("[Placeable deposits and anomalies] " .. text)
	end
end

-- These are the same marker families the game uses to turn map markers into
-- real deposits/effects. Adding Building as a parent lets the normal build
-- placement controller place them for us.
DefineClass.MPT_SubsurfaceDepositMarker = {
	__parents = {
		"SubsurfaceDepositMarker",
		"Building",
	},
	grade = "Very High",
	instant_build = true,
}

DefineClass.MPT_TerrainDepositMarker = {
	__parents = {
		"TerrainDepositMarker",
		"Building",
	},
	grade = "Very High",
	instant_build = true,
}

DefineClass.MPT_EffectDepositMarker = {
	__parents = {
		"EffectDepositMarker",
		"Building",
	},
	instant_build = true,
}

DefineClass.MPT_SubsurfaceAnomalyMarker = {
	__parents = {
		"SubsurfaceAnomalyMarker",
		"Building",
	},
	instant_build = true,
}

-- BuildingTemplate IDs are deliberately based on the class name. The game
-- stores the template ID in fx_actor_class, which gives us an easy lookup for
-- what the placed marker should become.
local deposit_lookup = {
	MPT_SubsurfaceDepositMarker_Metals = "Metals",
	MPT_SubsurfaceDepositMarker_PreciousMetals = "PreciousMetals",
	MPT_SubsurfaceDepositMarker_Water = "Water",
	MPT_SubsurfaceDepositMarker_PreciousMinerals = "PreciousMinerals",
	MPT_TerrainDepositMarker_Concrete = "Concrete",

	MPT_EffectDepositMarker_Vista = "BeautyEffectDeposit",
	MPT_EffectDepositMarker_ResearchSite = "ResearchEffectDeposit",

	MPT_SubsurfaceAnomalyMarker_Breakthrough = "breakthrough",
	MPT_SubsurfaceAnomalyMarker_Tech = "unlock",
	MPT_SubsurfaceAnomalyMarker_Research = "complete",
	MPT_SubsurfaceAnomalyMarker_Resources = "resources",
}

local function GameInit_Resource(self)
	self.resource = deposit_lookup[self.fx_actor_class]
	if not self.resource then
		MPT_Log("Unknown resource template: " .. tostring(self.fx_actor_class))
		self:delete()
		return
	end

	local deposit = self:SpawnDeposit()
	if not deposit then
		MPT_Log("SpawnDeposit failed for " .. tostring(self.resource))
		self:delete()
		return
	end

	deposit:SetPos(self:GetVisualPos())

	if deposit.resource ~= "Concrete" and deposit.SetRevealed then
		deposit:SetRevealed(true)
	elseif deposit.resource ~= "Concrete" then
		deposit.revealed = true
	end

	if deposit.resource ~= "Concrete" then
		deposit.amount = DEPOSIT_AMOUNT
	end
	deposit.max_amount = DEPOSIT_AMOUNT

	MPT_Log("Placed " .. tostring(self.resource) .. " deposit")
	self:delete()
end

MPT_SubsurfaceDepositMarker.GameInit = GameInit_Resource
MPT_TerrainDepositMarker.GameInit = GameInit_Resource

local function GameInit_Effect(self)
	self.deposit_type = deposit_lookup[self.fx_actor_class]
	if not self.deposit_type then
		MPT_Log("Unknown effect template: " .. tostring(self.fx_actor_class))
		self:delete()
		return
	end

	local deposit = self:SpawnDeposit()
	if not deposit then
		MPT_Log("SpawnDeposit failed for " .. tostring(self.deposit_type))
		self:delete()
		return
	end

	deposit:SetPos(self:GetVisualPos())
	if deposit.SetRevealed then
		deposit:SetRevealed(true)
	else
		deposit.revealed = true
	end

	if self.deposit_type == "ResearchEffectDeposit" then
		deposit.research_increase = RESEARCH_SITE_PERCENT
		if deposit.modifier then
			deposit.modifier.percent = RESEARCH_SITE_PERCENT
		end
	elseif self.deposit_type == "BeautyEffectDeposit" then
		deposit.comfort_increase = VISTA_COMFORT
		if deposit.modifier then
			deposit.modifier.amount = VISTA_COMFORT
		end
	end

	MPT_Log("Placed " .. tostring(self.deposit_type))
	self:delete()
end

MPT_EffectDepositMarker.GameInit = GameInit_Effect

local storable_resources = {
	"Concrete",
	"Electronics",
	"Food",
	"Fuel",
	"MachineParts",
	"Metals",
	"Polymers",
	"PreciousMetals",
}

local function GameInit_Anomaly(self)
	self.tech_action = deposit_lookup[self.fx_actor_class]
	if not self.tech_action then
		MPT_Log("Unknown anomaly template: " .. tostring(self.fx_actor_class))
		self:delete()
		return
	end

	local deposit = self:SpawnDeposit()
	if not deposit then
		MPT_Log("SpawnDeposit failed for anomaly " .. tostring(self.tech_action))
		self:delete()
		return
	end

	deposit:SetPos(self:GetVisualPos())
	if deposit.SetRevealed then
		deposit:SetRevealed(true)
	else
		deposit.revealed = true
	end

	if self.tech_action == "breakthrough" then
		if UIColony and UIColony.GetUnregisteredBreakthroughs then
			local breakthroughs = UIColony:GetUnregisteredBreakthroughs()
			if breakthroughs and #breakthroughs > 0 then
				deposit.breakthrough_tech = table.rand(breakthroughs)
			end
		end
	elseif self.tech_action == "resources" then
		deposit.granted_resource = table.rand(storable_resources)
		deposit.granted_amount = ANOMALY_RESOURCE_AMOUNT
	end

	MPT_Log("Placed anomaly: " .. tostring(self.tech_action))
	self:delete()
end

MPT_SubsurfaceAnomalyMarker.GameInit = GameInit_Anomaly

local function AddTemplate(obj, params)
	if not obj then
		MPT_Log("Skipped missing source object for " .. tostring(params and params.deposit_type))
		return
	end

	local description = obj.description
	local display_icon = params.display_icon or obj.display_icon
	local display_name = obj.display_name

	if params.display_name then
		display_name = T(0, params.display_name)
	end
	if params.description then
		description = T(0, params.description)
	end

	PlaceObj("BuildingTemplate", {
		"Id", params.class .. params.deposit_type,
		"template_class", params.class,
		"display_name", display_name,
		"display_name_pl", display_name,
		"description", description or T(0, "Place this map object."),
		"display_icon", display_icon,
		"disabled_entity", obj.disabled_entity,
		"entity", obj.entity,
		"build_pos", params.build_pos,
		"build_category", CATEGORY_ID,
		"Group", CATEGORY_ID,
		"instant_build", true,
		"build_points", 0,
		"construction_cost_Concrete", 0,
		"construction_cost_Metals", 0,
		"construction_cost_Polymers", 0,
		"construction_cost_Electronics", 0,
		"construction_cost_MachineParts", 0,
		"dome_forbidden", true,
		"on_off_button", false,
		"prio_button", false,
		"count_as_building", false,
		"disabled_in_environment1", "",
		"disabled_in_environment2", "",
		"disabled_in_environment3", "",
		"disabled_in_environment4", "",
	})
end

local function SetupBuildMenu()
	if not BuildMenuSubcategories or not BuildingTemplates then
		return false
	end

	if not BuildMenuSubcategories[CATEGORY_ID] then
		PlaceObj("BuildMenuSubcategory", {
			build_pos = 99,
			category = "Storages",
			description = T(0, "Place resource deposits, anomalies, Vistas, and Research Sites directly on the map."),
			display_name = T(0, CATEGORY_NAME),
			group = "Default",
			icon = "UI/Icons/Buildings/res_all.tga",
			category_name = CATEGORY_ID,
			id = CATEGORY_ID,
		})
		MPT_Log("Registered Map Placement build-menu category")
	end

	-- If this exists, the rest were already registered during this class pass.
	if BuildingTemplates.MPT_SubsurfaceDepositMarker_Water then
		if RefreshXBuildMenu then
			RefreshXBuildMenu()
		end
		return true
	end

	-- Resource deposits
	AddTemplate(TerrainDepositConcrete, {
		class = "MPT_TerrainDepositMarker",
		deposit_type = "_Concrete",
		build_pos = 1,
		display_name = "Concrete Deposit",
		description = "Place a mineable Concrete deposit.",
	})

	AddTemplate(SubsurfaceDepositWater, {
		class = "MPT_SubsurfaceDepositMarker",
		deposit_type = "_Water",
		build_pos = 2,
		display_name = "Water Deposit",
		description = "Place a subsurface Water deposit.",
	})

	AddTemplate(SubsurfaceDepositMetals, {
		class = "MPT_SubsurfaceDepositMarker",
		deposit_type = "_Metals",
		build_pos = 3,
		display_name = "Metals Deposit",
		description = "Place a subsurface Metals deposit.",
	})

	AddTemplate(SubsurfaceDepositPreciousMetals, {
		class = "MPT_SubsurfaceDepositMarker",
		deposit_type = "_PreciousMetals",
		build_pos = 4,
		display_name = "Rare Metals Deposit",
		description = "Place a subsurface Rare Metals deposit.",
	})

	if rawget(_G, "SubsurfaceDepositPreciousMinerals") then
		AddTemplate(SubsurfaceDepositPreciousMinerals, {
			class = "MPT_SubsurfaceDepositMarker",
			deposit_type = "_PreciousMinerals",
			build_pos = 5,
			display_name = "Exotic Minerals Deposit",
			description = "Place a subsurface Exotic Minerals deposit.",
		})
	end

	-- Anomalies
	AddTemplate(SubsurfaceAnomaly_complete or SubsurfaceAnomaly, {
		class = "MPT_SubsurfaceAnomalyMarker",
		deposit_type = "_Research",
		build_pos = 10,
		display_name = "Research Anomaly",
		description = "Place an anomaly that grants research when analyzed.",
		display_icon = "UI/Icons/Anomaly_Research.tga",
	})

	AddTemplate(SubsurfaceAnomaly_unlock or SubsurfaceAnomaly, {
		class = "MPT_SubsurfaceAnomalyMarker",
		deposit_type = "_Tech",
		build_pos = 11,
		display_name = "Technology Anomaly",
		description = "Place an anomaly that unlocks technology when analyzed.",
		display_icon = "UI/Icons/Anomaly_Tech.tga",
	})

	AddTemplate(SubsurfaceAnomaly_breakthrough or SubsurfaceAnomaly, {
		class = "MPT_SubsurfaceAnomalyMarker",
		deposit_type = "_Breakthrough",
		build_pos = 12,
		display_name = "Breakthrough Anomaly",
		description = "Place an anomaly that unlocks a Breakthrough when analyzed.",
		display_icon = "UI/Icons/Anomaly_Breakthrough.tga",
	})

	AddTemplate(SubsurfaceAnomaly, {
		class = "MPT_SubsurfaceAnomalyMarker",
		deposit_type = "_Resources",
		build_pos = 13,
		display_name = "Resource Anomaly",
		description = "Place an anomaly that grants resources when analyzed.",
		display_icon = "UI/Icons/Anomaly_Event.tga",
	})

	-- Map effects
	AddTemplate(BeautyEffectDeposit, {
		class = "MPT_EffectDepositMarker",
		deposit_type = "_Vista",
		build_pos = 20,
		display_name = "Vista",
		description = "Place a Vista that boosts Comfort for nearby Domes.",
		display_icon = "UI/Icons/Buildings/dome.tga",
	})

	AddTemplate(ResearchEffectDeposit, {
		class = "MPT_EffectDepositMarker",
		deposit_type = "_ResearchSite",
		build_pos = 21,
		display_name = "Research Site",
		description = "Place a Research Site that boosts nearby research buildings.",
		display_icon = "UI/Icons/Buildings/research.tga",
	})

	MPT_Log("Registered Map Placement templates")
	if RefreshXBuildMenu then
		RefreshXBuildMenu()
	end
	return true
end

-- ClassesPostprocess is correct during normal startup. ModsReloaded and the
-- immediate call are important for Relaunched's in-game Mod Editor, where a
-- Code item can be reloaded after ClassesPostprocess has already happened.
function OnMsg.ClassesPostprocess()
	SetupBuildMenu()
end

function OnMsg.ModsReloaded()
	SetupBuildMenu()
end

function OnMsg.CityStart()
	SetupBuildMenu()
end

function OnMsg.LoadGame()
	SetupBuildMenu()
end

-- Try immediately as well. The Modding Guide guarantees game/DLC Lua is loaded
-- before mod Code items, so the preset tables normally exist at this point.
SetupBuildMenu()

MPT_Log("Script loaded")
