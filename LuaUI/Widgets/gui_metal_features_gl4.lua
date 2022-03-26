-- $Id: gui_metal_features.lua 3171 2008-11-06 09:06:29Z det $
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  file:    gui_metal_features.lua
--  brief:   highlights features with metal in metal-map viewmode
--  author:  Dave Rodgers
--
--  Copyright (C) 2007.
--  Licensed under the terms of the GNU GPL, v2 or later.
--
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
  return {
    name      = "MetalFeatures GL4",
    desc      = "Highlights features with the GL4 unit highlight system.",
    author    = "GoogleFrog",
    date      = "26 March 2022",
    license   = "GNU GPL, v2 or later",
    layer     = 0,
    enabled   = true,  --  loaded by default?
  }
end

--------------------------------------------------------------------------------
-- Speed Ups

local spGetMapDrawMode = Spring.GetMapDrawMode
local spGetActiveCommand = Spring.GetActiveCommand
local spGetActiveCmdDesc = Spring.GetActiveCmdDesc
local spGetGameFrame = Spring.GetGameFrame

local BAR_COMPAT = Spring.Utilities.IsCurrentVersionNewerThan(105, 500)

local FEATURE_RADIUS = 120
local ALL_FEATURES = false

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

options_path = 'Settings/Interface/Reclaim Highlight'
options_order = { 'showhighlight', 'pregamehighlight', 'minmetal'}
options = {
	showhighlight = {
		name = 'Show Reclaim',
		desc = "When to highlight reclaimable features",
		type = 'radioButton',
		value = 'constructors',
		items = {
			{key ='always', name='Always'},
			{key ='withecon', name='With the Economy Overlay'},
			{key ='constructors',  name='With Constructors Selected'},
			{key ='conorecon',  name='With Constructors or Overlay'},
			{key ='conandecon',  name='With Constructors and Overlay'},
			{key ='reclaiming',  name='When Reclaiming'},
		},
		noHotkey = true,
	},

	pregamehighlight = {
		name = "Show Reclaim Before Round Start",
		desc = "Enabled: Show reclaimable metal features before game begins \n Disabled: No highlights before game begins",
		type = 'bool',
		value = true,
		noHotkey = true,
	},

	minmetal = {
		name = 'Minimum Reclaim To Highlight',
		desc = "Metal below this amount will not be highlighted",
		type = "number",
		value = 1,
		min = 1,
		max = 200,
		step = 1,
	},
}

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local handledFeatureList = false
local handledFeatures = false
local handledFeatureCheck = false
local handledFeatureApiIDs = false

local firstUpdate = true
local enableCondOld = false
local minMetalShownOld = -1
local highlight = false
local conSelected = false
local currCmd = spGetActiveCommand() --remember current command

