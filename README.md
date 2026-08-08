# Owlab LINK65 ZMK Firmware

[한국어](README_ko.md)

Wired ZMK firmware for the Owlab LINK65 hotswap PCB. It runs ZMK from
`0x08006000` while preserving the factory DFU bootloader.

**This firmware has only been tested on a LINK65 hotswap PCB with an
`APM32F103CBT6` at U3. Do not flash it onto a solder PCB, a different revision,
or a board with a different MCU.**

## Features

- Wired USB keyboard support with a 67-key ANSI 65% layout
- Preserves the factory DFU bootloader and physical **B** button
- Uses the same active-low row drive and column input scheme as the factory firmware
- Applies the 30 us matrix settling time measured on the LINK65
- Releases PA15 for key input by disabling JTAG while retaining the SWD pins
- Reproducible ZMK firmware builds through GitHub Actions

The stock PCB has no wireless hardware, so Bluetooth is not supported. The
current firmware also does not include ZMK Studio, persistent settings storage,
or RGB/lighting control.

## Supported Hardware

| Item | Verified configuration |
| --- | --- |
| Keyboard | Owlab LINK65 hotswap PCB |
| MCU | Geehy `APM32F103CBT6` |
| Compatible SoC configuration | Zephyr `STM32F103xB` |
| Flash / SRAM | 128 KiB / 20 KiB |
| System clocks | 8 MHz HSE, 72 MHz CPU, 48 MHz USB |
| Key matrix | 5 rows × 15 columns, 67 switches |
| Connection | USB Full-Speed |
| DFU device | `1688:2220`, alternate setting 0 |

Stop if the marking on U3 differs from the one above. A board carrying the same
LINK65 name does not necessarily use the same PCB or flash layout.

## Quick Install

### Windows one-click flasher

