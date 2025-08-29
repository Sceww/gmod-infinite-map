-- this file handles the collision for the terrain
InfMap.chunk_table = InfMap.chunk_table or {}

local function try_invalid_chunk(chunk, filter)
	if !chunk then return end
	local invalid = InfMap.chunk_table[InfMap.ezcoord(chunk)]
	for k, v in ipairs(ents.GetAll()) do
		if InfMap.filter_entities(v) or !v:IsSolid() or v == filter then continue end
		if v.CHUNK_OFFSET == chunk then
			invalid = nil
			break
		end
	end
	SafeRemoveEntity(invalid)
end

local function update_chunk(ent, chunk, oldchunk)
	if IsValid(ent) and !InfMap.filter_entities(ent) and ent:IsSolid() then
		-- remove chunks that dont have anything in them
		try_invalid_chunk(oldchunk)

		-- chunk already exists, dont make another
		if IsValid(InfMap.chunk_table[InfMap.ezcoord(chunk)]) then return end

		local e = ents.Create("infmap_terrain_collider")
		InfMap.prop_update_chunk(e, chunk)
		e:SetModel("models/props_c17/FurnitureCouch002a.mdl")
		e:Spawn()
		InfMap.chunk_table[InfMap.ezcoord(chunk)] = e
	end
end

local function resetAll()
	local e = ents.Create("prop_physics")
	e:InfMap_SetPos(Vector(0, 0, -10))
	e:SetModel("models/hunter/blocks/cube8x8x025.mdl")
	e:SetMaterial("models/gibs/metalgibs/metal_gibs")
	e:Spawn()
	e:GetPhysicsObject():EnableMotion(false)
	constraint.Weld(e, game.GetWorld(), 0, 0, 0)
	InfMap.prop_update_chunk(e, Vector())

	-- spawn chunks
	for k, v in ipairs(ents.GetAll()) do
		if !v.CHUNK_OFFSET then continue end
		update_chunk(v, v.CHUNK_OFFSET)
	end
end

hook.Add("EntityRemoved", "infmap_infgen_terrain", function(ent)
	try_invalid_chunk(ent.CHUNK_OFFSET, ent)
end)

-- handles generating chunk collision
hook.Add("PropUpdateChunk", "infmap_infgen_terrain", function(ent, chunk, oldchunk)
	update_chunk(ent, chunk, oldchunk)
	-- remove ents too far below
	if chunk[3] <= -100 then
		print("Force removing stray", ent)
		SafeRemoveEntity(ent)
	end
end)

hook.Add("InitPostEntity", "infmap_terrain_init", resetAll)
hook.Add("PostCleanupMap", "infmap_cleanup", resetAll)