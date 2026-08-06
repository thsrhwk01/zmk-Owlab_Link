# Porting ZMK to an STM32F103-Class Board While Preserving Factory USB DFU

[한국어](porting-guide_ko.md)

This document records the findings and failed approaches encountered while
porting ZMK to the `APM32F103CBT6` on the Owlab LINK65 hotswap PCB. It assumes
that factory USB DFU is the only available programming interface, with no
SWD/J-Link debugger.

The goal is not to provide LINK65 settings that can be copied unchanged. It is
to document how to independently establish the following facts on a similar
STM32F103/APM32F103-class board:

- Which flash ranges must be preserved for the factory bootloader
- The application address to which the bootloader actually jumps
- The vector table and initial MSP conditions required by the bootloader
- CPU and interrupt state inherited when the application is chain-loaded
  without a system reset
- The actual 48 MHz clock supplied to USB
- Matrix pins, scan direction, polarity, and settling time

> [!WARNING]
> The addresses, USB ID, pin list, and timings in this document were verified
> on the LINK65. They may differ even on a board using the same MCU. If a
> bootloader is erased from a device that only has USB DFU available, recovery
> may be impossible without SWD hardware.

## 1. Verified LINK65 Baseline

| Item | Value |
| --- | --- |
| PCB | Owlab LINK65 hotswap |
| MCU marking | Geehy `APM32F103CBT6` |
| Zephyr SoC | Compatible `STM32F103xB` configuration |
| CPU | Cortex-M3, 72 MHz |
| External crystal | 8 MHz HSE |
| Flash | 128 KiB, `0x08000000`-`0x0801FFFF` |
| SRAM | 20 KiB, `0x20000000`-`0x20004FFF` |
| USB | PA11/PA12, Full-Speed at 48 MHz |
| Factory DFU USB ID | `1688:2220` |
| Application start | `0x08006000` |
| Matrix | 5 rows × 15 columns, 67 positions, `row2col` |

The following build was verified on physical hardware:

| Item | Value |
| --- | --- |
| Source | [`2a8cde7`](https://github.com/thsrhwk01/zmk-Owlab_Link/commit/2a8cde7fc346bc73e935f38bb52aeee44a7fb05f) |
| Build | [GitHub Actions run `31102550907`](https://github.com/thsrhwk01/zmk-Owlab_Link/actions/runs/31102550907) |
| File | `owlab_link_hotswap-zmk.bin` |
| Size | 38,332 bytes (`0x95BC`) |
| SHA-256 | `D5EE854CFCD732570BC6BF489201F14E15E6A8BE8A8A966B57C6DE78128CF8E0` |
| Initial MSP | `0x20000D00` |
| Reset Handler | `0x08008429` |
| Flash usage | 38,332 / 106,496 bytes (35.99%) |
| RAM usage | 9,880 / 20,480 bytes (48.24%) |

Builds made after documentation-only changes may have a different hash. Treat
these values as the baseline recorded at the time of the port.

## 2. Safety Rules When USB DFU Is the Only Recovery Path

When no SWD debugger is available, prove the recovery path before adding
features.

1. Confirm that the physical button enters factory DFU reliably.
2. Record the DFU USB ID and alternate setting.
3. Obtain the currently working official firmware.
4. Read and back up every flash region the device permits you to upload.
5. Record the size and SHA-256 of every backup.
6. Define fixed partitions so the first experimental build cannot write below
   the application boundary.
7. Change one hypothesis at a time and record the build ID and result.
8. Reconfirm physical DFU entry after every successful stage.

Avoid the following:

- Writing at `0x08000000` before the application address is known
- Using a `dfu-util` mass erase
- Restoring a full-flash image from another PCB revision
- Flashing several changes in succession without checking that preserved
  regions still match their readbacks
- Assuming that a USB enumeration failure proves a hardware fault

## 3. Establish Backups and a Recovery Path First

### 3.1 Identify the DFU device

On the LINK65, disconnect USB, hold the physical **B** button, and reconnect the
cable.

```console
dfu-util -l
```

The verified device uses `1688:2220` and alternate setting 0. Its internal flash
descriptor has the following form:

```text
@Internal Flash /0x08000000/22*001Ka,106*001Kg
```

In a DfuSe descriptor, the `a` region is read-only, while the `g` region is
readable, erasable, and writable. The LINK65 bootloader therefore exposes these
access ranges:

| Descriptor segment | Address | Access |
| --- | --- | --- |
| `22*001Ka` | `0x08000000`-`0x080057FF` | Read-only |
| `106*001Kg` | `0x08005800`-`0x0801FFFF` | Read/erase/write |

The critical point is that **the beginning of a writable region is not
necessarily the application start address**. The LINK65 becomes writable at
`0x08005800`, but its application vector table is at `0x08006000`.

### 3.2 Read the flash

If the device and bootloader permit uploads, read the entire flash before
making any changes.

```console
dfu-util -d 1688:2220 -a 0 -s 0x08000000:0x20000 -U link65-full-flash.bin
dfu-util -d 1688:2220 -a 0 -s 0x08005800:0x800 -U link65-handoff.bin
dfu-util -d 1688:2220 -a 0 -s 0x08006000:0x1A000 -U link65-application.bin
```

On PowerShell, record sizes and hashes as follows:

```powershell
Get-Item .\link65-*.bin | Select-Object Name, Length
Get-FileHash .\link65-*.bin -Algorithm SHA256
```

A backup may contain vendor firmware. Store it separately and do not
accidentally commit it to a public repository. Before continuing, have at least
a known-good official application and a verified restore command available.

## 4. Determine the Actual Flash Layout

The final layout used on the LINK65 is:

| Region | Address range | Size | Treatment |
| --- | --- | ---: | --- |
| Factory bootloader | `0x08000000`-`0x080057FF` | 22 KiB | Never overwrite |
| Vendor handoff | `0x08005800`-`0x08005FFF` | 2 KiB | Preserve as a read-only partition |
| ZMK application | `0x08006000`-`0x0801FFFF` | 104 KiB | Build and DFU target |

### 4.1 Do not infer the layout from the descriptor alone

A DFU descriptor describes flash access permissions. It does not guarantee the
address to which the bootloader jumps. Establish the application start by
cross-checking at least the following evidence:

- Whether the first eight bytes of the official `.bin` form a valid initial MSP
  and Reset Handler
- Whether the same kind of vector table exists at the candidate address on a
  working device
- Whether the factory bootloader contains literals or cross-references using
  the candidate address
- The address at which the official update script writes the `.bin`

The first two words of the official LINK65 Vial/VIA image are:

```text
Initial MSP   = 0x20000400
Reset Handler = 0x08006239
```

The official update script writes this image at `0x08006000`. The protected
bootloader readback also contains two literal references to `0x08006000` and no
observed reference to `0x08005800`. Therefore, ZMK must not be linked at
`0x08005800` merely because that is where writable flash begins.

### 4.2 Basic vector table checks

Read the first two little-endian 32-bit words of the application `.bin`.

```powershell
$image = [IO.File]::ReadAllBytes((Resolve-Path .\owlab_link_hotswap-zmk.bin))
$msp = [BitConverter]::ToUInt32($image, 0)
$reset = [BitConverter]::ToUInt32($image, 4)
'MSP   = 0x{0:X8}' -f $msp
'Reset = 0x{0:X8}' -f $reset
```

In general, verify all of the following:

- The MSP lies within the physical SRAM range and satisfies its alignment
  requirements.
- Bit 0 of the Reset Handler is 1, selecting Thumb state.
- After masking bit 0, the Reset Handler lies within the application flash
  range.
- The first load segment in the `.elf` matches the address used by DFU.

The LINK65 factory bootloader imposes one additional MSP check.

## 5. Satisfy the Factory Bootloader's Jump Contract

### 5.1 LINK65 initial MSP mask

The factory bootloader jumps to an application only when its first word passes
this test:

```c
(initial_msp & 0x2FFFB000) == 0x20000000
```

With Zephyr's default link layout, `z_main_stack` was placed late in `.noinit`,
causing the initial MSP to fail this test. An image can be written correctly
yet remain in or return to DFU when this happens.

Do not patch a fake MSP into the vector table. A real, reserved Zephyr stack
must exist at that address. This repository uses
[`zephyr/link65_boot_stacks.ld`](../zephyr/link65_boot_stacks.ld) to collect the
unique `.noinit` sections for the main, idle, and interrupt stacks at the start
of RAM. Linker assertions enforce both of these conditions:

- The early stacks do not extend beyond `0x20001000`.
- `z_main_stack + CONFIG_MAIN_STACK_SIZE` passes the bootloader MSP mask.

ELF section names generated through `__in_section_unique()` may include quotes
around the source filename. Verify that the wildcard actually collects those
sections by checking the link map and the final MSP.

### 5.2 A chain-load is not a system reset

The LINK65 factory DFU chain-loads the application without a complete Cortex-M
system reset. The application may inherit:

- SysTick configuration and pending state
- NVIC interrupt enable and pending bits
- Interrupt priorities
- `CONTROL` and stack-selection state
- Peripheral clocks and USB state

This port sets the following option in
[`owlab_link_hotswap_defconfig`](../boards/arm/owlab_link_hotswap/owlab_link_hotswap_defconfig):

```text
CONFIG_INIT_ARCH_HW_AT_BOOT=y
```

This allows Zephyr to initialize architectural state before enabling its own
interrupts. Do not assume this option is sufficient for every proprietary
bootloader; inspect any registers and peripheral state left behind by the
specific bootloader.

## 6. Prove the USB Clock

The STM32F103 USB Full-Speed peripheral requires an accurate 48 MHz clock. The
LINK65 clock path is:

```text
8 MHz HSE -> PLL x9 -> 72 MHz system clock
                    -> PLL / 1.5 -> 48 MHz USB
```

The RCC `USBPRE` bit on STM32F1 is easy to misread from its name. In this
configuration, clearing the bit divides the 72 MHz PLL clock by 1.5 to produce
48 MHz. With the Zephyr devicetree binding used by this port, omitting the
`usbpre` property from the PLL node keeps that bit clear.

```dts
&pll {
    mul = <9>;
    clocks = <&clk_hse>;
    /* Omit usbpre: 72 MHz / 1.5 = 48 MHz */
    status = "okay";
};
```

When `usbpre` was set and USB received 72 MHz, Windows reported an unrecognized
USB device almost immediately. The time it takes for an error to appear is only
a diagnostic clue, not proof of a particular cause. Check the clock in this
order:

1. Verify the actual HSE frequency and PLL multiplier.
2. Confirm the USB prescaler bit semantics in the SoC reference manual.
3. Check how the active Zephyr clock driver interprets the devicetree property.
4. Verify that the generated devicetree and resulting RCC register state match
   the expected values.
5. Only then move on to USB D-/D+ pin configuration, pinctrl, and inherited
   interrupt state.

## 7. Correct Matrix Pins Are Not Enough

The factory LINK65 Vial scanner drives five rows low one at a time and reads 15
pulled-up columns as active-low inputs.

### 7.1 Verified pins and order

| Group | Order |
| --- | --- |
| Row outputs | PA1, PA2, PA3, PA4, PA5 |
| Column inputs | PA7, PB0, PB1, PB2, PB10, PB11, PB12, PB13, PB14, PB15, PA8, PA9, PA10, PA6, PA15 |

The essential devicetree settings are:

```dts
diode-direction = "row2col";

col-gpios = <... (GPIO_ACTIVE_LOW | GPIO_PULL_UP)>;
row-gpios = <... GPIO_ACTIVE_LOW>;
```

See
[`owlab_link_hotswap.dts`](../boards/arm/owlab_link_hotswap/owlab_link_hotswap.dts)
for the complete definition.

### 7.2 Scan delays

The factory binary waits 2,160 CPU cycles after switching rows. At 72 MHz, that
is exactly 30 us. ZMK uses:

```text
CONFIG_ZMK_KSCAN_MATRIX_WAIT_BEFORE_INPUTS=1
CONFIG_ZMK_KSCAN_MATRIX_WAIT_BETWEEN_OUTPUTS=30
```

`WAIT_BEFORE_INPUTS=1` supplies a short propagation delay before reading the
inputs. `WAIT_BETWEEN_OUTPUTS=30` allows the matrix to settle between releasing
one row and driving the next.

Scanning in the opposite direction with the default 0 us delay produced these
observed symptoms:

- Pressing `F` reported `F+G`.
- Pressing `G` reported `G+H`.
- Pressing `Esc` reported `Esc+1`.
- The sparsely populated bottom row appeared comparatively normal.

This pattern points first to a previous output or input state persisting into
the next position, rather than simply an incorrect keymap order. Validate pin
order, diode direction, active level, pull-up/down, and settling delay as one
system.

### 7.3 Debug-pin conflicts

The final column uses PA15. On STM32F1, PA15 can conflict with its default JTAG
function, so JTAG must be disabled.

```dts
&pinctrl {
    swj-cfg = "jtag-disable";
};
```

This disables JTAG while retaining SWD on PA13/PA14. If the entire last column
is dead, inspect this pin mux before changing the matrix transform.

## 8. Zephyr/ZMK Board Definition

The files directly involved in this port are:

| File | Purpose |
| --- | --- |
| [`owlab_link_hotswap.dts`](../boards/arm/owlab_link_hotswap/owlab_link_hotswap.dts) | Memory partitions, clocks, USB, matrix, and pinctrl |
| [`owlab_link_hotswap_defconfig`](../boards/arm/owlab_link_hotswap/owlab_link_hotswap_defconfig) | SoC, USB, kscan delays, and boot initialization |
| [`Kconfig.board`](../boards/arm/owlab_link_hotswap/Kconfig.board) | Board and SoC dependency |
| [`Kconfig.defconfig`](../boards/arm/owlab_link_hotswap/Kconfig.defconfig) | ZMK board defaults |
| [`board.cmake`](../boards/arm/owlab_link_hotswap/board.cmake) | dfu-util and J-Link runner settings |
| [`owlab_link_hotswap.keymap`](../boards/arm/owlab_link_hotswap/owlab_link_hotswap.keymap) | Physical layout and ZMK keymap |
| [`zephyr/link65_boot_stacks.ld`](../zephyr/link65_boot_stacks.ld) | Stack placement satisfying the factory MSP check |
| [`zephyr/CMakeLists.txt`](../zephyr/CMakeLists.txt) | Registration of the board-specific linker snippet |
| [`build.yaml`](../build.yaml) | GitHub Actions build matrix |
| [`config/west.yml`](../config/west.yml) | Pinned ZMK revision |

The repository is currently pinned to ZMK `v0.3.0`. A ZMK or Zephyr upgrade may
change linker section names, clock bindings, or Kconfig defaults. Revalidate the
port instead of assuming these details remain unchanged.

### 8.1 Fixed partitions

The devicetree explicitly declares the bootloader, handoff, and code regions,
then selects only the code partition for the application.

```text
CONFIG_USE_DT_CODE_PARTITION=y
```

The current bring-up firmware does not define a settings/storage partition. To
add ZMK Studio or persistent settings, create a separate partition within the
104 KiB application area and reduce the code partition accordingly. Recheck the
20 KiB RAM budget as well. Adding Studio and settings before basic bring-up is
stable makes it harder to distinguish boot/USB faults from storage faults.

## 9. Build and Static Inspection

### 9.1 Verified build path

The repository runs
[`Build ZMK firmware`](https://github.com/thsrhwk01/zmk-Owlab_Link/actions/workflows/build.yml)
on a push, pull request, or manual dispatch. The expected artifact is
`owlab_link_hotswap-zmk.bin`.

The GitHub workflow uses a command of this form:

```console
west build -s zmk/app -b owlab_link_hotswap -- \
  -DZMK_CONFIG=/path/to/config \
  -DZMK_EXTRA_MODULES=/path/to/zmk-Owlab_Link
```

For a local build, prepare a west workspace and the matching ZMK/Zephyr SDK,
then replace both paths with their actual absolute paths. The cloud build is
the validated build path for this port.

### 9.2 Mandatory pre-flash checks

Verify the following in the final `.config`, devicetree, `.elf`, and `.bin`:

- `CONFIG_FLASH_SIZE=128`
- `CONFIG_SRAM_SIZE=20`
- `CONFIG_FLASH_LOAD_OFFSET=0x6000`
- `CONFIG_USE_DT_CODE_PARTITION=y`
- `CONFIG_INIT_ARCH_HW_AT_BOOT=y`
- `CONFIG_ZMK_KSCAN_MATRIX_WAIT_BEFORE_INPUTS=1`
- `CONFIG_ZMK_KSCAN_MATRIX_WAIT_BETWEEN_OUTPUTS=30`
- The generated PLL node has no `usbpre` property.
- The first load segment starts at `0x08006000`.
- No load segment targets an address below `0x08006000`.
- The image fits within 104 KiB of flash and 20 KiB of SRAM.
- The initial MSP satisfies `(msp & 0x2FFFB000) == 0x20000000`.
- The Reset Handler satisfies both the Thumb bit and application-range checks.

When an ELF is available, these tools are useful:

```console
arm-none-eabi-size zmk.elf
arm-none-eabi-readelf -l zmk.elf
arm-none-eabi-objdump -h zmk.elf
```

When only the `.bin` is available, PowerShell can enforce the LINK65-specific
MSP condition:

```powershell
$image = [IO.File]::ReadAllBytes((Resolve-Path .\owlab_link_hotswap-zmk.bin))
$msp = [BitConverter]::ToUInt32($image, 0)
$reset = [BitConverter]::ToUInt32($image, 4)
$masked = $msp -band 0x2FFFB000
'Size   = {0} bytes' -f $image.Length
'MSP    = 0x{0:X8}' -f $msp
'Masked = 0x{0:X8}' -f $masked
'Reset  = 0x{0:X8}' -f $reset
if ($image.Length -gt 0x1A000) { throw 'Image exceeds LINK65 code partition' }
if ($masked -ne 0x20000000) { throw 'MSP will be rejected by factory bootloader' }
```

## 10. Flashing and Hardware Validation

### 10.1 Capture the handoff region before flashing

Read the region that must be preserved immediately before writing ZMK.

```console
dfu-util -d 1688:2220 -a 0 -s 0x08005800:0x800 -U handoff-before.bin
```

### 10.2 Write only the application

```console
dfu-util -d 1688:2220 -a 0 -s 0x08006000:leave -D owlab_link_hotswap-zmk.bin
```

Do not omit the address or change it to `0x08000000`.

### 10.3 Staged acceptance test

1. Confirm that the board leaves DFU and enumerates as a USB HID device.
2. Test all 67 switches individually in a key tester.
3. Confirm that each key reports alone without an adjacent key.
4. Perform three cold boots by completely disconnecting USB.
5. Re-enter factory DFU with the physical **B** button.
6. Read the handoff region again and compare its SHA-256 with the pre-flash file.
7. If needed, read back the application region and compare it with the image
   that was written.

```console
dfu-util -d 1688:2220 -a 0 -s 0x08005800:0x800 -U handoff-after.bin
dfu-util -d 1688:2220 -a 0 -s 0x08006000:0x1A000 -U application-readback.bin
```

A readback may be padded through the end of the requested region. Compare only
the original image length or account for erased padding when comparing the
application.

## 11. Symptom-Based Diagnostics

| Symptom | Check first |
| --- | --- |
| Board returns to or remains in DFU after flashing | Application address, vector table, MSP mask, and Reset Handler |
| “USB device not recognized” appears immediately | USB 48 MHz clock, `USBPRE`, PA11/PA12 pinctrl, and inherited interrupt state |
| USB failure appears after several seconds | Whether the app runs at all, clock startup, USB reset/interrupt state; do not diagnose from timing alone |
| `F` reports `F+G` or another key also reports its right-hand neighbor | Scan direction, active level, pull-up/down, and settling time between outputs |
| Only the final matrix column is dead | PA15 JTAG release and pinctrl |
| Warm reset works but cold boot is unreliable | HSE/PLL startup, bootloader handoff state, and initialization order |
| No device appears in the DFU list | Data cable, Windows driver, physical-button sequence, and USB ID |
| Factory DFU itself disappears | Possible damage to low flash or option bytes; stop writing and consider SWD recovery |

Do not determine the cause from USB error timing or a single LED state. Compare
the build artifact, first two vector words, USB clock, and readback together.

## 12. Checklist for Another STM32F103/APM32F103 Board

### Before the first build

- [ ] Confirm the exact MCU part marking and actual flash/SRAM capacity.
- [ ] Identify the HSE frequency and USB D-/D+ pins.
- [ ] Record the physical DFU entry method and USB ID.
- [ ] Store a working firmware image and full-flash readback separately.
- [ ] Distinguish the DFU descriptor boundary from the actual application vector
      address.
- [ ] Determine the bootloader jump address and its MSP/Reset Handler checks.
- [ ] Declare preserved regions and the code partition in devicetree.
- [ ] Confirm matrix pin order, direction, polarity, pulls, and delays.

### Before flashing

- [ ] Confirm that ELF load segments begin only inside the code partition.
- [ ] Confirm that the initial MSP and Reset Handler satisfy the bootloader.
- [ ] Prove that the USB peripheral receives exactly 48 MHz.
- [ ] Keep flash and RAM usage within the physical MCU limits.
- [ ] Begin without settings, storage, or Studio.
- [ ] Have an official recovery image and exact DFU restore command ready.

### After flashing

- [ ] Confirm USB HID enumeration.
- [ ] Test every matrix position as an independent key.
- [ ] Repeat cold boots.
- [ ] Confirm physical DFU re-entry.
- [ ] Confirm that preserved-region hashes are unchanged.
- [ ] Record the source commit, Actions run, binary hash, and test result.

The purpose of this checklist is not to produce a complete firmware image in a
single attempt. It is to prove each hardware contract one at a time without
losing the USB DFU recovery path when an experiment fails.
