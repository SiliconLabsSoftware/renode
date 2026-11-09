cmake_minimum_required(VERSION 3.10)

project(librenode_api)

# socket: connects to a Renode server over TCP
# in_process: connects to the Renode instance that runs in the same program through librenode
if(NOT DEFINED RENODE_API_TRANSPORT)
    set(RENODE_API_TRANSPORT socket)
endif()

if(RENODE_API_TRANSPORT STREQUAL "socket")
    set(transport_source connection.c)
elseif(RENODE_API_TRANSPORT STREQUAL "in_process")
    set(transport_source connection_in_process.c)
else()
    message(FATAL_ERROR "Unknown RENODE_API_TRANSPORT '${RENODE_API_TRANSPORT}', expected 'socket' or 'in_process'")
endif()

set(renode_api_sources
    ${CMAKE_CURRENT_LIST_DIR}/renode_api.c
    ${CMAKE_CURRENT_LIST_DIR}/${transport_source}
    ${CMAKE_CURRENT_LIST_DIR}/silabs_time.c
    )

# The host-library build passes -DCMAKE_BUILD_SHARED_LIBS=ON so silabs_time.c
# can interpose clock_gettime and gettimeofday. A plain add_library() would
# ignore that variable because CMake only honors BUILD_SHARED_LIBS.
if(CMAKE_BUILD_SHARED_LIBS)
    add_library(renode_api SHARED ${renode_api_sources})
else()
    add_library(renode_api STATIC ${renode_api_sources})
endif()

target_compile_options(renode_api
    PRIVATE
    -Wall
    -Werror
    -Wextra
    -fno-strict-aliasing
    )
set_property(TARGET renode_api PROPERTY POSITION_INDEPENDENT_CODE ON)

find_package(Threads REQUIRED)
target_link_libraries(renode_api PRIVATE Threads::Threads)

if(RENODE_API_TRANSPORT STREQUAL "in_process")
    if(NOT TARGET renode::renode)
        include(${CMAKE_CURRENT_LIST_DIR}/../../NativeInterface/cmake/renode.cmake)
    endif()
    target_compile_definitions(renode_api PRIVATE RENODE_API_TRANSPORT_IN_PROCESS)
    target_link_libraries(renode_api PUBLIC renode::renode)
endif()

target_include_directories(
    renode_api
    PUBLIC ${CMAKE_CURRENT_LIST_DIR}/../include
    )

include(${CMAKE_CURRENT_LIST_DIR}/RenodeAPISanitizers.cmake)
renode_api_add_sanitizers_flags(renode_api)
