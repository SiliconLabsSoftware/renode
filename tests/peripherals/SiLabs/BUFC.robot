*** Settings ***
Resource                      ${RENODEKEYWORDS}
Resource                      common_keywords.robot

Suite Setup                   Run Keywords  Setup  AND  Configure Layout
Suite Teardown                Teardown
Test Setup                    Specific Test Setup
Test Teardown                 Test Teardown

*** Comments ***
BUFC tests shared by SiLabs_BUFC_1, SiLabs_BUFC_4 and SiLabs_BUFC_5.

Select the model from the command line:
renode-test --variable BUFC_VERSION:1 tests/peripherals/SiLabs/BUFC.robot

*** Variables ***
${BUFC_VERSION}                 1
${RAM_ADDRESS}                  0x20000000
${BUFFER1_ADDRESS}              0x20001000
${STRIDE}                       0x40
${DEFAULT_SIZE}                 64

${CTRL_REL}                     0x00
${ADDR_REL}                     0x04
${WRITEOFFSET_REL}              0x08
${READOFFSET_REL}               0x0C
${WRITESTART_REL}               0x10
${READDATA_REL}                 0x14
${WRITEDATA_REL}                0x18
${XWRITE_REL}                   0x1C
${STATUS_REL}                   0x20
${THRESHOLDCTRL_REL}            0x24
${CMD_REL}                      0x28
# One reserved word sits between CMD and the 32-bit data ports.
${READDATA32_REL}               0x30
${WRITEDATA32_REL}              0x34
${XWRITE32_REL}                 0x38

${CMD_CLEAR}                    0x1
${CMD_PREFETCH}                 0x2
${CMD_UPDATEWRITESTART}         0x4
${CMD_RESTOREWRITEOFFSET}       0x8

${IF_OF}                        0x1
${IF_UF}                        0x2
${IF_THR}                       0x4
${IF_CORR}                      0x8
${IF_NWA}                       0x10
${IF_BUSERROR}                  0x80000000
${EVENT_REGISTER_MASK}          0x9F1F1F1F
${STATUS_BYTES_MASK}            0x3FFF
${STATUS_RDATARDY}              0x10000
${STATUS_THRESHOLD}             0x100000
${STATUS_RDATA32RDY}            0x1000000

${SIZE_256}                     0x2
${EN_REG}                       0x0004
${LPMODE_REG}                   0x0008
${HWCTRL_REG}                   0x000C

${REPL_STRING}=                 SEPARATOR=
...  """                                                                                     ${\n}
...  ram: Memory.MappedMemory @ sysbus ${RAM_ADDRESS}                                        ${\n}
...  ${SPACE*4}size: 0x10000                                                                 ${\n}
...  bufc: Miscellaneous.SiLabs.SiLabs_BUFC_${BUFC_VERSION} @ sysbus <0x0, +0x4000>          ${\n}
...  """

*** Keywords ***
Configure Layout
    IF  '${BUFC_VERSION}' != '1' and '${BUFC_VERSION}' != '4' and '${BUFC_VERSION}' != '5'
        Fail    BUFC_VERSION must be 1, 4 or 5
    END
    Set Suite Variable    ${BUF0}                 0x0C
    Set Suite Variable    ${IF_REG}               0x114
    Set Suite Variable    ${IEN_REG}              0x118
    Set Suite Variable    ${SEQIF_REG}            0x11C
    Set Suite Variable    ${SEQIEN_REG}           0x120
    Set Suite Variable    ${FSWIF_REG}            0x12C
    Set Suite Variable    ${FSWIEN_REG}           0x130
    Set Suite Variable    ${THRESHOLD_MODE_BIT}   13

Buffer Register
    [Arguments]                 ${index}  ${relative}
    ${address}=                 Evaluate  ${BUF0} + ${index} * ${STRIDE} + ${relative}
    [Return]                    ${address}

Write Register
    [Arguments]                 ${offset}  ${value}
    Execute Command             sysbus.bufc WriteDoubleWord ${offset} ${value}

Read Register
    [Arguments]                 ${offset}
    ${text}=                    Execute Command  sysbus.bufc ReadDoubleWord ${offset}
    ${value}=                   Convert To Integer  ${text}
    [Return]                    ${value}

Write Buffer
    [Arguments]                 ${index}  ${relative}  ${value}
    ${offset}=                  Buffer Register  ${index}  ${relative}
    Write Register              ${offset}  ${value}

Read Buffer
    [Arguments]                 ${index}  ${relative}
    ${offset}=                  Buffer Register  ${index}  ${relative}
    ${value}=                   Read Register  ${offset}
    [Return]                    ${value}

