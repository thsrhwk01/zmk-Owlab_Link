# 공장 USB DFU를 유지하는 STM32F103 계열 ZMK 포팅 가이드

[English](porting-guide.md)

이 문서는 Owlab LINK65 핫스왑 PCB의 `APM32F103CBT6`를 ZMK로 포팅하면서
확인한 사실과 시행착오를 기록합니다. SWD/J-Link 없이 공장 USB DFU만 사용할
수 있는 상황을 기준으로 작성했습니다.

목표는 LINK65 설정을 다른 기판에 그대로 복사하는 것이 아닙니다. 비슷한
STM32F103/APM32F103 계열 기판에서 다음 항목을 **직접 확인하는 방법**을
남기는 것입니다.

- 공장 부트로더가 보존해야 하는 플래시 범위
- 부트로더가 실제로 점프하는 애플리케이션 주소
- 부트로더가 요구하는 벡터 테이블과 초기 MSP 조건
- 시스템 리셋 없이 체인로드될 때 남는 CPU/인터럽트 상태
- USB에 공급되는 실제 48 MHz 클럭
- 키 매트릭스 핀, 스캔 방향, 극성 및 안정화 시간

> [!WARNING]
> 이 문서의 주소, USB ID, 핀 목록과 타이밍은 LINK65에서 확인된 값입니다.
> MCU가 같아도 부트로더와 PCB가 다르면 값이 달라집니다. 특히 USB DFU만
> 있는 장치에서 부트로더를 지우면 SWD 장비 없이는 복구하지 못할 수 있습니다.

## 1. 검증된 LINK65 기준점

| 항목 | 값 |
| --- | --- |
| PCB | Owlab LINK65 핫스왑 |
| MCU 마킹 | Geehy `APM32F103CBT6` |
| Zephyr SoC | `STM32F103xB` 호환 설정 |
| CPU | Cortex-M3, 72 MHz |
| 외부 크리스털 | 8 MHz HSE |
| 플래시 | 128 KiB, `0x08000000`-`0x0801FFFF` |
| SRAM | 20 KiB, `0x20000000`-`0x20004FFF` |
| USB | PA11/PA12, Full-Speed 48 MHz |
| 공장 DFU USB ID | `1688:2220` |
| 애플리케이션 시작 | `0x08006000` |
| 매트릭스 | 5행 × 15열, 67개 위치, `row2col` |

실기기 동작이 확인된 기준 빌드는 다음과 같습니다.

