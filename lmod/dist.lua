--- LuaDist Primary API functions
-- Peter Drahoš, Peter Kapec, LuaDist Project, 2010

--- This file contains the basic functions of LuaDist.
-- Feel free to use this exposed API in your projects if you need to deploy something automatically.
-- Please note that everything may change in future releases.
--- Terminology used:
-- _dist_ - General reference to "package" in LuaDist, often synonymous with _info_.
-- _info_ - Meta-data describing a _dist_. Collected from dist.info files inside dist archives.
-- _manifest_ - A collection of sorted _info_ entries in a table. Sorted alphabetically by name and by version descending.
-- _name_ - Refers to a string containing dist name and version constraints. Eg. "lua-5.1.4" or "luajit>=2"
-- _deployment_ - A directory containing dists installed using LuaDist.

module ("dist", package.seeall)

-- Include Submodules
local man = require "dist.manifest"
local pkg = require "dist.package"
local per = require "dist.persist"
local cfg = require "dist.config"
local sys = require "dist.sys"
local dep = require "dist.dep"
local log = require "dist.log"

--- Get contents of repository or a list of repositories.
-- _getManifest_ is used to fetch or generate collections of dist.info entries from
-- URIs, system paths and on-line repositories. Returned dist manifests are not 
-- filtered and may not be appropriate for installation, see _filterManifest_ for this 
-- purpose.
--
-- Dist information is gathered by collecting dist.info entries from dist.manifest 
-- file in case an URL to on-line repository is given. System paths are searched 
-- for dist.info files on demand and do extracted dists can be used for local 
-- repositories, this is handy for bootstrap and development of multiple 
-- interconnected dists. Zip archives and dists are peeked into on demand and in
-- case it contains dist.info entry its added to the manifest. 
--
-- In case of multiple repositories, first repository always has priority. Dists are
-- ordered by repository, name and version. Every item is checked, malformed entries 
-- are removed.
--
-- @param repositories string or table: Path or URL of a repository or repositories. By default cfg.repo is used if argument is not defined.
-- @return manifest: Table containing collections of available dists.
function getManifest(repositories)
    -- If no repository is provided use default ones from configuration.
    repositories = repositories or cfg.repo
    -- Make sure the argument is always a table.
    if type(repositories) == "string" then repositories = { repositories } end
    -- Check if we can continue.
    assert(type(repositories) == "table", "dist.getManifest: Argument 'repositories' is not a table or string.") 

    local manifest = {}
    -- Collect all dists.info entries from each repo.
    for i = 1, #repositories do
    	-- Append all dist.infos found.
    	local repo = man.get(repositories[i]) or {}
    	for j = 1, #repo do
    		table.insert(manifest, repo[j]) 
    	end
    end
    return manifest
end

--- Get all installed dists from deployment directory.
-- _getInstalled_ will collect all installed dists inside a deployment directory.
-- These represent installed dists; provided dists are not included, see _getDeployed_
-- if you need a provided dists too.
--
-- @param deployment string: Path to deployment directory. If not specified the deployment LuaDist is running in will be used.
-- @return manifest: Table containing collections of installed dists.
function getInstalled(deployment)
	-- Set up deployment directory if not set
	deployment = sys.path(deployment or getDeployment())
	assert(type(deployment) == "string", "dist.getInstalled: Argument 'deployment' is not a string.") 
	if not sys.isDir(sys.path(deployment, cfg.dists)) then
		return {}
	end
	-- Collect dists in deployment using getManifest.
	return getManifest(sys.path(deployment, cfg.dists)) or {}
end

