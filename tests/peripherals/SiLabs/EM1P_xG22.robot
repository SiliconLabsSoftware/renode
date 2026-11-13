*** Settings ***
Resource                      ${RENODEKEYWORDS}

*** Comments ***
EM1P coverage for the xG22 EMU and its radio sequencer.

EM1P is the energy mode where the host is in deep sleep but an EM1P requester keeps the
PD1 domain powered. On xG22 the requester is the radio: RAC EM1PCSR reports a request while
the sequencer is running, or while software has taken EM1P control, and the request drops
once the sequencer is in WFI with the radio state machine idle. The sequencer's own WFI
must not select the system energy mode, because that core sleeps with SLEEPDEEP clear.
EM2 shuts the sequencer down: it is held in CPUWAIT and reset, and it stays there until
software sets CPUWAITDIS again.

xG22 has no EMU STATUS.EM1P bit, so the tests read the energy mode from the EMU model.
Host clocks run in EM0 and EM1, stop in EM2, and in EM1P stop unless RAC EM1PCSR.MCUEM1PMODE
is in software control with MCUEM1PDISSWREQ clear.

The host executes a real "wfi" out of SRAM. IRQ0 is enabled up front and pended to leave
the energy mode; its handler is a short counting loop so the core stays awake there
instead of running off the end of the image. A branch to itself is not usable for that,
because this CPU model reports one as WFI.

*** Variables ***
${PLATFORM_FILE}                platforms/boards/silabs/brd4182a.repl

${RAC_CTRL}                     0xA8020014
${RAC_EM1PCSR}                  0xA802005C
${RAC_CPUWAITDIS}               0x04000000
${RAC_EM1P_SWCTRL}              0x1
${RAC_EM1P_MCU_SWCTRL}          0x10
${RAC_EM1P_MCU_DISSWREQ}        0x20
${RAC_EM1P_REQ}                 0x10000
${RAC_EM1P_ACK}                 0x20000
${RAC_EM1P_HWREQ}               0x40000

${NVIC_ISER}                    0x100
${NVIC_ISPR}                    0x200
${NVIC_SCR}                     0xD10
${SCR_SLEEPDEEP}                0x4

# Host image in the 32 KB SRAM. The vector table needs the stack pointer, the reset vector and IRQ0.
${HOST_STACK}                   0x20007000
${HOST_CODE}                    0x20000100
${HOST_IRQ0}                    0x20000200
# "movs r0, #1; subs r0, #1; b subs". Issued a PR to fix branch-to-self: https://github.com/antmicro/tlib/pull/69
${SPIN_LOOP_0}                  0x38012101
${SPIN_LOOP_1}                  0x0000E7FD
# "wfi" followed by the same loop.
${WFI_LOOP_0}                   0x2101BF30
${WFI_LOOP_1}                   0xE7FD3801

${SEQ_RAM}                      0xB0000000
${SEQ_STACK}                    0xB0003F00
${SEQ_SPIN}                     0xB0000100
${SEQ_SLEEP}                    0xB0000200

${RUN_TIME}                     0.0001
${QUANTUM}                      0.00001

${TIMER0_CMD}                   0xC
${TIMER0_CNT}                   0x24

# EUART0 is the EM2 capable UART. RXDMAWU is CFG1 bit 10. RXDATA is at offset 0x34.
${EUART0_ENABLE}                0x4
${EUART0_CFG1}                  0xC
${EUART0_CMD}                   0x30
${EUART0_RXDATA}                0x34
${EUART0_RXDATA_ADDRESS}        0x4A030034
${EUART_CMD_RXEN}               0x1
${EUART_CFG1_RXDMAWU}           0x400
${EUART_FRAME}                  0x41

