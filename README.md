# ZMK for Owlab LINK65

Experimental wired ZMK support for the Owlab LINK65 hotswap PCB.

## Hardware target

- Expected MCU: Geehy APM32F103CBT6, used through Zephyr's STM32F103xB support
- CPU: Arm Cortex-M3 at 72 MHz from an 8 MHz HSE
- Memory: 128 KiB flash and 20 KiB SRAM
- USB: full-speed device on PA11/PA12
- Matrix: 5 rows by 15 columns, 67 populated positions, COL2ROW
- Wireless: not supported by the stock PCB

Check the marking on U3 before flashing. Stop if the installed MCU is not an
APM32F103CBT6 or another verified 128 KiB STM32F103xB-compatible part.

## Flash layout

| Region | Address range | Size |
| --- | --- | ---: |
| Factory bootloader | `0x08000000`-`0x08005FFF` | 24 KiB |
| ZMK application | `0x08006000`-`0x0801FFFF` | 104 KiB |

The first bring-up firmware intentionally has no settings/storage partition and
does not enable ZMK Studio. Never mass-erase the controller and never flash an
application at `0x08000000`.

## Build

The repository is pinned to ZMK v0.3.0. Push the branch or manually dispatch the
GitHub Actions workflow; the expected artifact is
`owlab_link_hotswap-zmk.bin`.

Before flashing, inspect the build output and confirm all of the following:

- `CONFIG_FLASH_SIZE=128`
- `CONFIG_SRAM_SIZE=20`
- `CONFIG_FLASH_LOAD_OFFSET=0x6000`
- the first flash load segment in `zmk.elf` starts at `0x08006000`
- no load segment targets an address below `0x08006000`
- the firmware fits within `0x1A000` bytes of flash and 20 KiB of SRAM

## Safe flashing and rollback

Keep a known-good LINK65 Vial firmware available before testing.

1. Disconnect the keyboard.
2. Hold the physical **B** button while reconnecting it.
3. Run `dfu-util -l` and confirm the bootloader reports USB ID `1688:2220` and
   alternate setting 0.
4. Flash only after the ID and firmware layout have both been verified:

   ```text
   dfu-util -d 1688:2220 -a 0 -s 0x08006000:leave -D owlab_link_hotswap-zmk.bin
   ```

Use the same address to restore the known-good Vial `.bin`. The physical B
button is the supported bootloader-entry method; the first ZMK firmware does not
attempt a software jump into the factory bootloader. `Left Ctrl + Left Alt +
Backspace` performs a normal application reset.

## First hardware acceptance test

After flashing, verify that the board enumerates as a USB HID keyboard, test all
67 positions with a key tester, cold-boot it three times, and confirm the
physical B button still enters the factory bootloader. In particular, test the
last matrix column because it uses PA15, which must be released from JTAG.