--- Get all deployed dists in the target dir, this will also list dists provided by other dists.
-- _getDeployed_ will collect all deployed dists inside a deployment directory.
-- This inludes entries that simulate provided dists which act as dependency satisfaction for dists
-- during installation.
--
-- Integration with host package managers can be achieved by providing a list of modules already
-- installed directly to the host system. The list can be edited directly by the user in configuration.
--
-- @param deployment string: Path to deployment directory. If not specified the deployment LuaDist is running in will be used.
-- @return manifest: Table containing collections of deployed dists.
function getDeployed(deployment)
	-- Set up deployment directory if not set
	deployment = sys.path(deployment or getDeployment())
	assert(type(deployment) == "string", "dist.getDeployed: Argument 'deployment' is not a string.") 
	-- Get installed dists
	local list, err = getInstalled(deployment)
	if not list then return nil, err end
		
	-- Helpful dist.info generator from dists and cfg.provided
	local function getProvidedDists(info)
		if not info then
			-- Fake host provides
			info = { name = "Host", version = "config", provides = cfg.provides, arch = cfg.arch, type = cfg.type }
		end
		
		-- Generate dist.info for the provided dists
		local manifest = {}
		for _, provide in pairs(info.provides or {}) do
			local dist = {}
			dist.name, dist.version = dep.split(provide)
			dist.arch = info.arch
			dist.type = info.type
			dist.provided = info.name .. "-" .. info.version
			table.insert(manifest, dist)
		end 
		return manifest
	end
	 
	-- Insert provided entries collected from installed dists
	local manifest = {}
	for i = 1, #list do
		local dist = list[i]
		table.insert(manifest, dist)
		local provided = getProvidedDists(dist)
		for j = 1, #provided do
			table.insert(manifest, provided[j])
		end
	end

	-- Include list of provided dists from host (cfg.provided)
	local provided = getProvidedDists()
	for j = 1, #provided do
		table.insert(manifest, provided[j])
	end
	
	return manifest
end

--- Filter dist manifests using constraint functions.
-- _filterManifest_ is used to remove dists from dist manifests that don't satisfy conditions.
-- Conditions are specified using a table of functions. Functions are named after the attribute
-- they check and return true if an argument satisfies its condition.
--
-- When constraint are not defined a default set of constraints is used. These constraints filter
-- out dists not suitable for the architecture LuaDist is running on. More specifically, only dists
-- of arch "Universal" or of arch equal to cfg.arch and of type "all" or type equal to cfg.type
-- are preserved. Additionally when source dists are enabled in configuration this will include dists
-- of type equal to "source".
--
-- In case no manifest is specified _filterManifest_ will automatically collect dist manifests from default
-- repositories using _getManifest_.
--
-- @param list table: Dist list or manifest to filter. By default all dists collected from cfg.repo will be filtered.
-- @param constraints table: Table of constraint function. Key determines what dist attribute is checked while the value is the actual constraint test written as a function. By default dists are filtered for correct arch-type.
-- @return manifest: Table containing collections of filtered dists.
function filterManifest(list, constraints)
	-- By default fetch dists if not provided
	list = list or getManifest() or {}

	-- Default constraints filter arch and type of dists
	constraints = constraints or { 
		-- Architecture constraints
		arch = function(arch)
			if not arch or arch == "Universal" then return true end
			if cfg.binary and arch == cfg.arch then return true end
			return false
		end,
		-- Type constraints
		type = function(type)
			if not type or type == "all" then return true end
			if cfg.binary and type == cfg.type then return true end
			if cfg.source and type == "source" then return true end
			return false
		end
	}

	-- Check if we can continue.
	assert(type(list) == "table", "dist.filterManifest: Argument 'list' is not a table.")
	assert(type(constraints) == "table", "dist.filterManifest: Argument 'constraints' is not a table.")

	-- Matching dists
	local manifest = {}
	
	-- For each dist match constraints
	for i = 1, #list do
		local dist = list[i]
		local match = true
		-- Accumulate constraint checks
		for key, constraint in pairs(constraints) do
			match = match and constraint(dist[key])
		end
		-- If all went ok
		if match then
			table.insert(manifest, dist)
		end
	end
	
	return manifest
end

