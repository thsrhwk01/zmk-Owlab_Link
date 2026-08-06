board_runner_args(dfu-util "--pid=1688:2220" "--alt=0" "--dfuse")
board_runner_args(jlink "--device=STM32F103CB" "--speed=4000")

include(${ZEPHYR_BASE}/boards/common/dfu-util.board.cmake)
include(${ZEPHYR_BASE}/boards/common/jlink.board.cmake)