# LDMA channel 0. REQSEL picks EUART0 (source 0x10) receive FIFO level (signal 0).
${LDMA_BASE}                    0x40040000
${LDMAXBAR_BASE}                0x40044000
${LDMA_CHEN}                    0x24
${LDMA_SWREQ}                   0x3C
${LDMA_IF}                      0x50
${LDMA_IEN}                     0x54
${LDMA_CH0_CTRL}                0x64
${LDMA_CH0_SRC}                 0x68
${LDMA_CH0_DST}                 0x6C
${LDMAXBAR_CH0_REQSEL}          0x0
${LDMA_REQSEL_EUART0_RXFL}      0x00100000
${LDMA_CTRL_WORD_COPY}          0x08300000
${LDMA_CTRL_BYTE_FROM_FIXED}    0x03300000
${LDMA_SOURCE}                  0x20002000
${LDMA_TARGET}                  0x20002100
${LDMA_PATTERN}                 0xA5A5A5A5

*** Keywords ***
Create Machine
    Execute Command             mach create "test"
    Execute Command             machine LoadPlatformDescription @${PLATFORM_FILE}
    Execute Command             emulation SetQuantum "${QUANTUM}"
    Execute Command             sysbus.cpu IsHalted true
    Install Host Image
    # The radio connects to the EMU from the EM1PCSR write callback, and that callback
    # only runs when the value changes. Toggle the software request so the host WFI
    # hook is installed, then leave the request clear.
    Write EM1PCSR               ${RAC_EM1P_SWCTRL}
    Write EM1PCSR               0x0

Install Host Image
    Execute Command             sysbus.cpu VectorTableOffset 0x20000000
    Execute Command             sysbus WriteDoubleWord 0x20000000 ${HOST_STACK}
    Execute Command             sysbus WriteDoubleWord 0x20000004 0x20000101
    Execute Command             sysbus WriteDoubleWord 0x20000040 0x20000201
    Execute Command             sysbus WriteDoubleWord ${HOST_CODE} ${WFI_LOOP_0}
    Execute Command             sysbus WriteDoubleWord 0x20000104 ${WFI_LOOP_1}
    Execute Command             sysbus WriteDoubleWord ${HOST_IRQ0} ${SPIN_LOOP_0}
    Execute Command             sysbus WriteDoubleWord 0x20000204 ${SPIN_LOOP_1}
    Execute Command             sysbus.nvic WriteDoubleWord ${NVIC_ISER} 0x1

Install Sequencer Image
    Execute Command             sysbus WriteDoubleWord ${SEQ_RAM} ${SEQ_STACK}
    Execute Command             sysbus WriteDoubleWord 0xB0000004 0xB0000101
    Execute Command             sysbus WriteDoubleWord ${SEQ_SPIN} ${SPIN_LOOP_0}
    Execute Command             sysbus WriteDoubleWord 0xB0000104 ${SPIN_LOOP_1}
    Execute Command             sysbus WriteDoubleWord ${SEQ_SLEEP} ${WFI_LOOP_0}
    Execute Command             sysbus WriteDoubleWord 0xB0000204 ${WFI_LOOP_1}

Enter Host Sleep
    [Arguments]                 ${deep}
    IF  ${deep}
        Execute Command         sysbus.nvic WriteDoubleWord ${NVIC_SCR} ${SCR_SLEEPDEEP}
    ELSE
        Execute Command         sysbus.nvic WriteDoubleWord ${NVIC_SCR} 0x0
    END
    Execute Command             sysbus.cpu PC ${HOST_CODE}
    Execute Command             sysbus.cpu SP ${HOST_STACK}
    Execute Command             sysbus.cpu IsHalted false
    Execute Command             emulation RunFor "${RUN_TIME}"

Wake Host
    Execute Command             sysbus.nvic WriteDoubleWord ${NVIC_ISPR} 0x1
    Execute Command             emulation RunFor "${RUN_TIME}"

Release Sequencer
    Install Sequencer Image
    Execute Command             sysbus WriteDoubleWord ${RAC_CTRL} ${RAC_CPUWAITDIS}
    Execute Command             emulation RunFor "${RUN_TIME}"

Write EM1PCSR
    [Arguments]                 ${value}
    Execute Command             sysbus WriteDoubleWord ${RAC_EM1PCSR} ${value}

