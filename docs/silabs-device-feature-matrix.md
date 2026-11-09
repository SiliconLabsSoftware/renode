# Silicon Labs Renode Device Model Feature Matrix

This matrix summarizes what the Renode platform descriptions and regression suite currently model for xG24, xG26, and SixG301. It is an initial source-based inventory for engineering review; a peripheral being mapped does not imply cycle-accurate behavior or complete silicon fidelity.

**Scope:** SiliconLabsSoftware/renode `silabs/release/26q3` source snapshot. The matrix should be reviewed and updated by the owning peripheral/radio engineers as models or tests change.

**Legend:** ✓ model or behavior is present (see Notes for test coverage); ✗ not modeled; N/A not applicable to that target. A * means the model is present but the current suite does not directly exercise that feature on that target.

| Feature | xG24 | xG26 | SixG301 | Notes |
|:--|:--:|:--:|:--:|:--|
| Main CPU and radio sequencer | ✓ | ✓ | ✓ | xG24/xG26: Cortex-M33 + Cortex-M0+; SixG301: Cortex-M33 + CV32E40P. See the [xG24](../platforms/cpus/silabs/efr32s2/efr32xG24.repl), [xG26](../platforms/cpus/silabs/efr32s2/efr32xG26.repl), and [SixG301](../platforms/cpus/silabs/sixG30x/sixG301.repl) platform descriptions. |
| SRAM and flash address space | ✓ | ✓ | ✓ | Memory regions are mapped. Flash is represented as mapped memory; this does not model physical flash timing, wear, or all controller behavior. |
| GPIO | ✓ | ✓ | ✓ | Silicon Labs GPIO model is instantiated in each platform description. |
| I2C | ✓ | ✓ | ✓ | I2C controller is instantiated in each platform description. |
| USART / EUSART | ✓ | ✓ | ✓ | UART models are instantiated. EUSART behavior has regression coverage for IP versions 2 and 4. |
| LDMA | ✓ | ✓ | ✓ | DMA model is instantiated. Regression suite covers LDMA IP versions 0_1, 0_3, and 3_3. |
| General-purpose timers | ✓ | ✓ | ✓ | Timer models are instantiated; test coverage spans timer IP versions 0 and 2. |
| SYSRTC | ✓ | ✓ | ✓ | SYSRTC model is instantiated; see the SiLabs peripheral tests. |
| Watchdogs | ✓ | ✓ | ✓ | Watchdog models are instantiated; see the SiLabs peripheral tests. |
| Symmetric crypto accelerator | ✓ | ✓ | ✓ | SYMCRYPTO model is instantiated and has a peripheral test. |
| ADC / analog comparator / DAC / pulse counter | ✗ | ✗ | ✗ | These peripherals are not instantiated in the selected platform descriptions. This describes Renode model support, not whether a particular silicon SKU contains the peripheral. |
| Low-power wireless radio register model | ✓ | ✓ | ✓ | xG24 and xG26 use `SiLabs_xG24_LPW`; SixG301 uses `SiLabs_xG301_LPW`. |
| Deterministic packet-level radio TX/RX | ✓ | ✓* | ✓ | LPW RX tests cover channel match, sync-word match, PHY compatibility, and frame delivery. The test configuration explicitly runs xG22, xG24, and xG301; xG26 uses the xG24 model class but is not a named LPW RX test target. |
| Packet collision behavior | ✓ | ✓* | ✓ | The LPW RX tests exercise deterministic co-channel packet collision cases for xG24 and xG301. xG26 uses the xG24 model class; direct test coverage is not listed. |
| Thread / OpenThread software integration | ✓ | ✓* | ✓ | Test configurations include OpenThread runs for xG24 and SixG301. xG26 uses the xG24 radio model, but no xG26 OpenThread scenario is listed in the current test configuration. |
| Zigbee software integration | ✓ | ✓ | ✓ | Test configurations include Zigbee runs for xG24 and SixG301; xG26 is exercised by the Zigbee + BLE dynamic multiprotocol scenario. |
| Bluetooth LE software integration | ✓ | ✓ | ✓ | BLE NCP scenarios are configured for xG24, xG26, and SixG301. These exercise firmware and protocol behavior on the modeled radio path; they do not establish RF accuracy. |
| Zigbee + BLE dynamic multiprotocol scenario | ✓ | ✓ | ✓ | Dynamic multiprotocol tests are configured for xG24, xG26, and SixG301. |
| Wi-Fi | N/A | N/A | N/A | These targets are not Wi-Fi devices. |
| RF-accurate propagation, path loss, fading, or calibrated RF power | ✗ | ✗ | ✗ | Packet-level delivery and collision rules are deterministic abstractions; they do not model a calibrated RF environment or physical radio measurements. |
| Power consumption / battery-life prediction | ✗ | ✗ | ✗ | Peripheral and radio models do not provide validated current-consumption or battery-life results. |

## Maintaining the matrix

When changing a status or caveat:

1. Check the target's platform description and the relevant model implementation.
2. Check whether a regression test covers the behavior for that target; link it in Notes.
3. Keep a * when a model is reused across targets but target-specific test coverage is absent.
4. Use ✗ only when the behavior is not represented by the Renode model, and N/A only when the feature does not apply to the target.
5. Update the source snapshot/version at the top when the matrix is reviewed against a newer branch.

Useful references: [Silicon Labs platform descriptions](../platforms/boards/silabs), [SiLabs peripheral tests](../tests/peripherals/SiLabs), [SiLabs platform integration tests](../tests/platforms/SiLabs), and [test configuration](../tests/silabs_tests.json).
