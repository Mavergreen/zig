cmake_minimum_required(VERSION 3.16)
set(ZIG_VARIANT "native" CACHE STRING "which product this updater updates: native | cross")
if(ZIG_VARIANT STREQUAL "native")
  set(CMAKE_OSX_DEPLOYMENT_TARGET 10.9 CACHE STRING "")
  set(CMAKE_OSX_ARCHITECTURES x86_64 CACHE STRING "")
  set(_short zig)
  set(_product "Mavericks Zig")
elseif(ZIG_VARIANT STREQUAL "cross")
  set(CMAKE_OSX_DEPLOYMENT_TARGET 11.0 CACHE STRING "")
  set(CMAKE_OSX_ARCHITECTURES arm64 CACHE STRING "")
  set(_short zig-cross)
  set(_product "Mavericks Zig (cross)")
else()
  message(FATAL_ERROR "ZIG_VARIANT must be 'native' or 'cross' (got '${ZIG_VARIANT}')")
endif()
project(ZigUpdater LANGUAGES OBJC)
find_package(MavericksShipyard REQUIRED)
# spec: shipyard SKILL.md "Sparkle updater" -- build/build-updater.sh configures this with clang22, not AppleClang
set(MAVERICKS_REQUIRE_APPLECLANG OFF)
include(Mavericks)
include(MavericksSparkle)
mavericks_resolve_version(MAV_ZIG_VERSION)
mavericks_add_updater_app(
  PRODUCT ${_short}
  PRODUCT_NAME "${_product}"
  VERSION "${MAV_ZIG_VERSION}"
  LOG_PREFIX "MavZigUpdater"
  CONFIRM_TITLE "${_product} updated"
  CONFIRM_BODY "Zig for Mavericks in /usr/local/mavergreen/${_short} was updated."
)
