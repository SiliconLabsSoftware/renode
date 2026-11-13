*** Settings ***
Resource                      ${RENODEKEYWORDS}

*** Comments ***
EM1P coverage for the SiXG301 EMU and its RISC-V radio sequencer.

The behavior matches the xG24 suite (EM1P_xG24.robot): the radio requests EM1P through RAC EM1PCSR
while its sequencer runs, or while software has taken EM1P control, and the request drops once
the sequencer is in WFI with the radio state machine idle. On SiXG301 the sequencer is released
from CPUWAIT by RAC CTRL.CPUWAITDIS, starting at the RVCFG1 boot address. It is not a Cortex-M
core, so its WFI never selects the system energy mode, but it takes part in the EM2 quiescence
handshake: the RISC-V subsystem accepts the request while the core waits in WFI. EM2 powers the
sequencer down, and it boots again from the retained boot address when EM2 exits.

The Host EM1P clock domain (bus, LDMA, EUSART0, ...) stops in EM2 and in EM1P unless
MCUEM1PMODE asks for it. The HostAll domain, which holds the timers and SysTick, only runs in
EM0 and EM1. EUSART0 is the EM2 capable instance and requests EM1P and the bus clock for its
DMA wake-ups. The watchdog follows EM2RUN in EM1P.

The design book lists EM1P and EM2 as not officially supported on this device. The model
follows the same handshake as the other Series 2 radios.

*** Variables ***
${PLATFORM_FILE}                platforms/boards/silabs/brd4407a.repl

${EMU_STATUS}                   0xA3008084
${EMU_STATUS_EM1P}              0x800

${RAC_CTRL}                     0xA0220014
${RAC_STATUS}                   0xA022000C
${RAC_STATUS_SEQSLEEPING}       0x400000
${RAC_EM1PCSR}                  0xA022008C
${RAC_CPUWAITDIS}               0x04000000
${RAC_EM1P_SWCTRL}              0x1
${RAC_EM1P_MCU_SWCTRL}          0x10
${RAC_EM1P_MCU_DISSWREQ}        0x20
${RAC_EM1P_REQ}                 0x10000
${RAC_EM1P_ACK}                 0x20000
${RAC_EM1P_HWREQ}               0x40000
${RVCFG1_BOOTADDR}              0xA0248024

${NVIC_ISER}                    0x100
${NVIC_ISPR}                    0x200
${NVIC_SCR}                     0xD10
${SCR_SLEEPDEEP}                0x4

# Host image in SRAM. The vector table needs the stack pointer, the reset vector and IRQ0.
${HOST_STACK}                   0x20010000
${HOST_CODE}                    0x20000100
${HOST_IRQ0}                    0x20000200
# The CPU model reports a branch-to-self as WFI, so an idle loop has to do some
# work or leaving WFI puts the core straight back to sleep. "movs r0, #1; subs r0, #1; b subs".
${SPIN_LOOP_0}                  0x38012101
${SPIN_LOOP_1}                  0x0000E7FD
# "wfi" followed by the same loop.
${WFI_LOOP_0}                   0x2101BF30
${WFI_LOOP_1}                   0xE7FD3801

# RISC-V sequencer image in sequencer RAM. "addi t0, t0, 1; j .-4" spins, and the sleep entry
# is "wfi" followed by the same loop.
${SEQ_SPIN}                     0xA0000100
${SEQ_SLEEP}                    0xA0000200
${RV_ADDI_T0}                   0x00128293
${RV_JUMP_BACK}                 0xFFDFF06F
${RV_WFI}                       0x10500073

${RUN_TIME}                     0.0001
${QUANTUM}                      0.00001

# WDOG0, same programming model as the xG24 suite.
${WDOG0_EN}                     0x4
${WDOG0_CFG}                    0x8
${WDOG0_IF}                     0x18
${WDOG_CFG_EM1RUN}              0x00030102
${WDOG_CFG_EM2RUN}              0x00030104
${WDOG_PAST_TIMEOUT}            0.004

${TIMER0_CMD}                   0xC
${TIMER0_CNT}                   0x28
${TIMER0_EN}                    0x30

# EUSART0, the EM2 capable instance.
${EUSART0_ENABLE}               0x4
${EUSART0_CFG1}                 0xC
${EUSART0_CMD}                  0x38
${EUSART0_RXDATA}               0x3C
${EUSART0_RXDATA_ADDRESS}       0x4020803C
${EUSART_CMD_RXEN}              0x1
${EUSART_CFG1_TXDMAWU}          0x200
${EUSART_CFG1_RXDMAWU}          0x400
${EUSART_CFG1_RXDMAWU_RXFIW_1}  0x08000400
${EUSART_FRAME}                 0x41

