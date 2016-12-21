#Penalty Addon for [Project Cars Dedicated Server](http://forum.projectcarsgame.com/showthread.php?22370-Dedicated-Server-HowTo-(Work-in-Progress))
____________

Introduction
------------

This software is an **addon** for Project Cars game, it's written in **Lua** language and is installed directly in **Dedicated Server**. Its objective is to give opportunity to players have a fair and clean race, penalizing drivers responsible for collision. The penalty system is based on Penalty Points the players receive when a collision happens.

Penalty System
----------

The idea behind this addon is not kick every player that crashes during a race, but only those who are unfair or can't drive without collide. These are the rules:

* Every player starts with 0 penalty points. These points are increased when an impact happens. The car with the greater race position will receive the penalty, this means if you are in 9th and when you try to overtake the 8th and a collision happens, you will be considered the culprit and receive the penalty points.

* The points are given to a player every time an impact happens if the last impact was more than 3 seconds before. The host of the session receives a different number of points.

* When a player cuts track, he will receive penalty points if gained position while off-track.

* During the first 4 seconds of the race start, the first player to crash will receive penalty points doubled.

* On every clean lap (without impact) completed, the player will have its accumulated penalty points reduced.

* On every lap completed as P1, the player will have its accumulated penalty points reduced.

The server will send messages in chat with information about penalty points given, and a warning (WARN) when the player reaches the number of points configured. When the player reaches the points to be kicked, server will do it using a temp-ban (configurable time).

>  **Example**:
>  
> Considering the default configuration values, if the player collide during the race start (first 4 seconds) he will receive 24 points. If this player receive one more penalty, he will be kicked (default 33pts to kick). So, the player that received 24pts during racestart need to complete a full lap without impact to reduce its penalty by 4pts, and another full lap by more 4pts. This way, the player will have 16pts after 2 clean laps.

Default configuration
----------
The configuration is stored in **lua_config/epinter_penalty_config.json** (the file is auto generated when server starts first time with addon enabled). By default, the penalty system is configured with this parameters:

* Each impact:  +12 points
* Each impact by the host of the session:  +6 points
* Cutting track:  +8 points
* First impact on race start:  +24 points
* Each clean lap completed:  -4 points
* Each lap as P1: -6 points
* Warning: 24 points
* Kick: 33 points

>**Other configuration**:
>  
>```  
>//When 1, the penalty system will only work during the race, not practices or qualify
>
>    raceOnly: 1
>        
>//When 1, the first player to crash during race start will be penalized with 'pointsPerHit x 2'
>
>    enableRaceStartPenalty: 1
>       
>//When 1, the player will be penalized when he cuts track and gain position while offtrack
>
>    enableCutTrackPenalty: 1
>        
>//Time in seconds to keep a player banned after kick
>
>    tempBanTime: 60  
>```

Installation
----------
All the files must be inside the directory **lua/epinter_penalty/**. DON'T rename any files, or the addon won't work. The directory structure should be like this:
```
DedicatedServerCmd
readme.txt
steam_appid.txt
lua/
lua_config/
lua/epinter_penalty/
lua/epinter_penalty/epinter_penalty.json
lua/epinter_penalty/README.md
lua/epinter_penalty/epinter_penalty.lua
lua/epinter_penalty/epinter_penalty_default_config.json
``` 

With the files in the correct directory, the addon must be enabled in server.cfg:

```
luaApiAddons : [
    // Core server bootup scripts and helper functions. This will be always loaded first even if not specified here because it's an implicit dependency of all addons.
    "sms_base",
    // Automatic race setup rotation.
    "sms_rotate",
    // Sends greetings messages to joining members, optionally with race setup info, optionally also whenever returning back to lobby post-race.
    "sms_motd",
    // Tracks various stats on the server - server, session and player stats.
    "sms_stats",
    //Penalty
    "epinter_penalty",
]
```
The sms_base, sms_rotate,sms_motd and sms_stats are there by default, the line added to **luaApiAddons** is **"epinter_penalty",**

Limitations
----------

The addon receives events from the game using callbacks. These events have some information that permits us to store the points in memory and take an action when the player reaches a critical level of points. The only action the dedicated server has available is the KickMember. The KickMember is used here with a temp-ban parameter. There's no way to, for example, return a player to pit, reduce it's speed or apply a time penalty as the game does with a player cuts the track.

Known Issue
----------

During the tests of this addon one player tried to return after the kick but was unable because the server didn't respected the temp-ban used by the addon duo some bug in the dedicated server itself. Many other times players returned after the temp-ban without any problem.

Note
----------

The idea in this software is  similar to the penalty system present in [PCDSG (a gui for the server)](http://forum.projectcarsgame.com/showthread.php?31634-Project-Cars-Dedicated-Server-GUI-Launcher-with-%93live-timing%93-(results-timetable-)) created by cogent. I liked that idea and decided to implement a similar and improved system in Lua, to install directly on the server, without the need to keep a GUI opened to control the penalties.
