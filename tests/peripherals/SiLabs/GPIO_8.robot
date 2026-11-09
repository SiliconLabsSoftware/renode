*** Variables ***
${REPL_STRING}=                 SEPARATOR=
...  """                                                                    ${\n}
...  gpio: GPIOPort.SiLabs_GPIO_8 @ sysbus <0x40006000, +0x4000>            ${\n}
...  """

# Register offsets
${PORTA_MODEL_REG}              0x0034
${PORTA_MODEH_REG}              0x003C
${PORTA_DOUT_REG}               0x0040
${PORTA_DIN_REG}                0x0044
${PORTB_MODEL_REG}              0x0064
${PORTB_MODEH_REG}              0x006C
${PORTB_DOUT_REG}               0x0070
${PORTB_DIN_REG}                0x0074
${PORTC_MODEL_REG}              0x0094
${PORTC_MODEH_REG}              0x009C
${PORTC_DOUT_REG}               0x00A0
${PORTC_DIN_REG}                0x00A4
${PORTD_MODEL_REG}              0x00C4
${PORTD_MODEH_REG}              0x00CC
${PORTD_DOUT_REG}               0x00D0
${PORTD_DIN_REG}                0x00D4

# External interrupt registers
${EXTINT_EXTIPSELL_REG}         0x0400
${EXTINT_EXTIPSELH_REG}         0x0404
${EXTINT_EXTIPINSELL_REG}       0x0408
${EXTINT_EXTIPINSELH_REG}       0x040C
${EXTINT_EXTIRISE_REG}          0x0410
${EXTINT_EXTIFALL_REG}          0x0414
${EXTINT_IF_REG}                0x0420
${EXTINT_IEN_REG}               0x0424

# Lock and status registers
${LOCK_REG}                     0x0300
${STATUS_GPIOLOCKSTATUS_REG}    0x0310

# SET/CLEAR/TOGGLE register offsets
${SET_REGISTER_OFFSET}           0x1000
${CLEAR_REGISTER_OFFSET}         0x2000
${TOGGLE_REGISTER_OFFSET}        0x3000

# Pin mode values
${PIN_MODE_DISABLED}             0x0
${PIN_MODE_INPUT}                0x1
${PIN_MODE_INPUT_PULL}           0x2
${PIN_MODE_INPUT_PULL_FILTER}    0x3
${PIN_MODE_PUSHPULL}             0x4
${PIN_MODE_PUSHPULL_ALT}         0x5
${PIN_MODE_WIRED_OR}             0x6
${PIN_MODE_WIRED_OR_PULLDOWN}    0x7
${PIN_MODE_WIRED_AND}            0x8
${PIN_MODE_WIRED_AND_FILTER}     0x9
${PIN_MODE_WIRED_AND_PULLUP}     0xA
${PIN_MODE_WIRED_AND_PULLUP_FILTER}    0xB
${PIN_MODE_WIRED_AND_ALT}               0xC
${PIN_MODE_WIRED_AND_ALT_FILTER}        0xD
${PIN_MODE_WIRED_AND_ALT_PULLUP}        0xE
${PIN_MODE_WIRED_AND_ALT_PULLUP_FILTER}  0xF

# Port values
${PORT_A}                        0x0
${PORT_B}                        0x1
${PORT_C}                        0x2
${PORT_D}                        0x3

# Lock code
${UNLOCK_CODE}                   0xA534

*** Keywords ***
Create Machine
    Execute Command             mach create "test"
    Execute Command             machine LoadPlatformDescriptionFromString ${REPL_STRING}