--- Find dists in manifest by name.
-- _findDists_ will find all dists in manifest that satisfy conditions in the name string.
-- Name contains dist name to search for and a set of optional version constraints. For example
-- searching for "lua-5.1.4" will find all dists of name "lua" and version "5.1.4". Searching for version
-- ranges is done using sets of constraints eg. "luajit >= 2.0 < 3.0". For more information, limitations
-- and use of the constraint system please see LuaDist documentation.
--
-- @param name string: String specifying the dist to find, version constraints can be used. Case sensitive.
-- @param manifest string: Dist manifest to search through.
-- @return dist, log: List of matching dists. Returns nil on error and log message.
function findDists(names, manifest)
	-- We can handle name lists and mane sring directly
	if type(names) == "string" then names =  { names } end
	
	-- If manifest is missing we get it from configured repository
	manifest = manifest or filterManifest() or {}
	
	-- Check if we can continue
	assert(type(names) == "table", "dist.findDists: Argument 'names' is not a table or string.")
	assert(type(manifest) == "table", "dist.findDists: Argument 'manifest' is not a table.")

	if #names == 0 then return manifest end

	local dists = {}
	for i = 1, #names do
		local name = names[i]
		
		-- Split name to dist-name and constraints
		local name, constraints = dep.split(name)
		-- Escape special chars in name
		local match = "^" .. name:gsub("%.", "%%."):gsub("%-", "%%-"):gsub("%_", "%%_"):gsub("%*", ".*") .. "$"
		-- Filter manifest using custom constraints
		local list = filterManifest(manifest, {
			name = function(distName)
				return string.match(distName, match)
			end,
			version = function(distVer)
				return dep.constrain(distVer, constraints or "") 
			end
		})
		for j = 1, #list do
			table.insert(dists, list[j])
		end
	end
	return dists
end

--- Small help function to get relevant names from info
local function getInfoNames(tbl) 
    local ret = {}
    tbl = tbl or {}
    tbl = tbl[cfg.arch] or tbl
    tbl = tbl[cfg.type] or tbl
    for _, entry in pairs(tbl) do
        if type(entry) == "string" then
            table.insert(ret, entry)
        end
    end
    return ret
end

