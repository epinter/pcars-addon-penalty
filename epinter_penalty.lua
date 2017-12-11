--[[
Penalty Addon for Project Cars Dedicated Server

This addon monitors players impact and gives penalty points to them. When the player reach an Warning level,
the server sends a message through chat. The player is kicked when he reaches the Kick level. Each lap a player
completes a lap without crash, the penalty points are decreased. The same happens when the player crosses the line in P1.

Copyright (C) 2017  Emerson Pinter <dev@pinter.com.br>

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 3 of the License, or
   (at your option) any later version.
   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.
   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software Foundation,
   Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA

--]]

local revision=0
local major,minor=GetAddonVersion()
local VERSION=string.format("%d.%d.%d",major,minor,revision)

local addon_storage = ...
local config = addon_storage.config

local to_kick = {}
local lastAccident = {}
local lastPenaltyLap = {}
local playerPoints = {}
local cutTrackStartRacePos = {}
local scheduled_sends_motd = {}
local penaltyDelay = 3
local kickDelay = 3
local logTag="PENALTYADDON: "
local logPrioDebug = "DEBUG"
local logPrioInfo = "INFO"
local logPrioError = "ERROR"

local enableRaceStartPenalty = config.enableRaceStartPenalty
local enableCutTrackPenalty = config.enableCutTrackPenalty
local pointsPerHit = config.pointsPerHit
local pointsPerCut = config.pointsPerCut
local pointsPerLapLead = config.pointsPerLapLead
local pointsPerLapClean = config.pointsPerLapClean
local pointsWarn = config.pointsWarn
local pointsKick = config.pointsKick
local pointsPerHitHost = config.pointsPerHitHost
local raceOnly = config.raceOnly
local tempBanTime = config.tempBanTime
local raceStartDelay = config.raceStartDelay
local minCollisionMagnitude = config.minCollisionMagnitude

local function penalty_getlogprefix(priority)
	return (os.date("[%Y-%m-%d %H:%M:%S] ")..(priority..": ")..logTag)
end

local function penalty_log( msg, priority )
	if not priority or string.len(priority) == 0 then
		priority = logPrioInfo
	end
	if (config.debug == 1 and priority == logPrioDebug) or priority ~= logPrioDebug then
		print(penalty_getlogprefix(priority)..msg)
	end
end

local function penalty_dump( table, logpriority )
	if table == nil then
		return
	end
	if not logpriority or string.len(logpriority) == 0 then
		logpriority = logPrioDebug
	end
	if (config.debug == 1 and logpriority == logPrioDebug) or logpriority ~= logPrioDebug then
		dump(table, penalty_getlogprefix(logpriority).."    ")
	end
end

local function penalty_sendChatToAll( msg )
	penalty_log(msg)
	SendChatToAll(msg)
end

local function penalty_sendChatToMember( refid, msg )
	penalty_log(msg)
	SendChatToMember(refid,msg)
end

local function penalty_isSteamUserWhitelisted ( steamId )
	for k,v in pairs ( config.whitelist ) do
		if (""..v) == steamId then
			return true
		end
	end
	return false
end

local function penalty_send_motd_to( refid )
        local send_time = GetServerUptimeMs() + 2000
        if refid then
                scheduled_sends_motd[ refid ] = send_time
        else
                for k,_ in pairs( session.members ) do
                        scheduled_sends_motd[ k ] = send_time
                end
        end
end