Set Pin Mode
    [Arguments]                 ${port}  ${pin}  ${mode}
    ${reg_offset}=              evaluate  ${port} * 0x30
    ${pin_low}=                 evaluate  ${pin} < 8
    ${base_reg}=                evaluate  0x34 if ${pin_low} else 0x3C
    ${model_reg}=               evaluate  ${reg_offset} + ${base_reg}
    ${pin_mod}=                 evaluate  ${pin} % 8
    ${bit_offset}=              evaluate  ${pin_mod} * 4
    ${mask_val}=                evaluate  0xF << ${bit_offset}
    ${current}=                 Execute Command  sysbus.gpio ReadDoubleWord ${model_reg}
    ${current_int}=             evaluate  int(${current})
    ${mask_int}=                evaluate  int(${mask_val})
    ${not_mask}=                evaluate  ~${mask_int} & 0xFFFFFFFF
    ${cleared}=                 evaluate  ${current_int} & ${not_mask}
    ${mode_shifted}=            evaluate  ${mode} << ${bit_offset}
    ${new_value}=               evaluate  ${cleared} | ${mode_shifted}
    Execute Command             sysbus.gpio WriteDoubleWord ${model_reg} ${new_value}

Set Pin Output
    [Arguments]                 ${port}  ${pin}
    Set Pin Mode                ${port}  ${pin}  ${PIN_MODE_PUSHPULL}

Set Pin Input
    [Arguments]                 ${port}  ${pin}
    Set Pin Mode                ${port}  ${pin}  ${PIN_MODE_INPUT}

Write Pin
    [Arguments]                 ${port}  ${pin}  ${value}
    ${reg_offset}=              evaluate  ${port} * 0x30
    ${dout_reg}=                evaluate  ${reg_offset} + 0x40
    ${current}=                 Execute Command  sysbus.gpio ReadDoubleWord ${dout_reg}
    ${current_int}=             evaluate  int(${current})
    ${bit_mask}=                evaluate  1 << ${pin}
    ${value_int}=               evaluate  int(${value})
    ${set_value}=               evaluate  ${current_int} | ${bit_mask}
    ${not_mask}=                evaluate  ~${bit_mask} & 0xFFFFFFFF
    ${clear_value}=             evaluate  ${current_int} & ${not_mask}
    ${new_value}=               evaluate  ${set_value} if ${value_int} else ${clear_value}
    Execute Command             sysbus.gpio WriteDoubleWord ${dout_reg} ${new_value}

Read Pin
    [Arguments]                 ${port}  ${pin}
    ${reg_offset}=              evaluate  ${port} * 0x30
    ${din_reg}=                 evaluate  ${reg_offset} + 0x44
    ${value}=                   Execute Command  sysbus.gpio ReadDoubleWord ${din_reg}
    ${value_int}=               evaluate  int(${value})
    ${bit_mask}=                evaluate  1 << ${pin}
    ${masked}=                  evaluate  ${value_int} & ${bit_mask}
    ${result}=                  evaluate  ${masked} >> ${pin}
    [Return]                    ${result}