Read Byte At
    [Arguments]                 ${address}
    ${text}=                    Execute Command  sysbus ReadByte ${address}
    ${value}=                   Convert To Integer  ${text}
    [Return]                    ${value}

Bytes In Buffer
    [Arguments]                 ${index}
    ${status}=                  Read Buffer  ${index}  ${STATUS_REL}
    ${bytes}=                   Evaluate  ${status} & ${STATUS_BYTES_MASK}
    [Return]                    ${bytes}

*** Test Cases ***
Reset Values
    ${version}=                 Read Register  0x0
    Should Be Equal As Integers  ${version}  ${BUFC_VERSION}
    # IPVERSION is read-only.
    Write Register              0x0  0xFFFFFFFF
    ${version}=                 Read Register  0x0
    Should Be Equal As Integers  ${version}  ${BUFC_VERSION}

    ${address}=                 Read Buffer  0  ${ADDR_REL}
    Should Be Equal As Integers  ${address}  ${RAM_ADDRESS}
    ${write_offset}=            Read Buffer  0  ${WRITEOFFSET_REL}
    Should Be Equal As Integers  ${write_offset}  0
    ${read_offset}=             Read Buffer  0  ${READOFFSET_REL}
    Should Be Equal As Integers  ${read_offset}  0
    ${bytes}=                   Bytes In Buffer  0
    Should Be Equal As Integers  ${bytes}  0

    # An empty buffer has no read data ready.
    ${status}=                  Read Buffer  0  ${STATUS_REL}
    ${ready}=                   Evaluate  ${status} & (${STATUS_RDATARDY} | ${STATUS_RDATA32RDY})
    Should Be Equal As Integers  ${ready}  0

    ${enable}=                  Read Register  ${EN_REG}
    Should Be Equal As Integers  ${enable}  0
    ${low_power}=               Read Register  ${LPMODE_REG}
    Should Be Equal As Integers  ${low_power}  0

    Assert IRQ Is Unset         sysbus.bufc  IRQ
    Assert IRQ Is Unset         sysbus.bufc  SequencerIRQ

Address Size And Reset
    # The two least significant bits of ADDR are forced to zero.
    Write Buffer                0  ${ADDR_REL}  0x20000003
    ${address}=                 Read Buffer  0  ${ADDR_REL}
    Should Be Equal As Integers  ${address}  ${RAM_ADDRESS}

    Write Buffer                0  ${CTRL_REL}  ${SIZE_256}
    ${size}=                    Read Buffer  0  ${CTRL_REL}
    Should Be Equal As Integers  ${size}  ${SIZE_256}

    Write Buffer                0  ${ADDR_REL}  0x20001000
    Write Buffer                0  ${WRITEOFFSET_REL}  7
    Execute Command             sysbus.bufc Reset
    ${address}=                 Read Buffer  0  ${ADDR_REL}
    Should Be Equal As Integers  ${address}  ${RAM_ADDRESS}
    ${write_offset}=            Read Buffer  0  ${WRITEOFFSET_REL}
    Should Be Equal As Integers  ${write_offset}  0
    ${size}=                    Read Buffer  0  ${CTRL_REL}
    Should Be Equal As Integers  ${size}  0

Byte Write Read And Xor
    Write Buffer                0  ${WRITEDATA_REL}  0xF0
    Write Buffer                0  ${WRITEDATA_REL}  0x22
    ${bytes}=                   Bytes In Buffer  0
    Should Be Equal As Integers  ${bytes}  2
    ${write_offset}=            Read Buffer  0  ${WRITEOFFSET_REL}
    Should Be Equal As Integers  ${write_offset}  2
    ${stored}=                  Read Byte At  ${RAM_ADDRESS}
    Should Be Equal As Integers  ${stored}  0xF0

    # Rewinding the write offset drops the second byte out of the counted range.
    # The XOR still updates the byte already stored in RAM.
    Write Buffer                0  ${WRITEOFFSET_REL}  0
    Write Buffer                0  ${XWRITE_REL}  0x0F
    ${stored}=                  Read Byte At  ${RAM_ADDRESS}
    Should Be Equal As Integers  ${stored}  0xFF
    ${first}=                   Read Buffer  0  ${READDATA_REL}
    Should Be Equal As Integers  ${first}  0xFF
    ${bytes}=                   Bytes In Buffer  0
    Should Be Equal As Integers  ${bytes}  0