--- Collect dependencies.
-- _getDeps_ is the magic function where dependency resolving happens.
-- This function handles multiple names for which it computes the best possible set of dists that satisfy
-- all the names. It consideres provided dists, conflicts and dependencies of each candidate dist and avoids
-- dependency loops. It may not be very elegant or efficient, contributions welcome.
--
-- The algorithm relies on sequential satisfaction of names. For each name it tries to determine
-- best possible candidate and tries to install its dependencies and rest of the names list. 
-- If dependencies fail another candidate is checked untill all names check out or candidates run out.
-- Provides are faked by injecting dists into manifest and replaced before return.
-- 
-- @param names string or table: Names to compute dependencies for.
-- @param manifest table: Manifest of dists to select dependencies from, needs to be sorted.
function getDeps(names, manifest)
    manifest = manifest or filterDists()
	if type(names) == "string" then names = { names } end

	-- Type Checks
	assert(type(names) == "table", "dist.getDeps: Argument 'names' is not a table or string.")
	assert(type(manifest)=="table", "dist.getDeps: Argument 'manifest' is not a table.")

	-- Check out first from the list and find its candidates
	local name = names[1]
	local candidates = findDists(name, manifest)
	
	-- For each candidate we check its suitability
	for i = 1, #candidates do
		local info = candidates[i]
	    local infoName = info.name .. "-" .. info.version
	    
		-- Add candidate dependencies to names
		-- Notice deps will be used according to arch and type if they are available
		local newNames = {}
		for _, entry in pairs(getInfoNames(info.depends)) do
	        table.insert(newNames, entry)
		end
		for j = 2, #names do
		    table.insert(newNames, names[j])
		end
		
		-- Make new manifest with provided dists
		local newManifest = {}
		for _, entry in pairs(getInfoNames(info.provides)) do
		    -- Construct a fake provided dist pointing to the provider
		    local dist = {}
		    dist.name, dist.version = dep.split(entry)
			dist.arch = info.arch
			dist.type = info.type
			dist.provided = info
			table.insert(newManifest, dist)
		end
		for j = 1, #manifest do
		    table.insert(newManifest, manifest[j])
		end
				
		-- Check dependencies first
		local dependencies = {}
		if #newNames > 0 then
		    dependencies, err = getDeps(newNames, newManifest)
		    if not dependencies then
		        return nil, err
		    end
	    end
	
		-- If provided we skip tests as the providing dist will make sure of it
		if info.provided then
			if type(info.provided) == "table" then
				table.insert(dependencies, info.provided)
			end
			return dependencies
		end
			
        -- Skip rest if candidate is in deps
        for _, prov in pairs(dependencies) do
            local provName = prov.name .. "-" .. prov.version

		    -- Check if already provided
		    if info.name == prov.name then
		        if info.version == prov.version then
		            -- If provided by a dist checking its deps.
		            return dependencies
		        else
		            -- Different version
		            return nil, infoName .. " is blocked by " .. provName
		        end
		    end
		    		    
		    -- Check dependency constraints
		    for _, entry in pairs(getInfoNames(prov.depends)) do
	            local name, const = dep.split(entry)
	            if info.name == name and (not const or not dep.constrain(info.version, const)) then
    			    return nil, infoName .. " is blocked by " .. provName .. " dependency " .. entry
    		    end
        	end
        	
        	-- Indirect conflicts
    	    for _, entry in pairs(getInfoNames(prov.conflicts)) do
		        local name, const = dep.split(entry)
		        if info.name == name and (not const or not dep.constrain(info.version, const)) then
        			return nil, infoName .. " is blocked by " .. provName .. " conflict " .. entry
        		end
        	end
        	
        	-- Direct conflicts
            for _, entry in pairs(getInfoNames(info.conflicts)) do
		        local name, const = dep.split(entry)
		        if prov.name == name and (not const or not dep.constrain(prov.version, const)) then
        			return nil, infoName .. " is in conflict with " .. provName .. " conflict " .. entry
        		end
        	end
		end
	    
		--- Candidate matches, add it to result
	    table.insert(dependencies, info)
	    return dependencies
	end
	return nil, "No suitable dists in repository for " .. name
end

--- Install dist by name.
-- _install_ is capable to install dists from various sources and of both source and binary type. 
-- Sources can be accumulated into install lists in which case LuaDist will install the sources in sequence. 
-- Sources supported by the command currently include: name, path and URL to .dist and .zip, path to unpacked dist
-- and dist.info table.
--
-- @param name string: Package to install identified by name which can include version constraints. Case sensitive.
-- @param deployment string: Deployment directory to install into. Leave undefined for current deployment directory.
-- @param manifest table: Manifest of dists used to search for sources and resolve dependencies. Leave undefined for default repositories.
-- @param variables table: Table of key value pairs that can be used to set additional CMake variables for source dists.
-- @return ok, log: Returns true on success. nil on error and log message.
function install(names, deployment, manifest, variables)
	-- Make sure deployment path is absolute and set
	deployment = sys.path(deployment or getDeployment())
	-- Make sure we have a manifest to install dists from
	manifest = manifest or filterManifest()
	-- Default variables can be omitted so make sure we have a table
	variables = variables or {}
	-- Make sure names are always in a list
	if type(names) == "string" then names = { names } end
	
	-- Check types
	assert(type(names) == "table", "dist.install: Argument 'name' is not a string or table.")
	assert(type(deployment)=="string", "dist.install: Argument 'deployment' is not a string.")
	assert(type(manifest)=="table", "dist.install: Argument 'manifest' is not a table.")
	assert(type(variables)=="table", "dist.install: Argument 'variables' is not a table.")

    log.message("Computing dependencies.")

    -- Create custom manifest starting with deployed dists
	local manif = {}
	for _, depl in pairs(getDeployed(deployment) or {}) do
		table.insert(manif, depl)
	end
	for j = 1, #manifest do
		local dist = manifest[j]
		table.insert(manif, dist)
	end

	-- Compute dependencies
	local deps, err = getDeps(names, manif)
	if not deps then return nil, err end
	
	-- Fetch and deploy
	for i = 1, #deps do
		local ok, err = deploy(deps[i].path, deployment, variables)
		if not ok then return nil, err end
	end
	return true, "Install Successful."
