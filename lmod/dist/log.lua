--- LuaDist simple message logger
-- Peter Drahoš, Peter Kapec, LuaDist Project, 2010

--- Very simple log system.
-- 2DO: change to LuaLogging on next version.
-- write - write a log line
-- message - write and optionally display a message

module ("dist.log", package.seeall)

local lfs 		= require "lfs"
local config	= require "dist.config"

-- Profile to store info in
lfs.mkdir(config.temp)
local log = assert(io.open(config.log, "a"), "Could not create log file!")

--- Display and log a message
function message(...)
	if config.message then config.message(...) end
	return write(...)
end

--- Write a line to log
function write(...)

	local args = ...
	if type(...) == "string" then args = { ... } end
	if type(args) ~= "table" then return nil end

	log:write(os.date("%c", os.time()) .. ":: ")
	for i = 1, #args do
		log:write(tostring(args[i]) .. " ")
	end
	log:write("\n")
	log:flush()
end
