---
name: renode-test_lib
description: >-
  Runs a pyrenode3/test_lib-based test in renode
  Use when the user mentions "run renode test"
disable-model-invocation: true
---

# renode-test_lib

Provides the command and CLI parameters for running a pyrenode3/test_lib-based test in renode.

## When to use

- Reproduce a bug by running a specific pyrenode3/test_lib-based test with specific parameters
- Run a single test locally with `python3`
- Debug a failing test by temporarily augmenting the test script (function tracing, radio logs)

## Prerequisites

- Path or repo context: `renode/`
- `test_lib` installed: `pip install -e $RENODE_ROOT/tests/test_lib`
- `RENODE_BASE_PATH` set to the renode repo root (so board `.repl` files resolve)

## Running a test

```sh
# From renode repo root
RENODE_BASE_PATH=$PWD python3 tests/platforms/SiLabs/zigbee.py \
  --board brd4186c --uart eusart0 --elf /path/to/firmware.out -r 0x1234ABCD
```

## CLI parameters (`test_lib.parse_arguments()`)

All test_lib-based tests share the same argparse schema defined in `tests/test_lib/src/test_lib/__init__.py`.

### Required (at least one node)

| Flag | Long form | Description |
|------|-----------|-------------|
| `-b` | `--board` | Board name for node 1 (e.g. `brd4186c`, `brd1019a`) |
| `-u` | `--uart` | UART peripheral name on sysbus for node 1 (e.g. `eusart0`) |
| `-e` | `--elf` | ELF path or URL for node 1 (local path or `https://…`) |

### Optional — additional nodes (up to 5 numbered, then variadic)

| Flag | Long form | Description |
|------|-----------|-------------|
| `-b2` … `-b5` | `--board2` … `--board5` | Board for nodes 2–5 |
| | `--boards` | More boards after node 5 (`nargs=*`) |
| `-u2` … `-u5` | `--uart2` … `--uart5` | UART for nodes 2–5 |
| | `--uarts` | More UARTs after node 5 (`nargs=*`) |
| `-e2` … `-e5` | `--elf2` … `--elf5` | ELF for nodes 2–5 |
| | `--elfs` | More ELFs after node 5 (`nargs=*`) |

Numbered and variadic arguments are collected in CLI order into three lists: `boards`, `uarts`, `elfs`. Typical usage:

```python
boards, uarts, elfs = test_lib.parse_arguments()
board, uart, elf = boards[0], uarts[0], elfs[0]
```

Multi-node tests (e.g. `zigbee.py`) reuse the first value when only one is given:

```python
board2 = boards[1] if len(boards) > 1 else boards[0]
```

### Optional — emulation control

| Flag | Long form | Description |
|------|-----------|-------------|
| `-l` | `--log_file` | File to log Renode activity |
| `-r` | `--rng_seed` | RNG seed for emulation (decimal or hex, e.g. `1234` or `0x1234ABCD`) |

`--rng_seed` and `--log_file` are consumed by `create_emulation()` when its `rng_seed` / `log_file` arguments are left at default (`None`).

## Environment variables

| Variable | Purpose |
|----------|---------|
| `RENODE_BASE_PATH` | Renode repo root; used to resolve `platforms/boards/silabs/<board>.repl` |
| `RENODE_PORT` | Set internally by `launch_host_process()` for external-control time sync |

## Example commands

```sh
# Single-node BLE NCP test
RENODE_BASE_PATH=$PWD python3 tests/platforms/SiLabs/ble_ncp.py \
  --board brd4186c --uart eusart0 \
  --elf https://artifactory.silabs.net/artifactory/renode-production/prebuilt/xg24/…

# Two-node Zigbee (different boards/ELFs)
RENODE_BASE_PATH=$PWD python3 tests/platforms/SiLabs/zigbee.py \
  --board brd4186c --board2 brd4407a \
  --uart eusart0 --uart2 eusart0 \
  --elf https://…/light.out --elf2 https://…/light2.out

# Reproducible run with fixed seed and log capture
RENODE_BASE_PATH=$PWD python3 tests/platforms/SiLabs/zigbee.py \
  --board brd4186c --uart eusart0 --elf /path/to/fw.out \
  --rng_seed 0xDEADBEEF --log_file /tmp/renode.log
```

## Debugging augmentations

Temporary changes to the test script for local debugging. Remove before committing.

### Function tracing

When UART output is not enough, use `test_lib.add_function_trace()`. It installs CPU execution hooks on symbol names or raw addresses and fires a callback on every hit.

Add tracing **after** `create_node()` (you need the returned `tester`). Enable `debug=True` in `create_emulation()` or call `test_lib.enable_debug_prints(True)` so trace lines appear on stdout.

```python
node = test_lib.create_node("node1", board, elf, uart)

# Default hook: prints function name, up to num_args integer args, caller, virtual time
test_lib.add_function_trace(node, ["sl_foo", "sl_bar"])
test_lib.add_function_trace(node, "sli_mac_lower_mac_send", num_args=2)

# Explicit labels, custom callback, or secondary CPU
test_lib.add_function_trace(
    node,
    {"GENERIC_PHY_CanModifyAck": "CanModifyAck"},
    callback=test_lib.example_trace_hook,
)
test_lib.add_function_trace(node, {0x2000abcd: "isr"}, cpu="secpu")
```

`targets` accepts a single symbol/address, a list, or a `{target: label}` dict. Symbols are resolved from the loaded ELF; addresses are used as-is. Set `num_args` to the traced function's arity (extra slots show stale register contents). Pass a custom `callback(ctx)` to inspect registers, memory, or accumulate stats — see `example_trace_hook` in `test_lib` for the `ctx` dict fields.

### Radio activity logging

For wireless/multi-node tests, call `test_lib.log_radio_activity_as_error()` **after** `create_node()` to surface radio TX/RX activity in Renode logs:

```python
test_lib.create_emulation(debug=True, quantum_time=QUANTUM_TIME)
node1 = test_lib.create_node("node1", board, elf, uart)
node2 = test_lib.create_node("node2", board, elf, uart)
test_lib.log_radio_activity_as_error()
```

This sets `LogBasicRadioActivityAsError = True` on each node's `sysbus.radio`. Combine with `--log_file` or `test_lib.set_log_file()` to capture the output.

## Notes

- Individual test scripts may define additional **in-script** constants (e.g. `QUANTUM_TIME`, `DEBUG`, `STUBS`) passed to `create_emulation()` / `create_node()` — those are not CLI parameters unless the test adds its own argparse.
- `create_node()` also accepts `tester_timeout` and `function_stubs` programmatically; see `test_lib` docstrings for stub formats.
- ELF values may be local paths or `http://` / `https://` URLs (downloaded to a temp file before load).