local function penalty_send_motd_now( refid )
	SendChatToMember(refid,"")
	SendChatToMember(refid,"*** Penalty addon, version "..VERSION.." by EPinter * https://github.com/epinter/pcars-addon-penalty ***")
	SendChatToMember(refid,"  Each impact: +"..pointsPerHit.." points")
	if enableCutTrackPenalty == 1 then
		SendChatToMember(refid,"  Cutting track: +"..pointsPerCut.." points")
	end
	if enableRaceStartPenalty == 1 then
		SendChatToMember(refid,"  First impact on race start: +"..(pointsPerHit * 2).." points")
	end
	SendChatToMember(refid,"  Each clean lap: -"..pointsPerLapClean.." points")
	SendChatToMember(refid,"  Each lap as P1: -"..pointsPerLapLead.." points")
	SendChatToMember(refid,"*** WARNING at "..pointsWarn.."pts and KICK at "..pointsKick.."pts")
	SendChatToMember(refid,"*** Penalty points are earned every time you hit other players, clean laps reduces your penalty ***")
	SendChatToMember(refid,"")
end

local function penalty_tick()
	local now = GetServerUptimeMs()
	for refId, time in pairs( to_kick ) do
		if now >= time then
			penalty_log( "Kicking " .. refId )
			KickMember( refId, tempBanTime )
			to_kick[ refId ] = nil
		end
	end
        for refid,time in pairs( scheduled_sends_motd ) do
                if now >= time then
                        penalty_send_motd_now( refid )
                        scheduled_sends_motd[ refid ] = nil
                end
        end
end

local function handler_penalty_participant_lap (event)
		local participantid = event.participantid
		local participant = session.participants[ participantid ]
		penalty_log( "**** Participant " .. session.members[ participant.attributes.RefId ].name .. " (" .. participantid .. ") lap:", logPrioDebug)
		if participant.attributes.RacePosition then
			local participantPos = participant.attributes.RacePosition
			if playerPoints[ participantid ] and playerPoints[ participantid ] > 0 then
				if ( playerPoints[ participantid ] - pointsPerLapLead ) >= 0 and participantPos == 1 then
					playerPoints[ participantid ] = playerPoints[ participantid ] - pointsPerLapLead
				end
				if lastPenaltyLap[ participantid ] and ( playerPoints[ participantid ] - pointsPerLapClean ) >= 0 and participant.attributes.CurrentLap >= 1 and participant.attributes.CurrentLap >  lastPenaltyLap[ participantid ] then
					playerPoints[ participantid ] = playerPoints[ participantid ] - pointsPerLapClean
				end
				SendChatToMember(participant.attributes.RefId,"YOUR points: ".. playerPoints[ participantid ])
			end
		end

		penalty_dump( event.attributes )
		penalty_log("************************", logPrioDebug)
end

local function handler_penalty_session_statechanged(event)
	penalty_log( "Session state changed from " .. event.attributes.PreviousState .. " to " .. event.attributes.NewState, logPrioDebug )
	if ( event.attributes.PreviousState ~= "None" ) and ( event.attributes.NewState == "Lobby" ) then
		penalty_send_motd_to()
	end
	if ( event.attributes.PreviousState ~= "None" ) and ( event.attributes.NewState == "Race" ) then
		lastAccident = {}
		lastPenaltyLap = {}
		playerPoints = {}
	end
end

local function handler_penalty_participant_cuttrackstart(event)
	local participantid = event.participantid
	local participant = session.participants[ participantid ]
	if enableCutTrackPenalty == 1 and session.attributes.SessionStage == "Race1" and session.attributes.SessionState == "Race" then
		cutTrackStartRacePos[participantid] = participant.attributes.RacePosition
		penalty_log("CutTrackStart ".. session.members[participant.attributes.RefId ].name..": Lap "..event.attributes.Lap..", RacePosition "..participant.attributes.RacePosition, logPrioDebug)
		penalty_dump(event)
	end
end