Configure External Interrupt
    [Arguments]                 ${extint_num}  ${port}  ${pin}  ${rising}  ${falling}  ${enable}
    # Configure port select
    ${extint_low}=              evaluate  ${extint_num} < 8
    ${reg}=                     evaluate  ${EXTINT_EXTIPSELL_REG} if ${extint_low} else ${EXTINT_EXTIPSELH_REG}
    ${extint_mod}=              evaluate  ${extint_num} % 8
    ${bit_offset}=              evaluate  ${extint_mod} * 4
    ${current}=                 Execute Command  sysbus.gpio ReadDoubleWord ${reg}
    ${current_int}=             evaluate  int(${current})
    ${mask_val}=                evaluate  0x3 << ${bit_offset}
    ${mask_int}=                evaluate  int(${mask_val})
    ${not_mask}=                evaluate  ~${mask_int} & 0xFFFFFFFF
    ${cleared}=                evaluate  ${current_int} & ${not_mask}
    ${port_shifted}=           evaluate  ${port} << ${bit_offset}
    ${new_value}=              evaluate  ${cleared} | ${port_shifted}
    Execute Command             sysbus.gpio WriteDoubleWord ${reg} ${new_value}
    
    # Configure pin select
    ${reg}=                     evaluate  ${EXTINT_EXTIPINSELL_REG} if ${extint_low} else ${EXTINT_EXTIPINSELH_REG}
    ${current}=                Execute Command  sysbus.gpio ReadDoubleWord ${reg}
    ${current_int}=             evaluate  int(${current})
    ${cleared}=                evaluate  ${current_int} & ${not_mask}
    ${pin_shifted}=            evaluate  ${pin} << ${bit_offset}
    ${new_value}=              evaluate  ${cleared} | ${pin_shifted}
    Execute Command             sysbus.gpio WriteDoubleWord ${reg} ${new_value}
    
    # Configure rising edge
    ${current}=                Execute Command  sysbus.gpio ReadDoubleWord ${EXTINT_EXTIRISE_REG}
    ${current_int}=             evaluate  int(${current})
    ${bit_mask}=               evaluate  1 << ${extint_num}
    ${rising_int}=             evaluate  int(${rising})
    ${set_value}=              evaluate  ${current_int} | ${bit_mask}
    ${not_bit_mask}=           evaluate  ~${bit_mask} & 0xFFFFFFFF
    ${clear_value}=            evaluate  ${current_int} & ${not_bit_mask}
    ${new_value}=              evaluate  ${set_value} if ${rising_int} else ${clear_value}
    Execute Command             sysbus.gpio WriteDoubleWord ${EXTINT_EXTIRISE_REG} ${new_value}
    
    # Configure falling edge
    ${current}=                Execute Command  sysbus.gpio ReadDoubleWord ${EXTINT_EXTIFALL_REG}
    ${current_int}=             evaluate  int(${current})
    ${falling_int}=            evaluate  int(${falling})
    ${set_value}=              evaluate  ${current_int} | ${bit_mask}
    ${clear_value}=            evaluate  ${current_int} & ${not_bit_mask}
    ${new_value}=              evaluate  ${set_value} if ${falling_int} else ${clear_value}
    Execute Command             sysbus.gpio WriteDoubleWord ${EXTINT_EXTIFALL_REG} ${new_value}
    
    # Enable interrupt
    ${current}=                Execute Command  sysbus.gpio ReadDoubleWord ${EXTINT_IEN_REG}
    ${current_int}=             evaluate  int(${current})
    ${enable_int}=             evaluate  int(${enable})
    ${set_value}=              evaluate  ${current_int} | ${bit_mask}
    ${clear_value}=            evaluate  ${current_int} & ${not_bit_mask}
    ${new_value}=              evaluate  ${set_value} if ${enable_int} else ${clear_value}
    Execute Command             sysbus.gpio WriteDoubleWord ${EXTINT_IEN_REG} ${new_value}

Assert Odd IRQ Is Set
    ${irqState}=                Execute Command  sysbus.gpio OddIRQ
    Should Contain              ${irqState}  GPIO: set

Assert Odd IRQ Is Unset
    ${irqState}=                Execute Command  sysbus.gpio OddIRQ
    Should Contain              ${irqState}  GPIO: unset

Assert Even IRQ Is Set
    ${irqState}=                Execute Command  sysbus.gpio EvenIRQ
    Should Contain              ${irqState}  GPIO: set

Assert Even IRQ Is Unset
    ${irqState}=                Execute Command  sysbus.gpio EvenIRQ
    Should Contain              ${irqState}  GPIO: unset

Unlock Configuration
    Execute Command             sysbus.gpio WriteDoubleWord ${LOCK_REG} ${UNLOCK_CODE}

Lock Configuration
    Execute Command             sysbus.gpio WriteDoubleWord ${LOCK_REG} 0x0

*** Test Cases ***
GPIO Pin Mode Configuration
    Create Machine
    
    # Test setting pin to input mode
    Set Pin Input                ${PORT_A}  0
    ${mode_reg}=                Execute Command  sysbus.gpio ReadDoubleWord ${PORTA_MODEL_REG}
    ${mode_value}=              evaluate  int(${mode_reg}) & 0xF
    Should Be Equal As Integers  ${mode_value}  ${PIN_MODE_INPUT}
    
    # Test setting pin to output mode
    Set Pin Output               ${PORT_A}  0
    ${mode_reg}=                Execute Command  sysbus.gpio ReadDoubleWord ${PORTA_MODEL_REG}
    ${mode_value}=              evaluate  int(${mode_reg}) & 0xF
    Should Be Equal As Integers  ${mode_value}  ${PIN_MODE_PUSHPULL}

