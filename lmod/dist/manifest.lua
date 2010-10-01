--- LuaDist manifest specific functions including checks
-- Peter Drahoš, Peter Kapec, LuaDist Project, 2010

--- The purpose of this module is to check and collect dist manifests.
-- There are three functions provided:
-- make - Generates manifest for local directory
-- get - Gets sorted manifest from URI, this uses make for local paths. For remote directories it requires dist.manifest file to be present.
-- info - Loads and/or corrects and checks dist.info contents
-- Dists and manifests are simply arrays of collected dist.info files.

module ("dist.manifest", package.seeall)

local log		= require "dist.log"
local fetch 	= require "dist.fetch"
local persist 	= require "dist.persist"
local sys 		= require "dist.sys"
local config 	= require "dist.config"
local dep		= require "dist.dep"

local function couldBeDistFile(path)
	return (path:match"%.dist$" or path:match"%.zip$") and
	       sys.isFile(path)
end

--- Collect and sort dists in a directory.
-- @param dir string: Directory to get manifest from.
-- @return dists, log: Dists in the directory and log message.
function make(dir)
	assert(type(dir) == "string", "manifest.make: argument 'dir' not a string.")

	-- Collection
	local dists
	
	for id, file in pairs(sys.dir(dir) or {}) do
		local path = sys.path(dir, file)
		-- Try to load dist.info in case the file is expanded dist directory, then try loading it from the file using unzip
		local dist =
		    persist.load(sys.path(path, "dist.info")) or
		    couldBeDistFile(path) and
		        persist.loadText(sys.getZipFile(path, "*/dist.info") or "fail")
		-- note: couldBeDistFile test avoids calling unnecessarily calling
		-- getZipFile, which requires io.popen and unzip, which may be
		-- unavailable in the bootstrapping Lua.
		
		-- We have identified a dist
		if dist then
			-- Test it
			local dist, err = info(dist)
			if dist then
				-- Collect the dist
				dists = dists or {}
				dist.path = file
				table.insert(dists, dist)
			else
				-- Log warnings
				log.message("Warning, skipped malformed dist.info for file: ", file, "err:", err)
			end
		-- Recursively traverse subdirectory
		elseif sys.isDir(path) then
			local ret = make(path)
			for _,v in pairs(ret or {}) do
				dists = dists or {}
				v.path = file .. "/" .. v.path
				table.insert(dists, v)
			end
		end
	end
	if not dists then return nil, "No dists found in directory " .. dir end
	return dists, "Generated manifest for directory" .. dir
end

--- Get or generate repository contents from URI.
-- @param url string: URL to load the dist.manifest from. In case file:// is used generate the manifest.
-- @return dists, log: Returns true on success and nil and error message on failure.
function get(src, variables)
	assert(type(src) == "string", "manifest:get, argument 'url' is not a string." )
	
	-- If the src is local then make the manifest
	local dir = src:gsub("^file://","")
	local dists

    -- If src points to a unpacked dist
	if sys.isFile(sys.path(src, "dist.info")) then
	    local dist = info(sys.path(src, "dist.info"))
	    if dist then dists = { dist } end
	-- If src points to a dir
	elseif sys.isDir(dir) then
		dists = make(dir)
	-- Try collecting from manifest, assuming non-local reporitory
	else
		local manifest = fetch.get(sys.path(src, "dist.manifest"))
		if not manifest then return nil, "Could not obtain manifest for " .. src end
		dists = persist.loadText(manifest)
	end

	-- Sort by name and version
	if not dists then return nil, "No suitable dists found in " .. src end

	-- Check every dist
	local checked 
	for i = 1, #dists do
		local dist, err = info(dists[i])
		if dist then
			-- Dist is ok
			checked = checked or {}
			dist.path = sys.path(src:gsub("file://",""), dist.path)
			table.insert(checked, dist)
		else
			-- Malformed dist
			local name = tostring(dist.name) .. " " .. tostring(dist.version)
			log.message("Warning, skipped malformed dist.info (" .. name .. ") from:", src, "err:", err)
		end
	end
	if not checked then return nil, "No suitable dists found in " .. src end

	table.sort(checked, function(a, b) 
		-- If names match
		if a.name == b.name then
			-- When versions match
			if a.version == b.version then
				-- Prefer Universal arch
				if a.arch == b.arch then
					-- Prefer source arch
					if a.type == "source" then return false end
				end
				if a.arch == "Universal" then return false end
			end
			return dep.compareVersions(a.version ,b.version)
		end
		return a.name < b.name
	end)
	return checked, "Succesfuly obtained dists from " .. src
