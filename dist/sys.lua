--- LuaDist UNIX and Windows system functions
-- Peter Drahoš, LuaDist Project, 2010
-- Original Code contributed to and then borrowed back from the LuaRocks Project

--- Host system dependent commands.
-- Override the default UNIX commands if needed for your platform.
-- Commands currently depend on popen and unzip being available. For future releases we would like
-- to use lua packages handling the compression issues. Additionally some filesystem functionality
-- not available in luafilesystem is emulated here.

module ("dist.sys", package.seeall)

local log	= require "dist.log"
local config	= require "dist.config"
local lfs	= require "lfs"

--- Quote argument for shell processing.
-- Adds single quotes and escapes.
-- @param arg string: Unquoted argument.
-- @return string: Quoted argument.
function Q(arg)
	assert(type(arg) == "string", "Q argument 'arg' is not a string.")

	return "'" .. arg:gsub("\\", "\\\\"):gsub("'", "'\\''") .. "'"
end

--- Compose full system path or part of url
-- @args string: Path components
-- @return string: Path string
function path(...)
	local args = ...
	--if not args then return curDir() end
	if type(...) == "string" then args = { ... } end
	if type(args) ~= "table" then return nil end
	
	if args[1]:match("^[%a:]*[/\\]") then
		return table.concat(args,"/")
	end
	return curDir() .. "/" .. table.concat(args,"/")
end

--- Run the given system command.
-- The command is executed in the current directory in the dir stack.
-- @param cmd string: No quoting/escaping is applied to the command.
-- @return boolean: True if command succeeds, false otherwise.
function executeString(cmd)
	assert(type(cmd) == "string", "sys.executeString: Argument 'cmd' is not a string.")
	
	-- Command log
	local execPath = path(config.temp, "execute.log")
	
	-- Hande std output
	local run = cmd
	if not ( config.verbose or config.debug) then 
		run = run .. " >" .. execPath .. " 2>&1"
	end
	
	-- Run the command
	local ok = os.execute( run )

	-- Append the execution log to the log
	local execFile, err = io.open( execPath, "r")
	if execFile then
		assert(execFile, "sys.executeString: Cannot create log.")
		log.write("Command: " .. cmd .. "\n" .. execFile:read("*all") .. "\n")
		execFile:close()
		if not config.debug then os.remove(execPath) end
	end
	
	if ok~=0 then return nil, "Failed running command: " .. cmd end
	return true, "Sucessfully executed command: " .. cmd
end

--- Run the given system command, quoting its arguments.
-- The command is executed in the current directory in the dir stack.
-- @param command string: The command to be executed. No quoting/escaping need to be applied.
-- @param ... strings: containing additional arguments, which are quoted.
-- @return ok, log: true on success, false on failure and log message.
function execute(command, ...)
	assert(type(command) == "string", "execute argument 'command' is not a string.")

	for k, arg in ipairs({...}) do
		assert(type(arg) == "string", "execute argument #" .. tostring(k+1) .. "is not a string.")
		command = command .. " " .. Q(arg)
	end
	return executeString(command)
end

--- Create a directory.
-- @param dir string: Path to create.
-- @return ok, log: true on success, false on failure and log message.
-- Succeeds if already exists.
function makeDir(dir)
	assert(type(dir)=="string", "sys.makeDir: Argument 'dir' is not a string.")
	dir = path(dir)

	if isDir(dir) then return true end -- done

	-- Find out if the base dir exists, if not make it
	local base = dir:gsub("/[^/]*$","")
	if base == "" then base = "/" end
	-- Recursion!
	if not isDir(base) then makeDir(base) end

	-- Make directory
	local ok = lfs.mkdir(dir)
	if not ok then return nil, "Cannot create directory: " .. dir end
	return true, "Created directory: " .. dir
	end