local function AddFeature(featureID)
	local metal = Spring.GetFeatureResources(featureID)
	local x100  = 100  / (100  + metal)
	local x1000 = 1000 / (1000 + metal)
	local r = 1 - x1000
	local g = x1000 - x100
	local b = x100
	
	handledFeatureCheck[#handledFeatureCheck + 1] = 1
	handledFeatureList[#handledFeatureList + 1] = featureID
	handledFeatureMap[featureID] = #handledFeatureList
	
	if not (metal and metal > 1) then
		return
	end
	handledFeatureApiIDs[featureID] = WG.HighlightUnitGL4(featureID, 'featureID', r, g, b, 0.5, 0.5, 1, 0.5, 0, 0, 0)
end

--local function HighlightUnitGL4(objectID, objecttype, r, g, b, alpha, edgealpha, edgeexponent, animamount, px, py, pz, rotationY, highlight)

local function UpdateFeatureVisibility()
	-- This whole function is rediculous, but there are no events to handle what is required.
	if not handledFeatureMap then
		return
	end
	local visibleFeatures = (ALL_FEATURES and Spring.GetAllFeatures()) or Spring.GetVisibleFeatures(-1, FEATURE_RADIUS, false, false)
	local newCheck = 3 - (handledFeatureCheck[1] or 1)
	
	-- Add new features and mark existing ones as seen.
	for i = 1, #visibleFeatures do
		local featureID = visibleFeatures[i]
		if handledFeatureMap[featureID] then
			handledFeatureCheck[handledFeatureMap[featureID]] = newCheck
		else
			AddFeature(featureID)
		end
	end
	
	-- Remove features that don't appear in the list of visible features.
	local i = 1
	while i <= #handledFeatureCheck do
		if handledFeatureCheck[i] ~= newCheck then
			local featureID = handledFeatureList[i]
			if handledFeatureApiIDs[featureID] then
				WG.StopHighlightUnitGL4(handledFeatureApiIDs[featureID])
			end
			
			handledFeatureCheck[i] = handledFeatureCheck[#handledFeatureCheck]
			handledFeatureList[i] = handledFeatureList[#handledFeatureList]
			handledFeatureMap[handledFeatureList[i]] = i
			
			handledFeatureCheck[#handledFeatureCheck] = nil
			handledFeatureList[#handledFeatureList] = nil
			handledFeatureMap[featureID] = nil
			handledFeatureApiIDs[featureID] = nil
		else
			i = i + 1
		end
	end
end

function widget:Update()
	if firstUpdate then
		firstUpdate = false
		if not BAR_COMPAT then
			Spring.Echo("Using gl3 reclaim highlight) due to 104.")
			Spring.SendCommands{"luaui enablewidget MetalFeatures GL3 (old)"}
		else
			Spring.SendCommands{"luaui disablewidget MetalFeatures GL3 (old)"}
		end
	end
	if not BAR_COMPAT then
		return
	end
	if Spring.IsGUIHidden() then
		if enableCondOld then
			Spring.SendCommands("luarules metal_highlight 0")
			enableCondOld = false
		end
		return
	end

	local activeCurrentCmd = spGetActiveCommand()
	if currCmd ~= activeCurrentCmd then
		currCmd = activeCurrentCmd --update active command
		local activeCmdDesc = spGetActiveCmdDesc(currCmd)
		highlight = (activeCmdDesc and (activeCmdDesc.name == "Reclaim" or activeCmdDesc.name == "Resurrect"))
	end

	-- Minimum Metal Setting should not interfere with reclaim and area reclaim
	local minMetalShownNew
	if highlight then
		minMetalShownNew = 1
	else
		minMetalShownNew = options.minmetal.value
	end

	local pregame = (spGetGameFrame() < 1)

-- ways to bypass heavy resource load in economy overlay
	local enableCondNew =
		(pregame and options.pregamehighlight.value) or highlight
		or (options.showhighlight.value == 'always')
		or (options.showhighlight.value == 'withecon' and WG.showeco)
		or (options.showhighlight.value == "constructors" and conSelected)
		or (options.showhighlight.value == 'conorecon' and (conSelected or WG.showeco))
		or (options.showhighlight.value == 'conandecon' and (conSelected and WG.showeco))

	if Spring.GetConfigInt("ForceDisableShaders") == 1 then
		enableCondOld = false
		return
	end

	if enableCondNew and minMetalShownOld ~= minMetalShownNew then
		minMetalShownOld = minMetalShownNew
		if Script.LuaRules.SetWreckMetalThreshold then
			Script.LuaRules.SetWreckMetalThreshold(minMetalShownNew)
		end
	end
	
	Spring.Echo("enableCondNew", enableCondNew)
	if enableCondNew ~= enableCondOld then
		enableCondOld = enableCondNew
		if enableCondNew then
			local visibleFeatures = (ALL_FEATURES and Spring.GetAllFeatures()) or Spring.GetVisibleFeatures(-1, FEATURE_RADIUS, false, false)
			handledFeatureList = {}
			handledFeatureMap = {}
			handledFeatureCheck = {}
			handledFeatureApiIDs = {}
			for i = 1, #visibleFeatures do
				--Spring.Utilities.FeatureEcho(visibleFeatures[i], i)
				AddFeature(visibleFeatures[i])
			end
		else
			for i = 1, #handledFeatureList do
				WG.StopHighlightUnitGL4(handledFeatureApiIDs[handledFeatureList[i]])
			end
			handledFeatureList = false
			handledFeatureMap = false
			handledFeatureCheck = false
			handledFeatureApiIDs = false
		end
	end
	
	UpdateFeatureVisibility()
end

function widget:SelectionChanged(units)
	if not BAR_COMPAT then
		return
	end
	if (WG.selectionEntirelyCons) then
		conSelected = true
	else
		conSelected = false
	end
end