Read EM1PCSR
    ${value}=                   Execute Command  sysbus ReadDoubleWord ${RAC_EM1PCSR}
    ${value}=                   Convert To Integer  ${value}
    RETURN                      ${value}

Hardware Request Should Be
    [Arguments]                 ${expected}
    ${em1pcsr}=                 Read EM1PCSR
    ${hwreq}=                   Evaluate  (${em1pcsr} & ${RAC_EM1P_HWREQ}) != 0
    Should Be Equal As Strings  ${hwreq}  ${expected}

Energy Mode Should Be
    [Arguments]                 ${expected}
    ${mode}=                    Execute Command  sysbus.emu CurrentEnergyMode
    Should Start With           ${mode}  ${expected}\n

Host Clocks Should Be
    [Arguments]                 ${expected}
    ${enabled}=                 Execute Command  sysbus.emu HostClocksEnabled
    Should Start With           ${enabled}  ${expected}

HostAll Clocks Should Be
    [Arguments]                 ${expected}
    ${enabled}=                 Execute Command  sysbus.emu HostAllClocksEnabled
    Should Start With           ${enabled}  ${expected}

Start TIMER0
    Execute Command             sysbus.timer0 WriteDoubleWord ${TIMER0_CMD} 0x1

Read TIMER0 Count
    ${value}=                   Execute Command  sysbus.timer0 ReadDoubleWord ${TIMER0_CNT}
    ${value}=                   Convert To Integer  ${value}
    RETURN                      ${value}

Configure EUART0
    [Arguments]                 ${cfg1}
    Execute Command             sysbus.eusart0 WriteDoubleWord ${EUART0_ENABLE} 0x1
    Execute Command             sysbus.eusart0 WriteDoubleWord ${EUART0_CFG1} ${cfg1}
    Execute Command             sysbus.eusart0 WriteDoubleWord ${EUART0_CMD} ${EUART_CMD_RXEN}

Receive EUART0 Frame
    Execute Command             sysbus.eusart0 WriteChar ${EUART_FRAME}

Write LDMA Register
    [Arguments]                 ${base}  ${offset}  ${value}
    ${address}=                 Evaluate  ${base} + ${offset}
    Execute Command             sysbus WriteDoubleWord ${address} ${value}

Read Word
    [Arguments]                 ${address}
    ${value}=                   Execute Command  sysbus ReadDoubleWord ${address}
    ${value}=                   Convert To Integer  ${value}
    RETURN                      ${value}

Prepare LDMA Word Copy
    Execute Command             sysbus WriteDoubleWord ${LDMA_SOURCE} ${LDMA_PATTERN}
    Execute Command             sysbus WriteDoubleWord ${LDMA_TARGET} 0x0
    Write LDMA Register         ${LDMA_BASE}  ${LDMA_CH0_CTRL}  ${LDMA_CTRL_WORD_COPY}
    Write LDMA Register         ${LDMA_BASE}  ${LDMA_CH0_SRC}  ${LDMA_SOURCE}
    Write LDMA Register         ${LDMA_BASE}  ${LDMA_CH0_DST}  ${LDMA_TARGET}
    Write LDMA Register         ${LDMA_BASE}  ${LDMA_IEN}  0x1
    Write LDMA Register         ${LDMA_BASE}  ${LDMA_CHEN}  0x1

Request LDMA Word Copy
    Write LDMA Register         ${LDMA_BASE}  ${LDMA_SWREQ}  0x1

Prepare LDMA EUART0 Receive
    Execute Command             sysbus WriteDoubleWord ${LDMA_TARGET} 0x0
    Write LDMA Register         ${LDMAXBAR_BASE}  ${LDMAXBAR_CH0_REQSEL}  ${LDMA_REQSEL_EUART0_RXFL}
    Write LDMA Register         ${LDMA_BASE}  ${LDMA_CH0_CTRL}  ${LDMA_CTRL_BYTE_FROM_FIXED}
    Write LDMA Register         ${LDMA_BASE}  ${LDMA_CH0_SRC}  ${EUART0_RXDATA_ADDRESS}
    Write LDMA Register         ${LDMA_BASE}  ${LDMA_CH0_DST}  ${LDMA_TARGET}
    Write LDMA Register         ${LDMA_BASE}  ${LDMA_IEN}  0x1
    Write LDMA Register         ${LDMA_BASE}  ${LDMA_CHEN}  0x1

