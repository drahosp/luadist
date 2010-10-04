# Copyright (C) 2007-2010 LuaDist.
# Created by Peter Drahoš
# Redistribution and use of this file is allowed according to the terms of the MIT license.
# For details see the COPYRIGHT file distributed with LuaDist.
# Please note that the package source code is licensed under its own license.

PROJECT (luadist NONE)
CMAKE_MINIMUM_REQUIRED(VERSION 2.6)
INCLUDE(dist.cmake)

# Determine symlink behavior.
IF (CYGWIN)
	SET(DIST_SYMLINKS false CACHE BOOL "Use symlinks to deploy files. (NOTE: While Cygwin supports symlinks it cannot load symlinked dynamic libraties as it relies on Windows built in dynamic linker. This feature is therefore not available under Cygwin.)")
ELSEIF (WIN32)
	SET (DIST_SYMLINKS false CACHE BOOL "Use symlinks to deploy files. (NOTE: This feature is not available on Windows)")
ELSE ()
	SET (DIST_SYMLINKS true CACHE BOOL "Use symlinks to deploy files.")
ENDIF ()
MESSAGE ("-- Symlinks allowed - ${DIST_SYMLINKS}")

CONFIGURE_FILE(lmod/dist/config.lua.in ${CMAKE_CURRENT_BINARY_DIR}/dist/config.lua @ONLY)

IF (NOT DIST_BOOTSTRAP)	
	INSTALL(FILES ${CMAKE_CURRENT_BINARY_DIR}/dist/config.lua DESTINATION ${INSTALL_LMOD}/dist/ )
	INSTALL(PROGRAMS luadist DESTINATION ${INSTALL_BIN})
	INSTALL(DIRECTORY lmod/ DESTINATION ${INSTALL_LMOD} PATTERN ".git" EXCLUDE PATTERN "*.in" EXCLUDE)
	INSTALL(FILES COPYRIGHT README DESTINATION ${INSTALL_DATA})
#	INSTALL(DIRECTORY etc doc DESTINATION ${INSTALL_DATA} PATTERN ".git" EXCLUDE)
ENDIF (NOT DIST_BOOTSTRAP)