GPIO Pin Output Write
    Create Machine
    
    # Configure pin as output
    Set Pin Output               ${PORT_A}  0
    
    # Write high
    Write Pin                    ${PORT_A}  0  1
    ${dout}=                    Execute Command  sysbus.gpio ReadDoubleWord ${PORTA_DOUT_REG}
    ${bit_value}=               evaluate  int(${dout}) & 0x1
    Should Be Equal As Integers  ${bit_value}  1
    
    # Write low
    Write Pin                    ${PORT_A}  0  0
    ${dout}=                    Execute Command  sysbus.gpio ReadDoubleWord ${PORTA_DOUT_REG}
    ${bit_value}=               evaluate  int(${dout}) & 0x1
    Should Be Equal As Integers  ${bit_value}  0

GPIO Pin Input Read
    Create Machine
    
    # Configure pin as input
    Set Pin Input                ${PORT_A}  0
    
    # Set pin state externally (simulate external input)
    Execute Command              sysbus.gpio OnGPIO 0 true
    ${din}=                     Execute Command  sysbus.gpio ReadDoubleWord ${PORTA_DIN_REG}
    ${bit_value}=               evaluate  int(${din}) & 0x1
    Should Be Equal As Integers  ${bit_value}  1
    
    # Clear pin state
    Execute Command              sysbus.gpio OnGPIO 0 false
    ${din}=                     Execute Command  sysbus.gpio ReadDoubleWord ${PORTA_DIN_REG}
    ${bit_value}=               evaluate  int(${din}) & 0x1
    Should Be Equal As Integers  ${bit_value}  0

GPIO SET Register Operation
    Create Machine
    
    Set Pin Output               ${PORT_A}  0
    
    # Use SET register to set bit
    ${set_reg}=                 evaluate  ${PORTA_DOUT_REG} + ${SET_REGISTER_OFFSET}
    Execute Command             sysbus.gpio WriteDoubleWord ${set_reg} 0x1
    ${dout}=                    Execute Command  sysbus.gpio ReadDoubleWord ${PORTA_DOUT_REG}
    ${bit_value}=               evaluate  int(${dout}) & 0x1
    Should Be Equal As Integers  ${bit_value}  1

GPIO CLEAR Register Operation
    Create Machine
    
    Set Pin Output               ${PORT_A}  0
    
    # Set bit first
    Write Pin                    ${PORT_A}  0  1
    ${dout}=                    Execute Command  sysbus.gpio ReadDoubleWord ${PORTA_DOUT_REG}
    ${bit_value}=               evaluate  int(${dout}) & 0x1
    Should Be Equal As Integers  ${bit_value}  1
    
    # Use CLEAR register to clear bit
    ${clear_reg}=               evaluate  ${PORTA_DOUT_REG} + ${CLEAR_REGISTER_OFFSET}
    Execute Command             sysbus.gpio WriteDoubleWord ${clear_reg} 0x1
    ${dout}=                    Execute Command  sysbus.gpio ReadDoubleWord ${PORTA_DOUT_REG}
    ${bit_value}=               evaluate  int(${dout}) & 0x1
    Should Be Equal As Integers  ${bit_value}  0