# LDMA channel 0. REQSEL picks EUSART0 (source 0x9) receive FIFO level (signal 0).
${LDMA_BASE}                    0x40814000
${LDMAXBAR_BASE}                0x40844000
${LDMA_CHEN}                    0x28
${LDMA_SWREQ}                   0x40
${LDMA_IF}                      0x54
${LDMA_IEN}                     0x58
${LDMA_CH0_CTRL}                0x78
${LDMA_CH0_SRC}                 0x7C
${LDMA_CH0_DST}                 0x80
${LDMAXBAR_CH0_REQSEL}          0x4
${LDMA_REQSEL_EUSART0_RXFL}     0x00090000
${LDMA_CTRL_WORD_COPY}          0x08300000
${LDMA_CTRL_BYTE_FROM_FIXED}    0x03300000
${LDMA_SOURCE}                  0x20002000
${LDMA_TARGET}                  0x20002100
${LDMA_PATTERN}                 0xA5A5A5A5

${SYST_CSR}                     0x10
${SYST_RVR}                     0x14
${SYST_CVR}                     0x18
${SYST_CSR_ENABLE_CORECLK}      0x5
${SYST_CSR_COUNTFLAG}           0x10000
${SYST_RELOAD}                  1000000
${SYST_PAST_RELOAD}             0.04

*** Keywords ***
Create Machine
    Execute Command             mach create "test"
    Execute Command             machine LoadPlatformDescription @${PLATFORM_FILE}
    Execute Command             emulation SetQuantum "${QUANTUM}"
    Execute Command             sysbus.cpu IsHalted true
    Install Host Image
    # The radio connects to the EMU on its first EM1PCSR update. Toggle the software request so
    # that happens, then leave the request clear.
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
    Execute Command             sysbus WriteDoubleWord ${SEQ_SPIN} ${RV_ADDI_T0}
    Execute Command             sysbus WriteDoubleWord 0xA0000104 ${RV_JUMP_BACK}
    Execute Command             sysbus WriteDoubleWord ${SEQ_SLEEP} ${RV_WFI}
    Execute Command             sysbus WriteDoubleWord 0xA0000204 ${RV_ADDI_T0}
    Execute Command             sysbus WriteDoubleWord 0xA0000208 ${RV_JUMP_BACK}
    Execute Command             sysbus WriteDoubleWord ${RVCFG1_BOOTADDR} ${SEQ_SPIN}

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

Wake Host With Interrupt Line
    # The NVIC resumes SysTick on exiting deep sleep only for a wake-up by an external
    # interrupt line, not for a software pend, so SysTick needs this wake-up.
    Execute Command             sysbus.nvic OnGPIO 0 true
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

Energy Mode Should Be
    [Arguments]                 ${expected}
    # Reading the property prints the current value followed by the accepted values.
    ${mode}=                    Execute Command  sysbus.emu CurrentEnergyMode
    Should Start With           ${mode}  ${expected}\n

Sequencer Should Be Running
    ${em1pcsr}=                 Read EM1PCSR
    ${hwreq}=                   Evaluate  (${em1pcsr} & ${RAC_EM1P_HWREQ}) != 0
    Should Be Equal As Strings  ${hwreq}  True

Sequencer Sleeping Should Be
    [Arguments]                 ${expected}
    ${status}=                  Execute Command  sysbus ReadDoubleWord ${RAC_STATUS}
    ${status}=                  Convert To Integer  ${status}
    ${bit}=                     Evaluate  (${status} & ${RAC_STATUS_SEQSLEEPING}) != 0
    Should Be Equal As Strings  ${bit}  ${expected}

EM1P Status Should Be
    [Arguments]                 ${expected}
    ${status}=                  Execute Command  sysbus ReadDoubleWord ${EMU_STATUS}
    ${status}=                  Convert To Integer  ${status}
    ${bit}=                     Evaluate  (${status} & ${EMU_STATUS_EM1P}) != 0
    Should Be Equal As Strings  ${bit}  ${expected}

Host Clocks Should Be
    [Arguments]                 ${expected}
    ${enabled}=                 Execute Command  sysbus.emu HostClocksEnabled
    Should Start With           ${enabled}  ${expected}

HostAll Clocks Should Be
    [Arguments]                 ${expected}
    ${enabled}=                 Execute Command  sysbus.emu HostAllClocksEnabled
    Should Start With           ${enabled}  ${expected}

