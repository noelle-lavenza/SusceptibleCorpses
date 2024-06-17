-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

require "Susceptible/SusceptibleTrait"

susceptibleCorpses = susceptibleCorpses or {}
-- we keep a reference to the original method so as to not break with future mod updates
susceptibleCorpses.oldCalculateThreat = susceptibleCorpses.oldCalculateThreat or SusceptibleMod.calculateThreat

-- some of this code is reused from the base mod
SusceptibleMod.calculateThreat = function (player)
	-- start reused code. I hate that this is necessary but it's not exposed any other way
	-- maybe I can ask the mod author to make infection distance and multiplier parameters to calculateThreat
	local corpseInfectionDistance = SusceptibleMod.calculateInfectionDistance(player) / SandboxVars.SusceptibleCorpses.CorpseInfectionDistanceDivisor; -- corpses are less active and so spread the infection a shorter distance
	local isOutside = player:isOutside();

	local multiplier = 1;
	if player:getVehicle() then
		multiplier = SusceptibleMod.calculateVehicleInfectionMultiplier(player, player:getVehicle());
	end
	
	if multiplier == 0 then -- short-circuit without a base function call here
		return 0, 0;
	end
	-- end reused code
	local baseThreatLevel, baseParanoiaLevel = susceptibleCorpses.oldCalculateThreat(player) -- original function call
	-- i considered dividing them by multiplier, adding the new values, and re-multiplying
	-- but because the multiplier is always the same we can rely on the distributive property
	-- and just add our new threatLevel/paranoiaLevel * multiplier to the old values
	local threatLevel, paranoiaLevel = 0, 0;
	local playerSquare = player:getSquare();
	-- we never check across z-levels, so this can be simplified a bit
	local cell = getCell();
	local playerX, playerY, playerZ = playerSquare:getX(), playerSquare:getY(), playerSquare:getZ();
	local corpsesSquare, corpseDistance, squareCorpses, currentCorpse;
	local currentWorldAgeHours = getGameTime():getWorldAgeHours();
	local corpseInfectionThreat, maxCorpseAgeHours = SandboxVars.SusceptibleCorpses.CorpseInfectionThreat, SandboxVars.SusceptibleCorpses.MaxCorpseAgeHours;
	for dX = -corpseInfectionDistance, corpseInfectionDistance do
		for dY = -corpseInfectionDistance, corpseInfectionDistance do repeat -- repeat until true end allows us to use break as continue instead
			corpsesSquare = cell:getGridSquare(playerX+dX, playerY+dY, playerZ);
			if corpsesSquare == nil then
				break; -- continue
			end
			squareCorpses = corpsesSquare:getDeadBodys()
			for i = 0, squareCorpses:size() - 1 do repeat -- see above about break-as-continue
				currentCorpse = squareCorpses:get(i);
				-- deathTime is a private field so we have to use reflection
				-- last checked for:
				-- Build 41.78
				if susceptibleCorpses.deathTimeField == nil then
					for i = 0, getNumClassFields(currentCorpse) - 1 do
						local field = getClassField(currentCorpse, i);
						if tostring(field):find("deathTime$") then
							susceptibleCorpses.deathTimeField = field;
							break;
						end
					end
				end
				if currentWorldAgeHours > (getClassFieldVal(currentCorpse, susceptibleCorpses.deathTimeField) + maxCorpseAgeHours) then -- too old to be infectious
					break; -- continue
				end
				corpseDistance = player:DistTo(currentCorpse);
				if not susceptibleCorpses.corpseIsValid(player, currentCorpse, corpseDistance, isOutside) then
					break; -- continue
				end
				if not currentCorpse:isZombie() then
					paranoiaLevel = paranoiaLevel + corpseInfectionThreat;
				else
					if corpseDistance < 1 then
						threatLevel = threatLevel + corpseInfectionThreat;
					else
						threatLevel = threatLevel + (corpseInfectionThreat / (0.75 + corpseDistance * 0.25));
					end
				end
			until true end
		until true end
	end
	return baseThreatLevel + (threatLevel * multiplier), baseParanoiaLevel + (paranoiaLevel * multiplier);
end

-- Heavily adapted from SusceptibleMod.zombieIsValid
function susceptibleCorpses.corpseIsValid(player, corpse, distance, playerIsOutside)
	-- No infection across floors
	if player:getZ() ~= corpse:getZ() then
		return false;
	end
	
	-- Skeletons can't be infectious
	if corpse:isSkeleton() then
		return false;
	end

	-- Ignore if not in the same environment and more than 2 tiles away
	-- corpses are not characters and so don't have isOutside; we have to use IsoGridSquare:isOutside() instead
	local corpseSqr = corpse:getSquare();
	local outdoorMismatch = playerIsOutside ~= corpseSqr:isOutside();
	if outdoorMismatch and distance > 2 then
		return false;
	end

	-- Out of sight, out of mind
	-- we only check player->corpse because corpses cannot see!
	if not player:CanSee(corpse) then
		return false;
	end

	-- If we're both outside and see each other, don't bother with pathfinding
	if playerIsOutside and not outdoorMismatch then
		return true;
	end

	-- Dumb pathfind straight at the player
	local cell = getCell();
	local playerSqr = player:getSquare();
	local z = playerSqr:getZ();
	while playerSqr ~= nil and not playerSqr:equals(corpseSqr) do
		playerSqr = SusceptibleMod.stepTowardsTargetIfNotBlocked(cell, z, playerSqr, corpseSqr);
	end
	return playerSqr ~= nil; -- If we make it here and playerSqr is not nil, we found a straight path
end