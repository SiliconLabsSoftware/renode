# PyRenode3 Test Library

A simple test framework for Renode using pyrenode3.  (Python 3.11+ required).

[PyRenode3](https://github.com/antmicro/pyrenode3)

Provides common cli argument parsing for test scripts, as well as generic functionality for interacting with Renode emulations.

Tests are structured as a single executable script that imports the test library, configures the test devices and then executes the test logic.
Most tests will be driven via serial TerminalTester interactions with the emulated devices, sending commands and expecting certain responses.

## Installation and Execution

The test library can be installed from source via pip.  It is generally recommended to use a virtual environment, for example.

```sh
python -m venv .venv
source .venv/bin/activate
pip install -e $RENODE_ROOT/tests/test_lib
python $RENODE_ROOT/tests/platforms/SiLabs/zigbee.py --board brd4186c --uart eusart0 --elf https://artifactory.silabs.net/artifactory/renode-production/prebuilt/xg24/zigbee_z3_light_v2025.6.2.out
```

CI and local Renode test runs install the same package automatically when `./r runtest` runs a Python test (see `scripts/silabs-dev/runtest.js`).

## Contributing

If contributing changes to the test_lib package please follow general guidelines, and if
necessary increment the version number in the `pyproject.toml`.