Word Access And Short Underflow
    Write Buffer                0  ${WRITEDATA32_REL}  0xA1B2C3D4
    ${bytes}=                   Bytes In Buffer  0
    Should Be Equal As Integers  ${bytes}  4
    ${bus_text}=                Execute Command  sysbus ReadDoubleWord ${RAM_ADDRESS}
    ${bus_word}=                Convert To Integer  ${bus_text}
    Should Be Equal As Integers  ${bus_word}  0xA1B2C3D4
    ${word}=                    Read Buffer  0  ${READDATA32_REL}
    Should Be Equal As Integers  ${word}  0xA1B2C3D4
    # XOR the word just consumed, then read it back.
    Write Buffer                0  ${WRITEOFFSET_REL}  0
    Write Buffer                0  ${READOFFSET_REL}  0
    Write Buffer                0  ${XWRITE32_REL}  0x0000FFFF
    ${xored}=                   Read Buffer  0  ${READDATA32_REL}
    Should Be Equal As Integers  ${xored}  0xA1B23C2B
    ${bytes}=                   Bytes In Buffer  0
    Should Be Equal As Integers  ${bytes}  0

    Write Buffer                0  ${WRITEDATA_REL}  0x11
    Write Buffer                0  ${WRITEDATA_REL}  0x22
    ${partial}=                 Read Buffer  0  ${READDATA32_REL}
    Should Be Equal As Integers  ${partial}  0x2211
    # A short word read sets underflow and leaves both offsets where they were.
    ${read_offset}=             Read Buffer  0  ${READOFFSET_REL}
    Should Be Equal As Integers  ${read_offset}  4
    ${write_offset}=            Read Buffer  0  ${WRITEOFFSET_REL}
    Should Be Equal As Integers  ${write_offset}  6
    ${flags}=                   Read Register  ${IF_REG}
    ${underflow}=               Evaluate  ${flags} & ${IF_UF}
    Should Be Equal As Integers  ${underflow}  ${IF_UF}

    # Fewer than 4 free bytes rejects the word write. 62 bytes are used, 2 are free.
    Write Buffer                0  ${WRITEOFFSET_REL}  64
    Write Buffer                0  ${READOFFSET_REL}  2
    Write Register              ${IF_REG}  0x0
    Write Buffer                0  ${WRITEDATA32_REL}  0x11223344
    ${write_offset}=            Read Buffer  0  ${WRITEOFFSET_REL}
    Should Be Equal As Integers  ${write_offset}  64
    ${flags}=                   Read Register  ${IF_REG}
    ${overflow}=                Evaluate  ${flags} & ${IF_OF}
    Should Be Equal As Integers  ${overflow}  ${IF_OF}

Full Empty Overflow And Wrap
    FOR  ${i}  IN RANGE  ${DEFAULT_SIZE}
        Write Buffer            0  ${WRITEDATA_REL}  0xA5
    END
    ${bytes}=                   Bytes In Buffer  0
    Should Be Equal As Integers  ${bytes}  ${DEFAULT_SIZE}
    ${write_offset}=            Read Buffer  0  ${WRITEOFFSET_REL}
    Should Be Equal As Integers  ${write_offset}  ${DEFAULT_SIZE}

    # The buffer is full, so another byte is dropped and raises overflow.
    Write Buffer                0  ${WRITEDATA_REL}  0x5A
    ${bytes}=                   Bytes In Buffer  0
    Should Be Equal As Integers  ${bytes}  ${DEFAULT_SIZE}
    ${flags}=                   Read Register  ${IF_REG}
    ${overflow}=                Evaluate  ${flags} & ${IF_OF}
    Should Be Equal As Integers  ${overflow}  ${IF_OF}
    ${seq_flags}=               Read Register  ${SEQIF_REG}
    ${seq_overflow}=            Evaluate  ${seq_flags} & ${IF_OF}
    Should Be Equal As Integers  ${seq_overflow}  ${IF_OF}

    # Reading the buffer back consumes it. The rejected byte never landed.
    FOR  ${i}  IN RANGE  ${DEFAULT_SIZE}
        ${byte}=                Read Buffer  0  ${READDATA_REL}
        Should Be Equal As Integers  ${byte}  0xA5
    END
    ${bytes}=                   Bytes In Buffer  0
    Should Be Equal As Integers  ${bytes}  0
    ${empty}=                   Read Buffer  0  ${READDATA_REL}
    Should Be Equal As Integers  ${empty}  0
    ${flags}=                   Read Register  ${IF_REG}
    ${underflow}=               Evaluate  ${flags} & ${IF_UF}
    Should Be Equal As Integers  ${underflow}  ${IF_UF}

    # The offset has one extra bit, so it wraps at twice the buffer size.
    Write Buffer                0  ${WRITEOFFSET_REL}  127
    Write Buffer                0  ${WRITEDATA_REL}  0xAB
    ${write_offset}=            Read Buffer  0  ${WRITEOFFSET_REL}
    Should Be Equal As Integers  ${write_offset}  0
    ${wrapped}=                 Read Byte At  0x2000003F
    Should Be Equal As Integers  ${wrapped}  0xAB