Start TIMER0
    Execute Command             sysbus.timer0 WriteDoubleWord ${TIMER0_EN} 0x1
    Execute Command             sysbus.timer0 WriteDoubleWord ${TIMER0_CMD} 0x1

Read TIMER0 Count
    ${value}=                   Execute Command  sysbus.timer0 ReadDoubleWord ${TIMER0_CNT}
    ${value}=                   Convert To Integer  ${value}
    RETURN                      ${value}

Start SysTick
    Execute Command             sysbus.nvic WriteDoubleWord ${SYST_RVR} ${SYST_RELOAD}
    # Any write to CVR loads the reload value, otherwise the first period is the 24-bit maximum.
    Execute Command             sysbus.nvic WriteDoubleWord ${SYST_CVR} 0x0
    Execute Command             sysbus.nvic WriteDoubleWord ${SYST_CSR} ${SYST_CSR_ENABLE_CORECLK}

SysTick Should Have Counted
    [Arguments]                 ${expected}
    ${csr}=                     Execute Command  sysbus.nvic ReadDoubleWord ${SYST_CSR}
    ${csr}=                     Convert To Integer  ${csr}
    ${counted}=                 Evaluate  (${csr} & ${SYST_CSR_COUNTFLAG}) != 0
    Should Be Equal As Strings  ${counted}  ${expected}

Configure EUSART0
    [Arguments]                 ${cfg1}
    Execute Command             sysbus.eusart0 WriteDoubleWord ${EUSART0_ENABLE} 0x1
    Execute Command             sysbus.eusart0 WriteDoubleWord ${EUSART0_CFG1} ${cfg1}
    Execute Command             sysbus.eusart0 WriteDoubleWord ${EUSART0_CMD} ${EUSART_CMD_RXEN}

Receive EUSART0 Frame
    Execute Command             sysbus.eusart0 WriteChar ${EUSART_FRAME}

Read EUSART0 Frame
    Execute Command             sysbus.eusart0 ReadDoubleWord ${EUSART0_RXDATA}

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

Prepare LDMA EUSART0 Receive
    Execute Command             sysbus WriteDoubleWord ${LDMA_TARGET} 0x0
    Write LDMA Register         ${LDMAXBAR_BASE}  ${LDMAXBAR_CH0_REQSEL}  ${LDMA_REQSEL_EUSART0_RXFL}
    Write LDMA Register         ${LDMA_BASE}  ${LDMA_CH0_CTRL}  ${LDMA_CTRL_BYTE_FROM_FIXED}
    Write LDMA Register         ${LDMA_BASE}  ${LDMA_CH0_SRC}  ${EUSART0_RXDATA_ADDRESS}
    Write LDMA Register         ${LDMA_BASE}  ${LDMA_CH0_DST}  ${LDMA_TARGET}
    Write LDMA Register         ${LDMA_BASE}  ${LDMA_IEN}  0x1
    Write LDMA Register         ${LDMA_BASE}  ${LDMA_CHEN}  0x1

LDMA Target Should Be
    [Arguments]                 ${expected}
    ${value}=                   Read Word  ${LDMA_TARGET}
    Should Be Equal As Integers  ${value}  ${expected}

LDMA Done Flag Should Be
    [Arguments]                 ${expected}
    ${address}=                 Evaluate  ${LDMA_BASE} + ${LDMA_IF}
    ${flags}=                   Read Word  ${address}
    ${done}=                    Evaluate  (${flags} & 0x1) != 0
    Should Be Equal As Strings  ${done}  ${expected}

Timer Should Be Frozen In EM1P
    [Arguments]                 ${host_clock_request}
    Create Machine
    Start TIMER0
    ${request}=                 Set Variable  ${RAC_EM1P_SWCTRL}
    IF  ${host_clock_request}
        ${request}=             Evaluate  ${RAC_EM1P_SWCTRL} | ${RAC_EM1P_MCU_SWCTRL}
    END
    Write EM1PCSR               ${request}
    Enter Host Sleep            True
    Energy Mode Should Be       EM1P
    HostAll Clocks Should Be    False
    ${before}=                  Read TIMER0 Count
    Execute Command             emulation RunFor "${RUN_TIME}"
    ${after}=                   Read TIMER0 Count
    Should Be Equal As Integers  ${after}  ${before}

    Wake Host
    Energy Mode Should Be       EM0
    HostAll Clocks Should Be    True
    ${resumed}=                 Read TIMER0 Count
    Should Not Be Equal As Integers  ${resumed}  ${after}

