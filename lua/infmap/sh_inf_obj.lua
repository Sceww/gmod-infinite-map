local color_red = Color(255,0,0)

-- obj parser
local yield_quota = 3000
local max_collision_verts = 7500
InfMap.parsed_collision_data = InfMap.parsed_collision_data or {}
InfMap.parsed_objects = InfMap.parsed_objects or {}

local function vColtoInt(vfloatstring)
	return tonumber(vfloatstring) * 255
end
-- creates collisions for chunk .objs (defined later)
local build_object_collision

-- client generates meshes & materials from obj data
local materials_path = "materials/infmap/"
local function parse_client_data(object_name, faces, materials, usesVertexLighting, shaders)
	print("Started parsing " .. object_name)
	
	-- parse mtl file for materials
	local mtl_data = {}
	local mtl = file.Read("maps/" .. object_name .. ".mtl.ain", "GAME")  	-- ex. object.mtl.ain
	or file.Read("maps/" .. object_name .. ".mtl", "GAME")					-- 

	if mtl then
		local mtl_split = string.Split(mtl, "\n")
		local material
		for i = 1, #mtl_split do
			local data = string.Split(mtl_split[i], " ")
			if !data[2] then continue end	-- ignore empty lines
			local first = table.remove(data, 1)

			local material_data = string.Trim(data[1])
			if first == "newmtl" then 
				material = material_data
			elseif first == "map_Kd" then -- creating material
				local material_path = materials_path .. material_data

				-- check if usesVertexLighting
				if usesVertexLighting[material] then
					-- 1. load texture from disk
					local diskMat = Material(material_path, "noclamp mips smooth")
					-- 2. create new material (NOTE: DOES NOT CURRENTLY SUPPORT TRANSPARENCY)
					local vertexlitMat = CreateMaterial(material_data, "UnlitGeneric", {
						["$basetexture"] = "error",  -- replace this texture...
						["$vertexcolor"] = 1,
						-- ["$vertexalpha"] = 1,
						-- ["$nocull"] = 1, 
						["$model"] = 1, 
					})
					vertexlitMat:SetTexture("$basetexture", diskMat:GetTexture("$basetexture"))
					mtl_data[material] = vertexlitMat
				else -- The object doesn't use vertexlighting, so use the normal stuff.
					mtl_data[material] = Material(material_path, "vertexlitgeneric mips smooth noclamp" .. shaders)	-- alphatest
				end
			elseif first == "bump" and mtl_data[material] then
				local material_path = materials_path .. material_data
				local bumpmap = Material(material_path, "mips smooth noclamp")
				mtl_data[material]:SetTexture("$bumpmap", bumpmap:GetTexture("$basetexture"))	-- alphatest
			end
		end
	else
		print("Couldn't find .mtl file when parsing " .. object_name .. "!")
	end

	-- build meshes & materials
	for i = 1, #faces do
		local face_mesh = Mesh()
		face_mesh:BuildFromTriangles(faces[i])
		table.insert(InfMap.parsed_objects, {
			mesh = face_mesh,
			material = mtl_data[materials[i]]
		})

		if faces[i] and #faces[i] / 3 > 21845 then 
			print("Failed to parse face " .. i .. " as it has " .. #faces[i] / 3 .. " triangles! (Limit of 21,845)")
		end
		coroutine.yield()	-- looks cool
	end
end


-- server generates physmesh data from obj file
-- tris are in the format collisiondata[chunk][mat] = {{pos = Vector}, {pos = Vector}, {pos = Vector}...}
local function parse_server_data(faces)
	local function add_data(chunk, face1, face2, face3)
		local chunk_str = InfMap.ezcoord(chunk)
		InfMap.parsed_collision_data[chunk_str] = InfMap.parsed_collision_data[chunk_str] or {{}}
		local parsed_len = #InfMap.parsed_collision_data[chunk_str]
		local parsed_tri_len = #InfMap.parsed_collision_data[chunk_str][parsed_len]
		if parsed_tri_len > max_collision_verts then
			InfMap.parsed_collision_data[chunk_str][parsed_len + 1] = {}
			parsed_tri_len = 0
			parsed_len = parsed_len + 1
		end

		local offset = -InfMap.unlocalize_vector(Vector(), chunk)
		InfMap.parsed_collision_data[chunk_str][parsed_len][parsed_tri_len + 1] = {pos = face1 + offset}
		InfMap.parsed_collision_data[chunk_str][parsed_len][parsed_tri_len + 2] = {pos = face2 + offset}
		InfMap.parsed_collision_data[chunk_str][parsed_len][parsed_tri_len + 3] = {pos = face3 + offset}
	end

	-- combine and split faces into chunks
	for mat, face in ipairs(faces) do
		for i = 1, #face, 3 do
			local face1 = face[i    ].pos
			local face2 = face[i + 1].pos
			local face3 = face[i + 2].pos

			-- too small, dont bother generating collision
			if (face1 - face2):Cross(face1 - face3):LengthSqr() < 100000 then continue end

			local _, chunk1 = InfMap.localize_vector(face1)
			local _, chunk2 = InfMap.localize_vector(face2)
			local _, chunk3 = InfMap.localize_vector(face3)

			add_data(chunk1, face1, face2, face3)

			if chunk2 ~= chunk1 then
				add_data(chunk2, face1, face2, face3)
			end

			if chunk3 ~= chunk2 and chunk3 ~= chunk1 then
				add_data(chunk3, face1, face2, face3)
			end
		end

		coroutine.yield()
	end

	print("Finished parsing collision")

	for k, v in ipairs(player.GetAll()) do
		if !v.CHUNK_OFFSET then continue end
		build_object_collision(v, v.CHUNK_OFFSET, true)
	end
end

-- stupid obj format
local function unfuck_negative(v_str, max)
	if !v_str or v_str == "" then return 0 end

	local v_num = tonumber(v_str)
	return v_num > 0 and v_num or v_num % max + 1
end

-- anti memory leak stuff (for hotreloading)
function InfMap.clear_parsed_objects()
	if CLIENT then
		for _, object in ipairs(InfMap.parsed_objects) do
			object.mesh:Destroy()
		end
	end
	if SERVER then
		for k, v in pairs(ents.FindByClass("infmap_obj_collider")) do
			v:Remove()
		end
	end
	table.Empty(InfMap.parsed_objects)

	hook.Remove("PropUpdateChunk", "infmap_obj_spawn")
end

-- Main parsing function
local mesh_tangent = {1, 1, 1, 1}
function InfMap.parse_obj(object_name, translation, client_only, shaders) -- translation: matrix
	if SERVER and client_only == 1 then return end

	-- clear all collision data
	table.Empty(InfMap.parsed_collision_data)

	-- actual obj file
	local obj = file.Read("maps/" .. object_name .. ".obj.ain", "GAME")
	or 			file.Read("maps/" .. object_name .. ".obj", "GAME")

	if !obj then 
		print("Couldn't find .obj file when parsing " .. object_name .. "! (is the file in maps/ ?)")
		return 
	end
	
	local rotation = translation:GetAngles()

	-- time to parse
	-- Order of an obj:
	--[[ 	1. o 	  <MESHNAME>
			2. v 	  (xyz)
			3. vn 	  (xyz)
			4. vt 	  (xy)
			5. s	  0
			6. usemtl <MATERIAL>
			7. f  	  i/i/i i/i/i i/i/i i/i/i
	]]
	local coro = coroutine.create(function()
		local meshName = "NIL OBJECT"
		local using_vertex_lighting = false

		local err, str = pcall(function()
		local group = 0
		local material = 0
		-- local material_name = "" -- equivalent to materials[materialIndex]
		local vertices = {}
		local uvs = {}
		local normals = {}
		local colors = {}
		local materials = {}
		local uses_vertex_lighting = {}
		local faces = {}

		-- sort the data
		local split_obj = string.Split(obj, "\n")
		local split_obj_len = #split_obj
		for i = 1, split_obj_len do
			-- get data from line
			local line_data = string.Split(split_obj[i], " ")
			local first = table.remove(line_data, 1)
			-- vertex processing (but actually never first.)
			if first == "v" then
				table.insert(vertices[group], translation * Vector(-tonumber(line_data[1]), tonumber(line_data[3]), tonumber(line_data[2])))
				if line_data[4] and CLIENT then -- object uses vertex colors to represent lighting as told by the inclusion of an extra float value in v.
					using_vertex_lighting = true
					table.insert(colors[group], Color( vColtoInt(line_data[4]), vColtoInt(line_data[5]), vColtoInt(line_data[6]) ))
				elseif CLIENT then
					table.insert(colors[group], color_white)
				end
					

			-- only client uses uvs and normals
			elseif first == "vt" and CLIENT then
				table.insert(uvs[group], Vector(tonumber(line_data[1]), tonumber(line_data[2])))
			elseif first == "vn" and CLIENT then
				local normal = Vector(-tonumber(line_data[1]), tonumber(line_data[3]), tonumber(line_data[2]))
				normal:Rotate(rotation)
				table.insert(normals[group], normal)

			-- face processing
			elseif first == "f" then 
				-- sometimes a material isnt defined, not sure why.. define empty one
				if !faces[material] then
					print("Material undefined for group " .. group)
					material = material + 1
					faces[material] = {}
				end
				
				-- who tf uses negative indexes?!??
				-- why am I adding support for this!?
				local max_verts = #vertices[group]
				local max_uvs = #uvs[group]
				local max_normals = #normals[group]
				local max_colors = #colors[group] -- Might be totally unneeded?

				-- n gon support
				for i = 3, #line_data do
					-- get our vertex indices data
					local vertex1 = string.Split(line_data[i - 1], "/")  -- indices
					local vertex2 = string.Split(line_data[1], "/")
					local vertex3 = string.Split(line_data[i], "/")

					local vertex1_pos = vertices[group][unfuck_negative(vertex1[1], max_verts)] -- vertex1[1]: number. but maybe this returns a Vector?
					local vertex2_pos = vertices[group][unfuck_negative(vertex2[1], max_verts)] -- Vertex color is stored right next to the vertex.
					local vertex3_pos = vertices[group][unfuck_negative(vertex3[1], max_verts)]

					local v1_c = color_white
					local v2_c = color_white
					local v3_c = color_white
					if CLIENT then
						v1_c = colors[group][unfuck_negative(vertex1[1], max_verts)] or color_red
						v2_c = colors[group][unfuck_negative(vertex2[1], max_verts)] or color_red
						v3_c = colors[group][unfuck_negative(vertex3[1], max_verts)] or color_red
					end

					-- this should never be run, but just in case
					--if !vertex1_pos or !vertex2_pos or !vertex3_pos then continue end

					-- degenerate triangle check
					if (vertex1_pos - vertex2_pos):Cross(vertex1_pos - vertex3_pos):LengthSqr() < 0.0001 then continue end

					local face_len = #faces[material]
					local uv = uvs[group][unfuck_negative(vertex1[2], max_uvs)]
					faces[material][face_len + 1] = {
						pos = vertex1_pos,
						u = uv and  uv[1],
						v = uv and -uv[2],	-- reverse triangle winding
						normal = normals[group][unfuck_negative(vertex1[3], max_normals)],
						userdata = mesh_tangent,
						color = v1_c
					}

					uv = uvs[group][unfuck_negative(vertex2[2], max_uvs)]
					faces[material][face_len + 2] = {
						pos = vertex2_pos,
						u = uv and  uv[1],
						v = uv and -uv[2],
						normal = normals[group][unfuck_negative(vertex2[3], max_normals)],
						userdata = mesh_tangent,
						color = v2_c
					}

					uv = uvs[group][unfuck_negative(vertex3[2], max_uvs)]
					faces[material][face_len + 3] = {
						pos = vertex3_pos,
						u = uv and  uv[1],
						v = uv and -uv[2],
						normal = normals[group][unfuck_negative(vertex3[3], max_normals)],
						userdata = mesh_tangent,
						color = v3_c
					}
				end
			elseif first == "usemtl" then -- 
				material = material + 1
				
				-- material_name = string.Trim(line_data[1])
				
				faces[material] = {}
				materials[material] = string.Trim(line_data[1])

				if using_vertex_lighting then
					uses_vertex_lighting[materials[material]] = true -- {["Landscape"] = true, ["Road"] = true, ["Dummy"] = false}
				else
					uses_vertex_lighting[materials[material]] = false
				end
			elseif first == "o" or first == "g" then -- Tends to be the first thing to be defined.
				-- if using_vertex_lighting then -- print previous mesh info
				-- 	print("\tVertex Lighting data found!, enabling vertex lighting for ".. meshName)
				-- end
			-- reset using_vertex_lighting
			using_vertex_lighting = false
			meshName = line_data[1]
			-- print("new obj: "..meshName)
				if group == 0 then -- incase it doesnt exist
					group = group + 1
					vertices[group] = {}
					uvs[group] = {}
					normals[group] = {}
					colors[group] = {}	
				end
			elseif first == "mtllib" then	-- increment groups of tris
				group = group + 1
				vertices[group] = {}
				uvs[group] = {}
				normals[group] = {}
				colors[group] = {}
			end

			table.Empty(line_data) line_data = nil

			if i % yield_quota == 0 then
				coroutine.yield()
			end
		end

		if CLIENT and client_only ~= 2 then
			parse_client_data(object_name, faces, materials, uses_vertex_lighting, shaders or "")
		end

		if client_only ~= 1 then
			parse_server_data(faces)
			hook.Add("PropUpdateChunk", "infmap_obj_spawn", build_object_collision)
		end

		-- free data
		table.Empty(split_obj) split_obj = nil
		table.Empty(vertices) vertices = nil
		table.Empty(uvs) uvs = nil
		table.Empty(normals) normals = nil
		table.Empty(faces) faces = nil
		table.Empty(materials) materials = nil
		table.Empty(colors) colors = nil

		print("Finished parsing " .. object_name)
		end)
		if !err then print(str) end
	end)

	hook.Add("Think", "infmap_parse" .. object_name, function() 
		if coroutine.status(coro) == "suspended" then
			coroutine.resume(coro)
		else
			hook.Remove("Think", "infmap_parse" .. object_name)
		end
	end)
end

if CLIENT then
	-- render parsed objs
	local ambient = render.GetLightColor(Vector())
	local model_lights = {{ 
		type = MATERIAL_LIGHT_DIRECTIONAL,
		color = Vector(2, 2, 2),
		dir = Vector(1, 1, 1):GetNormalized(),
	}}
	local default_material = CreateMaterial("infmap_objdefault", "VertexLitGeneric", { -- previously VertexLitGeneric
		["$basetexture"] = "dev/graygrid", 
		-- ["$vertexcolor"] = 1,
		-- ["$vertexalpha"] = 1,
		["$nocull"] = 1,
		-- ["$alpha"] = 1,
		["$model"] = 1, 
	})
	hook.Add("PostDrawOpaqueRenderables", "infmap_obj_render", function()
		local sun = util.GetSunInfo()
		if sun and sun.direction then
			model_lights[1].dir = -sun.direction
		end
		render.SetLocalModelLights(model_lights) -- no lighting
		render.ResetModelLighting(ambient[1], ambient[2], ambient[3])

		cam.Start3D(InfMap.unlocalize_vector(EyePos(), LocalPlayer().CHUNK_OFFSET))
		for i = 1, #InfMap.parsed_objects do
			local object = InfMap.parsed_objects[i]
			render.SetMaterial(object.material or default_material)
			object.mesh:Draw()
		end
		cam.End3D()
	end)
end

build_object_collision = function(ent, chunk)
	if SERVER and InfMap.filter_entities(ent) then return end
	if CLIENT and ent ~= LocalPlayer() then return end

	local chunk_coord = InfMap.ezcoord(chunk)
	if IsValid(InfMap.parsed_objects[chunk_coord]) then return end

	local chunk_data = InfMap.parsed_collision_data[chunk_coord]
	if !chunk_data then return end

	if SERVER then
		for i = 1, #chunk_data do
			local collider = ents.Create("infmap_obj_collider")
			collider:SetModel("models/props_junk/CinderBlock01a.mdl")
			collider:Spawn()
			collider:UpdateCollision(chunk_data[i])
			InfMap.prop_update_chunk(collider, chunk)
			InfMap.parsed_objects[chunk_coord] = collider
		end
	else
		timer.Simple(0, function()	-- race condition
			-- try to find a collider in our chunk
			local collider_len = #chunk_data
			local collider_count = 1
			for _, collider in ipairs(ents.FindByClass("infmap_obj_collider")) do
				if collider.CHUNK_OFFSET ~= LocalPlayer().CHUNK_OFFSET then continue end
				if collider:GetPhysicsObject():IsValid() then continue end
				
				-- weird hack to prevent null physobjs on client
				if !collider.UpdateCollision then
					collider.RENDER_MESH = chunk_data[collider_count]
				else
					collider:UpdateCollision(chunk_data[collider_count])
				end

				collider_count = collider_count + 1

				-- we found our colliders, stop looking
				if collider_count > collider_len then
					break
				end
			end
		end)
	end
end