| 항목 | 값 |
| --- | --- |
| 소스 | [`2a8cde7`](https://github.com/thsrhwk01/zmk-Owlab_Link/commit/2a8cde7fc346bc73e935f38bb52aeee44a7fb05f) |
| 빌드 | [GitHub Actions run `31102550907`](https://github.com/thsrhwk01/zmk-Owlab_Link/actions/runs/31102550907) |
| 파일 | `owlab_link_hotswap-zmk.bin` |
| 크기 | 38,332 bytes (`0x95BC`) |
| SHA-256 | `D5EE854CFCD732570BC6BF489201F14E15E6A8BE8A8A966B57C6DE78128CF8E0` |
| 초기 MSP | `0x20000D00` |
| Reset Handler | `0x08008429` |
| 플래시 사용량 | 38,332 / 106,496 bytes (35.99%) |
| RAM 사용량 | 9,880 / 20,480 bytes (48.24%) |

문서만 변경한 이후 빌드는 해시가 달라질 수 있으므로, 위 값은 포팅 당시의
기준점으로 사용하십시오.

## 2. USB DFU만 있을 때의 안전 원칙

SWD 디버거가 없는 포팅에서는 기능보다 복구 경로를 먼저 증명해야 합니다.

1. 물리 버튼으로 공장 DFU에 반복 진입할 수 있는지 확인합니다.
2. DFU USB ID와 alternate setting을 기록합니다.
3. 현재 정상 동작하는 공식 펌웨어를 확보합니다.
4. 가능한 모든 플래시 영역을 읽어 별도 위치에 백업합니다.
5. 백업 파일의 크기와 SHA-256을 기록합니다.
6. 첫 실험부터 부트로더 아래 주소를 쓰지 못하도록 파티션을 고정합니다.
7. 한 번에 한 가지 가설만 바꾸고 빌드 ID와 결과를 기록합니다.
8. 각 성공 단계에서 물리 DFU 진입이 여전히 되는지 다시 확인합니다.

다음 행동은 피해야 합니다.

- 애플리케이션 시작 주소를 모르는 상태에서 `0x08000000`에 쓰기
- `dfu-util`의 mass erase 사용
- 다른 PCB 리비전의 전체 플래시 이미지를 그대로 복원
- 부트로더 영역을 보존했다는 readback 검증 없이 여러 변경을 연속 플래시
- USB 인식 실패를 곧바로 하드웨어 고장으로 단정

## 3. 먼저 백업과 복구 경로를 만든다

### 3.1 DFU 장치 확인

LINK65에서는 USB를 분리하고 물리 **B** 버튼을 누른 채 다시 연결합니다.

```console
dfu-util -l
```

확인된 장치는 `1688:2220`, alternate setting 0이며 내부 플래시 descriptor는
다음 형태입니다.

```text
@Internal Flash /0x08000000/22*001Ka,106*001Kg
```

DfuSe descriptor의 `a` 영역은 읽기 전용, `g` 영역은 읽기/지우기/쓰기가
가능하다는 뜻입니다. 따라서 LINK65 부트로더가 노출하는 접근 범위는 다음과
같습니다.

| Descriptor 구간 | 주소 | 권한 |
| --- | --- | --- |
| `22*001Ka` | `0x08000000`-`0x080057FF` | 읽기 전용 |
| `106*001Kg` | `0x08005800`-`0x0801FFFF` | 읽기/지우기/쓰기 |

여기서 가장 중요한 점은 **쓰기 가능 영역의 시작이 애플리케이션 시작 주소라는
뜻은 아니라는 것**입니다. LINK65는 쓰기 가능 영역이 `0x08005800`부터지만
애플리케이션 벡터 테이블은 `0x08006000`에 있습니다.

### 3.2 플래시 읽기

장치와 부트로더가 upload를 허용한다면 첫 변경 전에 전체 플래시를 읽습니다.

```console
dfu-util -d 1688:2220 -a 0 -s 0x08000000:0x20000 -U link65-full-flash.bin
dfu-util -d 1688:2220 -a 0 -s 0x08005800:0x800 -U link65-handoff.bin
dfu-util -d 1688:2220 -a 0 -s 0x08006000:0x1A000 -U link65-application.bin
```

PowerShell에서는 다음과 같이 크기와 해시를 기록할 수 있습니다.

```powershell
Get-Item .\link65-*.bin | Select-Object Name, Length
Get-FileHash .\link65-*.bin -Algorithm SHA256
```

백업에는 벤더 펌웨어가 포함될 수 있으므로 공개 저장소에 무심코 커밋하지
말고 별도 보관하십시오. 적어도 정상 동작하는 공식 애플리케이션과 플래시
명령을 확보한 뒤 다음 단계로 진행합니다.

## 4. 실제 플래시 레이아웃을 결정한다

LINK65에서 최종적으로 사용한 레이아웃은 다음과 같습니다.

| 영역 | 주소 범위 | 크기 | 취급 |
| --- | --- | ---: | --- |
| 공장 부트로더 | `0x08000000`-`0x080057FF` | 22 KiB | 절대 덮어쓰지 않음 |
| 벤더 handoff | `0x08005800`-`0x08005FFF` | 2 KiB | 읽기 전용 파티션으로 보존 |
| ZMK 애플리케이션 | `0x08006000`-`0x0801FFFF` | 104 KiB | 빌드 및 DFU 대상 |

### 4.1 Descriptor만으로 판단하지 않는다

DFU descriptor는 플래시 접근 권한을 설명할 뿐, 부트로더의 점프 주소를
보장하지 않습니다. 애플리케이션 시작 주소는 최소한 다음 증거를 교차 확인해
정합니다.

- 공식 `.bin` 첫 8바이트가 유효한 초기 MSP와 Reset Handler인지
- 정상 기기의 해당 주소에 같은 형태의 벡터 테이블이 있는지
- 공장 부트로더 코드에 후보 주소를 사용하는 literal/xref가 있는지
- 공식 업데이트 스크립트가 어느 주소에 `.bin`을 쓰는지

LINK65 공식 Vial/VIA 이미지의 첫 두 word는 다음과 같습니다.

```text
Initial MSP   = 0x20000400
Reset Handler = 0x08006239
```

공식 업데이트 스크립트는 이 파일을 `0x08006000`에 기록합니다. 보호된
부트로더 readback에서도 `0x08006000` literal 참조가 두 곳 확인되었고
`0x08005800` 참조는 확인되지 않았습니다. 따라서 `0x08005800`부터 쓰기
가능하다는 이유만으로 그 주소에 ZMK를 링크하면 안 됩니다.

### 4.2 벡터 테이블의 기본 검사

애플리케이션 `.bin`의 첫 두 32-bit little-endian word를 확인합니다.

```powershell
$image = [IO.File]::ReadAllBytes((Resolve-Path .\owlab_link_hotswap-zmk.bin))
$msp = [BitConverter]::ToUInt32($image, 0)
$reset = [BitConverter]::ToUInt32($image, 4)
'MSP   = 0x{0:X8}' -f $msp
'Reset = 0x{0:X8}' -f $reset
```

일반적으로 다음 조건을 확인해야 합니다.

- MSP가 실제 SRAM 범위 안에 있고 요구 정렬을 만족하는가
- Reset Handler의 bit 0이 1인가(Thumb 상태)
- bit 0을 제외한 Reset Handler 주소가 애플리케이션 플래시 범위 안인가
- `.elf`의 첫 load segment와 DFU 기록 주소가 일치하는가

LINK65에서는 여기에 공장 부트로더 고유의 MSP 검사가 하나 더 있습니다.

## 5. 공장 부트로더의 점프 조건을 맞춘다

### 5.1 LINK65의 초기 MSP 마스크

공장 부트로더는 애플리케이션의 첫 word에 다음 검사를 수행한 뒤에만
점프합니다.

```c
(initial_msp & 0x2FFFB000) == 0x20000000
```

Zephyr의 기본 링크 결과에서는 `z_main_stack`이 `.noinit` 뒤쪽에 놓여 초기
MSP가 이 검사를 통과하지 못했습니다. 이 경우 이미지를 정상적으로 기록해도
부트로더가 애플리케이션으로 넘어가지 않거나 다시 DFU로 보일 수 있습니다.

벡터 테이블에 가짜 MSP만 써 넣으면 안 됩니다. 실제로 예약된 Zephyr 스택이
그 위치에 있어야 합니다. 이 저장소는
[`zephyr/link65_boot_stacks.ld`](../zephyr/link65_boot_stacks.ld)에서 main,
idle, interrupt stack의 고유 `.noinit` section을 RAM 앞쪽에 먼저 배치합니다.
링커 assertion도 다음 두 조건을 빌드 시 강제합니다.

- 초기 스택들이 `0x20001000`을 넘지 않음
- `z_main_stack + CONFIG_MAIN_STACK_SIZE`가 부트로더 MSP 마스크를 통과함

`__in_section_unique()`로 만들어지는 ELF section 이름에는 소스 파일 이름의
따옴표가 포함될 수 있습니다. wildcard가 실제 section을 수집하는지 link map과
최종 MSP를 반드시 다시 확인하십시오.

### 5.2 체인로드는 시스템 리셋과 다르다

LINK65 공장 DFU는 Cortex-M 전체 system reset 없이 애플리케이션으로
체인로드합니다. 따라서 bootloader가 사용하던 다음 상태가 남을 수 있습니다.

- SysTick 설정과 pending 상태
- NVIC interrupt enable/pending bits
- interrupt priority
- `CONTROL` 및 stack 선택 상태
- peripheral clock과 USB 상태

이 포트는
[`owlab_link_hotswap_defconfig`](../boards/arm/owlab_link_hotswap/owlab_link_hotswap_defconfig)에
다음을 설정합니다.

```text
CONFIG_INIT_ARCH_HW_AT_BOOT=y
```

Zephyr가 자체 interrupt를 활성화하기 전에 아키텍처 상태를 초기화하도록 하기
위함입니다. 다른 부트로더에서는 이 옵션만으로 충분하다고 가정하지 말고,
부트로더가 남기는 레지스터와 peripheral 상태를 확인해야 합니다.

## 6. USB 클럭을 먼저 증명한다

STM32F103 USB Full-Speed peripheral에는 정확한 48 MHz가 필요합니다. LINK65의
클럭 경로는 다음과 같습니다.

```text
8 MHz HSE -> PLL x9 -> 72 MHz system clock
                    -> PLL / 1.5 -> 48 MHz USB
```

STM32F1의 RCC `USBPRE` bit 의미는 이름만 보면 헷갈리기 쉽습니다. 이 구성에서는
bit가 clear일 때 72 MHz PLL이 1.5로 나뉘어 48 MHz가 됩니다. 사용 중인 Zephyr
devicetree binding에서는 PLL node에 `usbpre` property를 넣지 않아 bit를 clear로
유지합니다.

```dts
&pll {
    mul = <9>;
    clocks = <&clk_hse>;
    /* usbpre를 넣지 않는다: 72 MHz / 1.5 = 48 MHz */
    status = "okay";
};
```

`usbpre`를 설정해 USB에 72 MHz가 공급되었을 때 Windows는 매우 빠르게
“USB 장치 인식 실패”를 표시했습니다. 다만 오류가 나타나는 시간은 진단의
힌트일 뿐 원인을 확정하는 증거는 아닙니다. 다음 순서로 확인하십시오.

1. HSE 실제 주파수와 PLL multiplier를 확인합니다.
2. SoC reference manual에서 USB prescaler bit 의미를 확인합니다.
3. 사용 중인 Zephyr clock driver가 devicetree property를 어떻게 해석하는지
   확인합니다.
4. 생성된 devicetree와 RCC register 결과가 기대값과 같은지 확인합니다.
5. USB D-/D+ 핀, pinctrl과 interrupt 초기화 문제를 그다음 확인합니다.

## 7. 매트릭스는 핀 목록만 맞아도 끝나지 않는다

LINK65 공장 Vial scanner는 5개 행을 하나씩 low로 구동하고, pull-up된 15개
열을 active-low로 읽습니다.

### 7.1 확인된 핀과 순서

| 구분 | 순서 |
| --- | --- |
| Row 출력 | PA1, PA2, PA3, PA4, PA5 |
| Column 입력 | PA7, PB0, PB1, PB2, PB10, PB11, PB12, PB13, PB14, PB15, PA8, PA9, PA10, PA6, PA15 |

devicetree 핵심 설정은 다음과 같습니다.

```dts
diode-direction = "row2col";

col-gpios = <... (GPIO_ACTIVE_LOW | GPIO_PULL_UP)>;
row-gpios = <... GPIO_ACTIVE_LOW>;
```

전체 정의는
[`owlab_link_hotswap.dts`](../boards/arm/owlab_link_hotswap/owlab_link_hotswap.dts)에
있습니다.

### 7.2 스캔 지연

공장 바이너리는 행을 전환한 뒤 2,160 CPU cycle을 기다립니다. 72 MHz에서
정확히 30 us입니다. ZMK에서는 다음 값을 사용합니다.

```text
CONFIG_ZMK_KSCAN_MATRIX_WAIT_BEFORE_INPUTS=1
CONFIG_ZMK_KSCAN_MATRIX_WAIT_BETWEEN_OUTPUTS=30
```

`WAIT_BEFORE_INPUTS=1`은 입력을 읽기 전의 짧은 전파 지연이고,
`WAIT_BETWEEN_OUTPUTS=30`은 이전 행을 해제하고 다음 행을 구동하는 사이의
안정화 시간입니다.

반대 방향으로 스캔하고 기본 0 us 지연을 사용했을 때 다음과 같은 실제 증상이
나왔습니다.

- `F`를 누르면 `F+G`
- `G`를 누르면 `G+H`
- `Esc`를 누르면 `Esc+1`
- 스위치가 드문 하단 행은 상대적으로 정상처럼 보임

이 패턴은 단순 keymap 순서 오류보다 이전 출력/입력 상태가 다음 위치에
잔류하는 현상을 먼저 의심하게 합니다. 핀 순서, diode direction, active level,
pull-up/down과 settling delay를 한 묶음으로 검증해야 합니다.

### 7.3 디버그 핀과의 충돌

마지막 column은 PA15를 사용합니다. STM32F1에서 PA15는 기본 JTAG 기능과
충돌할 수 있으므로 JTAG를 해제해야 합니다.

```dts
&pinctrl {
    swj-cfg = "jtag-disable";
};
```

이 설정은 JTAG만 해제하고 PA13/PA14의 SWD는 유지합니다. 마지막 열 전체가
입력되지 않는다면 matrix transform보다 먼저 이 핀 mux를 확인하십시오.

## 8. Zephyr/ZMK 보드 정의 구성

이 저장소에서 포팅에 직접 관여하는 파일은 다음과 같습니다.

| 파일 | 역할 |
| --- | --- |
| [`owlab_link_hotswap.dts`](../boards/arm/owlab_link_hotswap/owlab_link_hotswap.dts) | 메모리 파티션, 클럭, USB, 매트릭스 및 pinctrl |
| [`owlab_link_hotswap_defconfig`](../boards/arm/owlab_link_hotswap/owlab_link_hotswap_defconfig) | SoC, USB, kscan 지연 및 부팅 초기화 설정 |
| [`Kconfig.board`](../boards/arm/owlab_link_hotswap/Kconfig.board) | board와 SoC 의존성 |
| [`Kconfig.defconfig`](../boards/arm/owlab_link_hotswap/Kconfig.defconfig) | ZMK board 기본값 |
| [`board.cmake`](../boards/arm/owlab_link_hotswap/board.cmake) | dfu-util/J-Link runner 설정 |
| [`owlab_link_hotswap.keymap`](../boards/arm/owlab_link_hotswap/owlab_link_hotswap.keymap) | 물리 배열과 ZMK 키맵 |
| [`zephyr/link65_boot_stacks.ld`](../zephyr/link65_boot_stacks.ld) | 공장 부트로더 MSP 검사에 맞춘 스택 배치 |
| [`zephyr/CMakeLists.txt`](../zephyr/CMakeLists.txt) | board 전용 linker snippet 등록 |
| [`build.yaml`](../build.yaml) | GitHub Actions 빌드 matrix |
| [`config/west.yml`](../config/west.yml) | 사용 ZMK revision 고정 |

현재 코드는 ZMK `v0.3.0`에 고정되어 있습니다. ZMK 또는 Zephyr 버전을 올리면
linker section 이름, clock binding, Kconfig 기본값이 바뀔 수 있으므로 이식이
그대로 유지된다고 가정하면 안 됩니다.

### 8.1 고정 파티션

devicetree에는 부트로더, handoff, code 영역을 모두 명시하고 code partition만
애플리케이션 대상으로 선택합니다.

```text
CONFIG_USE_DT_CODE_PARTITION=y
```

현재 bring-up 펌웨어는 설정/storage 파티션을 만들지 않습니다. ZMK Studio나
영구 설정을 추가하려면 104 KiB code 영역 안에서 별도 파티션을 설계하고 code
크기를 줄여야 합니다. 20 KiB RAM 사용량도 함께 확인하십시오. 초기 포팅 단계에
Studio와 settings를 먼저 추가하면 부팅/USB 문제와 storage 문제를 구분하기
어려워집니다.

## 9. 빌드와 정적 검사

### 9.1 검증된 빌드 경로

이 저장소는 펌웨어 관련 push, pull request 또는 수동 실행 시
[`Build and Release ZMK firmware`](https://github.com/thsrhwk01/zmk-Owlab_Link/actions/workflows/build.yml)를
실행합니다. `boards/`, `config/`, `zephyr/`, `build.yaml` 또는 workflow 자체의
변경이 빌드를 시작하며 문서만 바꾼 push는 제외합니다. 기대 build artifact는
`owlab_link_hotswap-zmk.bin`입니다.

Release 동작은 성공한 빌드에만 연결됩니다.

- 어느 브랜치든 펌웨어 관련 변경을 push하면 Actions artifact를 만듭니다.
- `main`에 push하면 `Automatic build #<run> (<short-sha>)` 이름의 정식 GitHub
  Release도 게시하고 latest로 지정합니다.
- `v*.*` 태그를 push하면 `Release <tag>`를 게시합니다. 문자가 포함된 버전은
  prerelease, 숫자로만 된 버전은 정식 Release이자 latest가 됩니다.
- pull request와 수동 실행은 artifact만 만들고 Release를 게시하지 않습니다.

Release job은 게시 전에 104 KiB 크기 제한, 공장 부트로더 MSP 마스크, Thumb
bit와 Reset Handler 주소 범위를 검사합니다. 검사를 통과하면
`SHA256SUMS.txt`를 만들고 `.bin`과 함께 Release에 첨부합니다. 빌드 또는 검증이
실패하면 Release를 게시하지 않습니다.

GitHub workflow가 사용하는 핵심 명령 형태는 다음과 같습니다.

```console
west build -s zmk/app -b owlab_link_hotswap -- \
  -DZMK_CONFIG=/path/to/config \
  -DZMK_EXTRA_MODULES=/path/to/zmk-Owlab_Link
```

로컬 환경에서는 west workspace와 ZMK/Zephyr SDK를 먼저 준비하고 두 경로를
실제 절대 경로로 바꾸십시오. cloud build가 이 포트에서 검증된 기준 경로입니다.

### 9.2 플래시 전 필수 검사

최종 `.config`, devicetree, `.elf`, `.bin`에서 다음을 확인합니다.

- `CONFIG_FLASH_SIZE=128`
- `CONFIG_SRAM_SIZE=20`
- `CONFIG_FLASH_LOAD_OFFSET=0x6000`
- `CONFIG_USE_DT_CODE_PARTITION=y`
- `CONFIG_INIT_ARCH_HW_AT_BOOT=y`
- `CONFIG_ZMK_KSCAN_MATRIX_WAIT_BEFORE_INPUTS=1`
- `CONFIG_ZMK_KSCAN_MATRIX_WAIT_BETWEEN_OUTPUTS=30`
- 생성된 PLL node에 `usbpre` property가 없음
- 첫 load segment가 `0x08006000`에서 시작함
- 어떤 load segment도 `0x08006000` 아래를 대상으로 하지 않음
- 이미지가 flash 104 KiB와 SRAM 20 KiB 안에 들어감
- 초기 MSP가 `(msp & 0x2FFFB000) == 0x20000000`을 만족함
- Reset Handler가 Thumb bit와 애플리케이션 주소 범위를 만족함

ELF가 있다면 다음 도구가 유용합니다.

```console
arm-none-eabi-size zmk.elf
arm-none-eabi-readelf -l zmk.elf
arm-none-eabi-objdump -h zmk.elf
```

`.bin`만 있다면 PowerShell로 LINK65 전용 MSP 조건을 확인할 수 있습니다.

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

## 10. 플래시 및 실기기 검증 순서

### 10.1 handoff 영역 사전 확인

ZMK를 기록하기 직전에 보존할 영역을 다시 읽습니다.

```console
dfu-util -d 1688:2220 -a 0 -s 0x08005800:0x800 -U handoff-before.bin
```

### 10.2 애플리케이션만 기록

```console
dfu-util -d 1688:2220 -a 0 -s 0x08006000:leave -D owlab_link_hotswap-zmk.bin
```

주소를 생략하거나 `0x08000000`으로 바꾸지 마십시오.

### 10.3 단계별 acceptance test

1. DFU에서 나와 USB HID 장치로 인식되는지 확인합니다.
2. 67개 스위치를 키 테스터로 하나씩 검사합니다.
3. 각 키가 단독 입력되고 인접 키가 함께 나오지 않는지 확인합니다.
4. USB를 완전히 분리한 cold boot를 세 번 반복합니다.
5. 물리 **B** 버튼으로 공장 DFU에 다시 들어갑니다.
6. handoff 영역을 다시 읽어 사전 파일과 SHA-256이 같은지 비교합니다.
7. 필요하면 애플리케이션 영역을 readback하여 기록한 이미지와 비교합니다.

```console
dfu-util -d 1688:2220 -a 0 -s 0x08005800:0x800 -U handoff-after.bin
dfu-util -d 1688:2220 -a 0 -s 0x08006000:0x1A000 -U application-readback.bin
```

readback은 요청한 영역 끝까지 채워질 수 있으므로 애플리케이션 비교 시 원본
파일 길이만큼 비교하거나 erased padding을 고려하십시오.

## 11. 증상별 진단표

| 증상 | 우선 확인할 항목 |
| --- | --- |
| 플래시 후 다시 DFU로만 진입 | 앱 시작 주소, 벡터 테이블, MSP 마스크, Reset Handler |
| 연결 직후 “USB 장치 인식 실패” | USB 48 MHz, `USBPRE`, PA11/PA12 pinctrl, inherited interrupt 상태 |
| 몇 초 뒤 USB 인식 실패 | 앱이 실제 실행되는지, clock startup, USB reset/interrupt; 오류 시간만으로 단정하지 않음 |
| `F`가 `F+G`처럼 오른쪽 키와 함께 입력 | scan direction, active level, pull-up/down, output 간 settling delay |
| 마지막 매트릭스 열만 입력되지 않음 | PA15 JTAG 해제와 pinctrl |
| warm reset은 되지만 cold boot가 불안정 | HSE/PLL startup, bootloader handoff 상태, 초기화 순서 |
| DFU 목록에 장치가 없음 | 데이터 케이블, Windows 드라이버, 물리 버튼 순서, USB ID |
| 공장 DFU 자체가 사라짐 | 저주소 플래시 또는 option byte 훼손 가능성; 추가 쓰기를 중단하고 SWD 복구 검토 |

USB 오류가 뜨는 데 걸린 시간이나 LED 상태 하나만으로 원인을 확정하지
마십시오. build artifact, 첫 두 vector word, USB clock, readback을 함께 비교해야
합니다.

## 12. 다른 STM32F103/APM32F103 기판에 적용하는 체크리스트

### 첫 빌드 전

- [ ] MCU의 정확한 part marking과 실제 flash/SRAM 크기를 확인했다.
- [ ] HSE 주파수와 USB D-/D+ 핀을 확인했다.
- [ ] 물리 DFU 진입 방법과 USB ID를 기록했다.
- [ ] 정상 펌웨어와 전체 flash readback을 별도 보관했다.
- [ ] DFU descriptor와 실제 앱 벡터 주소를 구분했다.
- [ ] bootloader의 jump 주소와 MSP/Reset Handler 검사를 확인했다.
- [ ] 보존 영역과 code partition을 devicetree에 명시했다.
- [ ] matrix 핀 순서, 방향, 극성, pull과 지연을 확인했다.

### 플래시 전

- [ ] ELF load segment가 code partition에서만 시작한다.
- [ ] 초기 MSP와 Reset Handler가 bootloader 조건을 통과한다.
- [ ] USB peripheral clock이 정확히 48 MHz다.
- [ ] flash와 RAM 사용량이 실제 MCU 한계 안이다.
- [ ] settings/storage/Studio 없이 최소 기능부터 시작한다.
- [ ] 복구용 공식 이미지와 정확한 DFU 명령이 준비되어 있다.

### 플래시 후

- [ ] USB HID enumeration을 확인했다.
- [ ] 모든 matrix 위치를 단독 입력으로 검사했다.
- [ ] cold boot를 반복했다.
- [ ] 물리 DFU 재진입을 확인했다.
- [ ] 보존 영역의 전후 해시가 같다.
- [ ] 소스 commit, Actions run, 바이너리 해시와 결과를 기록했다.

이 체크리스트의 목적은 한 번에 완성된 펌웨어를 만드는 것이 아니라, 실패해도
USB DFU 복구 경로를 잃지 않으면서 각 하드웨어 계약을 하나씩 증명하는 것입니다.