local function handler_penalty_participant_cuttrackend(event)
	local participantid = event.participantid
	local participant = session.participants[ participantid ]
	if enableCutTrackPenalty == 1
			and session.attributes.SessionStage == "Race1" and session.attributes.SessionState == "Race"
			and cutTrackStartRacePos[participantid] and participant.attributes.RacePosition < cutTrackStartRacePos[participantid] then
		penalty_log("CutTrackEnd ".. session.members[ participant.attributes.RefId ].name..", RacePosition "..participant.attributes.RacePosition, logPrioDebug)
		penalty_dump(event)
		cutTrackStartRacePos[participantid] = nil
		if not playerPoints[ participantid ] then
			playerPoints[ participantid ] = 0
		end
		playerPoints[ participantid ] = playerPoints[ participantid ] + pointsPerCut
		penalty_sendChatToAll("Penalty: ".. session.members[ participant.attributes.RefId ].name .. " +" .. pointsPerCut.." pts")
	end
end

local function handler_penalty_participant_impact(event)
	local participantid = event.participantid
	local participant = session.participants[ participantid ]
	local otherparticipantid = event.attributes.OtherParticipantId
	local otherparticipant = session.participants[ otherparticipantid ]
	local collisionmagnitude = event.attributes.CollisionMagnitude
	if ((raceOnly==1 and session.attributes.SessionStage == "Race1") or raceOnly==0) and session.attributes.SessionState == "Race" then
		local now = GetServerUptimeMs()

		penalty_log("***** Impact Event *****", logPrioDebug)
		penalty_dump( event )

		delay = GetServerUptimeMs() - (penaltyDelay * 1000)
		if participantid >= 0 and otherparticipantid >= 0 and participant.attributes.IsPlayer == 1 and otherparticipant.attributes.IsPlayer == 1 then
			if not playerPoints[ participantid ] then
				playerPoints[ participantid ] = 0
			end
			if not playerPoints[ otherparticipantid ] then
				playerPoints[ otherparticipantid ] = 0
			end

			penalty_log( "Participant " .. session.members[ participant.attributes.RefId ].name .. " (" .. participantid .. ") impact:" , logPrioDebug)

			local participantPos
			local otherParticipantPos

			if participant.attributes.RacePosition then
				participantPos = participant.attributes.RacePosition
				otherParticipantPos = otherparticipant.attributes.RacePosition
			else
				participantPos = participant.attributes.GridPosition
				otherParticipantPos = otherparticipant.attributes.GridPosition
			end

			local firstCrash = 0
			if ( not lastAccident[ participantid ]
					or ( lastAccident [ participantid ] and lastAccident [ participantid ] < delay )
					) and participantPos > otherParticipantPos
					and participant.attributes.CurrentLap <= session.attributes.RaceLength 
					and collisionmagnitude >= minCollisionMagnitude then
				local next = next
				if next(lastAccident) == nil
						and enableRaceStartPenalty == 1
						and session.attributes.SessionStage == "Race1"
						and (	(participant.attributes.Sector1Time <= (raceStartDelay * 1000) and participant.attributes.Sector2Time == 0 and participant.attributes.Sector3Time == 0) or
							(participant.attributes.Sector3Time <= (raceStartDelay * 1000) and participant.attributes.Sector2Time == 0 and participant.attributes.Sector1Time == 0) )
						and participant.attributes.CurrentLap == 1 then
					firstCrash = 1
				end
				lastAccident[ participantid ] = now
				lastAccident[ otherparticipantid ] = now
				lastPenaltyLap[ participantid ] = participant.attributes.CurrentLap

				local penaltyPoints = 0
				if not penalty_isSteamUserWhitelisted(session.members[ participant.attributes.RefId ].steamid) then
					if session.members[ participant.attributes.RefId ].host then
						penaltyPoints = pointsPerHitHost
					else
						penaltyPoints = pointsPerHit
					end
				end
				if firstCrash == 1 then
					penaltyPoints = penaltyPoints * 2
				end
				playerPoints[ participantid ] = playerPoints[ participantid ] + penaltyPoints
				penalty_sendChatToAll("Penalty: ".. session.members[ participant.attributes.RefId ].name .. " +" .. penaltyPoints.." pts")

				if playerPoints[ participantid ] >= pointsKick then
					penalty_sendChatToAll("PENALTY KICK ".. session.members[ participant.attributes.RefId ].name ..", in "..kickDelay.."s")
					to_kick [ participant.attributes.RefId ] =  now + (kickDelay*1000)
				elseif  playerPoints[ participantid ] >= pointsWarn then
					penalty_sendChatToMember(participant.attributes.RefId, "WARN ".. session.members[ participant.attributes.RefId ].name .. " " .. playerPoints[ participantid ].."pts /"..pointsKick)
				end
			end
			if ( not lastAccident[ otherparticipantid ]
					or ( lastAccident [ otherparticipantid ] and lastAccident [ otherparticipantid ] < delay )
					) and otherParticipantPos > participantPos 
					and otherparticipant.attributes.CurrentLap <= session.attributes.RaceLength
					and collisionmagnitude >= minCollisionMagnitude then
				local next = next
				local firstCrash = 0
				if next(lastAccident) == nil
						and enableRaceStartPenalty == 1
						and session.attributes.SessionStage == "Race1"
						and (	(otherparticipant.attributes.Sector1Time <= (raceStartDelay * 1000) and otherparticipant.attributes.Sector2Time == 0 and otherparticipant.attributes.Sector3Time == 0) or
							(otherparticipant.attributes.Sector3Time <= (raceStartDelay * 1000) and otherparticipant.attributes.Sector2Time == 0 and otherparticipant.attributes.Sector1Time == 0) )
						and otherparticipant.attributes.CurrentLap == 1 then
					firstCrash = 1
				end
				lastAccident[ otherparticipantid ] = now
				lastAccident[ participantid ] = now
				lastPenaltyLap[ otherparticipantid ] = participant.attributes.CurrentLap

				local penaltyPoints = 0
				if not penalty_isSteamUserWhitelisted(session.members[ otherparticipant.attributes.RefId ].steamid) then
					if session.members[ otherparticipant.attributes.RefId ].host then
						penaltyPoints = pointsPerHitHost
					else
						penaltyPoints = pointsPerHit
					end
				end
				if firstCrash == 1 then
					penaltyPoints = penaltyPoints * 2
				end
				playerPoints[ otherparticipantid ] = playerPoints[ otherparticipantid ] + penaltyPoints
				penalty_sendChatToAll("Penalty: ".. session.members[ otherparticipant.attributes.RefId ].name .. " +" .. penaltyPoints.." pts")

				if playerPoints[ otherparticipantid ] >= pointsKick then
					penalty_sendChatToMember(otherparticipant.attributes.RefId, "KICK ".. session.members[ otherparticipant.attributes.RefId ].name ..", in "..kickDelay.."s")
					to_kick [ otherparticipant.attributes.RefId ] =  now + (kickDelay*1000)
				elseif  playerPoints[ otherparticipantid ] >= pointsWarn then
					penalty_sendChatToMember(otherparticipant.attributes.RefId, "WARN ".. session.members[ otherparticipant.attributes.RefId ].name .. " " .. playerPoints[ otherparticipantid ].."pts /"..pointsKick)
				end
			end
		end
		penalty_dump(participant)
		penalty_dump(otherparticipant)
		penalty_log("************************", logPrioDebug)
	end
