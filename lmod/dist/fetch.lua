--- LuaDist URL fetch functions
-- Peter Drahoš, LuaDist Project, 2010

--- This module is responsible for downloading contents using URIs. 
-- It should handle at least HTTP and FILE URIs as well as system paths transparently.
-- 2DO: support for more protocols if demanded.
-- Two functions are provided. Notice that http requests are cached.
-- download - To download dists.
-- get - To directly obtain manifests.

module ("dist.fetch", package.seeall)

local config 	= require "dist.config"
local sys 		= require "dist.sys"
local log		= require "dist.log"

--- Fetch file from URI into destination.
-- @param src string: URI to fetch file from. Accepts paths too.
-- @param dest string: Destination dir, if not provided temporary dir will be used.
-- @return path, log: Path the file was downloaded and the resulting log message.
function download(src, dest)
	assert(type(src) == "string", "fetch.download: Argument 'src' is not a string.")
	assert(not dest or type(dest) == "string", "fecth.download: Argument 'dest' is not a string.")
	
	-- Dont waste time
	if src == dest then return true end
	
	-- Make sure all paths are absolute and set
	dest = sys.path(dest) or config.temp
	src = sys.path(src)
	
	-- Test destination existstence
	local ok, err = sys.isDir(dest)
	if not ok then return nil, "Destination " .. dest .. " is not a directory." end
	
	-- Construct destination filename
	local name = src:match("([^/]+)$")
	dest = sys.path(dest, name)
	part = dest .. ".part"

	-- Test if the file is local
	local file = sys.path((src:gsub("^file://","")))
	if sys.isFile(file) then
		local ok, err = sys.copy(file, dest)
		if not ok then return nil, "Failed to coply local file " .. file .. " to " .. dest end
		return dest, "Succesfuly copied " .. file .. " to " .. dest
	elseif src:match("^file://") then
		return nil, "Failed to get contents of " .. src .. " error: not found"
	end -- else uncertain

	-- Cache check
	if config.cache then
		local md5 = require "md5"
		local lfs = require "lfs"
		
		local path = sys.path(config.temp, "luadist_cache")
		local cache = sys.path(path, md5.sumhexa(src))
		
		if ((lfs.attributes(cache, "modification") or 0) + config.cache) > os.time() then
			sys.copy(cache, dest)
			return dest, "Retrieved from cache."
		end
	end

	local ltn12	= require "ltn12"
	local http  = require "socket.http"

	-- Remote download, for now just HTTP
	local request = {
		url = src,
		headers = {
			USERAGENT = "LuaDist",
			TIMEOUT = config.timeout,
		},
		proxy = config.proxy or nil,
		sink = ltn12.sink.file(assert(io.open(part, "wb"))),	
	}

	-- Download
	local ok, err = http.request(request)
	if ok then sys.move(part, dest) end

	-- Save cache
	if config.cache then
		local md5 = require "md5"
		
		local path = sys.path(config.temp, "luadist_cache")
		local cache = sys.path(path, md5.sumhexa(src))
		sys.makeDir(path)
		sys.copy(dest, cache)
	end
	
	if not ok then return nil, "Failed to get contents of " .. src .. " error: " .. err end
	return dest, "Succesfuly downloaded " .. src .. " to " .. dest
end

--- Directly get file contents from URI using luasocket.
-- @param src string: URI to fetch file from. Accepts paths too.
-- @return text, log: Contents of the URL file or nil and log message.
function get(src)
	assert(type(src) == "string", "fetch.get: Argument 'src' is not a string.")

	-- Test if file is local
	local file = sys.path((src:gsub("^file://","")))
	if sys.isFile(file) then
		local handle = io.open(file, "rb")
		if not handle then return nil, "Failed to get contents of " .. file end
		local ret = handle:read("*all")
		handle:close()
		return ret, "Succesfuly obtained contents of " .. file
	elseif src:match("^file://") then
		return nil, "Failed to get contents of " .. src .. " error: not found"
	end -- else uncertain

	-- Cache check
	if config.cache then
		local md5 = require "md5"
		local lfs = require "lfs"
		
		local path = sys.path(config.temp, "luadist_cache")
		local cache = sys.path(path, md5.sumhexa(src))
		
		if ((lfs.attributes(cache, "modification") or 0) + config.cache) > os.time() then
			local file = io.open(cache, "rb")
			if file then
				local data = file:read("*all")
				file:close()
				return data, "Retrieved from cache."
			end
		end
	end
	
	-- Download
	local ltn12	= require "ltn12"
	local http  = require "socket.http"

	-- Remote URIs	
	local contents = {}
	local request = {
		url = src,
		headers = {
			USERAGENT = "LuaDist",
			TIMEOUT = config.timeout,
		},
		proxy = config.proxy or nil,
		sink = ltn12.sink.table(contents),
	}
	if config.proxy then request.proxy = config.proxy end

	local ok, err = http.request(request)
	if not ok then return nil, "Failed to get contents of " .. src .. " error: " .. err end
	local data = table.concat(contents)
	
	-- Save cache
	if config.cache then
		local md5 = require "md5"
		
		local path = sys.path(config.temp, "luadist_cache")
		local cache = sys.path(path, md5.sumhexa(src))
		sys.makeDir(path)
		local file = io.open(cache, "wb")
		if file then
			file:write(data)
			file:close()
		end
	end
	
	return data, "Succesfuly obtained contents of " .. src
end
