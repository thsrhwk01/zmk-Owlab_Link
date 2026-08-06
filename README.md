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
| Factory bootloader | `0x08000000`-`0x080057FF` | 22 KiB |
| Vendor handoff data | `0x08005800`-`0x08005FFF` | 2 KiB |
| ZMK application | `0x08006000`-`0x0801FFFF` | 104 KiB |

The first bring-up firmware intentionally has no settings/storage partition and
does not enable ZMK Studio. Never mass-erase the controller and never flash an
application at `0x08000000`.

The factory DFU descriptor reports the internal flash as
`22*001Ka,106*001Kg`: 22 read-only 1 KiB pages followed by 106 readable,
erasable, and writable 1 KiB pages. This describes access permissions, not the
application entry point. A readback of the protected bootloader contains two
literal references to `0x08006000` and none to `0x08005800`; a known-good image
also contains a vector table at `0x08006000`. Preserve the writable 2 KiB
handoff region before the ZMK application.

The bootloader also masks the application's initial main stack pointer with
`0x2FFFB000` and only jumps when the result is `0x20000000`. The board linker
snippet places Zephyr's early kernel stacks at the beginning of SRAM so the
first vector passes that check without substituting a fake stack pointer.
`CONFIG_INIT_ARCH_HW_AT_BOOT` is enabled because the factory DFU chain-loads
the application without a Cortex-M system reset; Zephyr must clear inherited
SysTick and NVIC state before enabling its own interrupts.

On STM32F103, the RCC `USBPRE` bit has inverted-looking semantics: when clear,
the 72 MHz PLL is divided by 1.5 to produce the required 48 MHz USB clock. The
devicetree therefore intentionally omits the PLL node's `usbpre` property.

The matrix configuration matches the factory Vial scanner: it drives each of
the five rows active-low and reads the 15 columns as pulled-up active-low
inputs. The factory binary waits 2,160 CPU cycles after releasing a row, which
is 30 microseconds at 72 MHz. ZMK uses the same settling delay plus a 1
microsecond propagation delay before reading inputs. Scanning in the opposite
direction with ZMK's zero-delay default can retain the previous input level and
report the key in the next column as well.

## Build

The repository is pinned to ZMK v0.3.0. Push the branch or manually dispatch the
GitHub Actions workflow; the expected artifact is
`owlab_link_hotswap-zmk.bin`.

Before flashing, inspect the build output and confirm all of the following:

- `CONFIG_FLASH_SIZE=128`
- `CONFIG_SRAM_SIZE=20`
- `CONFIG_FLASH_LOAD_OFFSET=0x6000`
- `CONFIG_INIT_ARCH_HW_AT_BOOT=y`
- `CONFIG_ZMK_KSCAN_MATRIX_WAIT_BEFORE_INPUTS=1`
- `CONFIG_ZMK_KSCAN_MATRIX_WAIT_BETWEEN_OUTPUTS=30`
- the generated devicetree does not set the PLL `usbpre` property
- the first vector (initial MSP) passes
  `(initial_msp & 0x2FFFB000) == 0x20000000`
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

Normal ZMK updates must not overwrite the handoff region at `0x08005800`. A
known-good Vial application backup that includes that region is restored at
`0x08005800`. The physical B button is the supported bootloader-entry method;
the first ZMK firmware does not attempt a software jump into the factory
bootloader. `Left Ctrl + Left Alt + Backspace` performs a normal application
reset.

## First hardware acceptance test

After flashing, verify that the board enumerates as a USB HID keyboard, test all
67 positions with a key tester, cold-boot it three times, and confirm the
physical B button still enters the factory bootloader. In particular, test the
last matrix column because it uses PA15, which must be released from JTAG.
