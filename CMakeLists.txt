# Copyright (C) 2007-2010 LuaDist.
# Created by Peter Drahoš
# Redistribution and use of this file is allowed according to the terms of the MIT license.
# For details see the COPYRIGHT file distributed with LuaDist.
# Please note that the package source code is licensed under its own license.

PROJECT (luadist NONE)
CMAKE_MINIMUM_REQUIRED(VERSION 2.6)
INCLUDE(dist.cmake)

CONFIGURE_FILE(lmod/dist/config.lua.in ${CMAKE_CURRENT_BINARY_DIR}/dist/config.lua @ONLY)

IF (NOT DIST_BOOTSTRAP)	
	INSTALL(FILES ${CMAKE_CURRENT_BINARY_DIR}/dist/config.lua DESTINATION ${INSTALL_LMOD}/dist/ )
	INSTALL(PROGRAMS luadist DESTINATION ${INSTALL_BIN})
	INSTALL(DIRECTORY lmod/ DESTINATION ${INSTALL_LMOD} PATTERN ".git" EXCLUDE PATTERN "*.in" EXCLUDE)
	INSTALL(FILES COPYRIGHT README DESTINATION ${INSTALL_DATA})
ENDIF (NOT DIST_BOOTSTRAP)