Configure WDOG
    [Arguments]                 ${em2run}
    IF  ${em2run}
        Execute Command         sysbus.wdog0 WriteDoubleWord ${WDOG0_CFG} ${WDOG_CFG_EM2RUN}
    ELSE
        Execute Command         sysbus.wdog0 WriteDoubleWord ${WDOG0_CFG} ${WDOG_CFG_EM1RUN}
    END
    Execute Command             sysbus.wdog0 WriteDoubleWord ${WDOG0_EN} 0x1

WDOG Timeout Should Be
    [Arguments]                 ${expected}
    ${flags}=                   Execute Command  sysbus.wdog0 ReadDoubleWord ${WDOG0_IF}
    ${flags}=                   Convert To Integer  ${flags}
    ${timeout}=                 Evaluate  (${flags} & 0x1) != 0
    Should Be Equal As Strings  ${timeout}  ${expected}

*** Test Cases ***
Deep Sleep Is EM2 Until Software Requests EM1P
    Create Machine
    Energy Mode Should Be       EM0
    EM1P Status Should Be       False

    Enter Host Sleep            True
    Energy Mode Should Be       EM2
    EM1P Status Should Be       False
    Host Clocks Should Be       False
    HostAll Clocks Should Be    False
    ${em1pcsr}=                 Read EM1PCSR
    Should Be Equal As Integers  ${em1pcsr}  0x0

    # Software control with the request enabled. The ack follows the request at once.
    Write EM1PCSR               ${RAC_EM1P_SWCTRL}
    Energy Mode Should Be       EM1P
    EM1P Status Should Be       True
    Host Clocks Should Be       False
    HostAll Clocks Should Be    False
    ${em1pcsr}=                 Read EM1PCSR
    ${expected}=                Evaluate  ${RAC_EM1P_SWCTRL} | ${RAC_EM1P_REQ} | ${RAC_EM1P_ACK}
    Should Be Equal As Integers  ${em1pcsr}  ${expected}

    Write EM1PCSR               0x0
    Energy Mode Should Be       EM2
    EM1P Status Should Be       False

    Wake Host
    Energy Mode Should Be       EM0
    Host Clocks Should Be       True
    HostAll Clocks Should Be    True

Running Sequencer Holds EM1P Until It Sleeps
    Create Machine
    # CPUWAIT holds the sequencer, and SEQSLEEPING stays clear until it executes WFI.
    Sequencer Sleeping Should Be    False
    Release Sequencer
    Sequencer Sleeping Should Be    False
    # The host is halted, so a sequencer request on its own leaves the system in EM0.
    Energy Mode Should Be       EM0
    ${em1pcsr}=                 Read EM1PCSR
    ${expected}=                Evaluate  ${RAC_EM1P_REQ} | ${RAC_EM1P_ACK} | ${RAC_EM1P_HWREQ}
    Should Be Equal As Integers  ${em1pcsr}  ${expected}

    Enter Host Sleep            True
    Energy Mode Should Be       EM1P
    EM1P Status Should Be       True
    Host Clocks Should Be       False

    # The sequencer goes to WFI with the radio idle, which clears the hardware request. The
    # RISC-V subsystem accepts the quiescence request while the core waits in WFI.
    Execute Command             sysbus.seqcpu PC ${SEQ_SLEEP}
    Execute Command             emulation RunFor "${RUN_TIME}"
    Energy Mode Should Be       EM2
    EM1P Status Should Be       False
    ${em1pcsr}=                 Read EM1PCSR
    Should Be Equal As Integers  ${em1pcsr}  0x0
    # EM2 powers the sequencer down, so it is no longer in WFI.
    Sequencer Sleeping Should Be    False

    Wake Host
    Energy Mode Should Be       EM0

Sequencer Deep Sleep Lets The Host Enter EM2 And Resets The Sequencer
    Create Machine
    Release Sequencer
    Enter Host Sleep            True
    Energy Mode Should Be       EM1P

    # The sequencer goes to WFI with the radio idle, which clears the hardware request. WFI alone lets the
    # RISC-V subsystem accept the EM2 request.
    Execute Command             sysbus.seqcpu PC ${SEQ_SLEEP}
    Execute Command             emulation RunFor "${RUN_TIME}"
    Energy Mode Should Be       EM2
    EM1P Status Should Be       False
    ${em1pcsr}=                 Read EM1PCSR
    Should Be Equal As Integers  ${em1pcsr}  0x0
    # EM2 powers the sequencer down, so it is no longer in WFI.
    Sequencer Sleeping Should Be    False

    # Leaving EM2 powers the sequencer up again from the retained boot address.
    Wake Host
    Energy Mode Should Be       EM0
    Sequencer Should Be Running
    Sequencer Sleeping Should Be    False

