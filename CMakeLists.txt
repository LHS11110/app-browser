cmake_minimum_required(VERSION 3.21)

# Default to Release build if not specified
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Choose the type of build (Debug or Release)" FORCE)
endif()

project(AppBrowser LANGUAGES C CXX OBJC OBJCXX)

set_property(GLOBAL PROPERTY USE_FOLDERS ON)

# -----------------------------------------------------------------------------
# 1. CEF Configuration
# -----------------------------------------------------------------------------
if(NOT DEFINED CEF_ROOT)
  set(CEF_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/third_party/cef")
endif()

if(NOT EXISTS "${CEF_ROOT}/cmake/FindCEF.cmake")
  message(FATAL_ERROR "CEF binary distribution not found at: ${CEF_ROOT}\nPlease run ./scripts/setup_cef.sh to download and set up CEF.")
endif()

set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CEF_ROOT}/cmake")
find_package(CEF REQUIRED)

# Build libcef_dll_wrapper
add_subdirectory(${CEF_LIBCEF_DLL_WRAPPER_PATH} libcef_dll_wrapper)

# Print CEF configuration summary
PRINT_CEF_CONFIG()

# -----------------------------------------------------------------------------
# 2. Target Definition
# -----------------------------------------------------------------------------
set(CEF_TARGET "AppBrowser")
if(OS_MAC)
  set(CEF_HELPER_TARGET "${CEF_TARGET}_Helper")
  set(CEF_HELPER_OUTPUT_NAME "${CEF_TARGET} Helper")
endif()

SET_CEF_TARGET_OUT_DIR()

# Source files
set(APP_SOURCES
  src/main_mac.mm
  src/app_mac.mm
  src/client.mm
  src/app.h
  src/client.h
  src/config.h
)

set(APP_HELPER_SOURCES
  src/helper_mac.cc
)

# -----------------------------------------------------------------------------
# 3. macOS Application Bundle Configuration
# -----------------------------------------------------------------------------
if(OS_MAC)
  option(OPTION_USE_ARC "Build with ARC (Automatic Reference Counting) on macOS." ON)
  if(OPTION_USE_ARC)
    list(APPEND CEF_COMPILER_FLAGS -fobjc-arc)
  endif()

  set(CEF_APP "${CEF_TARGET_OUT_DIR}/${CEF_TARGET}.app")
  set(EXECUTABLE_NAME "${CEF_TARGET}")
  set(PRODUCT_NAME "${CEF_TARGET}")

  # Main app bundle target
  add_executable(${CEF_TARGET} MACOSX_BUNDLE ${APP_SOURCES})
  SET_EXECUTABLE_TARGET_PROPERTIES(${CEF_TARGET})

  # Ensure C++20 is applied to Objective-C++ (.mm) files as well
  target_compile_options(${CEF_TARGET} PRIVATE
    $<$<COMPILE_LANGUAGE:OBJCXX>:${CEF_COMPILER_FLAGS} ${CEF_CXX_COMPILER_FLAGS}>
    $<$<AND:$<COMPILE_LANGUAGE:OBJCXX>,$<CONFIG:Debug>>:${CEF_COMPILER_FLAGS_DEBUG} ${CEF_CXX_COMPILER_FLAGS_DEBUG}>
    $<$<AND:$<COMPILE_LANGUAGE:OBJCXX>,$<CONFIG:Release>>:${CEF_COMPILER_FLAGS_RELEASE} ${CEF_CXX_COMPILER_FLAGS_RELEASE}>
  )

  add_dependencies(${CEF_TARGET} libcef_dll_wrapper)
  target_link_libraries(${CEF_TARGET} libcef_dll_wrapper ${CEF_STANDARD_LIBS})

  target_include_directories(${CEF_TARGET} PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CEF_ROOT}
  )

  set_target_properties(${CEF_TARGET} PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_SOURCE_DIR}/resources/mac/Info.plist.in
  )

  # Copy Chromium Embedded Framework.framework into the app bundle
  COPY_MAC_FRAMEWORK("${CEF_TARGET}" "${CEF_BINARY_DIR}" "${CEF_APP}")

  # Create Helper targets (Main helper, GPU, Plugin, Renderer)
  foreach(_suffix_list ${CEF_HELPER_APP_SUFFIXES})
    string(REPLACE ":" ";" _suffix_list ${_suffix_list})
    list(GET _suffix_list 0 _name_suffix)
    list(GET _suffix_list 1 _target_suffix)
    list(GET _suffix_list 2 _plist_suffix)

    set(_helper_target "${CEF_HELPER_TARGET}${_target_suffix}")
    set(_helper_output_name "${CEF_HELPER_OUTPUT_NAME}${_name_suffix}")

    set(_helper_info_plist "${CMAKE_CURRENT_BINARY_DIR}/helper-Info${_target_suffix}.plist")
    file(READ "${CMAKE_CURRENT_SOURCE_DIR}/resources/mac/helper-Info.plist.in" _plist_contents)
    string(REPLACE "\${EXECUTABLE_NAME}" "${_helper_output_name}" _plist_contents ${_plist_contents})
    string(REPLACE "\${PRODUCT_NAME}" "${_helper_output_name}" _plist_contents ${_plist_contents})
    string(REPLACE "\${BUNDLE_ID_SUFFIX}" "${_plist_suffix}" _plist_contents ${_plist_contents})
    file(WRITE ${_helper_info_plist} ${_plist_contents})

    add_executable(${_helper_target} MACOSX_BUNDLE ${APP_HELPER_SOURCES})
    SET_EXECUTABLE_TARGET_PROPERTIES(${_helper_target})
    add_dependencies(${_helper_target} libcef_dll_wrapper)
    target_link_libraries(${_helper_target} libcef_dll_wrapper ${CEF_STANDARD_LIBS})

    target_include_directories(${_helper_target} PRIVATE
      ${CMAKE_CURRENT_SOURCE_DIR}
      ${CEF_ROOT}
    )

    set_target_properties(${_helper_target} PROPERTIES
      MACOSX_BUNDLE_INFO_PLIST ${_helper_info_plist}
      OUTPUT_NAME ${_helper_output_name}
    )

    add_dependencies(${CEF_TARGET} "${_helper_target}")

    add_custom_command(
      TARGET ${CEF_TARGET}
      POST_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy_directory
              "${CEF_TARGET_OUT_DIR}/${_helper_output_name}.app"
              "${CEF_APP}/Contents/Frameworks/${_helper_output_name}.app"
      VERBATIM
    )
  endforeach()
endif()