end

local function handler_penalty_serverstatechanged(oldState,newState)
	penalty_log( "Server state changed from " .. oldState .. " to " .. newState, logPrioDebug )
	penalty_dump(server)
	if oldState == "Starting" and newState == "Running" then
		penalty_log("Penalty addon v"..VERSION..", config loaded:")
		penalty_log("  pointsPerHit = " .. pointsPerHit)
		penalty_log("  pointsPerCut = " .. pointsPerCut)
		penalty_log("  pointsPerHitHost = " .. pointsPerHitHost)
		penalty_log("  pointsPerLapLead = " .. pointsPerLapLead)
		penalty_log("  pointsPerLapClean = " .. pointsPerLapClean)
		penalty_log("  pointsWarn = " .. pointsWarn)
		penalty_log("  pointsKick = " .. pointsKick)
		penalty_log("  penaltyDelay = " .. penaltyDelay)
		penalty_log("  kickDelay = " .. kickDelay)
		penalty_log("  raceOnly = " .. raceOnly)
		penalty_log("  raceStartDelay = " .. raceStartDelay)
		penalty_log("  enableRaceStartPenalty = " .. enableRaceStartPenalty)
		penalty_log("  enableCutTrackPenalty = " .. enableCutTrackPenalty)
		penalty_log("  tempBanTime = " .. tempBanTime)
		penalty_log("  minCollisionMagnitude = " .. minCollisionMagnitude)
		penalty_log("  debug = " .. config.debug)
		for k,v in pairs ( config.whitelist ) do
			penalty_log("  steamid whitelisted: "..v)
		end
	end
