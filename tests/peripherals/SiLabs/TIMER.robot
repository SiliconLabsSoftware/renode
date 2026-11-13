*** Variables ***
${IP_VERSION}                   0
${CLOCK_FREQUENCY}              50000
# A prescaler value of 1 actually causes the clock frequency to be halved
${PRESCALER}                    1
${FREQUENCY}                    25000
${REPL_STRING}=                 SEPARATOR=
...  """                                                               ${\n}
...  timer: Timers.SiLabs_TIMER_${IP_VERSION} @ sysbus <0x0, +0x4000>  ${\n}
...  cmu: Miscellaneous.SiLabs.SiLabs_CMU_1 @ sysbus <0x4000, +0x4000> ${\n}
...  ${SPACE*4}hfxoFrequency: ${CLOCK_FREQUENCY}                       ${\n}
...  """
${REPL_STRING_V1}=              SEPARATOR=
...  """                                                               ${\n}
...  timer: Timers.SiLabs_TIMER_1 @ sysbus <0x0, +0x4000>              ${\n}
...  ${SPACE*4}width: 32                                               ${\n}
...  cmu: Miscellaneous.SiLabs.SiLabs_CMU_1 @ sysbus <0x4000, +0x4000> ${\n}
...  ${SPACE*4}hfxoFrequency: ${CLOCK_FREQUENCY}                       ${\n}
...  """
${REPL_STRING_V3}=              SEPARATOR=
...  """                                                               ${\n}
...  timer: Miscellaneous.SiLabs.SiLabs_TIMER_3 @ sysbus <0x0, +0x4000> ${\n}
...  cmu: Miscellaneous.SiLabs.SiLabs_CMU_1 @ sysbus <0x4000, +0x4000> ${\n}
...  ${SPACE*4}hfxoFrequency: ${CLOCK_FREQUENCY}                       ${\n}
...  """
# 1 kHz so each RunFor "0.001" is one counter tick. Width is a constructor argument.
${REPL_STRING_V1_16}=           SEPARATOR=
...  """                                                               ${\n}
...  timer: Timers.SiLabs_TIMER_1 @ sysbus <0x0, +0x4000>              ${\n}
...  ${SPACE*4}width: 16                                               ${\n}
...  cmu: Miscellaneous.SiLabs.SiLabs_CMU_1 @ sysbus <0x4000, +0x4000> ${\n}
...  ${SPACE*4}hfxoFrequency: 1000                                     ${\n}
...  """
${REPL_STRING_V1_32}=           SEPARATOR=
...  """                                                               ${\n}
...  timer: Timers.SiLabs_TIMER_1 @ sysbus <0x0, +0x4000>              ${\n}
...  ${SPACE*4}width: 32                                               ${\n}
...  cmu: Miscellaneous.SiLabs.SiLabs_CMU_1 @ sysbus <0x4000, +0x4000> ${\n}
...  ${SPACE*4}hfxoFrequency: 1000                                     ${\n}
...  """

# Register definitions for different IP versions
&{REGS_V0}    CFG=0x0004    CTRL=0x0008    CMD=0x000C    STATUS=0x0010    IF=0x0014    IEN=0x0018    TOP=0x001C    CNT=0x0024    CCO_CFG=0x0060    CCO_CTRL=0x0064    CCO_OC=0x0070    CC1_CFG=0x0080    CC1_CTRL=0x0084    CC1_OC=0x0088
&{REGS_V1}    CFG=0x0004    CTRL=0x0008    CMD=0x000C    STATUS=0x0010    IF=0x0014    IEN=0x0018    TOP=0x001C    CNT=0x0024    EN=0x0030    CCO_CFG=0x0060    CCO_CTRL=0x0064    CCO_OC=0x0068    CC1_CFG=0x0080    CC1_CTRL=0x0084    CC1_OC=0x0088
&{REGS_V2}    CFG=0x0004    CTRL=0x0008    CMD=0x000C    STATUS=0x0010    IF=0x0018    IEN=0x001C    TOP=0x0020    CNT=0x0028    CCO_CFG=0x0060    CCO_CTRL=0x0064    CCO_OC=0x0070    CC1_CFG=0x0090    CC1_CTRL=0x0094    CC1_OC=0x00A0
&{REGS_V3}    EN=0x0004    CFG=0x0008    CTRL=0x0010    CMD=0x0014    STATUS=0x0018    IF=0x0020    IEN=0x0024    TOP=0x0028    CNT=0x0030    CCO_CFG=0x0060    CCO_CTRL=0x0064    CCO_OC=0x0070    CCO_IF=0x008C    CCO_IEN=0x0090    CC1_CFG=0x00A0    CC1_CTRL=0x00A4    CC1_OC=0x00B0    CC1_IF=0x00CC    CC1_IEN=0x00D0
&{REGS_V4}    CFG=0x0004    CTRL=0x0008    CMD=0x000C    STATUS=0x0010    IF=0x0018    IEN=0x001C    TOP=0x0020    CNT=0x0028    CCO_CFG=0x0060    CCO_CTRL=0x0064    CCO_OC=0x0070    CC1_CFG=0x0090    CC1_CTRL=0x0094    CC1_OC=0x00A0

