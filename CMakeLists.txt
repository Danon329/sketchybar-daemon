cmake_minimum_required(VERSION 3.20)

project(sketchybar_daemon LANGUAGES CXX OBJCXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_compile_options($<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>)

set(SRC
	src/main.mm
)

add_executable(${PROJECT_NAME} ${SRC})

target_include_directories(${PROJECT_NAME} PRIVATE
	${CMAKE_CURRENT_SOURCE_DIR}/include
)

target_link_libraries(${PROJECT_NAME} PRIVATE
	"-framework AppKit"
	"-framework ApplicationServices"
	"-framework Foundation"
)