Threshold
    # LARGER: the flag follows BYTES, and the interrupt flag stays set until software clears it.
    Write Buffer                0  ${THRESHOLDCTRL_REL}  3
    FOR  ${i}  IN RANGE  3
        Write Buffer            0  ${WRITEDATA_REL}  0x01
    END
    ${status}=                  Read Buffer  0  ${STATUS_REL}
    ${threshold}=               Evaluate  ${status} & ${STATUS_THRESHOLD}
    Should Be Equal As Integers  ${threshold}  0
    ${flags}=                   Read Register  ${IF_REG}
    ${threshold_if}=            Evaluate  ${flags} & ${IF_THR}
    Should Be Equal As Integers  ${threshold_if}  0

    Write Register              ${IEN_REG}  ${IF_THR}
    Write Buffer                0  ${WRITEDATA_REL}  0x01
    ${status}=                  Read Buffer  0  ${STATUS_REL}
    ${threshold}=               Evaluate  ${status} & ${STATUS_THRESHOLD}
    Should Be Equal As Integers  ${threshold}  ${STATUS_THRESHOLD}
    ${flags}=                   Read Register  ${IF_REG}
    ${threshold_if}=            Evaluate  ${flags} & ${IF_THR}
    Should Be Equal As Integers  ${threshold_if}  ${IF_THR}
    Assert IRQ Is Set           sysbus.bufc  IRQ

    Write Register              ${IF_REG}  0x0
    Assert IRQ Is Unset         sysbus.bufc  IRQ

    # LESSOREQUAL compares BYTES against the threshold.
    ${mode}=                    Evaluate  1 << ${THRESHOLD_MODE_BIT}
    ${threshold_value}=         Evaluate  ${mode} | 1
    Write Buffer                0  ${THRESHOLDCTRL_REL}  ${threshold_value}
    ${status}=                  Read Buffer  0  ${STATUS_REL}
    ${threshold}=               Evaluate  ${status} & ${STATUS_THRESHOLD}
    Should Be Equal As Integers  ${threshold}  0
    Write Buffer                0  ${READOFFSET_REL}  3
    ${status}=                  Read Buffer  0  ${STATUS_REL}
    ${threshold}=               Evaluate  ${status} & ${STATUS_THRESHOLD}
    Should Be Equal As Integers  ${threshold}  ${STATUS_THRESHOLD}

Commands
    FOR  ${i}  IN RANGE  4
        Write Buffer            0  ${WRITEDATA_REL}  0x10
    END
    Write Buffer                0  ${CMD_REL}  ${CMD_UPDATEWRITESTART}
    ${start}=                   Read Buffer  0  ${WRITESTART_REL}
    Should Be Equal As Integers  ${start}  4
    Write Buffer                0  ${WRITEDATA_REL}  0x20
    Write Buffer                0  ${WRITEDATA_REL}  0x20
    Write Buffer                0  ${CMD_REL}  ${CMD_RESTOREWRITEOFFSET}
    ${write_offset}=            Read Buffer  0  ${WRITEOFFSET_REL}
    Should Be Equal As Integers  ${write_offset}  4
    ${bytes}=                   Bytes In Buffer  0
    Should Be Equal As Integers  ${bytes}  4

    Write Buffer                0  ${CMD_REL}  ${CMD_CLEAR}
    ${bytes}=                   Bytes In Buffer  0
    Should Be Equal As Integers  ${bytes}  0
    ${write_offset}=            Read Buffer  0  ${WRITEOFFSET_REL}
    Should Be Equal As Integers  ${write_offset}  0
    ${read_offset}=             Read Buffer  0  ${READOFFSET_REL}
    Should Be Equal As Integers  ${read_offset}  0
    ${start}=                   Read Buffer  0  ${WRITESTART_REL}
    Should Be Equal As Integers  ${start}  0

    Write Register              ${IF_REG}  0x0
    Write Buffer                0  ${CMD_REL}  ${CMD_PREFETCH}
    ${flags}=                   Read Register  ${IF_REG}
    ${underflow}=               Evaluate  ${flags} & ${IF_UF}
    Should Be Equal As Integers  ${underflow}  ${IF_UF}

