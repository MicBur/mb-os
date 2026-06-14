cmake_minimum_required(VERSION 3.16)

project(mb-os-shell LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick Qml)

add_executable(mb-os-shell
    main.cpp
    ThemeManager.h
    ThemeManager.cpp
    resources.qrc
)

target_link_libraries(mb-os-shell PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
)