*** Keywords ***
Setup Registers
    # Set register variables based on IP_VERSION
    IF  ${IP_VERSION} == 0
        Set Suite Variable    ${CFG_REG}      ${REGS_V0.CFG}
        Set Suite Variable    ${CTRL_REG}     ${REGS_V0.CTRL}
        Set Suite Variable    ${CMD_REG}      ${REGS_V0.CMD}
        Set Suite Variable    ${STATUS_REG}   ${REGS_V0.STATUS}
        Set Suite Variable    ${IF_REG}       ${REGS_V0.IF}
        Set Suite Variable    ${IEN_REG}      ${REGS_V0.IEN}
        Set Suite Variable    ${TOP_REG}      ${REGS_V0.TOP}
        Set Suite Variable    ${CNT_REG}      ${REGS_V0.CNT}
        Set Suite Variable    ${CCO_CFG}      ${REGS_V0.CCO_CFG}
        Set Suite Variable    ${CCO_CTRL}     ${REGS_V0.CCO_CTRL}
        Set Suite Variable    ${CCO_OC}       ${REGS_V0.CCO_OC}
        Set Suite Variable    ${CC1_CFG}      ${REGS_V0.CC1_CFG}
        Set Suite Variable    ${CC1_CTRL}     ${REGS_V0.CC1_CTRL}
        Set Suite Variable    ${CC1_OC}       ${REGS_V0.CC1_OC}
    ELSE IF  ${IP_VERSION} == 1
        Set Suite Variable    ${CFG_REG}      ${REGS_V1.CFG}
        Set Suite Variable    ${CTRL_REG}     ${REGS_V1.CTRL}
        Set Suite Variable    ${CMD_REG}      ${REGS_V1.CMD}
        Set Suite Variable    ${STATUS_REG}   ${REGS_V1.STATUS}
        Set Suite Variable    ${IF_REG}       ${REGS_V1.IF}
        Set Suite Variable    ${IEN_REG}      ${REGS_V1.IEN}
        Set Suite Variable    ${TOP_REG}      ${REGS_V1.TOP}
        Set Suite Variable    ${CNT_REG}      ${REGS_V1.CNT}
        Set Suite Variable    ${EN_REG}       ${REGS_V1.EN}
        Set Suite Variable    ${CCO_CFG}      ${REGS_V1.CCO_CFG}
        Set Suite Variable    ${CCO_CTRL}     ${REGS_V1.CCO_CTRL}
        Set Suite Variable    ${CCO_OC}       ${REGS_V1.CCO_OC}
        Set Suite Variable    ${CC1_CFG}      ${REGS_V1.CC1_CFG}
        Set Suite Variable    ${CC1_CTRL}     ${REGS_V1.CC1_CTRL}
        Set Suite Variable    ${CC1_OC}       ${REGS_V1.CC1_OC}
    ELSE IF  ${IP_VERSION} == 2
        Set Suite Variable    ${CFG_REG}      ${REGS_V2.CFG}
        Set Suite Variable    ${CTRL_REG}     ${REGS_V2.CTRL}
        Set Suite Variable    ${CMD_REG}      ${REGS_V2.CMD}
        Set Suite Variable    ${STATUS_REG}   ${REGS_V2.STATUS}
        Set Suite Variable    ${IF_REG}       ${REGS_V2.IF}
        Set Suite Variable    ${IEN_REG}      ${REGS_V2.IEN}
        Set Suite Variable    ${TOP_REG}      ${REGS_V2.TOP}
        Set Suite Variable    ${CNT_REG}      ${REGS_V2.CNT}
        Set Suite Variable    ${CCO_CFG}      ${REGS_V2.CCO_CFG}
        Set Suite Variable    ${CCO_CTRL}     ${REGS_V2.CCO_CTRL}
        Set Suite Variable    ${CCO_OC}       ${REGS_V2.CCO_OC}
        Set Suite Variable    ${CC1_CFG}      ${REGS_V2.CC1_CFG}
        Set Suite Variable    ${CC1_CTRL}     ${REGS_V2.CC1_CTRL}
        Set Suite Variable    ${CC1_OC}       ${REGS_V2.CC1_OC}
    ELSE IF  ${IP_VERSION} == 4
        Set Suite Variable    ${CFG_REG}      ${REGS_V4.CFG}
        Set Suite Variable    ${CTRL_REG}     ${REGS_V4.CTRL}
        Set Suite Variable    ${CMD_REG}      ${REGS_V4.CMD}
        Set Suite Variable    ${STATUS_REG}   ${REGS_V4.STATUS}
        Set Suite Variable    ${IF_REG}       ${REGS_V4.IF}
        Set Suite Variable    ${IEN_REG}      ${REGS_V4.IEN}
        Set Suite Variable    ${TOP_REG}      ${REGS_V4.TOP}
        Set Suite Variable    ${CNT_REG}      ${REGS_V4.CNT}
        Set Suite Variable    ${CCO_CFG}      ${REGS_V4.CCO_CFG}
        Set Suite Variable    ${CCO_CTRL}     ${REGS_V4.CCO_CTRL}
        Set Suite Variable    ${CCO_OC}       ${REGS_V4.CCO_OC}
        Set Suite Variable    ${CC1_CFG}      ${REGS_V4.CC1_CFG}
        Set Suite Variable    ${CC1_CTRL}     ${REGS_V4.CC1_CTRL}
        Set Suite Variable    ${CC1_OC}       ${REGS_V4.CC1_OC}
    ELSE IF  ${IP_VERSION} == 3
        Set Suite Variable    ${EN_REG}       ${REGS_V3.EN}
        Set Suite Variable    ${CFG_REG}      ${REGS_V3.CFG}
        Set Suite Variable    ${CTRL_REG}     ${REGS_V3.CTRL}
        Set Suite Variable    ${CMD_REG}      ${REGS_V3.CMD}
        Set Suite Variable    ${STATUS_REG}   ${REGS_V3.STATUS}
        Set Suite Variable    ${IF_REG}       ${REGS_V3.IF}
        Set Suite Variable    ${IEN_REG}      ${REGS_V3.IEN}
        Set Suite Variable    ${TOP_REG}      ${REGS_V3.TOP}
        Set Suite Variable    ${CNT_REG}      ${REGS_V3.CNT}
        Set Suite Variable    ${CCO_CFG}      ${REGS_V3.CCO_CFG}
        Set Suite Variable    ${CCO_CTRL}     ${REGS_V3.CCO_CTRL}
        Set Suite Variable    ${CCO_OC}       ${REGS_V3.CCO_OC}
        Set Suite Variable    ${CCO_IF}       ${REGS_V3.CCO_IF}
        Set Suite Variable    ${CCO_IEN}      ${REGS_V3.CCO_IEN}
        Set Suite Variable    ${CC1_CFG}      ${REGS_V3.CC1_CFG}
        Set Suite Variable    ${CC1_CTRL}     ${REGS_V3.CC1_CTRL}
        Set Suite Variable    ${CC1_OC}       ${REGS_V3.CC1_OC}
        Set Suite Variable    ${CC1_IF}       ${REGS_V3.CC1_IF}
        Set Suite Variable    ${CC1_IEN}      ${REGS_V3.CC1_IEN}
    ELSE
        Fail  Unsupported IP version: ${IP_VERSION} 
    END