LDMA Target Should Be
    [Arguments]                 ${expected}
    ${value}=                   Read Word  ${LDMA_TARGET}
    Should Be Equal As Integers  ${value}  ${expected}

*** Test Cases ***
Deep Sleep Is EM2 Until Software Requests EM1P
    Create Machine
    Energy Mode Should Be       EM0

    Enter Host Sleep            True
    Energy Mode Should Be       EM2
    Host Clocks Should Be       False
    ${em1pcsr}=                 Read EM1PCSR
    Should Be Equal As Integers  ${em1pcsr}  0x0

    Write EM1PCSR               ${RAC_EM1P_SWCTRL}
    Energy Mode Should Be       EM1P
    Host Clocks Should Be       False
    ${em1pcsr}=                 Read EM1PCSR
    ${expected}=                Evaluate  ${RAC_EM1P_SWCTRL} | ${RAC_EM1P_REQ} | ${RAC_EM1P_ACK}
    Should Be Equal As Integers  ${em1pcsr}  ${expected}

    Write EM1PCSR               0x0
    Energy Mode Should Be       EM2

    Wake Host
    Energy Mode Should Be       EM0
    Host Clocks Should Be       True

Running Sequencer Holds EM1P Until It Sleeps
    Create Machine
    Release Sequencer
    Energy Mode Should Be       EM0
    ${em1pcsr}=                 Read EM1PCSR
    ${expected}=                Evaluate  ${RAC_EM1P_REQ} | ${RAC_EM1P_ACK} | ${RAC_EM1P_HWREQ}
    Should Be Equal As Integers  ${em1pcsr}  ${expected}

    Enter Host Sleep            True
    Energy Mode Should Be       EM1P
    Host Clocks Should Be       False

    Execute Command             sysbus.seqcpu PC ${SEQ_SLEEP}
    Execute Command             emulation RunFor "${RUN_TIME}"
    Energy Mode Should Be       EM2
    ${em1pcsr}=                 Read EM1PCSR
    Should Be Equal As Integers  ${em1pcsr}  0x0

    Wake Host
    Energy Mode Should Be       EM0

EM2 Shuts The Sequencer Down Until CPUWAITDIS
    Create Machine
    Release Sequencer
    Enter Host Sleep            True
    Energy Mode Should Be       EM1P

    Execute Command             sysbus.seqcpu PC ${SEQ_SLEEP}
    Execute Command             emulation RunFor "${RUN_TIME}"
    Energy Mode Should Be       EM2
    Hardware Request Should Be  False

    # Waking the host powers the sequencer back up, but it stays in CPUWAIT.
    Wake Host
    Energy Mode Should Be       EM0
    Hardware Request Should Be  False

    # Leaving EM2 for EM1P does not release it either.
    Enter Host Sleep            True
    Energy Mode Should Be       EM2
    Write EM1PCSR               ${RAC_EM1P_SWCTRL}
    Energy Mode Should Be       EM1P
    Hardware Request Should Be  False
    Write EM1PCSR               0x0
    Energy Mode Should Be       EM2

    # The host is still in deep sleep. Setting CPUWAITDIS is what releases the core,
    # and a running sequencer brings the system back to EM1P.
    Execute Command             sysbus WriteDoubleWord ${RAC_CTRL} ${RAC_CPUWAITDIS}
    Execute Command             emulation RunFor "${RUN_TIME}"
    Energy Mode Should Be       EM1P
    Hardware Request Should Be  True

Sleep Without Deep Sleep Stays EM1
    Create Machine
    Write EM1PCSR               ${RAC_EM1P_SWCTRL}
    Enter Host Sleep            False
    Energy Mode Should Be       EM1
    Host Clocks Should Be       True

    Wake Host
    Energy Mode Should Be       EM0