end

--- Check names in table, used in info checks.
-- @param table: Table to check names in.
-- @return ok, err: Returns true if everything is ok. In case of error nil and the malformed entry is returned.
local function checkNames(table)
    for k, v in pairs(table) do
        if type(v) == "string" then
            local name, const = dep.split(v)
            if not name then return nil, v end
        elseif type(v) == "table" then
            return checkNames(v)
        else
            return nil, "unknown entry"
        end
    end
    return true
end

--- Load and check info from file or check info table
-- @param dist string or table: Path to dist.info or info table to check.
-- @return info, log: Table containing loaded and checked info or nil and log message.
function info(dist)
	assert(type(dist) == "string" or type(dist) == "table", "manifest:info, argument 'dist' is not a string or table." )

	-- Load the info if needed from a file
	if type(dist) == "string" then
		dist = persist.load(dist)
		if not dist then return nil, "manifest.info: Failed loading dist.info from", dist end
		return info(dist), "manifest.info: Succesfully loaded dist.info from", dist
	end

	-- Add arch-type if not present
	dist.arch = dist.arch or "Universal"
	dist.type = dist.type or "source"

	
	-- Check the info entries
	if type(dist.name) ~= "string" then return nil, "Info does not contain valid name." end
	if not dist.name:match("[%l%d%.%:%_%-]+") then return nil, "Info info entry 'name' contains invalid characters" end
	if type(dist.version) ~= "string" then return nil, "Info does not contain valid version." end
	if not dist.version:match("[%l%d%.%:%_%-]+") then return nil, "Info entry 'version' contains invalid characters" end
	if type(dist.arch) ~= "string" then return nil, "Info does not contain valid architecture." end
	if not dist.arch:match("[%a%d]") then return nil, "Info entry 'arch' contains invalid characters." end
	if type(dist.type) ~= "string" then return nil, "Info does not contain valid type." end
	if not dist.type:match("[%a%d]") then return nil, "Info entry 'type' contains invalid characters." end
	
	-- Optional
	if dist.desc and type(dist.desc) ~= "string" then return nil, "Info does not contain valid description." end
	if dist.author and type(dist.author) ~= "string" then return nil, "Info does not contain valid author." end
	if dist.maintainer and type(dist.maintainer) ~= "string" then return nil, "Info does not contain valid maintainer." end
	if dist.url and type(dist.url) ~= "string" then return nil, "Info does not contain valid url." end
	if dist.license and type(dist.license) ~= "string" then return nil, "Info does not contain valid license." end
	if dist.depends and type(dist.depends) ~= "table" then return nil, "Info does not contain valid dependencies." end

	-- Check dependency format, swap for arch type specific id needed
	local ok, err = checkNames(dist.depends or {})
	if not ok then return nil, "Dependencies contain malformed entry: " .. err end
	
	-- Same for conflicts
	local ok, err = checkNames(dist.conflicts or {})
	if not ok then return nil, "Conflicts contain malformed entry: " .. err end

    -- And provides
	local ok, err = checkNames(dist.provides or {})
	if not ok then return nil, "Provides contain malformed entry: " .. err end
	
	-- Return, no log since it would spam the log file alot
	return dist, "Contents of dist is valid."
end