Host And Sequencer Interrupts
    Write Register              ${IEN_REG}  ${IF_OF}
    FOR  ${i}  IN RANGE  ${DEFAULT_SIZE}
        Write Buffer            0  ${WRITEDATA_REL}  0x01
    END
    Write Buffer                0  ${WRITEDATA_REL}  0x01
    Assert IRQ Is Set           sysbus.bufc  IRQ
    Assert IRQ Is Unset         sysbus.bufc  SequencerIRQ

    Write Register              ${IF_REG}  0x0
    Assert IRQ Is Unset         sysbus.bufc  IRQ
    Write Register              ${SEQIEN_REG}  ${IF_OF}
    Write Buffer                0  ${WRITEDATA_REL}  0x01
    Assert IRQ Is Set           sysbus.bufc  IRQ
    Assert IRQ Is Set           sysbus.bufc  SequencerIRQ

    Write Register              ${SEQIF_REG}  0x0
    Assert IRQ Is Set           sysbus.bufc  IRQ
    Assert IRQ Is Unset         sysbus.bufc  SequencerIRQ
    Write Register              ${IF_REG}  0x0
    Assert IRQ Is Unset         sysbus.bufc  IRQ

Set Clear And Toggle
    Write Buffer                0  ${CTRL_REL}  0x0
    ${ctrl}=                    Buffer Register  0  ${CTRL_REL}
    ${set}=                     Evaluate  ${ctrl} + 0x1000
    ${clr}=                     Evaluate  ${ctrl} + 0x2000
    ${tgl}=                     Evaluate  ${ctrl} + 0x3000
    Write Register              ${set}  ${SIZE_256}
    ${size}=                    Read Buffer  0  ${CTRL_REL}
    Should Be Equal As Integers  ${size}  ${SIZE_256}
    Write Register              ${tgl}  ${SIZE_256}
    ${size}=                    Read Buffer  0  ${CTRL_REL}
    Should Be Equal As Integers  ${size}  0
    Write Register              ${tgl}  ${SIZE_256}
    Write Register              ${clr}  ${SIZE_256}
    ${size}=                    Read Buffer  0  ${CTRL_REL}
    Should Be Equal As Integers  ${size}  0

Buffers Are Independent
    Write Buffer                1  ${ADDR_REL}  ${BUFFER1_ADDRESS}
    Write Buffer                0  ${WRITEDATA_REL}  0x11
    Write Buffer                1  ${WRITEDATA_REL}  0x22
    ${first}=                   Read Buffer  0  ${READDATA_REL}
    ${second}=                  Read Buffer  1  ${READDATA_REL}
    Should Be Equal As Integers  ${first}  0x11
    Should Be Equal As Integers  ${second}  0x22
    ${buf0}=                    Read Byte At  ${RAM_ADDRESS}
    ${buf1}=                    Read Byte At  ${BUFFER1_ADDRESS}
    Should Be Equal As Integers  ${buf0}  0x11
    Should Be Equal As Integers  ${buf1}  0x22

Read Ready Flags
    Write Buffer                0  ${WRITEDATA_REL}  0x01
    ${status}=                  Read Buffer  0  ${STATUS_REL}
    ${ready}=                   Evaluate  ${status} & ${STATUS_RDATARDY}
    Should Be Equal As Integers  ${ready}  ${STATUS_RDATARDY}
    ${ready32}=                 Evaluate  ${status} & ${STATUS_RDATA32RDY}
    Should Be Equal As Integers  ${ready32}  0

    FOR  ${i}  IN RANGE  4
        Write Buffer            0  ${WRITEDATA_REL}  0x01
    END
    ${status}=                  Read Buffer  0  ${STATUS_REL}
    ${ready32}=                 Evaluate  ${status} & ${STATUS_RDATA32RDY}
    Should Be Equal As Integers  ${ready32}  ${STATUS_RDATA32RDY}

    # Four bytes are left but the read offset is no longer on a word boundary.
    ${byte}=                    Read Buffer  0  ${READDATA_REL}
    ${status}=                  Read Buffer  0  ${STATUS_REL}
    ${ready}=                   Evaluate  ${status} & ${STATUS_RDATARDY}
    Should Be Equal As Integers  ${ready}  ${STATUS_RDATARDY}
    ${ready32}=                 Evaluate  ${status} & ${STATUS_RDATA32RDY}
    Should Be Equal As Integers  ${ready32}  0