end

--- Deploy a dist directly from source.
-- _deploy_ will install; and in case of source dists, build a dist from source path.
-- Deployment will automatically fetch from remote URLs and unpack dist or zip files into deploymemt.
-- Variables can contain additional CMake variables to be used when building source dists.
--
-- @param src string: Path to the dist directory to make/deploy or nil to use current directory.
-- @param deployment string: Deployment directory to install the dist into. If nil LuaDist directory is used.
-- @param variables table: Table of key value pairs that can be used to set additional CMake variables for source dists.
-- @return ok, log: Returns true on success. nil on error and log message.
function deploy(src, deployment, variables)
	-- Make sure deployment path is absolute and set
	deployment = sys.path(deployment or getDeployment())

	-- Make sure deployment exists and create startup script		
	sys.makeDir(deployment)
	if cfg.start then sys.makeStart(deployment) end

	-- Default variables can be omited so make sure we have a table
	variables = variables or {}
	
	-- Handle each source individually if a list is passed
	if type(src) == "table" then
		for i = 1, #src do
			local ok, err = deploy(src[i], deployment, variables)
			if not ok then return nil, err end
		end
		return true, "Install Successful"
	end
	
	-- By default build in current directory
	src = sys.path(src or sys.curDir())
	
	assert(type(src)=="string", "dist.deploy: Argument 'src' is not a string.")
	assert(type(deployment)=="string", "dist.deploy: Argument 'deployment' is not a string.")
	assert(type(variables)=="table", "dist.deploy: Argument 'variables' is not a table.")

	-- Fetch if needed
	local tmp, err
    if not sys.isDir(src) then
	    tmp, err = package.unpack(src)
	    if not tmp then
            log.message("Could not fetch following dist: " .. src .. " (" .. err .. ")")
            return false, "Could not fetch following dist: " .. src .. " (" .. err .. ")" 
	    end

	    -- Use the 1st subdirectory of the tmp
	    src = sys.path(tmp, sys.dir(tmp)[1])
    end		
	
	-- Check dist info
	local info, err = persist.load(sys.path(src, "dist.info"), variables)
	if not info then return nil, "Dist does not contain valid dist.info in " .. src end

	-- We have a dist
	local infoName = info.name .. "-" .. info.version
	log.message("Deploying " .. infoName)
	
	-- Check the package contents for CMakeLists.txt, that would mean the package is of type source.
	if sys.exists(sys.path(src, "CMakeLists.txt")) then
		info.arch = info.arch or "Universal"
		info.type = info.type or "source"
	end
	
	-- Check the architecture if its suitable for deployment.
	if info.arch ~= cfg.arch and info.arch ~= "Universal" then
		return nil, "Dist is of incompatible architecture " .. (info.arch or "NOT-SET") .. "-" .. (info.type or "NOT-SET")
	end
	
	-- Check the type if its suitable for deployment
	if info.type ~= cfg.type and info.type ~= "all" and info.type ~= "source" then
		return nil, "Dist is of incompatible architecture type " .. info.arch .. "-" .. info.type
	end

	-- If the dist is not source we simply deploy it.
	if info.type ~= "source" then 
		local ok, err = package.deploy(src, deployment)

		-- Cleanup		
		if not config.debug and tmp then sys.delete(tmp) end
		
		if not ok then return nil, "Failed to deploy package " .. src .. " to " .. deployment .. "." .. err end
		
		-- Display message
		if info.message then
			log.message(info.message)
		end
		
		return true, "Deployment Successful."
	end

	--- We have a source dist.
	log.message("Compiling ...")
	-- Setup variables by mergeing cfg.variables and variables
	local vars = {}
	for k,v in pairs(cfg.variables or {}) do
		vars[k] = v
	end
	for k, v in pairs(variables or {}) do
		vars[k] = v
	end

	-- Set CMake search paths for libs and headers to the deployment directory
	vars.CMAKE_INCLUDE_PATH = table.concat({ sys.path(vars.CMAKE_INCLUDE_PATH) or "", sys.path(deployment, "include")}, ";")
	vars.CMAKE_LIBRARY_PATH = table.concat({ sys.path(vars.CMAKE_LIBRARY_PATH) or "", sys.path(deployment, "lib"), sys.path(deployment, "bin")}, ";")
	
	-- Build and deploy the package
	local bin, err = package.build(src, deployment, vars)
	
	-- Cleanup		
	if not config.debug and tmp then sys.delete(tmp) end

	if not bin then return nil, "Failed to build dist " .. infoName .. " error: " .. err end
	
	-- Display message
	if info.message then
		log.message(info.message)
	end
	
	return true, "Deployment Successful."
