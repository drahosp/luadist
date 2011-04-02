--- LuaDist simple persistance functions
-- Peter Drahoš, LuaDist Project, 2010
-- Original Code borrowed from LuaRocks Project

--- Persistency table serializarion.
--- 2DO: If a better persistency dist with good readability becomes available change this code
-- This module contains functions that deal with serialization and loading of tables.
-- loadText - text 2 table
-- load - file 2 table
-- saveText - table 2 text
-- save - table 2 file
-- saveManifest - variant of save for manifests

module ("dist.persist", package.seeall)

local sys	= require "dist.sys"

--- Serialize a table into text.
-- @param tbl table: Table to serialize.
-- @param d number: Intendation lenght.
-- @return out string: Serialized text.
local function serialize(o, d)
	local out = ""
	if not d then d = 0 end

	if type(o) == "number" then
		out = out .. tostring(o)
	elseif type(o) == "table" then
		out = out .."{\n"
		for k,v in pairs(o) do
			for f = 1,d do out = out .."\t" end

			if type(k) ~="number" then
				out = out .."\t['" ..tostring(k) .."'] = "			
			end
			
			for f = 1,d do out = out .."\t" end
			out = out .. serialize(v, d + 1)
			if type(v) ~= "table" then out = out ..",\n" end
		end
		for f = 1,d do out = out .."\t" end
		out = out .."},\n"
	else
		out = out .. '[[' .. tostring(o) .. ']]'
	end
	return out
end

--- Load table from text.
-- @param text string: Text to load table from.
-- @return table, log: Returns table on success, nil on failure and log message.
function loadText(text)
	assert(type(text) == "string", "persist.loadText: Argument 'text' is not a string.")

	local chunk, err = loadstring(text)
	if not chunk then return false, "Failed to parse text " .. err end
	
	local result = {}

	setfenv(chunk, result)
	local ok, ret, err = pcall(chunk)
	if not ok then return false, ret end
	return ret or result, "Sucessfully loaded table from text"
end

--- Load table from file.
-- @param filename string: File to load table from
-- @return table, log: Returns table on success, nil on failure and log message.
function load(filename)
	assert(type(filename) == "string", "persist.load: Argument 'filename' is not a string.")

	local chunk, err = loadfile(filename)
	if not chunk then return false, "Cannot load from file " .. filename end
	
	local result = {}

	setfenv(chunk, result)
	local ok, ret, err = pcall(chunk)
	if not ok then return false, ret end
	return ret or result, "Sucessfully loaded table from file " .. filename
end

--- Save table to string. Used for dist.info.
-- @param tbl table: Table to save.
-- @return out string: Serialized text.
function saveText(tbl)
	assert(type(tbl) == "table", "persist.save: Argument 'tbl' is not a table.")
	
	local out = ""
	for k, v in pairs(tbl) do
		-- Small fix for non alphanumeric strings (i know it looks ugly)
		if not k:match("[^%w_]*$") then k = "_G['" .. k .. "']" end
		if type(v) == 'table' then
			-- little trick so top-level table won't have commas,  but sub-tables will have
			out = out .. k .. " = " .. serialize(v):gsub(',\n$', '\n') .."\n"
		else
			out = out .. k ..' = "' .. tostring(v):gsub('"','\\"') ..'"\n'
		end
	end
	return out
end

--- Special serialization formating for manifests.
-- @param filename string: Path to save manifest to
-- @return ok, log: Returns true on success, nil on failure and log message.
function saveManifest(filename, dists)
	assert(type(filename) == "string", "persist.saveManifest: Argument 'filename' is not a string.")
	assert(type(dists) == "table", "persist.saveManifest: Argument 'dists' is not a table.")

	local out = io.open(filename, "w")
	if not out then	return false, "Cannot write to file " .. filename end
	
	out:write("return ");
	out:write(serialize(dists).."true")
	out:close()
	return true, "Successfully saved manifest to " .. filename
end

--- Save table to file.
-- @param filename string: File to save table to.
-- @param tbl table: Table to save.
-- @return ok, log: Returns true on success, nil on failure and log message.
function save(filename, tbl)
	assert(type(filename) == "string", "persist.save: Argument 'filename' is not a string.")
	assert(type(tbl) == "table", "persist.save: Argument 'tbl' is not a table.")
	
	local out = io.open(filename, "w")
	if not out then	return false, "Cannot write to file" .. filename end
	out:write(saveText(tbl) or "")
	out:close()
	return true, "Successfully saved table to " .. filename
end