Unaligned Word Access
    Write Register              ${IEN_REG}  ${IF_NWA}
    FOR  ${i}  IN RANGE  9
        Write Buffer            0  ${WRITEDATA_REL}  0x01
    END
    # WRITEOFFSET is 9, so word writes do not complete.
    Write Buffer                0  ${WRITEDATA32_REL}  0x11223344
    ${write_offset}=            Read Buffer  0  ${WRITEOFFSET_REL}
    Should Be Equal As Integers  ${write_offset}  9
    ${flags}=                   Read Register  ${IF_REG}
    ${nwa}=                     Evaluate  ${flags} & ${IF_NWA}
    Should Be Equal As Integers  ${nwa}  ${IF_NWA}
    ${seq_flags}=               Read Register  ${SEQIF_REG}
    ${seq_nwa}=                 Evaluate  ${seq_flags} & ${IF_NWA}
    Should Be Equal As Integers  ${seq_nwa}  ${IF_NWA}
    Assert IRQ Is Set           sysbus.bufc  IRQ

    Write Register              ${IF_REG}  0x0
    Assert IRQ Is Unset         sysbus.bufc  IRQ
    Write Buffer                0  ${XWRITE32_REL}  0x11223344
    ${write_offset}=            Read Buffer  0  ${WRITEOFFSET_REL}
    Should Be Equal As Integers  ${write_offset}  9
    ${stored}=                  Read Byte At  0x20000009
    Should Be Equal As Integers  ${stored}  0
    Assert IRQ Is Set           sysbus.bufc  IRQ

    # READOFFSET is 1, so word reads do not complete either.
    Write Register              ${IF_REG}  0x0
    ${byte}=                    Read Buffer  0  ${READDATA_REL}
    ${word}=                    Read Buffer  0  ${READDATA32_REL}
    Should Be Equal As Integers  ${word}  0
    ${read_offset}=             Read Buffer  0  ${READOFFSET_REL}
    Should Be Equal As Integers  ${read_offset}  1
    ${flags}=                   Read Register  ${IF_REG}
    ${nwa}=                     Evaluate  ${flags} & ${IF_NWA}
    Should Be Equal As Integers  ${nwa}  ${IF_NWA}
    Assert IRQ Is Set           sysbus.bufc  IRQ

Corrupt Buffer
    Write Register              ${IEN_REG}  ${IF_CORR}
    # A read offset ahead of the write offset counts more bytes than the buffer holds.
    Write Buffer                0  ${READOFFSET_REL}  10
    ${bytes}=                   Bytes In Buffer  0
    Should Be Equal As Integers  ${bytes}  118
    ${flags}=                   Read Register  ${IF_REG}
    ${corrupt}=                 Evaluate  ${flags} & ${IF_CORR}
    Should Be Equal As Integers  ${corrupt}  ${IF_CORR}
    ${seq_flags}=               Read Register  ${SEQIF_REG}
    ${seq_corrupt}=             Evaluate  ${seq_flags} & ${IF_CORR}
    Should Be Equal As Integers  ${seq_corrupt}  ${IF_CORR}
    Assert IRQ Is Set           sysbus.bufc  IRQ

    # A full buffer is not corrupt.
    Write Register              ${IF_REG}  0x0
    Write Register              ${SEQIF_REG}  0x0
    Write Buffer                0  ${READOFFSET_REL}  0
    Write Buffer                0  ${WRITEOFFSET_REL}  ${DEFAULT_SIZE}
    ${flags}=                   Read Register  ${IF_REG}
    ${corrupt}=                 Evaluate  ${flags} & ${IF_CORR}
    Should Be Equal As Integers  ${corrupt}  0
    Assert IRQ Is Unset         sysbus.bufc  IRQ

Enable And Low Power Mode
    Write Register              ${EN_REG}  0xFFFFFFFF
    ${enable}=                  Read Register  ${EN_REG}
    Should Be Equal As Integers  ${enable}  0x1
    Write Register              ${LPMODE_REG}  0xFFFFFFFF
    ${low_power}=               Read Register  ${LPMODE_REG}
    Should Be Equal As Integers  ${low_power}  0x3
    Write Register              ${LPMODE_REG}  0x1
    ${low_power}=               Read Register  ${LPMODE_REG}
    Should Be Equal As Integers  ${low_power}  0x1

Fast Switch Interrupt Registers
    IF  '${BUFC_VERSION}' == '1' or '${BUFC_VERSION}' == '4'
        Pass Execution          FSWIF and FSWIEN exist from BUFC 5
    END
    FOR  ${register}  IN  ${FSWIF_REG}  ${FSWIEN_REG}
        ${value}=               Read Register  ${register}
        Should Be Equal As Integers  ${value}  0
        Write Register          ${register}  0xFFFFFFFF
        ${value}=               Read Register  ${register}
        Should Be Equal As Integers  ${value}  ${EVENT_REGISTER_MASK}
    END
    Assert IRQ Is Unset         sysbus.bufc  IRQ
    Assert IRQ Is Unset         sysbus.bufc  SequencerIRQ