Sequencer Restarts When EM2 Exits To EM1P
    Create Machine
    Release Sequencer
    Enter Host Sleep            True
    Execute Command             sysbus.seqcpu PC ${SEQ_SLEEP}
    Execute Command             emulation RunFor "${RUN_TIME}"
    Energy Mode Should Be       EM2
    ${em1pcsr}=                 Read EM1PCSR
    Should Be Equal As Integers  ${em1pcsr}  0x0

    # Software takes EM1P control while the host stays in deep sleep. The powered up sequencer
    # starts again and requests EM1P on its own.
    Write EM1PCSR               ${RAC_EM1P_SWCTRL}
    Energy Mode Should Be       EM1P
    Sequencer Should Be Running
    Write EM1PCSR               0x0
    Energy Mode Should Be       EM1P
    Sequencer Sleeping Should Be    False

Sleep Without Deep Sleep Stays EM1
    Create Machine
    Write EM1PCSR               ${RAC_EM1P_SWCTRL}
    Enter Host Sleep            False
    Energy Mode Should Be       EM1
    EM1P Status Should Be       False
    Host Clocks Should Be       True
    HostAll Clocks Should Be    True

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
    HostAll Clocks Should Be    False

    ${disabled}=                Evaluate  ${RAC_EM1P_SWCTRL} | ${RAC_EM1P_MCU_SWCTRL} | ${RAC_EM1P_MCU_DISSWREQ}
    Write EM1PCSR               ${disabled}
    Energy Mode Should Be       EM1P
    Host Clocks Should Be       False

    Wake Host
    Energy Mode Should Be       EM0
    Host Clocks Should Be       True

EM2RUN Clear Freezes WDOG In EM1P
    Create Machine
    Configure WDOG              False
    Write EM1PCSR               ${RAC_EM1P_SWCTRL}
    Enter Host Sleep            True
    Energy Mode Should Be       EM1P
    Execute Command             emulation RunFor "${WDOG_PAST_TIMEOUT}"
    Energy Mode Should Be       EM1P
    WDOG Timeout Should Be      False
    Wake Host
    Energy Mode Should Be       EM0
    Execute Command             emulation RunFor "${WDOG_PAST_TIMEOUT}"
    WDOG Timeout Should Be      True

EM2RUN Set Lets WDOG Run In EM1P
    Create Machine
    Configure WDOG              True
    Write EM1PCSR               ${RAC_EM1P_SWCTRL}
    Enter Host Sleep            True
    Energy Mode Should Be       EM1P
    Execute Command             emulation RunFor "${WDOG_PAST_TIMEOUT}"
    Energy Mode Should Be       EM1P
    WDOG Timeout Should Be      True

Timers Stop In EM1P Without Host Clock Request
    Timer Should Be Frozen In EM1P  False

Timers Stay Stopped In EM1P With MCUEM1PMODE
    Timer Should Be Frozen In EM1P  True

Timers Stop In EM2
    Create Machine
    Start TIMER0
    Enter Host Sleep            True
    Energy Mode Should Be       EM2
    ${before}=                  Read TIMER0 Count
    Execute Command             emulation RunFor "${RUN_TIME}"
    ${after}=                   Read TIMER0 Count
    Should Be Equal As Integers  ${after}  ${before}

Timers Run In EM1
    Create Machine
    Start TIMER0
    Enter Host Sleep            False
    Energy Mode Should Be       EM1
    ${before}=                  Read TIMER0 Count
    Execute Command             emulation RunFor "${RUN_TIME}"
    ${after}=                   Read TIMER0 Count
    Should Not Be Equal As Integers  ${after}  ${before}

SysTick Is Stopped In EM1P
    Create Machine
    Start SysTick
    ${request}=                 Evaluate  ${RAC_EM1P_SWCTRL} | ${RAC_EM1P_MCU_SWCTRL}
    Write EM1PCSR               ${request}
    Enter Host Sleep            True
    Energy Mode Should Be       EM1P
    Execute Command             emulation RunFor "${SYST_PAST_RELOAD}"
    Energy Mode Should Be       EM1P
    SysTick Should Have Counted  False

    Wake Host With Interrupt Line
    Energy Mode Should Be       EM0
    Execute Command             emulation RunFor "${SYST_PAST_RELOAD}"
    SysTick Should Have Counted  True

