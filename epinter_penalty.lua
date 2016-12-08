--[[
Penalty Addon for Project Cars Dedicated Server

This addon monitors players impact and gives penalty points to them. When the player reach an Warning level,
the server sends a message through chat. The player is kicked when he reaches the Kick level. Each lap a player
completes a lap without crash, the penalty points are decreased. The same happens when the player crosses the line in P1.

Copyright (C) 2016  Emerson Pinter <dev@pinter.com.br>

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

local VERSION='0.5.3'

local addon_storage = ...
local config = addon_storage.config

local first_event_offset = 0
local to_kick = {}
local lastAccident = {}
local lastPenaltyTime = {}
local lastPenaltyLap = {}
local playerPoints = {}
local scheduled_sends_motd = {}
local penaltyDelay = 3
local kickDelay = 3
local raceStartDelay = 4
local logPrefix="PENALTYADDON: "

local pointsPerHit = config.pointsPerHit
local pointsPerCut = config.pointsPerCut
local pointsPerLapLead = config.pointsPerLapLead
local pointsPerLapClean = config.pointsPerLapClean
local pointsWarn = config.pointsWarn
local pointsKick = config.pointsKick
local pointsPerHitHost = config.pointsPerHitHost
local raceOnly = config.raceOnly
if type( config.whitelist ) ~= "table" then config.whitelist = {} end

local function penalty_log( msg )
	print(logPrefix .. msg)
end

local function penalty_sendChatToAll( msg )
	penalty_log(msg)
	SendChatToAll(msg)
end

local function penalty_isSteamUserWhitelisted ( steamId )
	for k,v in pairs ( config.whitelist ) do
		if (""..v) == steamId then
			return true
		end
	end
	return false
end

if not pointsPerHit or not pointsPerHitHost or not pointsPerCut or not pointsPerLapLead or not pointsPerLapClean or not pointsWarn or not pointsKick or not raceOnly then
	penalty_log("Invalid config, addon disabled")
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
	SendChatToMember(refid,"*** Penalty addon, BETA version "..VERSION.." by EPinter ***")
--[[
	SendChatToMember(refid,"*** https://github.com/epinter/pcars-addon-penalty ***")
--]]
	SendChatToMember(refid,"Points per hit: "..pointsPerHit)
	SendChatToMember(refid,"Points for cut track: "..pointsPerCut)
--	SendChatToMember(refid,"Points for crash on race start: "..(pointsPerHit * 2).."pts")
	SendChatToMember(refid,"Warning: "..pointsWarn.."pts")
	SendChatToMember(refid,"Kick: "..pointsKick.."pts")
	SendChatToMember(refid,"*** Penalty points are earned every time you hit other players ***")
	SendChatToMember(refid,"*** Clean laps reduces penalty points, each lap in P1 too. ***")
	SendChatToMember(refid,"")
end


local function penalty_remember_event_offset()
	local log_info = GetEventLogInfo()
	first_event_offset = log_info.first + log_info.count - 1
	penalty_log( "Session created, first log event index = " .. first_event_offset )
end

local function penalty_log_events()
	penalty_log( "Dumping log for session, starting at " .. first_event_offset )
	local log = GetEventLogRange( first_event_offset )
	for _,event in ipairs( log.events ) do
		penalty_log( "Event: " )
		dump( event, "  " )
	end
	first_event_offset = log.first + log.count
end

local function penalty_tick()
	local now = GetServerUptimeMs()
	for refId, time in pairs( to_kick ) do
		if now >= time then
			penalty_log( "Kicking " .. refId )
			KickMember( refId, 120 )
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

local function callback_penalty( callback, ... )
	local now = GetServerUptimeMs()

	if callback == Callback.Tick then
		penalty_tick()
		return
	end

	if not pointsPerHit or not pointsPerHitHost or not pointsPerCut or not pointsPerLapLead or not pointsPerLapClean or not pointsWarn or not pointsKick or not raceOnly then
		do return end
	end

	if callback == Callback.EventLogged then
		local event = ...
		if event.type == "Participant" and event.name == "Lap" then
			participantid = event.participantid
			participant = session.participants[ participantid ]
			penalty_log( "**** Participant " .. session.members[ participant.attributes.RefId ].name .. " (" .. participantid .. ") lap:" )
			if participant.attributes.RacePosition then
				local participantPos = participant.attributes.RacePosition
				if playerPoints[ participantid ] and playerPoints[ participantid ] > 0 then
					if ( playerPoints[ participantid ] - pointsPerLapLead ) >= 0 and participantPos == 1 then
						playerPoints[ participantid ] = playerPoints[ participantid ] - pointsPerLapLead
					end
					if ( playerPoints[ participantid ] - pointsPerLapClean ) >= 0 and participant.attributes.CurrentLap >= 1 and participant.attributes.CurrentLap >  lastPenaltyLap[ participantid ] then
						playerPoints[ participantid ] = playerPoints[ participantid ] - pointsPerLapClean
					end
					SendChatToMember(participant.attributes.RefId,"YOUR points: ".. playerPoints[ participantid ])
				end
			end

			dump( event.attributes )
			penalty_log("************************")
		end
		-- Participant cutTrackEnd
--[[
  index: 608
  participantid: 3
  refid: 17859
  time: 1480777461
  attributes:
    PenaltyThreshold: 653
    SkippedTime: 2266
    ElapsedTime: 1737
    PenaltyValue: 3525
    PlaceGain: 1
  type: Participant
  name: CutTrackEnd
--]]
		if event.type == "Participant" and event.name == "CutTrackEnd" and (raceOnly==1 and session.attributes.SessionStage == "Race1") and session.attributes.SessionState == "Race" then
			if not playerPoints[ participantid ] then
				playerPoints[ participantid ] = 0
			end
			if event.attributes.PlaceGain > 0 then
				playerPoints[ participantid ] = playerPoints[ participantid ] + pointsPerCut
				penalty_sendChatToAll("Penalty: ".. session.members[ participant.attributes.RefId ].name .. " +" .. pointsPerCut.." pts")
			end
		
		end

		-- Participant impact
		if event.type == "Participant" and event.name == "Impact" and (raceOnly==1 and session.attributes.SessionStage == "Race1") and session.attributes.SessionState == "Race" then
			local now = GetServerUptimeMs()
			penalty_log("***** Impact Event *****")
			dump( event )
			delay = GetServerUptimeMs() - (penaltyDelay * 1000)
			participantid = event.participantid
			otherparticipantid = event.attributes.OtherParticipantId
			local participant = session.participants[ participantid ]
			local otherparticipant = session.participants[ otherparticipantid ]
			if participantid >= 0 and otherparticipantid >= 0 and participant.attributes.IsPlayer == 1 and otherparticipant.attributes.IsPlayer == 1 then
				if not playerPoints[ participantid ] then
					playerPoints[ participantid ] = 0
				end
				if not playerPoints[ otherparticipantid ] then
					playerPoints[ otherparticipantid ] = 0
				end

				penalty_log( "Participant " .. session.members[ participant.attributes.RefId ].name .. " (" .. participantid .. ") impact:" )

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
						) and participantPos > otherParticipantPos then
					local next = next
					if next(lastAccident) == nil
							and session.attributes.SessionStage == "Race1"
							and participant.attributes.Sector1Time <= (raceStartDelay * 1000)
							and participant.attributes.Sector2Time == 0
							and participant.attributes.Sector3Time == 0
							and participant.attributes.CurrentLap == 1 then
						firstCrash = 1
					end
					lastAccident[ participantid ] = now
					lastAccident[ otherparticipantid ] = now
					lastPenaltyTime[ participantid ] = now
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
						penalty_sendChatToAll("KICK ".. session.members[ participant.attributes.RefId ].name ..", in "..kickDelay.."s")
						to_kick [ participant.attributes.RefId ] =  now + (kickDelay*1000)
					elseif  playerPoints[ participantid ] >= pointsWarn then
						penalty_sendChatToAll("WARN ".. session.members[ participant.attributes.RefId ].name .. " " .. playerPoints[ participantid ].."pts /"..pointsKick)
					end
				end
				if ( not lastAccident[ otherparticipantid ]
						or ( lastAccident [ otherparticipantid ] and lastAccident [ otherparticipantid ] < delay )
						) and otherParticipantPos > participantPos  then
					local next = next
					local firstCrash = 0
					if next(lastAccident) == nil
							and session.attributes.SessionStage == "Race1"
							and otherparticipant.attributes.Sector1Time <= (raceStartDelay * 1000)
							and otherparticipant.attributes.Sector2Time == 0
							and otherparticipant.attributes.Sector3Time == 0
							and otherparticipant.attributes.CurrentLap == 1 then
						firstCrash = 1
					end
					lastAccident[ otherparticipantid ] = now
					lastAccident[ participantid ] = now
					lastPenaltyTime[ otherparticipantid ] = now
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
						penalty_sendChatToAll("KICK ".. session.members[ otherparticipant.attributes.RefId ].name ..", in "..kickDelay.."s")
						to_kick [ otherparticipant.attributes.RefId ] =  now + (kickDelay*1000)
					elseif  playerPoints[ otherparticipantid ] >= pointsWarn then
						penalty_sendChatToAll("WARN ".. session.members[ otherparticipant.attributes.RefId ].name .. " " .. playerPoints[ otherparticipantid ].."pts /"..pointsKick)
					end
				end
			end
			dump(participant)
			dump(otherparticipant)
			penalty_log("************************")
		end
	end

	if callback == Callback.ParticipantAttributesChanged then
--		local participantid, attrlist = ...
--		local participant = session.participants[ participantid ]
--		local attrset = table.list_to_set( attrlist )
--		if attrset.CurrentLap then
--			penalty_log( "Participant " .. participant.attributes.Name .. " (" .. participantid .. ") entering lap " .. participant.attributes.CurrentLap )
--		end
--		if attrset.FastestLapTime then
--			penalty_log( "Participant " .. participant.attributes.Name .. " (" .. participantid .. ") new fastest lap time: " .. participant.attributes.FastestLapTime )
--		end
--		if attrset.RacePosition then
--			penalty_log( "Participant " .. participant.attributes.Name .. " (" .. participantid .. ") new race position: " .. participant.attributes.RacePosition )
--		end
	end

	-- Dump events for whole session when it ends.
	if callback == Callback.EventLogged then
		local event = ...
		if ( event.type == "Session" ) and ( event.name == "SessionCreated" ) then
			penalty_remember_event_offset()
		elseif ( event.type == "Session" ) and ( event.name == "SessionDestroyed" ) then
			penalty_log_events()
		elseif ( event.type == "Session" ) and ( event.name == "StateChanged" ) then
			penalty_log( "Session state changed from " .. event.attributes.PreviousState .. " to " .. event.attributes.NewState )
			if ( event.attributes.PreviousState ~= "None" ) and ( event.attributes.NewState == "Lobby" ) then
				penalty_send_motd_to()
			end
			if ( event.attributes.PreviousState ~= "None" ) and ( event.attributes.NewState == "Race" ) then
				lastAccident = {}
				lastPenaltyTime = {}
				lastPenaltyLap = {}
				playerPoints = {}
			end
		end
	end

	-- Testing/loggin.
--	penalty_log( "Callback fired - " .. value_to_callback[ callback ] )
	if callback == Callback.ServerStateChanged then
		local oldState, newState = ...
		penalty_log( "Server state changed from " .. oldState .. " to " .. newState )
		if newState == "Running" then
			penalty_log("Penalty addon config loaded:")
			penalty_log("  pointsPerHit = " .. pointsPerHit)
			penalty_log("  pointsPerCut = " .. pointsPerCut)
			penalty_log("  pointsPerHitHost = " .. pointsPerHitHost)
			penalty_log("  pointsPerLapLead = " .. pointsPerLapLead)
			penalty_log("  pointsPerLapClean = " .. pointsPerLapClean)
			penalty_log("  pointsWarn = " .. pointsWarn)
			penalty_log("  pointsKick = " .. pointsKick)
			penalty_log("  raceOnly = " .. raceOnly)
			penalty_log("  penaltyDelay = " .. penaltyDelay)
			penalty_log("  kickDelay = " .. kickDelay)
			for k,v in pairs ( config.whitelist ) do
				penalty_log("  steamid whitelisted: "..v)
			end
		end
--		--penalty_log( "Server: " ); dump( server, "  " )
--		--penalty_log( "Session: " ); dump( session, "  " )
	elseif callback == Callback.SessionManagerStateChanged then
		local oldState, newState = ...
		penalty_log( "Session manager state changed from " .. oldState .. " to " .. newState )
		--dump( session )
	elseif callback == Callback.SessionAttributesChanged then
--		local dirtyList = ...
--		penalty_log( "Changed attributes: " )
--		for _, name in ipairs( dirtyList ) do
--			penalty_log( "- " .. name .. " = " .. tostring( session.attributes[ name ] ) )
--		end
--		--dump( session )
	elseif callback == Callback.MemberJoined then
--		local refId = ...
--		local name = session.members[ refId ].name;
--		penalty_log( "Member " .. name .. " (" .. refId ..") has joined" )
--		dump( session.members[ refId ], "  " )
	elseif callback == Callback.MemberStateChanged then
		local refid, _, new_state = ...
		if new_state == "Connected" then
			penalty_send_motd_to( refid )
		end
--		local refId, oldState, newState = ...
--		local name = session.members[ refId ].name;
--		penalty_log( "Member " .. name .. " (" .. refId ..") changed state from " .. oldState .. " to " .. newState )
	elseif callback == Callback.MemberAttributesChanged then
--		local refId, dirtyList = ...
--		local member = session.members[ refId ]
--		local name = member.name;
--		penalty_log( "Member " .. name .. " (" .. refId ..") changed attributes:" )
--		for _, name in ipairs( dirtyList ) do
--			penalty_log( "- " .. name .. " = " .. tostring( member.attributes[ name ] ) )
--		end
	elseif callback == Callback.HostMigrated then
--		local refId = ...
--		local name = session.members[ refId ].name;
--		penalty_log( "Host migrated to " .. name .. " (" .. refId ..")" )
	elseif callback == Callback.MemberLeft then
--		local refId = ...
--		local name = session.members[ refId ].name;
--		penalty_log( "Member " .. name .. " (" .. refId ..") has left" )
	elseif callback == Callback.ParticipantCreated then
		local participantId = ...
		lastAccident[ participantId ] = nil
		lastPenaltyTime[ participantId ] = nil
		lastPenaltyLap[ participantId ] = nil
		playerPoints[ participantId ] = nil
--		local participant = session.participants[ participantId ]
--		local owner = session.members[ participant.attributes.RefId ]
--		local ownerName = "unknown"
--		if owner then
--			ownerName = owner.name
--		end
--		penalty_log( "Participant " .. participantId .. " has been created, owned by member " .. ownerName )
--		dump( participant )
	elseif callback == Callback.ParticipantAttributesChanged then
--		local participantId, dirtyList = ...
--		local participant = session.participants[ participantId ]
--		penalty_log( "Participant " .. participantId .. " changed attributes:" )
--		for _, name in ipairs( dirtyList ) do
--			penalty_log( "- " .. name .. " = " .. tostring( participant.attributes[ name ] ) )
--		end
	elseif callback == Callback.ParticipantRemoved then
		local participantId = ...
		lastAccident[ participantId ] = nil
		lastPenaltyTime[ participantId ] = nil
		lastPenaltyLap[ participantId ] = nil
		playerPoints[ participantId ] = nil
--		local name = session.members[ refId ].name;
--		penalty_log( "Participant " .. participantId .. " has been removed" )
	elseif callback == Callback.EventLogged then
--		local event = ...
--		penalty_log( "Event: " )
--		dump( event, "  " )
	end
end

RegisterCallback( callback_penalty )
EnableCallback( Callback.Tick )
EnableCallback( Callback.ServerStateChanged )
EnableCallback( Callback.SessionManagerStateChanged )
EnableCallback( Callback.SessionAttributesChanged )
EnableCallback( Callback.NextSessionAttributesChanged )
EnableCallback( Callback.MemberJoined )
EnableCallback( Callback.MemberStateChanged )
EnableCallback( Callback.MemberAttributesChanged )
EnableCallback( Callback.HostMigrated )
EnableCallback( Callback.MemberLeft )
EnableCallback( Callback.ParticipantCreated )
EnableCallback( Callback.ParticipantAttributesChanged )
EnableCallback( Callback.ParticipantRemoved )
EnableCallback( Callback.EventLogged )

-- EOF --