Create Machine
    Setup Registers
    Execute Command                 mach create "test"
    IF  ${IP_VERSION} == 3
        Execute Command             machine LoadPlatformDescriptionFromString ${REPL_STRING_V3}
    ELSE IF  ${IP_VERSION} == 1
        Execute Command             machine LoadPlatformDescriptionFromString ${REPL_STRING_V1}
    ELSE
        Execute Command             machine LoadPlatformDescriptionFromString ${REPL_STRING}
    END
    Execute Command                 logLevel 1 sysbus.timer

Enable Timer Peripheral
    IF  ${IP_VERSION} == 1 or ${IP_VERSION} == 3
        Execute Command             sysbus.timer WriteDoubleWord ${EN_REG} 0x1
    END

Enable All Interrupts
    IF  ${IP_VERSION} == 3
        Enable Timer Peripheral
        Execute Command             sysbus.timer WriteDoubleWord ${IEN_REG} 0x7F
        Execute Command             sysbus.timer WriteDoubleWord ${CCO_IEN} 0x1
        Execute Command             sysbus.timer WriteDoubleWord ${CC1_IEN} 0x1
    ELSE
        Execute Command             sysbus.timer WriteDoubleWord ${IEN_REG} 0x7F3
    END

Clear Interrupt Flags
    Execute Command                 sysbus.timer WriteDoubleWord ${IF_REG} 0
    IF  ${IP_VERSION} == 3
        Execute Command             sysbus.timer WriteDoubleWord ${CCO_IF} 0
        Execute Command             sysbus.timer WriteDoubleWord ${CC1_IF} 0
    END

