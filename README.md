# GMod Infinite Map [![made with - mee++](https:--img.shields.io/badge/made_with-mee%2B%2B-2ea44f)](https:--) ![Discord](https:--img.shields.io/discord/962140720192421928?label=Discord) 
## Now with added baked lighting support via vertex color!

### Overview
This is a garrys mod addon that adds a map to the game called gm_infinite, as the title suggests this map visually appears infinite
This is partially inspired by gm_infiniteflatgrass (from the Gravity Hull addon), but the map was very buggy and mostly impractical for use, especially when it comes to planes and ACF cars. Since the original creator of Gravity Hull is (presumably) dead, I am attempting to recreate it (Only the infinite map).

### Documentation
Documentation can be found here: https:--github.com/Mee12345/gmod-infinite-map/wiki/Documentation
It explains (to the best of my ability) how to set up an infinite map, as well as all of the provided functions that are avalible on the lua side.
I apologize in advance if it is difficult to read or understand. Hopefully the API will improve over time.

### This mod attempts to recreate gm_infiniteflatgrass with more features including:
* Generally less buggy
* Generally better addon support
* Ability to see over 2 billion hammer units in real time
* ACF Support
* WAC & some LFS Support
* Simphys car support
* Basic terrain including a ocean / lake system
* Ability to "Go to space"
* Procedural Planets
* Water / Lake System
* An attempt to revive the Spacebuild gamemode

### Stuff I am NOT doing:
* Trees (On main terrain)
* Editable Terrain
* Higher poly terrain
* Support for every addon, there WILL be conflictions!
* NPC and Nextbot support
* Hammer editor support
* Perfect particle detours
* Optimizations reguarding large amounts of spawned objects, this is source internal and performance wont be great
* Planets bigger than 1 chunk

### How It Works
The map isnt actually infinite, its impossible to go past the source bounds, so the entirety of the play space in the map is occupied in the same location. A hook is used to determine which props should and should not collide, and all entities are given perceived visual offsets per entity depending on which chunk (or cell) they are in, giving the illusion the map is presumably infinite (You cant do anything physical past the source boundery, but you can render things past it). The original Gravity Hull addon used this same method with "Cells" (But I call them chunks)

## For better addon support this mod currently detours the following functions:
### SERVER:
* Entity:GetPos
* Entity:WorldSpaceCenter
* Entity:WorldSpaceAABB
* Entity:SetPos
* Entity:LocalToWorld
* Entity:WorldToLocal
* Entity:EyePos
* Entity:NearestPoint
* Entity:GetAttatchment
* Entity:GetBonePosition
* Entity:Spawn (for constraints)

* PhysObj:GetPos
* PhysObj:SetPos
* PhysObj:ApplyForceOffset
* PhysObj:LocalToWorld
* PhysObj:WorldToLocal
* PhysObj:CalculateVelocityOffset
* PhysObj:GetVelocityAtPoint
* PhysObj:SetMaterial (I dont want to have to explain why this is detoured)

* Vehicle:SetPos

* CTakeDamageInfo:GetDamagePosition

* Player:GetShootPos

* NextBot:GetRangeSquaredTo
* NextBot:GetRangeTo

* CLuaLocomotion:FaceTowards

* util.IsInWorld
* util.TraceLine
* util.TraceHull
* util.BlastDamage

* ents.FindInBox
* ents.FindInSphere
* ents.FindInCone

* gmsave.ShouldSaveEntity

* ParticleEffect

* WireLib.clampPos	(unclamp wiremod and starfall setpos functions)
* SF.clampPos

* Explosions
* Bullets
* PlayerCanPickupWeapon
* PlayerCanPickupItem
* GravGunPickupAllowed

### CLIENT
* Entity:GetPos
* Entity:SetPos
* Entity:LocalToWorld
* Entity:WorldSpaceCenter
* Entity:WorldSpaceAABB
* Entity:SetRenderBounds
* Entity:GetBonePosition

* PhysObj:SetPos

* util.TraceLine
* util.TraceHull
* util.TraceEntity

* ents.FindInBox
* ents.FindInSphere
* ents.FindInCone

* Bullets