Bus Error
    Write Register              ${IEN_REG}  ${IF_BUSERROR}
    Write Register              ${SEQIEN_REG}  ${IF_BUSERROR}

    # An empty buffer never touches the bus, so a bad address is only an underflow.
    Write Buffer                0  ${ADDR_REL}  0x21000000
    ${byte}=                    Read Buffer  0  ${READDATA_REL}
    Should Be Equal As Integers  ${byte}  0
    ${read_offset}=             Read Buffer  0  ${READOFFSET_REL}
    Should Be Equal As Integers  ${read_offset}  0
    ${flags}=                   Read Register  ${IF_REG}
    ${bus_error}=               Evaluate  ${flags} & ${IF_BUSERROR}
    Should Be Equal As Integers  ${bus_error}  0
    ${underflow}=               Evaluate  ${flags} & ${IF_UF}
    Should Be Equal As Integers  ${underflow}  ${IF_UF}
    Write Register              ${IF_REG}  0x0
    Write Register              ${SEQIF_REG}  0x0

    # A write to an address with nothing behind it does not complete.
    Write Buffer                0  ${WRITEDATA_REL}  0xAB
    ${write_offset}=            Read Buffer  0  ${WRITEOFFSET_REL}
    Should Be Equal As Integers  ${write_offset}  0
    ${flags}=                   Read Register  ${IF_REG}
    ${bus_error}=               Evaluate  ${flags} & ${IF_BUSERROR}
    Should Be Equal As Integers  ${bus_error}  ${IF_BUSERROR}
    ${seq_flags}=               Read Register  ${SEQIF_REG}
    ${seq_bus_error}=           Evaluate  ${seq_flags} & ${IF_BUSERROR}
    Should Be Equal As Integers  ${seq_bus_error}  ${IF_BUSERROR}
    Assert IRQ Is Set           sysbus.bufc  IRQ
    Assert IRQ Is Set           sysbus.bufc  SequencerIRQ
    # The fast-switch flags only store what software writes.
    IF  '${BUFC_VERSION}' != '1' and '${BUFC_VERSION}' != '4'
        ${fsw}=                 Read Register  ${FSWIF_REG}
        Should Be Equal As Integers  ${fsw}  0
    END

    # Clearing the host flag leaves the sequencer interrupt pending.
    Write Register              ${IF_REG}  0x0
    Assert IRQ Is Unset         sysbus.bufc  IRQ
    Assert IRQ Is Set           sysbus.bufc  SequencerIRQ
    Write Register              ${SEQIF_REG}  0x0
    Assert IRQ Is Unset         sysbus.bufc  SequencerIRQ

    # Word and xor writes are rejected the same way.
    Write Buffer                0  ${WRITEDATA32_REL}  0x11223344
    ${write_offset}=            Read Buffer  0  ${WRITEOFFSET_REL}
    Should Be Equal As Integers  ${write_offset}  0
    Write Register              ${IF_REG}  0x0
    Write Register              ${SEQIF_REG}  0x0
    Write Buffer                0  ${XWRITE_REL}  0x01
    ${write_offset}=            Read Buffer  0  ${WRITEOFFSET_REL}
    Should Be Equal As Integers  ${write_offset}  0
    Write Register              ${IF_REG}  0x0
    Write Register              ${SEQIF_REG}  0x0
    Write Buffer                0  ${XWRITE32_REL}  0x01
    ${write_offset}=            Read Buffer  0  ${WRITEOFFSET_REL}
    Should Be Equal As Integers  ${write_offset}  0

    # The first byte past the end of RAM faults. The bytes before it do not.
    Write Register              ${IF_REG}  0x0
    Write Register              ${SEQIF_REG}  0x0
    Write Buffer                0  ${ADDR_REL}  0x2000FFE0
    FOR  ${i}  IN RANGE  32
        Write Buffer            0  ${WRITEDATA_REL}  0x01
    END
    ${flags}=                   Read Register  ${IF_REG}
    ${bus_error}=               Evaluate  ${flags} & ${IF_BUSERROR}
    Should Be Equal As Integers  ${bus_error}  0
    ${write_offset}=            Read Buffer  0  ${WRITEOFFSET_REL}
    Should Be Equal As Integers  ${write_offset}  32
    Write Buffer                0  ${WRITEDATA_REL}  0x01
    ${write_offset}=            Read Buffer  0  ${WRITEOFFSET_REL}
    Should Be Equal As Integers  ${write_offset}  32
    Assert IRQ Is Set           sysbus.bufc  IRQ
    Assert IRQ Is Set           sysbus.bufc  SequencerIRQ

    # A word read of data that lives at an unmapped address returns 0.
    Write Buffer                0  ${CMD_REL}  ${CMD_CLEAR}
    Write Register              ${IF_REG}  0x0
    Write Register              ${SEQIF_REG}  0x0
    Write Buffer                0  ${ADDR_REL}  ${RAM_ADDRESS}
    Write Buffer                0  ${WRITEDATA32_REL}  0xA1B2C3D4
    Write Buffer                0  ${ADDR_REL}  0x21000000
    ${word}=                    Read Buffer  0  ${READDATA32_REL}
    Should Be Equal As Integers  ${word}  0
    ${read_offset}=             Read Buffer  0  ${READOFFSET_REL}
    Should Be Equal As Integers  ${read_offset}  0
    ${flags}=                   Read Register  ${IF_REG}
    ${bus_error}=               Evaluate  ${flags} & ${IF_BUSERROR}
    Should Be Equal As Integers  ${bus_error}  ${IF_BUSERROR}
    Write Register              ${IF_REG}  0x0
    ${byte}=                    Read Buffer  0  ${READDATA_REL}
    Should Be Equal As Integers  ${byte}  0
    ${read_offset}=             Read Buffer  0  ${READOFFSET_REL}
    Should Be Equal As Integers  ${read_offset}  0