Assert Overflow Interrupt Flag
    ${read_val}=                    Execute Command  sysbus.timer ReadDoubleWord ${IF_REG}
    Should Be Equal As Integers     ${read_val}  0x1

Assert Underflow Interrupt Flag
    ${read_val}=                    Execute Command  sysbus.timer ReadDoubleWord ${IF_REG}
    Should Be Equal As Integers     ${read_val}  0x2

Assert CC0 Interrupt Flag
    IF  ${IP_VERSION} == 3
        ${read_val}=                Execute Command  sysbus.timer ReadDoubleWord ${CCO_IF}
        Should Be Equal As Integers  ${read_val}  0x1
    ELSE
        ${read_val}=                Execute Command  sysbus.timer ReadDoubleWord ${IF_REG}
        Should Be Equal As Integers  ${read_val}  0x10
    END

Assert CC1 Interrupt Flag
    IF  ${IP_VERSION} == 3
        ${read_val}=                Execute Command  sysbus.timer ReadDoubleWord ${CC1_IF}
        Should Be Equal As Integers  ${read_val}  0x1
    ELSE
        ${read_val}=                Execute Command  sysbus.timer ReadDoubleWord ${IF_REG}
        Should Be Equal As Integers  ${read_val}  0x20
    END

Configure Timer
    [Arguments]  ${down_count}  ${one_shot}
    ${reg_val}                      Evaluate  ${PRESCALER} << 18
    IF  ${down_count}
        ${reg_val}                  Evaluate  ${reg_val} | 0x1
    END
    IF  ${one_shot}
        ${reg_val}                  Evaluate  ${reg_val} | 0x10
    END
    Enable Timer Peripheral
    Execute Command                 sysbus WriteDoubleWord ${CFG_REG} ${reg_val}

Set Top Value
    [Arguments]  ${top_val}
    Execute Command                 sysbus WriteDoubleWord ${TOP_REG} ${top_val}

Start Command
    Execute Command                 sysbus.timer WriteDoubleWord ${CMD_REG} 0x1

Stop Command
    Execute Command                 sysbus.timer WriteDoubleWord ${CMD_REG} 0x2

Assert Counter Value
    [Arguments]  ${expected_val}
    ${current_val}=                 Execute Command  sysbus.timer ReadDoubleWord ${CNT_REG}
    Should Be Equal As Integers     ${expected_val}  ${current_val}