GPIO TOGGLE Register Operation
    Create Machine
    
    Set Pin Output               ${PORT_A}  0
    
    # Initial state: low
    Write Pin                    ${PORT_A}  0  0
    ${dout}=                    Execute Command  sysbus.gpio ReadDoubleWord ${PORTA_DOUT_REG}
    ${bit_value}=               evaluate  int(${dout}) & 0x1
    Should Be Equal As Integers  ${bit_value}  0
    
    # Use TOGGLE register to toggle bit
    ${toggle_reg}=              evaluate  ${PORTA_DOUT_REG} + ${TOGGLE_REGISTER_OFFSET}
    Execute Command             sysbus.gpio WriteDoubleWord ${toggle_reg} 0x1
    ${dout}=                    Execute Command  sysbus.gpio ReadDoubleWord ${PORTA_DOUT_REG}
    ${bit_value}=               evaluate  int(${dout}) & 0x1
    Should Be Equal As Integers  ${bit_value}  1
    
    # Toggle again
    Execute Command             sysbus.gpio WriteDoubleWord ${toggle_reg} 0x1
    ${dout}=                    Execute Command  sysbus.gpio ReadDoubleWord ${PORTA_DOUT_REG}
    ${bit_value}=               evaluate  int(${dout}) & 0x1
    Should Be Equal As Integers  ${bit_value}  0

External Interrupt Rising Edge
    Create Machine
    
    # Configure pin as input
    Set Pin Input                ${PORT_A}  0
    
    # Set pin to known initial state (low) before configuring interrupt
    Execute Command             sysbus.gpio OnGPIO 0 false
    
    # Configure external interrupt 0 for Port A, Pin 0, rising edge (but don't enable yet)
    Configure External Interrupt  0  ${PORT_A}  0  True  False  False
    
    # Now enable the interrupt - this way UpdateInterrupts won't trigger on stale state
    ${current}=                 Execute Command  sysbus.gpio ReadDoubleWord ${EXTINT_IEN_REG}
    ${current_int}=             evaluate  int(${current})
    ${bit_mask}=                evaluate  1 << 0
    ${new_value}=               evaluate  ${current_int} | ${bit_mask}
    Execute Command             sysbus.gpio WriteDoubleWord ${EXTINT_IEN_REG} ${new_value}
    
    # Clear any pending interrupts
    ${if_clr_reg}=              evaluate  ${EXTINT_IF_REG} + ${CLEAR_REGISTER_OFFSET}
    Execute Command             sysbus.gpio WriteDoubleWord ${if_clr_reg} 0xFFFF
    
    # Trigger rising edge
    Execute Command             sysbus.gpio OnGPIO 0 false
    Execute Command             sysbus.gpio OnGPIO 0 true
    
    # Check interrupt flag is set
    ${if_reg}=                  Execute Command  sysbus.gpio ReadDoubleWord ${EXTINT_IF_REG}
    ${flag_value}=              evaluate  int(${if_reg}) & 0x1
    Should Be Equal As Integers  ${flag_value}  1
    
    # Check Even IRQ is set (interrupt 0 is even)
    Assert Even IRQ Is Set
    
    # Clear interrupt flag using CLR register
    ${if_clr_reg}=              evaluate  ${EXTINT_IF_REG} + ${CLEAR_REGISTER_OFFSET}
    Execute Command             sysbus.gpio WriteDoubleWord ${if_clr_reg} 0x1

