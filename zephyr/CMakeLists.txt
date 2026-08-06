# SPDX-License-Identifier: MIT

if(CONFIG_BOARD_OWLAB_LINK_HOTSWAP)
  zephyr_linker_sources(
    RAM_SECTIONS
    ${CMAKE_CURRENT_LIST_DIR}/link65_boot_stacks.ld
  )
endif()