Assert Timer Is Running
    [Arguments]  ${is_running}
    ${read_val}=                    Execute Command  sysbus.timer ReadDoubleWord ${STATUS_REG}
    ${read_val}=                    Convert To Integer  ${read_val}
    ${check_val}                    Evaluate  ${read_val} & 0x1
    IF  ${is_running}
        Should Be Equal As Integers  ${check_val}  0x1
    ELSE
        Should Be Equal As Integers  ${check_val}  0x0
    END

Assert IRQ Is Set
    ${irqState}=                    Execute Command  sysbus.timer IRQ
    Should Contain                  ${irqState}  GPIO: set

Assert IRQ Is Unset
    ${irqState}=                    Execute Command  sysbus.timer IRQ
    Should Contain                  ${irqState}  GPIO: unset

Require Counter Width Model
    Skip If    ${IP_VERSION} != 1    Counter width is a TIMER_1 constructor argument

# Up-count holds TOP for one counter clock, then wraps. At 25 kHz that clock is 40 us.
Advance Past Top
    Execute Command                 emulation RunFor "0.00004"

Create Width Machine
    [Arguments]    ${width}
    Require Counter Width Model
    Setup Registers
    Execute Command                 mach create "test"
    IF  ${width} == 32
        Execute Command             machine LoadPlatformDescriptionFromString ${REPL_STRING_V1_32}
    ELSE
        Execute Command             machine LoadPlatformDescriptionFromString ${REPL_STRING_V1_16}
    END
    Execute Command                 logLevel 1 sysbus.timer
    Execute Command                 sysbus.timer WriteDoubleWord ${EN_REG} 0x1

*** Test Cases ***
Overflow
    Create Machine
    Assert IRQ Is Unset
    Assert Timer Is Running         False
    # Configure the timer to count up, no one-shot mode
    Configure Timer                 False  False
    # Enable all implemented interrupts
    Enable All Interrupts
    # TOP is the counter maximum. After two seconds the counter equals TOP.
    # The next tick wraps to 0 and sets the overflow flag.
    ${top_val}                      Evaluate  ${FREQUENCY} * 2
    Set Top Value                   ${top_val}
    Assert Timer Is Running         False
    # Start the timer
    Start Command
    Assert Timer Is Running         True
    Assert Counter Value            0
    Assert IRQ Is Unset
    Execute Command                 emulation RunFor "1"
    ${check_val}                    Evaluate  ${FREQUENCY} * 1
    Assert Counter Value            ${check_val}
    Assert IRQ Is Unset
    Execute Command                 emulation RunFor "1"
    Assert Counter Value            ${top_val}
    Assert IRQ Is Unset
    Advance Past Top
    # Check that (only) the overflow interrupt fired
    Assert IRQ Is Set
    Assert Overflow Interrupt Flag
    # Clear interrupts
    Clear Interrupt Flags
    Assert IRQ Is Unset
    # Upon overflow, expect the timer to restart from 0
    Assert Counter Value            0
    # Go around one more time
    Execute Command                 emulation RunFor "2"
    Assert Counter Value            ${top_val}
    Assert IRQ Is Unset
    Advance Past Top
    Assert IRQ Is Set
    Assert Overflow Interrupt Flag
    # Clear interrupts
    Clear Interrupt Flags
    Assert IRQ Is Unset
    Execute Command                 emulation RunFor "1"
    ${check_val}                    Evaluate  ${FREQUENCY} * 1
    Assert Counter Value            ${check_val}
    Assert IRQ Is Unset
    # Stop the timer
    Stop Command
    Assert IRQ Is Unset
    Assert Timer Is Running         False
    Assert Counter Value            0