end

local function handler_penalty_memberstatechanged(refid,new_state)
	if new_state == "Connected" then
		penalty_send_motd_to( refid )
	end
end

local function handler_penalty_participantcreated(participantId)
	lastAccident[ participantId ] = nil
	lastPenaltyLap[ participantId ] = nil
	playerPoints[ participantId ] = nil
end

local function handler_penalty_participantremoved(participantId)
	lastAccident[ participantId ] = nil
	lastPenaltyLap[ participantId ] = nil
	playerPoints[ participantId ] = nil
end

local function callback_penalty( callback, ... )
	local now = GetServerUptimeMs()

	if callback == Callback.Tick then
		penalty_tick()
		return
	end

	if not raceStartDelay or not minCollisionMagnitude or not tempBanTime or not pointsPerHit or not pointsPerHitHost or not pointsPerCut or not pointsPerLapLead or not pointsPerLapClean or not pointsWarn or not pointsKick or not raceOnly then
		do return end
	end

	if callback == Callback.EventLogged then
		local event = ...

		if ( event.type == "Session" ) and ( event.name == "StateChanged" ) then
			handler_penalty_session_statechanged(event)
		end
		if event.type == "Participant" and event.name == "Lap" then
			handler_penalty_participant_lap(event)
		elseif event.type == "Participant" and event.name == "CutTrackStart" then
			handler_penalty_participant_cuttrackstart(event)
		elseif event.type == "Participant" and event.name == "CutTrackEnd" then
			handler_penalty_participant_cuttrackend(event)
		elseif event.type == "Participant" and event.name == "Impact" then
			handler_penalty_participant_impact(event)
		end
	elseif callback == Callback.ServerStateChanged then
		local oldState, newState = ...
		handler_penalty_serverstatechanged(oldState, newState)
	elseif callback == Callback.MemberStateChanged then
		local refid, _, new_state = ...
		handler_penalty_memberstatechanged(refid,new_state)
	elseif callback == Callback.ParticipantCreated then
		local participantId = ...
		handler_penalty_participantcreated(participantId)
	elseif callback == Callback.ParticipantRemoved then
		local participantId = ...
		handler_penalty_participantremoved(participantId)
	end
end

if type( config.whitelist ) ~= "table" then config.whitelist = {} end

if enableRaceStartPenalty == nil or enableCutTrackPenalty == nil or not raceStartDelay or not minCollisionMagnitude or not tempBanTime or not pointsPerHit or not pointsPerHitHost or not pointsPerCut or not pointsPerLapLead or not pointsPerLapClean or not pointsWarn or not pointsKick or not raceOnly then
	penalty_log("Invalid config, addon disabled. Remove or fix the config file (in lua_config directory).", logPrioError)
end

RegisterCallback( callback_penalty )
EnableCallback( Callback.Tick )
EnableCallback( Callback.ServerStateChanged )
EnableCallback( Callback.MemberStateChanged )
EnableCallback( Callback.ParticipantCreated )
EnableCallback( Callback.ParticipantRemoved )
EnableCallback( Callback.EventLogged )

-- EOF --