--- Force delete a file, even if it is open.
-- If the file can't be deleted because it is currently open, this function
-- will try to rename the file to a temporary file in the same directory.
-- Windows in particular doesn't allow running executables to be deleted, but
-- it does allow them to be renamed.  Cygwin 1.7 (unlike 1.5) does allow such
-- deletion but internally implements it via a mechanism like this.  For
-- futher details, see
-- http://sourceforge.net/mailarchive/message.php?msg_name=bc4ed2190909261323i7c6280bfp6e7be6f70c713b0c%40mail.gmail.com
--
-- @param src - file name
function forceDelete(src)
	os.remove(src) -- note: ignore fail

	if exists(src) then -- still exists, try move instead
		local tempfile
		local MAX_TRIES = 10
		for i=1,MAX_TRIES do
			local test = src .. ".luadist-temporary-" .. i
			os.remove(test) -- note: ignore fail
			if not exists(test) then
				tempfile = test
				break
			end
		end
		if not tempfile then
			return nil, "Failed removing temporary files: " .. tempfile .. "*"
		end
		local ok, err = os.rename(src, tempfile)
		if not ok then
			return nil, "Failed renaming file: " .. err
		end
	end
	return true
end

--- Move a file from one location to another.
-- @param src string: Pathname of source.
-- @param dest string: Pathname of destination.
-- @return ok, log: true on success, false on failure and log message.
function move(src, dest)
	assert(type(src)=="string", "sys.move: Argument 'src' is not a string.")
	assert(type(dest)=="string", "sys.move: Argument 'dest' is not a string.")
	
	local ok, err = execute("mv -f", src, dest)
	if not ok then return nil, "Failed moving source: " .. src .. " to: " .. dest .. " error: " .. err end
	return true, "Moved source: " .. src .. " to: " .. dest
end