Underflow
    Create Machine
    Assert IRQ Is Unset
    Assert Timer Is Running         False
    # Configure the timer to count down, no one-shot mode
    Configure Timer                 True  False
    # Enable all implemented interrupts
    Enable All Interrupts
    # Set top value so that the counter overflows right at the 2 second mark
    ${top_val}                      Evaluate  ${FREQUENCY} * 2
    Set Top Value                   ${top_val}
    Assert Timer Is Running         False
    # Start the timer
    Start Command
    Assert Timer Is Running         True
    ${check_val}                    Evaluate  ${FREQUENCY} * 2
    Assert Counter Value            ${check_val}
    Assert IRQ Is Unset
    Execute Command                 emulation RunFor "1"
    ${check_val}                    Evaluate  ${FREQUENCY} * 1
    Assert Counter Value            ${check_val}
    Assert IRQ Is Unset
    Execute Command                 emulation RunFor "1"
    # Check that (only) the underflow interrupt fired
    Assert IRQ Is Set
    Assert Underflow Interrupt Flag
    # Clear interrupts
    Clear Interrupt Flags
    Assert IRQ Is Unset
    # Upon underflow, expect the timer to restart from the top value
    ${check_val}                    Evaluate  ${FREQUENCY} * 2
    Assert Counter Value            ${check_val}
    # Go around one more time
    Execute Command                 emulation RunFor "2"
    Assert IRQ Is Set
    Assert Underflow Interrupt Flag
    # Clear interrupts
    Clear Interrupt Flags
    Assert IRQ Is Unset
    Execute Command                 emulation RunFor "1"
    ${check_val}                    Evaluate  ${FREQUENCY} * 1
    Assert Counter Value            ${check_val}
    Assert IRQ Is Unset
    # Stop the timer
    Stop Command
    Assert IRQ Is Unset
    Assert Timer Is Running         False
    Assert Counter Value            0

One Shot Mode
    Create Machine
    Assert IRQ Is Unset
    Assert Timer Is Running         False
    # Configure the timer to count up, one-shot mode
    Configure Timer                 False  True
    # Enable all implemented interrupts
    Enable All Interrupts
    # TOP is the counter maximum. After two seconds the counter equals TOP.
    # The next tick wraps to 0, sets overflow, and one-shot mode stops the timer.
    ${top_val}                      Evaluate  ${FREQUENCY} * 2
    Set Top Value                   ${top_val}
    Assert Timer Is Running         False
    # Start the timer
    Start Command
    Assert Timer Is Running         True
    Assert Counter Value            0
    Assert IRQ Is Unset
    Execute Command                 emulation RunFor "1"
    ${check_val}                    Evaluate  ${FREQUENCY} * 1
    Assert Counter Value            ${check_val}
    Assert IRQ Is Unset
    Execute Command                 emulation RunFor "1"
    Assert Counter Value            ${top_val}
    Assert IRQ Is Unset
    Advance Past Top
    # Check that (only) the overflow interrupt fired
    Assert IRQ Is Set
    Assert Overflow Interrupt Flag
    # Clear interrupts
    Clear Interrupt Flags
    Assert IRQ Is Unset
    # Check that the timer is no longer running
    Assert Timer Is Running         False
    Execute Command                 emulation RunFor "2"
    Assert IRQ Is Unset

