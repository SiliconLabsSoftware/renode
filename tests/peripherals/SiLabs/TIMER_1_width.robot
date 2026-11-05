*** Settings ***
Resource    ${RENODEKEYWORDS}

*** Keywords ***
Create BRD4186C
    Execute Command    mach create
    Execute Command    machine LoadPlatformDescription @platforms/boards/silabs/brd4186c.repl
    # No firmware is loaded; do not execute uninitialized flash.
    Execute Command    cpu IsHalted true
    Execute Command    seqcpu IsHalted true

Create 1 kHz Timer
    [Arguments]    ${width}=32
    Execute Command    mach create
    Execute Command    machine LoadPlatformDescriptionFromString 'timer: Timers.SiLabs_TIMER_1 @ sysbus <0x0, +0x4000> { width: ${width} }'
    Execute Command    machine LoadPlatformDescriptionFromString 'cmu: Miscellaneous.SiLabs.SiLabs_CMU_1 @ sysbus <0x4000, +0x4000> { hfxoFrequency: 1000 }'

Counter Should Be
    [Arguments]    ${address}    ${expected}
    ${actual}=    Execute Command    sysbus ReadDoubleWord ${address}
    Should Be Equal As Integers    ${actual}    ${expected}

*** Test Cases ***
BRD4186C Timer 0 And 1 Retain High Counter Bits On Both Bus Aliases
    # SiLabs SDK sisdk-2024.12, efr32mg24b310f1536im48.h:
    # https://raw.githubusercontent.com/SiliconLabs/simplicity_sdk/sisdk-2024.12/platform/Device/SiliconLabs/EFR32MG24/Include/efr32mg24b310f1536im48.h
    # TIMER0/1_CNTWIDTH=0x20; TIMER2-4_CNTWIDTH=0x10 (not instantiated on this platform).
    Create BRD4186C
    Execute Command    sysbus WriteDoubleWord 0x40048030 1
    Execute Command    sysbus WriteDoubleWord 0x4004800C 1
    Execute Command    sysbus WriteDoubleWord 0x40048024 0x00010002
    Counter Should Be    0x40048024    0x00010002
    Counter Should Be    0x50048024    0x00010002
    Execute Command    sysbus WriteDoubleWord 0x5004C030 1
    Execute Command    sysbus WriteDoubleWord 0x5004C00C 1
    Execute Command    sysbus WriteDoubleWord 0x5004C024 0x80010002
    Counter Should Be    0x5004C024    0x80010002
    Counter Should Be    0x4004C024    0x80010002
    Execute Command    machine Reset
    Counter Should Be    0x40048024    0
    Counter Should Be    0x5004C024    0

32-Bit Counter Compares Before Wrapping At 2 To The 32
    Create 1 kHz Timer
    Execute Command    sysbus WriteDoubleWord 0x30 1
    Execute Command    sysbus WriteDoubleWord 0xC 1
    Execute Command    sysbus WriteDoubleWord 0x68 0xFFFFFFFE
    Execute Command    sysbus WriteDoubleWord 0x18 0x11
    Execute Command    sysbus WriteDoubleWord 0x24 0xFFFFFFFD
    Execute Command    emulation RunFor "0.002"
    Counter Should Be    0x24    0xFFFFFFFF
    ${flags}=    Execute Command    sysbus ReadDoubleWord 0x14
    Should Be Equal As Integers    ${flags}    0x10
    Execute Command    emulation RunFor "0.001"
    Counter Should Be    0x24    0
    ${flags}=    Execute Command    sysbus ReadDoubleWord 0x14
    Should Be Equal As Integers    ${flags}    0x11

16-Bit Counter Also Wraps After Its Maximum Value
    Create 1 kHz Timer    16
    Execute Command    sysbus WriteDoubleWord 0x30 1
    Execute Command    sysbus WriteDoubleWord 0xC 1
    Execute Command    sysbus WriteDoubleWord 0x24 0xFFFE
    Execute Command    emulation RunFor "0.001"
    Counter Should Be    0x24    0xFFFF
    ${flags}=    Execute Command    sysbus ReadDoubleWord 0x14
    Should Be Equal As Integers    ${flags}    0
    Execute Command    emulation RunFor "0.001"
    Counter Should Be    0x24    0
    ${flags}=    Execute Command    sysbus ReadDoubleWord 0x14
    Should Be Equal As Integers    ${flags}    1