External Interrupt Falling Edge
    Create Machine
    
    # Configure pin as input
    Set Pin Input                ${PORT_A}  1
    
    # Set pin to known initial state (high) before configuring interrupt
    Execute Command             sysbus.gpio OnGPIO 1 true
    
    # Configure external interrupt 1 for Port A, Pin 1 (pin select 1 in group 0), falling edge (but don't enable yet)
    Configure External Interrupt  1  ${PORT_A}  1  False  True  False
    
    # Now enable the interrupt - this way UpdateInterrupts won't trigger on stale state
    ${current}=                 Execute Command  sysbus.gpio ReadDoubleWord ${EXTINT_IEN_REG}
    ${current_int}=             evaluate  int(${current})
    ${bit_mask}=                evaluate  1 << 1
    ${new_value}=               evaluate  ${current_int} | ${bit_mask}
    Execute Command             sysbus.gpio WriteDoubleWord ${EXTINT_IEN_REG} ${new_value}
    
    # Clear any pending interrupts
    ${if_clr_reg}=              evaluate  ${EXTINT_IF_REG} + ${CLEAR_REGISTER_OFFSET}
    Execute Command             sysbus.gpio WriteDoubleWord ${if_clr_reg} 0xFFFF
    
    # Trigger falling edge
    Execute Command             sysbus.gpio OnGPIO 1 true
    Execute Command             sysbus.gpio OnGPIO 1 false
    
    # Check interrupt flag is set
    ${if_reg}=                  Execute Command  sysbus.gpio ReadDoubleWord ${EXTINT_IF_REG}
    ${flag_value}=              evaluate  (int(${if_reg}) >> 1) & 0x1
    Should Be Equal As Integers  ${flag_value}  1
    
    # Check Odd IRQ is set (interrupt 1 is odd)
    Assert Odd IRQ Is Set
    
    # Clear interrupt flag using CLR register
    ${if_clr_reg}=              evaluate  ${EXTINT_IF_REG} + ${CLEAR_REGISTER_OFFSET}
    Execute Command             sysbus.gpio WriteDoubleWord ${if_clr_reg} 0x2
    # Trigger UpdateInterrupts by toggling IEN register (has write callback)
    ${current_ien}=             Execute Command  sysbus.gpio ReadDoubleWord ${EXTINT_IEN_REG}
    Execute Command             sysbus.gpio WriteDoubleWord ${EXTINT_IEN_REG} ${current_ien}
    Assert Odd IRQ Is Unset

External Interrupt Both Edges
    Create Machine
    
    # Configure pin as input
    Set Pin Input                ${PORT_A}  2
    
    # Set pin to known initial state (low) before configuring interrupt
    Execute Command             sysbus.gpio OnGPIO 2 false
    
    # Configure external interrupt 2 for Port A, Pin 2 (pin select 2 in group 0), both edges (but don't enable yet)
    Configure External Interrupt  2  ${PORT_A}  2  True  True  False
    
    # Now enable the interrupt - this way UpdateInterrupts won't trigger on stale state
    ${current}=                 Execute Command  sysbus.gpio ReadDoubleWord ${EXTINT_IEN_REG}
    ${current_int}=             evaluate  int(${current})
    ${bit_mask}=                evaluate  1 << 2
    ${new_value}=               evaluate  ${current_int} | ${bit_mask}
    Execute Command             sysbus.gpio WriteDoubleWord ${EXTINT_IEN_REG} ${new_value}
    
    # Clear any pending interrupts
    ${if_clr_reg}=              evaluate  ${EXTINT_IF_REG} + ${CLEAR_REGISTER_OFFSET}
    Execute Command             sysbus.gpio WriteDoubleWord ${if_clr_reg} 0xFFFF
    
    # Test rising edge
    Execute Command             sysbus.gpio OnGPIO 2 false
    Execute Command             sysbus.gpio OnGPIO 2 true
    ${if_reg}=                  Execute Command  sysbus.gpio ReadDoubleWord ${EXTINT_IF_REG}
    ${flag_value}=              evaluate  (int(${if_reg}) >> 2) & 0x1
    Should Be Equal As Integers  ${flag_value}  1
    Assert Even IRQ Is Set
    
    # Clear interrupt flag using CLR register
    ${if_clr_reg}=              evaluate  ${EXTINT_IF_REG} + ${CLEAR_REGISTER_OFFSET}
    Execute Command             sysbus.gpio WriteDoubleWord ${if_clr_reg} 0x4
    # Trigger UpdateInterrupts by toggling IEN register (has write callback)
    ${current_ien}=             Execute Command  sysbus.gpio ReadDoubleWord ${EXTINT_IEN_REG}
    Execute Command             sysbus.gpio WriteDoubleWord ${EXTINT_IEN_REG} ${current_ien}
    Assert Even IRQ Is Unset
    
    # Test falling edge
    Execute Command             sysbus.gpio OnGPIO 2 true
    Execute Command             sysbus.gpio OnGPIO 2 false
    ${if_reg}=                  Execute Command  sysbus.gpio ReadDoubleWord ${EXTINT_IF_REG}
    ${flag_value}=              evaluate  (int(${if_reg}) >> 2) & 0x1
    Should Be Equal As Integers  ${flag_value}  1
    Assert Even IRQ Is Set

