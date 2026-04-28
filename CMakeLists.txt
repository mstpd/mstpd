cmake_minimum_required(VERSION 3.12)

PROJECT(ustp C)

set(THREADS_PREFER_PTHREAD_FLAG ON)
find_package(Threads)

ADD_DEFINITIONS(-Os -Wall -Werror --std=gnu99 -g3 -Wmissing-declarations -Wno-error=missing-declarations -I${CMAKE_SOURCE_DIR})

ADD_EXECUTABLE(ustpd bridge_track.c brmon.c hmac_md5.c libnetlink.c mstp.c netif_utils.c packet.c worker.c config.c main.c ubus.c)
TARGET_LINK_LIBRARIES(ustpd ubox ubus Threads::Threads)

SET(CMAKE_INSTALL_PREFIX /)

INSTALL(TARGETS ustpd
	RUNTIME DESTINATION sbin
)
INSTALL(FILES scripts/bridge-stp
	DESTINATION sbin
)