end

--- Remove a deployed dist.
-- _remove_ will delete specified dist from deployment.
-- When no name is specified, the whole deployment directory will be removed.
-- WARNING: Calling "luadist remove" will instruct LuaDist to commit suicide.
--
-- @param dist string or table: Dist name or info to uninstall.
-- @param deployment string: Deployment directory to uninstall from, nil for default LuaDist directory.
-- @return ok, log: Returns true on success. nil on error and log message.
function remove(names, deployment)
	-- Make sure deployment path is absolute and set
	deployment = sys.path(deployment or getDeployment())

	-- Make sure names are always in a table
	if type(names) == "string" then names = {names} end
	
	-- Check types
	assert(type(names) == "table" , "dist.remove: Argument 'names' is not a string or table.")
	assert(type(deployment) == "string", "dist.remove: Argument 'deployment' is not a string.")

	-- Find dists
	local dists = findDists(names, getInstalled(deployment))
	if not dists then return nil, "Nothing to delete." end
		
	-- Delete the dists
	for _, dist in pairs(dists) do
		local ok = package.delete(dist.path, deployment)
		if not ok then return nil, "Could not remove dist " .. dist.name .. "-" .. dist.version end
	end
	return true, "Remove Successful."
end

--- Pack a deployed dist.
-- _pack_ will pack specified dist from deployment deployment and generate .dist archives in dest.
-- When no name is specified all dists will be packed.
--
-- @param dist string or table: Dist name or info to uninstall.
-- @param deployment string: Deployment directory to uninstall from, nil for default LuaDist directory.
-- @param dest string: Optional destination for the result
-- @return ok, log: Returns true on success. nil on error and log message.
function pack(names, deployment, dest)
	-- Make sure deployment path is absolute and set
	deployment = sys.path(deployment or getDeployment())	

	-- Make sure names are always in a table
	if type(names) == "string" then names = {names} end

	-- Check types
	assert(type(names) == "table" , "dist.pack: Argument 'names' is not a string or table.")
	assert(type(deployment) == "string", "dist.pack: Argument 'deployment' is not a string.")

	-- Find dists
	local dists = findDists(names, getInstalled(deployment))
	if not dists then return nil, "Nothing to pack." end

	-- Pack the dists
	for _, dist in pairs(dists) do
		local ok, err = package.pack(dist.path, deployment, dest)
		if not ok then return nil, "Failed to pack dist " .. dist.name .. "-" .. dist.version end
	end
	return true, "Pack Successful."
end

--- Get deployment directory.
-- @return path: Full path to the LuaDist install directory
function getDeployment()
	return cfg.root
end