1. Open the [latest GitHub Release](https://github.com/thsrhwk01/zmk-Owlab_Link/releases/latest).
2. Download `LINK65-ZMK-Windows.zip` and extract every file.
3. Double-click `flash-link65.cmd`.
4. Confirm the LINK65 hotswap PCB and the `APM32F103CBT6` at U3, then enter
   `y` at the warning prompt. Entering `n` or pressing Enter cancels without
   writing anything.
5. When prompted, hold the physical **B** button while connecting USB, then
   release the button. The script waits for the correct DFU device and flashes
   the verified firmware automatically.
6. After `Flash complete` appears, disconnect USB and reconnect it without
   holding the **B** button.

The factory bootloader does not reliably acknowledge an automatic leave
request. The flasher therefore leaves it in DFU mode after a successful write
and asks you to reconnect the cable manually.

On first use, Windows may require the DFU interface `1688:2220` to be associated
with the WinUSB driver. Follow `README_KO.txt` in the ZIP if the flasher cannot
find the keyboard. Do not change the driver for an unrelated USB device.

Every successful firmware build, including a non-`main` branch build, publishes
a `LINK65-ZMK-Windows` Actions artifact. A GitHub Release with the ready-to-use
ZIP is published only when a version tag such as `v1.0.0` is pushed.

### Manual installation

#### 1. Download the firmware

1. Open the [latest GitHub Release](https://github.com/thsrhwk01/zmk-Owlab_Link/releases/latest).
2. Download `owlab_link_hotswap-zmk.bin` and `SHA256SUMS.txt`.
3. Optionally verify the download before flashing:

   ```powershell
   Get-FileHash .\owlab_link_hotswap-zmk.bin -Algorithm SHA256
   ```

If no Release is available, open a successful
[Build and Release ZMK firmware](https://github.com/thsrhwk01/zmk-Owlab_Link/actions/workflows/build.yml)
run, download the `firmware` artifact, and extract it.

The current hardware-validated baseline is
[commit `2a8cde7`](https://github.com/thsrhwk01/zmk-Owlab_Link/commit/2a8cde7fc346bc73e935f38bb52aeee44a7fb05f),
built by [Actions run `31102550907`](https://github.com/thsrhwk01/zmk-Owlab_Link/actions/runs/31102550907).

#### 2. Prepare

- A USB cable capable of data transfer
- [`dfu-util`](https://dfu-util.sourceforge.net/)
- A known-good official Vial/VIA `.bin` for the LINK65 hotswap PCB, for recovery

Confirm that `dfu-util` is available before continuing.

```console
dfu-util --version
```

#### 3. Enter the factory DFU bootloader

1. Disconnect the keyboard's USB cable.
2. Hold the physical **B** button on the PCB while reconnecting the cable.
3. Release the **B** button.
4. List the DFU devices.

```console
dfu-util -l
```

The output must show USB ID `1688:2220` and alternate setting 0. Do not flash
anything if only a different device is listed or no device appears.

#### 4. Flash ZMK

Run the following command from the directory containing the firmware file.

```console
dfu-util -d ,1688:2220 -a 0 -s 0x08006000 -D owlab_link_hotswap-zmk.bin
```

After `File downloaded successfully` appears, disconnect USB and reconnect it
without holding the **B** button. The board should start as an `Owlab Link` USB
keyboard.

> [!CAUTION]
> Do not write an application at `0x08000000` or mass-erase the MCU. If the
> factory bootloader is erased, it cannot be restored through USB DFU alone.
> Firmware from this repository must always be flashed at `0x08006000`.

## Keymap

The default keymap is a conventional ANSI 65% QWERTY layout. Edit
[`boards/arm/owlab_link_hotswap/owlab_link_hotswap.keymap`](boards/arm/owlab_link_hotswap/owlab_link_hotswap.keymap)
to customize it.

![LINK65 keymap diagram](keymap-drawer/owlab_link_hotswap.svg "Generated by keymap-drawer")

The diagram is generated from the `.keymap` source by
[keymap-drawer](https://github.com/caksoylar/keymap-drawer) and is updated
automatically when the keymap changes.

| Input | Action |
| --- | --- |
| `Left Ctrl + Left Alt + Backspace` | Soft-reset ZMK |
| Hold the physical **B** button while connecting USB | Enter the factory DFU bootloader |

A soft reset only restarts the application; it does not enter the DFU
bootloader. Use the physical **B** button for firmware updates.

To change the keymap, fork this repository, edit the `.keymap` file, and push
the change. GitHub Actions builds both a raw `owlab_link_hotswap-zmk.bin` and a
`LINK65-ZMK-Windows` one-click flasher artifact. Normal pushes, including pushes
to `main`, do not publish a GitHub Release.

## Publishing a Release

After the intended commit is merged into `main` and its Actions build succeeds,
create and push an annotated version tag.

```console
git switch main
git pull --ff-only
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

Only a pushed tag matching `v*.*` publishes the firmware, checksums, and Windows
flasher ZIP. A tag containing letters, such as `v1.1.0-beta.1`, is published as
a prerelease; an ordinary numeric version becomes the latest stable release.

## Restore Vial/VIA

You can restore the factory firmware as long as the physical **B** button still
enters DFU. Obtain a verified official `.bin` for the LINK65 hotswap PCB and
flash it at the same application address.

```console
dfu-util -d ,1688:2220 -a 0 -s 0x08006000 -D owlab_link_hotswap_via_V3.bin
```

Adjust the filename to match the official firmware you have. After the download
succeeds, disconnect and reconnect USB without holding **B**. Do not substitute
firmware intended for another LINK65 revision.

## Post-Flash Checks

After the first installation, verify the following:

1. The operating system recognizes the board as a USB HID keyboard.
2. Every one of the 67 key positions registers in a key tester.
3. Pressing one key does not also report the key immediately to its right.
4. The keyboard survives three complete USB disconnect-and-reconnect cold boots.
5. The physical **B** button still enters the factory DFU bootloader.

Pay particular attention to the final matrix column, which uses PA15, and to
the keys around `Esc`, `F`, and `G`.

## Known Limitations

- Runtime keymap editing through ZMK Studio is not supported yet.
- No flash partition is reserved for persistent settings.
- RGB and board-specific auxiliary features are not implemented.
- Software entry into the factory DFU bootloader is not implemented.
- The default keymap provides only one layer.

Developers porting ZMK to another STM32F103/APM32F103-class board should read
[`docs/porting-guide.md`](docs/porting-guide.md) first. Do not copy the LINK65
flash map to another board without verifying it independently.