EUSART0 RX DMA Wakeup Holds EM1P Until The Frame Is Read
    Create Machine
    Configure EUSART0           ${EUSART_CFG1_RXDMAWU}
    Enter Host Sleep            True
    Energy Mode Should Be       EM2
    Host Clocks Should Be       False

    Receive EUSART0 Frame
    Energy Mode Should Be       EM1P
    EM1P Status Should Be       True
    Host Clocks Should Be       True
    HostAll Clocks Should Be    False

    Read EUSART0 Frame
    Energy Mode Should Be       EM2
    EM1P Status Should Be       False
    Host Clocks Should Be       False

EUSART0 Frame Without RXDMAWU Leaves The Host In EM2
    Create Machine
    Configure EUSART0           0x0
    Enter Host Sleep            True
    Energy Mode Should Be       EM2

    Receive EUSART0 Frame
    Energy Mode Should Be       EM2
    Host Clocks Should Be       False

EUSART0 RX DMA Wakeup Waits For RXFIW Frames
    Create Machine
    Configure EUSART0           ${EUSART_CFG1_RXDMAWU_RXFIW_1}
    Enter Host Sleep            True
    Energy Mode Should Be       EM2

    Receive EUSART0 Frame
    Energy Mode Should Be       EM2
    Receive EUSART0 Frame
    Energy Mode Should Be       EM1P
    Host Clocks Should Be       True

    Read EUSART0 Frame
    Energy Mode Should Be       EM2

EUSART0 TX DMA Wakeup Holds EM1P While Enabled
    Create Machine
    Configure EUSART0           ${EUSART_CFG1_TXDMAWU}
    Enter Host Sleep            True
    Energy Mode Should Be       EM1P
    Host Clocks Should Be       True
    HostAll Clocks Should Be    False

    Execute Command             sysbus.eusart0 WriteDoubleWord ${EUSART0_CFG1} 0x0
    Energy Mode Should Be       EM2
    Host Clocks Should Be       False

Only EUSART0 Requests EM1P
    Create Machine
    Execute Command             sysbus.eusart1 WriteDoubleWord ${EUSART0_ENABLE} 0x1
    Execute Command             sysbus.eusart1 WriteDoubleWord ${EUSART0_CFG1} ${EUSART_CFG1_TXDMAWU}
    Enter Host Sleep            True
    Energy Mode Should Be       EM2

LDMA Request Waits For Host Clocks In EM1P
    Create Machine
    Write EM1PCSR               ${RAC_EM1P_SWCTRL}
    Enter Host Sleep            True
    Energy Mode Should Be       EM1P
    Host Clocks Should Be       False
    Prepare LDMA Word Copy

    Request LDMA Word Copy
    LDMA Target Should Be       0x0
    LDMA Done Flag Should Be    False

    ${request}=                 Evaluate  ${RAC_EM1P_SWCTRL} | ${RAC_EM1P_MCU_SWCTRL}
    Write EM1PCSR               ${request}
    Host Clocks Should Be       True
    LDMA Target Should Be       ${LDMA_PATTERN}
    LDMA Done Flag Should Be    True

LDMA Request Waits For Host Clocks In EM2
    Create Machine
    Enter Host Sleep            True
    Energy Mode Should Be       EM2
    Prepare LDMA Word Copy

    Request LDMA Word Copy
    LDMA Target Should Be       0x0

    Wake Host
    Energy Mode Should Be       EM0
    LDMA Target Should Be       ${LDMA_PATTERN}
    LDMA Done Flag Should Be    True

LDMA Runs Immediately While The Host Clocks Run
    Create Machine
    Enter Host Sleep            False
    Energy Mode Should Be       EM1
    Prepare LDMA Word Copy

    Request LDMA Word Copy
    LDMA Target Should Be       ${LDMA_PATTERN}

LDMA Moves EUSART0 Data In EM1P While The Host Sleeps
    Create Machine
    Configure EUSART0           ${EUSART_CFG1_RXDMAWU}
    Prepare LDMA EUSART0 Receive
    Enter Host Sleep            True
    Energy Mode Should Be       EM2

    Receive EUSART0 Frame
    LDMA Target Should Be       ${EUSART_FRAME}
    LDMA Done Flag Should Be    True
    Energy Mode Should Be       EM2
    EM1P Status Should Be       False
    Host Clocks Should Be       False