--- Recursive copy a file or directory.
-- @param src string: Pathname of source
-- @param dest string: Pathname of destination.
-- @param copy_contents boolean: if true, copies contents of
--        directory src into directory dest, creating dest
--        and parents of dest if they don't exist. (false if omitted)
-- @return ok, log: true on success, false on failure and log message.
function copy(src, dest, copy_contents)
	assert(type(src)=="string", "copy argument 'src' is not a string.")
	assert(type(dest)=="string", "copy argument 'dest' is not a string.")

	if copy_contents and not isDir(dest) then
		local ok, err = makeDir(dest)
		if not ok then return nil, err end
	end

	local ok, err
	if copy_contents then
		ok, err = execute("cp -R -f -H " .. Q(src) .. [[/*]], dest)
	else
		ok, err = execute("cp -R -f -H ", src, dest)
	end
	if not ok then return nil, "Failed copying " .. src .. " to " .. dest .. ".\n" .. err end
	return true
end

--- little helper function to get file depth (for directories its +1)
local function pathLen(dir)
	local _, len = dir:gsub("[^\\/]+","")
	return len - 1
end

--- Delete a file or a directory and all its contents.
-- For safety, this only accepts absolute paths.
-- @param dir string: Pathname of the file or directory to delete
-- @return ok, log: true on success, false on failure and log message. Returns success if already deleted.
function delete(dir)
	assert(type(dir)=="string" and dir:match("^[%a:]*[/\\]"), "delete argument 'dir' is not a string or a full path.")
	if not exists(dir) then return true end
	return executeString("rm -rf " .. Q(dir))
end

--- List the contents of a directory.
-- @param path string: directory to list if not specified the current directory will be used.
-- @return table: an array of strings with the filenames representing the contents of a directory.
function dir(dir)
	assert(not dir or type(dir) == "string", "dir argument 'dir' is not a string.")
	dir = dir or curDir()	
	if not isDir(dir) then return nil, "Could not find directory " .. dir .. "." end
	local files = {}
	for file in lfs.dir(dir) do
		if not file:match("^%.") then table.insert(files, file) end
	end
	return files
end

--- Get current directory.
-- @return string: current direcotry.
function curDir()
	local dir, err = lfs.currentdir()
	if not dir then return nil, err end
	return dir:gsub("\\","/") -- Everyone loves win32
end

--- Test for existance of a file.
-- @param path string: filename to test
-- @return ok, log: true on success, false on failure and log message.
function exists(dir)
	assert(type(dir)=="string", "exists argument 'dir' is not a string.")
	return lfs.attributes(dir)
end

--- Test is pathname is a directory.
-- @param path string: pathname to test
-- @return ok, log: true on success, false on failure and log message.
function isDir(dir)
	assert(type(dir)=="string", "isDir argument 'dir' is not a string.")
	local attr, err = lfs.attributes(dir)
	if not attr then return nil, "Failed to obtain attributes for " .. dir .. "." end
	return attr.mode == "directory"
end

--- Test is pathname is a file.
-- @param path string: pathname to test
-- @return ok, log: true on success, false on failure and log message.
function isFile(dir)
	assert(type(dir)=="string", "isFile argument 'dir' is not a string.")
	local attr, err = lfs.attributes(dir)
	if not attr then return nil, "Failed to obtain attributes for " .. dir .. "." end
	return attr.mode == "file"
end

--- Recursively list the contents of a directory.
-- @param path string: directory to list if not specified the current directory will be used
-- @return table: an array of strings representing the contents of the directory structure
function list(dir)
	assert(type(dir)=="string", "list argument 'path' is not a string.")
	if not isDir(dir) then return nil, "Directory " .. dir .. " does not exist." end
	
	local files = {}
	
	local function collect (subdir)
		subdir = subdir or ""
		for file in lfs.dir(path(dir, subdir)) do
			if not file:match("^%.") then
				table.insert(files, subdir .. file)
				if isDir(path(dir, subdir .. file)) then collect(subdir .. "/" .. file .. "/") end
			end
		end
	end
	collect()
	return files
end

--- Compress files in a .zip archive.
-- @param zipfile string: pathname of .zip archive to be created.
-- @param ... Filenames to be stored in the archive are given as additional arguments.
-- @return ok, log: true on success, false on failure and log message.
function zip(workdir, zipfile, ...)
	assert (type(workdir)=="string", "zip argument 'workdir' is not a string.")
	assert (type(zipfile)=="string", "zip argument 'zipfile' is not a string.")
	return execute("cd " .. Q(workdir) .. " && "..config.root.."/bin/zip -r", zipfile, ...) or 
		execute("cd " .. Q(workdir) .. " && zip -r", zipfile, ...)
end

--- Unpack an archive.
-- Extract the contents of an archive, detecting its format by filename extension.
-- @param archive string: Filename of archive.
-- @return ok, log: true on success, false on failure and log message.
function unzip(archive, dest)
	assert(type(archive) == "string", "unpack argument 'archive' is not a string.")
	assert(type(dest) == "string", "unpack agrument 'dest' is not a string.")
	local ok
	if archive:match("%.zip$") or archive:match("%.dist$") then
		ok = executeString(config.root.."/bin/unzip " .. Q(archive) .. " -d " .. Q(dest)) or
			executeString("unzip " .. Q(archive) .. " -d " .. Q(dest))
	end
	if not ok then
		return false, "Failed extracting."
	end
	return dest
end

--- Extract file contents of a file from archive
-- @param zipfile string: pathname of .zip/.dist archive to read from.
-- @param file string: file to get contents of.
-- @return contents, err: returns contents of file or false and error message.
-- Requires io.popen (2DO: work when io.popen not available?)
function getZipFile(zipfile, file)
	assert(type(zipfile) == "string", "unpack argument 'zipfile' is not a string.")
	assert(type(file) == "string", "unpack agrument 'file' is not a string.")
	
	-- Try to get contents
	local f, err = io.popen(config.root.."/bin/unzip -cp " .. Q(zipfile) .. " " .. Q(file))	or
		io.popen("unzip -cp " .. Q(zipfile) .. " " .. Q(file))
	if not f then return false, "Failed to extract " .. file .. " from " .. zipfile end

	-- Read result
	local content = f:read("*a")
	f:close()
	if content == "" then return false, "Failed to extract " .. file .. " from " .. zipfile end
	return content 
end

--- Override different functions for Windows
if config.arch == "Windows" then 

	--- Quote argument for shell processing (Windows).
	-- Adds single quotes and escapes.
	-- @param arg string: Unquoted argument.
	-- @return string: Quoted argument.
	function Q(arg)
		assert(type(arg) == "string", "Q argument 'arg' is not a string.")
		-- Quote DIR for Windows
		if arg:match("^[\.a-zA-Z]?:?[\\/]")  then
			return '"' .. arg:gsub("//","\\"):gsub("/", "\\"):gsub('"', '\\"') .. '"'
		end
		-- URLs and anything else
		return '"' .. arg:gsub('"', '\\"') .. '"'
	end

	--- Move a file from one location to another (Windows).
	-- @param src string: Pathname of source.
	-- @param dest string: Pathname of destination.
	-- @return ok, log: true on success, false on failure and log message.
	function move(src, dest)
		assert(type(src)=="string", "sys.move: Argument 'src' is not a string.")
		assert(type(dest)=="string", "sys.move: Argument 'dest' is not a string.")

		-- note: copy+delete may be more reliable than move (e.g. copy across drives).
		-- [improve: cleanup on failure?]
		local ok, err = copy(src, dest)
		if ok then
			ok, err = delete(src)
		end
		if not ok then return nil, "Failed moving source: " .. src .. " to: " .. dest .. " error: " .. err end
		return true, "Moved source: " .. src .. " to: " .. dest
	end

	--- Recursive copy a file or directory (Windows).
	-- @param src string: Pathname of source
	-- @param dest string: Pathname of destination.
	-- If `src` is a directory, copies contents of `src` into contents of
	-- directory `dest`.  Otherwise, both must represent files.
	-- @return ok, log: true on success, false on failure and log message.
	function copy(src, dest)
		assert(type(src)=="string", "copy argument 'src' is not a string.")
		assert(type(dest)=="string", "copy argument 'dest' is not a string.")

		-- Avoid ambiguous behavior: file <-> directory
		--2DO - Improve?
		if isFile(src) then
			if isDir(dest) then
				return nil, "ambiguous request to copy file " .. src .. " to directory " .. dest
			end
		elseif isDir(src) then
			if isFile(dest) then
				return nil, "ambiguous request to copy directory " .. src .. " to file " .. dest
			end
		end

		--2DO: The below will cause problems if src and dest are the same.

		-- For any destination files that will be overwritten,
		-- force delete them to avoid conflicts from open files
		-- in subsequent copy.
		if isDir(src) then
			local srcfiles = list(src)
			for i = 1, #srcfiles do
				local destfile = path(dest, srcfiles[i])
				if isFile(destfile) then
					local ok, err = forceDelete(destfile)
					if not ok then return nil, "Failed removing file: " .. destfile .. " " .. err end
				end
			end
		elseif isFile(src) then
			local ok, err = forceDelete(dest)
			if not ok then return nil, "Failed removing file: " .. dest .. " " .. err end
		end

		local ok, err
		if isDir(src) then
			-- note: "xcopy /E /I /Y" copies contents of `src` into contents
			-- of `dest` and creates all leading directories of `dest` if needed.
			ok, err = execute("xcopy /I /E /Y " .. Q(src), dest)
		else
			ok, err = execute("copy /Y", src, dest)
		end
		if not ok then return nil, "Failed copying " .. src .. " to " .. dest .. ".\n" .. err end
		-- note: The /Q flag on xcopy is not fully quiet; it prints
		-- "1 File(s) copied".  Copy lacks a /Q flag.

		return true
	end

	--- Delete a file or a directory and all its contents (Windows).
	-- For safety, this only accepts absolute paths.
	-- @param dir string: Pathname of the file or directory to delete
	-- @return ok, log: true on success, false on failure and log message.
	--   Returns success if already deleted.
	function delete(dir)
		assert(type(dir)=="string" and dir:match("^[%a:]*[/\\]"), "delete argument 'dir' is not a string or a full path.")
		-- Note: `del /S` recursively deletes files but not directories.
		-- `rmdir /S` recursively deletes files and directories but does not
		-- work if its parameter is a file.
		if not exists(dir) then
			return true
		elseif isDir(dir) then
			local ok, err = executeString("rmdir /S /Q " .. Q(dir))
			if not ok then
				return nil, "Could not recursively delete directory " .. dir .. " . " .. err
			end
		else
			local ok, err = os.remove(dir)
			if not ok then
				return nil, "Could not delete file " .. dir .. " . " .. err
			end
		end
		return true
	end
end
