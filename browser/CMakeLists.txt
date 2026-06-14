cmake_minimum_required(VERSION 3.16)

project(mb-browser LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick WebEngineQuick)

add_executable(mb-browser
    main.cpp
    resources.qrc
)

target_link_libraries(mb-browser PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::WebEngineQuick
)
