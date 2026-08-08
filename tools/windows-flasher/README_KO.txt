LINK65 ZMK Windows 원클릭 플래셔
================================

지원 대상
---------
U3에 APM32F103CBT6가 장착된 Owlab LINK65 핫스왑 PCB 전용입니다.
솔더 PCB, 다른 리비전 또는 MCU가 다른 기판에는 사용하지 마십시오.

사용 방법
---------
1. ZIP의 파일을 모두 같은 폴더에 압축 해제합니다.
2. flash-link65.cmd를 더블 클릭합니다.
3. LINK65 핫스왑 PCB와 U3의 APM32F103CBT6를 확인한 뒤 경고창에서 Yes를
   클릭합니다. No를 클릭하면 아무것도 기록하지 않고 취소합니다.
4. 안내가 나오면 키보드의 USB 케이블을 분리합니다.
5. PCB의 물리 B 버튼을 누른 채 USB를 연결한 다음 B 버튼에서 손을 뗍니다.
6. Flash complete가 표시되면 USB 케이블을 분리합니다.
7. B 버튼을 누르지 않은 상태로 USB를 다시 연결합니다.
8. 키보드가 Owlab Link로 연결되는지 확인합니다.

공장 DFU 부트로더는 플래시 후 자동 재부팅 요청에 정상 응답하지 않으므로
플래셔가 자동 재부팅을 시도하지 않습니다. 완료 안내가 나온 뒤 USB를 직접
분리했다가 다시 연결하는 것이 정상 절차입니다.

처음 연결했는데 장치를 찾지 못하는 경우
----------------------------------------
Windows에서는 DFU 장치에 WinUSB 드라이버를 최초 한 번 연결해야 할 수 있습니다.

1. https://zadig.akeo.ie/ 에서 Zadig을 받습니다.
2. Options > List All Devices를 선택합니다.
3. USB ID가 1688:2220인 DFU 장치만 선택합니다.
4. 대상 드라이버를 WinUSB로 선택하고 Install Driver를 누릅니다.
5. 플래셔를 다시 실행합니다.

1688:2220이 아닌 장치의 드라이버는 변경하지 마십시오.

안전 주의
---------
이 플래셔는 LINK65 공장 부트로더를 보존하기 위해 애플리케이션 주소
0x08006000에만 기록합니다. MCU를 mass erase하거나 0x08000000에 펌웨어를
쓰지 마십시오. 공장 부트로더가 지워지면 USB DFU만으로 복구할 수 없습니다.

포함 파일
---------
- owlab_link_hotswap-zmk.bin: 이 Actions 실행에서 빌드된 ZMK 펌웨어
- flash-link65.cmd / flash-link65.ps1: 검증 및 플래시 스크립트
- dfu-util.exe / libusb-1.0.dll: dfu-util 0.11 Windows x64
- SHA256SUMS.txt: 포함된 핵심 파일의 SHA-256
- third-party/dfu-util: dfu-util/libusb 라이선스 안내 및 대응 소스