External Interrupt Disabled
    Create Machine
    
    # Configure pin as input
    Set Pin Input                ${PORT_A}  0
    
    # Configure external interrupt 0 but disable it
    Configure External Interrupt  0  ${PORT_A}  0  True  False  False
    
    # Clear any pending interrupts
    Execute Command             sysbus.gpio WriteDoubleWord ${EXTINT_IF_REG} 0xFFFFFFFF
    # Clear interrupt flags using CLR register to ensure they're cleared
    ${if_clr_reg}=              evaluate  ${EXTINT_IF_REG} + ${CLEAR_REGISTER_OFFSET}
    Execute Command             sysbus.gpio WriteDoubleWord ${if_clr_reg} 0xFFFFFFFF
    
    # Trigger rising edge
    Execute Command             sysbus.gpio OnGPIO 0 false
    Execute Command             sysbus.gpio OnGPIO 0 true
    
    # Interrupt flag should not be set (interrupt is disabled)
    ${if_reg}=                  Execute Command  sysbus.gpio ReadDoubleWord ${EXTINT_IF_REG}
    ${flag_value}=              evaluate  int(${if_reg}) & 0x1
    Should Be Equal As Integers  ${flag_value}  0
    Assert Even IRQ Is Unset

Lock Configuration
    Create Machine
    
    # Unlock configuration
    Unlock Configuration
    ${lock_status}=             Execute Command  sysbus.gpio ReadDoubleWord ${STATUS_GPIOLOCKSTATUS_REG}
    ${lock_bit}=                evaluate  int(${lock_status}) & 0x1
    Should Be Equal As Integers  ${lock_bit}  0
    
    # Lock configuration
    Lock Configuration
    ${lock_status}=             Execute Command  sysbus.gpio ReadDoubleWord ${STATUS_GPIOLOCKSTATUS_REG}
    ${lock_bit}=                evaluate  int(${lock_status}) & 0x1
    Should Be Equal As Integers  ${lock_bit}  1

Multiple Ports Configuration
    Create Machine
    
    # Configure pins on different ports
    Set Pin Output               ${PORT_A}  0
    Set Pin Output               ${PORT_B}  5
    Set Pin Output               ${PORT_C}  10
    Set Pin Output               ${PORT_D}  15
    
    # Write to different ports
    Write Pin                    ${PORT_A}  0  1
    Write Pin                    ${PORT_B}  5  1
    Write Pin                    ${PORT_C}  10  1
    Write Pin                    ${PORT_D}  15  1
    
    # Verify all pins are set
    ${dout_a}=                  Execute Command  sysbus.gpio ReadDoubleWord ${PORTA_DOUT_REG}
    ${dout_b}=                  Execute Command  sysbus.gpio ReadDoubleWord ${PORTB_DOUT_REG}
    ${dout_c}=                  Execute Command  sysbus.gpio ReadDoubleWord ${PORTC_DOUT_REG}
    ${dout_d}=                  Execute Command  sysbus.gpio ReadDoubleWord ${PORTD_DOUT_REG}
    
    ${bit_a}=                   evaluate  int(${dout_a}) & 0x1
    ${bit_b}=                   evaluate  (int(${dout_b}) >> 5) & 0x1
    ${bit_c}=                   evaluate  (int(${dout_c}) >> 10) & 0x1
    ${bit_d}=                   evaluate  (int(${dout_d}) >> 15) & 0x1
    Should Be Equal As Integers  ${bit_a}  1
    Should Be Equal As Integers  ${bit_b}  1
    Should Be Equal As Integers  ${bit_c}  1
    Should Be Equal As Integers  ${bit_d}  1