Channel Compare
    Create Machine
    Assert IRQ Is Unset
    Assert Timer Is Running         False
    # Configure the timer to count up, no one-shot mode
    Configure Timer                 False  False
    # Enable all implemented interrupts
    Enable All Interrupts
    # TOP is the counter maximum. After five seconds the counter equals TOP.
    ${top_val}                      Evaluate  ${FREQUENCY} * 5
    Set Top Value                   ${top_val}
    Assert Timer Is Running         False
    # Start the timer
    Start Command
    Assert Timer Is Running         True
    Assert Counter Value            0
    Assert IRQ Is Unset
    Execute Command                 emulation RunFor "1"
    ${check_val}                    Evaluate  ${FREQUENCY} * 1
    Assert Counter Value            ${check_val}
    Assert IRQ Is Unset
    # Set Channel 0 to hit the compare event right at the 3 second mark
    ${set_val}                      Evaluate  ${FREQUENCY} * 3
    Execute Command                 sysbus.timer WriteDoubleWord ${CCO_OC} ${set_val}
    Execute Command                 sysbus.timer WriteDoubleWord ${CCO_CFG} 0x2
    Execute Command                 emulation RunFor "1"
    ${check_val}                    Evaluate  ${FREQUENCY} * 2
    Assert Counter Value            ${check_val}
    Assert IRQ Is Unset
    # Set Channel 1 to hit the compare event right at the 4 second mark
    ${set_val}                      Evaluate  ${FREQUENCY} * 4
    Execute Command                 sysbus.timer WriteDoubleWord ${CC1_OC} ${set_val}
    Execute Command                 sysbus.timer WriteDoubleWord ${CC1_CFG} 0x2
    Execute Command                 emulation RunFor "1"
    # Check that (only) the CC0 interrupt fires
    Assert IRQ Is Set
    Assert CC0 Interrupt Flag
    # Clear interrupts
    Clear Interrupt Flags
    Assert IRQ Is Unset
    Execute Command                 emulation RunFor "1"
    # Check that (only) the CC1 interrupt fires
    Assert IRQ Is Set
    Assert CC1 Interrupt Flag
    # Clear interrupts
    Clear Interrupt Flags
    Assert IRQ Is Unset
    Execute Command                 emulation RunFor "1"
    # CNT is 16 bits on some IP versions, so a TOP above 0xFFFF is not visible there.
    # Overflow is still the tick after the counter reaches TOP.
    Assert IRQ Is Unset
    Advance Past Top
    # Check that (only) the overflow interrupt fired
    Assert IRQ Is Set
    Assert Overflow Interrupt Flag
    # Clear interrupts
    Clear Interrupt Flags
    # Go around one more time
    Execute Command                 emulation RunFor "3"
    # Check that (only) the CC0 interrupt fires
    Assert IRQ Is Set
    Assert CC0 Interrupt Flag
    # Clear interrupts
    Clear Interrupt Flags
    Assert IRQ Is Unset
    Execute Command                 emulation RunFor "1"
    # Check that (only) the CC1 interrupt fires
    Assert IRQ Is Set
    Assert CC1 Interrupt Flag
    # Clear interrupts
    Clear Interrupt Flags
    Assert IRQ Is Unset
    Execute Command                 emulation RunFor "1"
    Assert IRQ Is Unset
    Advance Past Top
    # Check that (only) the overflow interrupt fired
    Assert IRQ Is Set
    Assert Overflow Interrupt Flag

32-bit Counter Stops At Reset TOP
    # TOP resets to 0xFFFF, so a 32-bit counter wraps there until software raises it.
    Create Width Machine            32
    Execute Command                 sysbus.timer WriteDoubleWord ${IEN_REG} 0x1
    Start Command
    Execute Command                 sysbus.timer WriteDoubleWord ${CNT_REG} 0xFFFE
    Execute Command                 emulation RunFor "0.001"
    Assert Counter Value            0xFFFF
    ${flags}=                       Execute Command  sysbus.timer ReadDoubleWord ${IF_REG}
    Should Be Equal As Integers     ${flags}  0
    Execute Command                 emulation RunFor "0.001"
    Assert Counter Value            0
    Assert Overflow Interrupt Flag

32-bit Counter Wraps At Programmed TOP
    Create Width Machine            32
    Set Top Value                   0xFFFFFFFF
    Execute Command                 sysbus.timer WriteDoubleWord ${CCO_OC} 0xFFFFFFFE
    Execute Command                 sysbus.timer WriteDoubleWord ${CCO_CFG} 0x2
    Execute Command                 sysbus.timer WriteDoubleWord ${IEN_REG} 0x11
    Start Command
    Execute Command                 sysbus.timer WriteDoubleWord ${CNT_REG} 0xFFFFFFFD
    Execute Command                 emulation RunFor "0.002"
    Assert Counter Value            0xFFFFFFFF
    Assert CC0 Interrupt Flag
    Execute Command                 emulation RunFor "0.001"
    Assert Counter Value            0
    ${flags}=                       Execute Command  sysbus.timer ReadDoubleWord ${IF_REG}
    Should Be Equal As Integers     ${flags}  0x11

16-bit Counter Wraps After TOP
    Create Width Machine            16
    Set Top Value                   0xFFFF
    Execute Command                 sysbus.timer WriteDoubleWord ${IEN_REG} 0x1
    Start Command
    Execute Command                 sysbus.timer WriteDoubleWord ${CNT_REG} 0xFFFE
    Execute Command                 emulation RunFor "0.001"
    Assert Counter Value            0xFFFF
    ${flags}=                       Execute Command  sysbus.timer ReadDoubleWord ${IF_REG}
    Should Be Equal As Integers     ${flags}  0
    Execute Command                 emulation RunFor "0.001"
    Assert Counter Value            0
    Assert Overflow Interrupt Flag