Bulk Transfer Stops On Bus Error
    # FRC moves whole frames through TryReadBytes and TryWriteBytes. A bus error must stop
    # that transfer: the access does not raise underflow or overflow, and the offset stays put.
    Write Buffer                0  ${ADDR_REL}  0x21000000
    Write Buffer                0  ${WRITEOFFSET_REL}  4
    ${unmapped_read}=           Catenate  SEPARATOR=\n
    ...                         import sys
    ...                         bufc = self.Machine["sysbus.bufc"]
    ...                         ok, data = bufc.TryReadBytes(0, 4)
    ...                         sys.stdout.write("ok=%s len=%s" % (ok, len(data)))
    ${read}=                    Execute Command  python """${unmapped_read}"""
    Should Contain              ${read}  ok=False
    Should Contain              ${read}  len=0
    ${read_offset}=             Read Buffer  0  ${READOFFSET_REL}
    Should Be Equal As Integers  ${read_offset}  0
    ${flags}=                   Read Register  ${IF_REG}
    ${bus_error}=               Evaluate  ${flags} & ${IF_BUSERROR}
    Should Be Equal As Integers  ${bus_error}  ${IF_BUSERROR}
    ${underflow}=               Evaluate  ${flags} & ${IF_UF}
    Should Be Equal As Integers  ${underflow}  0

    # Forty bytes are pending, but only 32 of them sit inside the 64KB RAM at 0x20000000.
    Write Buffer                0  ${CMD_REL}  ${CMD_CLEAR}
    Write Register              ${IF_REG}  0x0
    Write Register              ${SEQIF_REG}  0x0
    Write Buffer                0  ${ADDR_REL}  0x2000FFE0
    Write Buffer                0  ${WRITEOFFSET_REL}  40
    ${partial_read}=            Catenate  SEPARATOR=\n
    ...                         import sys
    ...                         bufc = self.Machine["sysbus.bufc"]
    ...                         ok, data = bufc.TryReadBytes(0, 40)
    ...                         sys.stdout.write("ok=%s len=%s" % (ok, len(data)))
    ${read}=                    Execute Command  python """${partial_read}"""
    Should Contain              ${read}  ok=False
    Should Contain              ${read}  len=32
    ${read_offset}=             Read Buffer  0  ${READOFFSET_REL}
    Should Be Equal As Integers  ${read_offset}  32
    ${flags}=                   Read Register  ${IF_REG}
    ${underflow}=               Evaluate  ${flags} & ${IF_UF}
    Should Be Equal As Integers  ${underflow}  0

    # The same boundary on the way in. The 33rd byte is the one that faults.
    Write Buffer                0  ${CMD_REL}  ${CMD_CLEAR}
    Write Register              ${IF_REG}  0x0
    Write Register              ${SEQIF_REG}  0x0
    Write Buffer                0  ${ADDR_REL}  0x2000FFE0
    ${partial_write}=           Catenate  SEPARATOR=\n
    ...                         import sys
    ...                         from System import Array, Byte
    ...                         bufc = self.Machine["sysbus.bufc"]
    ...                         payload = Array[Byte]([Byte(0x5A)] * 40)
    ...                         ok, written = bufc.TryWriteBytes(0, payload)
    ...                         sys.stdout.write("ok=%s written=%s" % (ok, written))
    ${write}=                   Execute Command  python """${partial_write}"""
    Should Contain              ${write}  ok=False
    Should Contain              ${write}  written=32
    ${write_offset}=            Read Buffer  0  ${WRITEOFFSET_REL}
    Should Be Equal As Integers  ${write_offset}  32
    ${stored}=                  Read Byte At  0x2000FFFF
    Should Be Equal As Integers  ${stored}  0x5A
    ${flags}=                   Read Register  ${IF_REG}
    ${bus_error}=               Evaluate  ${flags} & ${IF_BUSERROR}
    Should Be Equal As Integers  ${bus_error}  ${IF_BUSERROR}
    ${overflow}=                Evaluate  ${flags} & ${IF_OF}
    Should Be Equal As Integers  ${overflow}  0