MCUEM1PMODE Enables Host Clocks In EM1P
    Create Machine
    Write EM1PCSR               ${RAC_EM1P_SWCTRL}
    Enter Host Sleep            True
    Energy Mode Should Be       EM1P
    Host Clocks Should Be       False

    ${request}=                 Evaluate  ${RAC_EM1P_SWCTRL} | ${RAC_EM1P_MCU_SWCTRL}
    Write EM1PCSR               ${request}
    Energy Mode Should Be       EM1P
    Host Clocks Should Be       True

    ${disabled}=                Evaluate  ${RAC_EM1P_SWCTRL} | ${RAC_EM1P_MCU_SWCTRL} | ${RAC_EM1P_MCU_DISSWREQ}
    Write EM1PCSR               ${disabled}
    Energy Mode Should Be       EM1P
    Host Clocks Should Be       False

    Wake Host
    Energy Mode Should Be       EM0
    Host Clocks Should Be       True

Timers Stop In EM1P With MCUEM1PMODE
    Create Machine
    Start TIMER0
    ${request}=                 Evaluate  ${RAC_EM1P_SWCTRL} | ${RAC_EM1P_MCU_SWCTRL}
    Write EM1PCSR               ${request}
    Enter Host Sleep            True
    Energy Mode Should Be       EM1P
    Host Clocks Should Be       True
    HostAll Clocks Should Be    False
    ${before}=                  Read TIMER0 Count
    Execute Command             emulation RunFor "${RUN_TIME}"
    ${after}=                   Read TIMER0 Count
    Should Be Equal As Integers  ${after}  ${before}

    Wake Host
    Energy Mode Should Be       EM0
    ${resumed}=                 Read TIMER0 Count
    Should Not Be Equal As Integers  ${resumed}  ${after}

Timers Run In EM1
    Create Machine
    Start TIMER0
    Enter Host Sleep            False
    Energy Mode Should Be       EM1
    ${before}=                  Read TIMER0 Count
    Execute Command             emulation RunFor "${RUN_TIME}"
    ${after}=                   Read TIMER0 Count
    Should Not Be Equal As Integers  ${after}  ${before}

EUART0 RX DMA Wakeup Holds EM1P Until The Frame Is Read
    Create Machine
    Configure EUART0            ${EUART_CFG1_RXDMAWU}
    Enter Host Sleep            True
    Energy Mode Should Be       EM2

    Receive EUART0 Frame
    Energy Mode Should Be       EM1P
    Host Clocks Should Be       True
    HostAll Clocks Should Be    False

    Execute Command             sysbus.eusart0 ReadDoubleWord ${EUART0_RXDATA}
    Energy Mode Should Be       EM2
    Host Clocks Should Be       False

EUART0 Frame Without RXDMAWU Leaves The Host In EM2
    Create Machine
    Configure EUART0            0x0
    Enter Host Sleep            True
    Receive EUART0 Frame
    Energy Mode Should Be       EM2
    Host Clocks Should Be       False

LDMA Request Waits For Host Clocks In EM1P
    Create Machine
    Write EM1PCSR               ${RAC_EM1P_SWCTRL}
    Enter Host Sleep            True
    Energy Mode Should Be       EM1P
    Host Clocks Should Be       False
    Prepare LDMA Word Copy
    Request LDMA Word Copy
    LDMA Target Should Be       0x0

    ${request}=                 Evaluate  ${RAC_EM1P_SWCTRL} | ${RAC_EM1P_MCU_SWCTRL}
    Write EM1PCSR               ${request}
    Host Clocks Should Be       True
    LDMA Target Should Be       ${LDMA_PATTERN}

LDMA Moves EUART0 Data In EM1P While The Host Sleeps
    Create Machine
    Configure EUART0            ${EUART_CFG1_RXDMAWU}
    Prepare LDMA EUART0 Receive
    Enter Host Sleep            True
    Energy Mode Should Be       EM2
    Receive EUART0 Frame
    LDMA Target Should Be       ${EUART_FRAME}
    Energy Mode Should Be       EM2
    Host Clocks Should Be       False
