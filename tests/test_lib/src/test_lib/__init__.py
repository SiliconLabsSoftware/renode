from pyrenode3.wrappers import Analyzer, Emulation, Monitor, TerminalTester
from Antmicro.Renode.Time import TimeInterval
from Antmicro.Renode.Peripherals.Wireless import IEEE802_15_4Medium
from Antmicro.Renode.Peripherals.CPU import ICpuSupportingGdb
from Antmicro.Renode.Peripherals.CPU import RegisterValue
from Antmicro.Renode.Peripherals.CPU import CpuAddressHook
from System import Action
from System.IO import Stream
import System
import sys
import argparse
import os
import pty
import threading
import subprocess
import queue
import time
import urllib.request
import tempfile
import stat
import re
import shlex
import atexit

DEFAULT_QUANTUM_TIME = 0.000020
DEFAULT_TESTER_TIMEOUT = 10
DEFAULT_ABSENCE_TIMEOUT = 1
DEFAULT_DEBUG_PRINT = False
DEFAULT_LOG_LEVEL = 1
DEFAULT_STUB_RETURN_VALUE = 0
DEFAULT_CLI_LOGGING_ENABLED = True
BASE_EXTERNAL_CONTROL_PORT = 3300
HOST_PROCESS_TRIGGER_PERIOD = 1.0

# ANSI colors used to tint the per-line tagged prints emitted by this
# module. Orange uses the 256-color form because the standard 16-color
# palette has no orange (33 'yellow' renders too greenish on most modern
# terminals). Lines that go to non-terminal sinks (log files, CI capture)
# will contain the literal escape bytes; if that ever becomes a problem,
# gate these constants on `sys.stdout.isatty()` or the NO_COLOR env var.
ANSI_RESET  = "\x1b[0m"
ANSI_GREEN  = "\x1b[92m"        # [EXP]: lines emitted on a wait_for match (bright green)
ANSI_ORANGE = "\x1b[38;5;214m"  # [SND]: lines emitted on write_line (brighter orange than 208)
ANSI_WHITE  = "\x1b[97m"        # [CLI]: lines emitted by enable_cli_logging (bright white)

#Location of renode repo relative to working directory;
#for unpackaged renode it is the root of unpackaged contents
RENODE_BASE_PATH = os.environ.get("RENODE_BASE_PATH", "")

def parse_arguments():
    """
    Parses command-line arguments for the Silicon Labs pyrenode3-based testing library.

    Returns:
        tuple: A 3-tuple (boards, uarts, elfs) where each element is a list of strings:
            - boards (list[str]): One or more boards to use for emulation, for example "brd4186c"
              (--board required; --board2, --board3, ... and --boards optional).
            - uarts (list[str]): One or more UART interfaces to interact with the emulated nodes
              (--uart required; --uart2, --uart3, ... and --uarts optional).
            - elfs (list[str]): One or more ELF files to be loaded
              (--elf required; --elf2, --elf3, ... and --elfs optional).

        Each list always contains at least one entry (the required argument is at index 0),
        followed by any optional values in CLI order. Typical usage:
            boards, uarts, elfs = test_lib.parse_arguments()
            board, uart, elf = boards[0], uarts[0], elfs[0]

    Raises:
        SystemExit: If required arguments are not provided or parsing fails.
    """
    global _cli_rng_seed, _cli_log_file
    parser = argparse.ArgumentParser(description="Silicon Labs pyrenode3-based testing library")
    parser.add_argument("-b", "--board", help="The board to use for emulation.", required=True)
    parser.add_argument("-b2", "--board2", help="An optional second board to be used for emulation", required=False)
    parser.add_argument("-b3", "--board3", help="An optional third board to be used for emulation", required=False)
    parser.add_argument("-b4", "--board4", help="An optional fourth board to be used for emulation", required=False)
    parser.add_argument("-b5", "--board5", help="An optional fifth board to be used for emulation", required=False)
    parser.add_argument("--boards", help="Additional boards (arbitrary number); use with or without --board2 through --board5", nargs="*", default=None, metavar="BOARD")
    parser.add_argument("-u", "--uart", help="The UART interface to be used to interact with the emulated nodes", required=True)
    parser.add_argument("-u2", "--uart2", help="An optional second UART interface to interact with the emulated nodes", required=False)
    parser.add_argument("-u3", "--uart3", help="An optional third UART interface to interact with the emulated nodes", required=False)
    parser.add_argument("-u4", "--uart4", help="An optional fourth UART interface to interact with the emulated nodes", required=False)
    parser.add_argument("-u5", "--uart5", help="An optional fifth UART interface to interact with the emulated nodes", required=False)
    parser.add_argument("--uarts", help="Additional UART interfaces (arbitrary number); use with or without --uart2 through --uart5", nargs="*", default=None, metavar="UART")
    parser.add_argument("-e", "--elf", help="The ELF file to be loaded into the emulated nodes", required=True)
    parser.add_argument("-e2", "--elf2", help="An optional second ELF file to be loaded into the emulated nodes", required=False)
    parser.add_argument("-e3", "--elf3", help="An optional third ELF file to be loaded into the emulated nodes", required=False)
    parser.add_argument("-e4", "--elf4", help="An optional fourth ELF file to be loaded into the emulated nodes", required=False)
    parser.add_argument("-e5", "--elf5", help="An optional fifth ELF file to be loaded into the emulated nodes", required=False)
    parser.add_argument("--elfs", help="Additional ELF files (arbitrary number); use with or without --elf2 through --elf5", nargs="*", default=None, metavar="ELF")
    parser.add_argument("-l", "--log_file", help="The file to log all activity", required=False)
    parser.add_argument(
        "-r", "--rng_seed",
        help="The random number generator seed to be used for emulation (decimal or hex, e.g., 1234 or 0x1234ABCD)",
        required=False,
        type=lambda x: int(x, 0) if x is not None else None
    )
    args = parser.parse_args()
    _cli_rng_seed = args.rng_seed
    _cli_log_file = args.log_file

    def _collect(required_value, numbered_values, extras):
        ordered = [required_value]
        for opt in numbered_values:
            if opt is not None:
                ordered.append(opt)
        if extras:
            ordered.extend(extras)
        return ordered

    boards = _collect(args.board, (args.board2, args.board3, args.board4, args.board5), args.boards)
    uarts = _collect(args.uart, (args.uart2, args.uart3, args.uart4, args.uart5), args.uarts)
    elfs = _collect(args.elf, (args.elf2, args.elf3, args.elf4, args.elf5), args.elfs)
    return boards, uarts, elfs

def create_emulation(debug=DEFAULT_DEBUG_PRINT, quantum_time=DEFAULT_QUANTUM_TIME, rng_seed=None, log_file=None):
    """
    Initializes and configures the emulation environment.

    Parameters:
        debug (callable, optional): Function to handle debug printing. Defaults to DEFAULT_DEBUG_PRINT.
        quantum_time (float, optional): The quantum time interval in seconds for the emulation. Defaults to DEFAULT_QUANTUM_TIME.
        rng_seed (int, optional): Seed value for the random number generator. If None, it shall use the seed parsed out from the command line arguments, if available. Otherwise, a random seed is used.
        log_file (str, optional): The file to log all activity. If None, it shall use the log filename parsed out from the command line arguments, if available. Otherwise, a no logging is performed.

    Side Effects:
        - Sets global variables _e (Emulation instance), _m (Monitor instance), and _debug_print.
        - Configures the emulation environment with serial execution, quantum time, and immediate advancement.
        - Creates an IEEE 802.15.4 wireless medium.
        - Sets the RNG seed if provided.
        - Prints the RNG seed in hexadecimal format.

    Returns:
        None
    """
    global _e, _m, _debug_print
    _debug_print = debug
    _e = Emulation()
    _m = Monitor()
    _e.SetGlobalSerialExecution(True)
    _e.SetQuantum(TimeInterval.FromSeconds(quantum_time))
    _e.SetAdvanceImmediately(True)
    _e.CreateIEEE802_15_4Medium("wireless")
    if rng_seed is not None:
        _e.SetSeed(rng_seed)
    elif _cli_rng_seed is not None:
        _e.SetSeed(_cli_rng_seed)
    if log_file is not None:
        set_log_file(log_file)
    elif _cli_log_file is not None:
        set_log_file(_cli_log_file)
    print(f"RNG SEED: {hex(_e.GetSeed())}")

def create_node(name, board, elf_file, tester_interface, tester_timeout = DEFAULT_TESTER_TIMEOUT, function_stubs=None):
    """
    Creates and configures a simulation node with the specified parameters.

    Args:
        name (str): The name of the node/machine to create.
        board (str): The Silicon Labs emulated board to be used.
        elf_file (str): Path to the ELF binary file to load into the node.
        tester_interface (str): The name of the interface on the node to attach the TerminalTester to.
        tester_timeout (int, optional): Timeout value for the TerminalTester. Defaults to DEFAULT_TESTER_TIMEOUT.
        function_stubs (dict or None, optional): Optional dictionary of function stubs to add to the node.

    Returns:
        TerminalTester: An instance of TerminalTester attached to the specified interface.

    Raises:
        SystemExit: If no testerInterface is provided.

    Side Effects:
        - Adds the created node to internal mappings for machine and tester tracking.
        - Loads the specified ELF files into the node.
        - Connects the node's radio to the system bus via the wireless connector.
        - Adds any provided function stubs to the node.
    """
    # Remote ELFs (http/https) are resolved to a local file so the ELF-direct
    # symbol resolution (and the reset macro's LoadSymbolsFrom) can read them
    # from disk. Renode itself can fetch URLs, but ELFSharp cannot.
    elf_file = _resolve_elf_path(elf_file)
    node = _e.add_mach(name)
    node.load_repl(RENODE_BASE_PATH + "platforms/boards/silabs/" + board + ".repl")
    node.load_elf(elf_file)
    _machine_name_to_elf_mapping[name] = elf_file
    _add_stubs(node, function_stubs, elf_file)
    _add_reset_macro(name, elf_file)
    execute_monitor_command("runMacro $reset")
    execute_monitor_command("connector Connect sysbus.radio wireless")
    if tester_interface is not None:
        uart_peripheral = getattr(node.sysbus, tester_interface)
        tester = TerminalTester(uart_peripheral, tester_timeout)
    else:
        fail("No TerminalTester interface provided")
    _machine_name_to_machine_mapping[name] = node
    _tester_to_machine_mapping[tester] = node
    # Keep a reference to the raw .NET UART so callers can attach extra
    # CharReceived listeners (e.g. enable_cli_logging) without touching
    # the TerminalTester's matching logic.
    _tester_to_uart_mapping[tester] = uart_peripheral.internal
    if _cli_logging_enabled:
        enable_cli_logging(tester, True)
    return tester

def create_unit_test_machine(name, repl_string):
    """
    Creates a unit test machine with the specified parameters.

    Args:
        name (str): The name of the machine to create.
        repl_string (str): The REPL string to load into the machine.
    """
    execute_monitor_command(f"mach create \"{name}\"")
    with tempfile.NamedTemporaryFile(mode='w', suffix='.repl', delete=False) as f:
        f.write(repl_string)
        repl_path = f.name
    execute_monitor_command(f"machine LoadPlatformDescription @{repl_path}")
    os.unlink(repl_path)

def launch_host_process(binary, name, args=None, cwd=None, env=None, virtual_time=False):
    """
    Launches a host process with the specified binary and saves a reference for later interaction.

    Args:
        binary (str): Path to the binary executable to launch, or a URL to download the binary from.
        name (str): Name to assign to this process for later reference.
        args (str or list, optional): Command-line arguments to pass to the binary. 
                                     Can be a string (will be parsed with shlex) or a list of arguments.
        cwd (str, optional): Working directory for the process. Defaults to None (current directory).
        env (dict, optional): Environment variables for the process. Defaults to None (inherit current environment).
        virtual_time (bool, optional): When True, the process drives its clock through Renode's
                                     virtual-time coordinator (see create_virtual_time_host) instead of
                                     the LD_PRELOAD time shim. In that mode no per-process external
                                     control server is created and librenode_api.so is not preloaded,
                                     since the host's clock is advanced over the VT socket. Defaults to False.

    Returns:
        subprocess.Popen: The launched process object.

    Raises:
        FileNotFoundError: If the binary file cannot be found.
        OSError: If the process cannot be launched.

    Examples:
        process = launch_host_process("/path/to/binary", "host1", ["-r", "c"], cwd="/tmp")
        process = launch_host_process("/path/to/binary", "host1", "-p /tmp/sim_ncp1 -r c")
        process = launch_host_process("https://example.com/binary", "host1", "-r c")
    """
    
    # Handle URL download if binary is a URL
    actual_binary = binary
    if binary.startswith(('http://', 'https://')):
        actual_binary = _download_binary_from_url(binary)
        
    # Build the command list
    cmd = [actual_binary]
    if args is not None:
        # Handle both string and list arguments
        if isinstance(args, str):
            # If args is a string, split it properly (handles quoted arguments)
            cmd.extend(shlex.split(args))
        elif isinstance(args, list):
            # If args is already a list, use it directly
            cmd.extend(args)
        else:
            # Convert other iterables to list
            cmd.extend(list(args))
    
    try:
        # Set up environment variables. Create a copy so we never mutate the caller's dict.
        if env is None:
            env = os.environ.copy()
        else:
            env = env.copy()

        if virtual_time:
            # The host advances its clock over the OpenThread virtual-time socket handled by the
            # Renode-side coordinator (create_virtual_time_host), so it needs neither a per-process
            # external control server nor the LD_PRELOAD time shim.
            debug_print(f"Process '{name}' launched in virtual-time mode (no LD_PRELOAD, no external control server)")
        else:
            # Create a dedicated external control server for this process
            # Each server can only handle one connection, so each process needs its own
            process_port = _create_external_control_server_for_process(name)

            # Set the RENODE_PORT environment variable to the dedicated port for this process
            env['RENODE_PORT'] = str(process_port)
            debug_print(f"Process '{name}' will connect to external control server on port {process_port}")

            # Add LD_PRELOAD for time override library (Linux)
            # Look for the library in common locations
            library_paths = [
                "build/librenode_api.so",  # Jenkins CI path
                "../build/librenode_api.so",
                "librenode_api.so",
                os.path.join(RENODE_BASE_PATH, "build/librenode_api.so"),
                os.path.join(RENODE_BASE_PATH, "tools/external_control_client/lib/build/librenode_api.so")
            ]

            library_found = None
            for lib_path in library_paths:
                if os.path.exists(lib_path):
                    library_found = os.path.abspath(lib_path)
                    break

            if library_found:
                if 'LD_PRELOAD' in env and env['LD_PRELOAD']:
                    # Append to existing LD_PRELOAD
                    env['LD_PRELOAD'] = f"{env['LD_PRELOAD']}:{library_found}"
                else:
                    # Set new LD_PRELOAD
                    env['LD_PRELOAD'] = library_found
                debug_print(f"LD_PRELOAD set to: {env['LD_PRELOAD']}")
            else:
                debug_print("Warning: Time override library not found, host process may use system time")
        
        master_fd, slave_fd = pty.openpty()
        # NOTE: The PTY is intentionally left in its default (canonical, echo-on)
        # mode. Interactive CLIs may print a prompt without a trailing newline
        # (e.g. "> "); terminal echo of the sent command injects a newline that
        # terminates that prompt line, so the command's response starts on its
        # own line. Anchored wait_for() patterns (e.g. "^[0-9a-fA-F]{32}$")
        # depend on this separation, which raw mode (echo off) would break.
        try:
            process = subprocess.Popen(
                cmd,
                cwd=cwd,
                env=env,
                stdin=slave_fd,
                stdout=slave_fd,
                stderr=slave_fd,
                close_fds=True,
            )
        finally:
            os.close(slave_fd)

        # Master-side handles: text stdin for write_line(); unbuffered binary
        # stdout (stderr is merged into the PTY). Reader decodes bytes to str.
        _process_pty_masters[process] = master_fd
        process.stdin = os.fdopen(os.dup(master_fd), "w", buffering=1)
        process.stdout = os.fdopen(os.dup(master_fd), "rb", buffering=0)
        process.stderr = None
        
        # Save the process reference and track its server port (VT hosts have no such server)
        _process_name_to_process_mapping[name] = process
        if not virtual_time:
            _process_to_server_port[process] = process_port
        
        # Track downloaded binary if we downloaded one
        if binary.startswith(('http://', 'https://')):
            # Track this process in the URL cache
            if binary in _url_cache:
                _url_cache[binary]["processes"].add(process)
            
        debug_print(f"Host process '{name}' launched with PID: {process.pid}")
        
        # Start reader threads for continuous output monitoring (stdout and stderr)
        _start_process_reader(process)

        if _cli_logging_enabled:
            enable_cli_logging(process, True)

        return process
        
    except FileNotFoundError as e:
        fail(f"Binary not found: {binary} - {e}")
    except OSError as e:
        fail(f"Failed to launch process: {binary} - {e}")
    
def wait_for(target, pattern, timeout=DEFAULT_TESTER_TIMEOUT, endline=False):
    """
    Waits for a specific pattern to appear in either tester output or process output.
    
    For host processes, this function monitors both stdout and stderr streams
    simultaneously and returns the first matching line from either stream.

    Args:
        target: Either a TerminalTester object (returned by create_node) or 
                a subprocess.Popen object (returned by launch_host_process).
        pattern (str): The string or regex pattern to wait for in the output.
        timeout (float, optional): Maximum time to wait in seconds. Defaults to DEFAULT_TESTER_TIMEOUT (10).
                                 Only used for process objects; tester objects use their own timeout.
        endline (bool, optional): If True, only matches on complete lines (waits for newline).
                                 If False, allows matching on partial/unfinished lines (default).
                                 Only affects TerminalTester objects.

    Returns:
        str: The line from the output that matches the given pattern. For host processes,
             this could be from either stdout or stderr.

    Raises:
        SystemExit: If the pattern is not found before a timeout occurs.

    Examples:
        # Wait for simulation node output
        soc1 = test_lib.create_node(...)
        line = wait_for(soc1, "NETWORK_UP 0x....")
        
        # Wait for host process output (checks both stdout and stderr)
        host1 = test_lib.launch_host_process(...)
        line = wait_for(host1, "Ready")  # Will match from either stdout or stderr
    """
    
    # Check if it's a subprocess.Popen object (host process)
    if isinstance(target, subprocess.Popen):
        # Handle host process using the threaded buffered approach
        
        process = target
        name = get_process_name_from_process(process)
        pattern_re = re.compile(pattern)
        start_time = get_simulation_time()
        end_time = start_time + timeout
        
        if process not in _process_output_threads:
            fail(f"Reader threads not running for process [{name}]")
        
        execute_monitor_command("start")
        
        # Track the last time we sent an empty line for output flushing
        # Initialize to 0 so the first check triggers an immediate flush
        last_flush_time = 0.0

        while get_simulation_time() < end_time:
            current_time = get_simulation_time()

            # If enabled, send empty line periodically to trigger output flushing
            if (_output_flushing_enabled and 
                current_time - last_flush_time >= HOST_PROCESS_TRIGGER_PERIOD):
                try:
                    write_line(target, "", log_write=False)
                    last_flush_time = current_time
                except (OSError, BrokenPipeError):
                    # Process may have terminated, ignore flush errors
                    pass
            
            # Check if process has terminated
            if process.poll() is not None:
                # Process any remaining buffered output before giving up
                remaining_time = 0.5  # Give a small window for final output
            else:
                remaining_time = end_time - current_time
                if remaining_time <= 0:
                    break
            
            # Try to get output from both stdout and stderr buffer queues
            output_found = False
            data = None
            
            # Check stdout first
            try:
                data = _process_stdout_buffers[process].get(timeout=0.05)
                output_found = True
            except queue.Empty:
                # No new stdout data available, continue to check stderr
                try:
                    data = _process_stderr_buffers[process].get(timeout=0.05)
                    output_found = True
                except queue.Empty:
                    # No new output available from either stream
                    continue
            
            if output_found:
                line_content = data.rstrip('\r\n')
                if line_content and pattern_re.search(line_content):
                    print(f"{ANSI_GREEN}[{name}]:[EXP]: {line_content}{ANSI_RESET}", flush=True)
                    execute_monitor_command("pause")
                    return line_content

        fail(f"Timeout waiting for pattern '{pattern}' from process '{name}' after {timeout} seconds")

    else:
        # Handle TerminalTester object (simulation node)
        name = get_machine_name_from_tester(target)
        result = target.WaitFor(pattern=pattern, timeout=TimeInterval.FromSeconds(timeout), treatAsRegex=True, includeUnfinishedLine=not endline, pauseEmulation=True)
        if result is None or result.IsFailingString:
            fail(f"Timed out waiting for: '{pattern}' from tester '{name}' after {timeout} seconds")
        print(f"{ANSI_GREEN}[{name}]:[EXP]: {result.Line}{ANSI_RESET}", flush=True)
        return result.Line

def assert_not_received(target, pattern, timeout=DEFAULT_ABSENCE_TIMEOUT, endline=False):
    """
    Assert that a pattern does NOT appear in a tester's or process's output
    within a given time window.

    This is the negative counterpart of wait_for: it waits up to timeout
    seconds and fails if a matching line is seen. If nothing matches by the
    time the window elapses, it returns normally. Use it to verify the absence
    of output, e.g. that a packet is not received on a different radio channel.

    Args:
        target: Either a TerminalTester object (returned by create_node) or
                a subprocess.Popen object (returned by launch_host_process).
        pattern (str): The string or regex pattern that must NOT appear.
        timeout (float, optional): How long to watch for the pattern, in
                seconds. Defaults to DEFAULT_ABSENCE_TIMEOUT. Keep this small;
                it is the settle window during which the output must stay clear.
        endline (bool, optional): If True, only matches on complete lines.
                If False (default), also matches on partial/unfinished lines.
                Only affects TerminalTester objects.

    Raises:
        SystemExit: If the pattern appears within the timeout window.

    Examples:
        # Verify a node on a different channel does not receive the packet
        write_line(tx, "tx 1")
        assert_not_received(rx, "\\(rxPacket\\)")
    """
    if isinstance(target, subprocess.Popen):
        process = target
        name = get_process_name_from_process(process)
        pattern_re = re.compile(pattern)
        end_time = get_simulation_time() + timeout

        if process not in _process_output_threads:
            fail(f"Reader threads not running for process [{name}]")

        execute_monitor_command("start")
        last_flush_time = 0.0
        try:
            while get_simulation_time() < end_time:
                current_time = get_simulation_time()

                if (_output_flushing_enabled and
                        current_time - last_flush_time >= HOST_PROCESS_TRIGGER_PERIOD):
                    try:
                        write_line(target, "", log_write=False)
                        last_flush_time = current_time
                    except (OSError, BrokenPipeError):
                        pass

                data = None
                try:
                    data = _process_stdout_buffers[process].get(timeout=0.05)
                except queue.Empty:
                    try:
                        data = _process_stderr_buffers[process].get(timeout=0.05)
                    except queue.Empty:
                        continue

                line_content = data.rstrip('\r\n')
                if line_content and pattern_re.search(line_content):
                    execute_monitor_command("pause")
                    fail(f"Unexpected pattern '{pattern}' appeared from process '{name}': {line_content}")
        finally:
            execute_monitor_command("pause")
    else:
        name = get_machine_name_from_tester(target)
        result = target.WaitFor(pattern=pattern, timeout=TimeInterval.FromSeconds(timeout), treatAsRegex=True, includeUnfinishedLine=not endline, pauseEmulation=True)
        if result is not None and not result.IsFailingString:
            fail(f"Unexpected pattern '{pattern}' appeared from tester '{name}': {result.Line}")

def start_gdb_server(tester, port, cpu=""):
    """
    Start a GDB server on ``port`` for the machine associated with ``tester``.

    Equivalent to running the following Renode monitor commands::

        mach set "<machine_name>"
        machine StartGdbServer <port> false [<cpu>]

    The ``autostartEmulation`` flag is hard-coded to ``false`` so the
    emulation stays paused when the GDB client attaches; this is what tests
    almost always want (set breakpoints first, then ``continue`` from gdb).
    Pair with :func:`wait_for_gdb_connection` to block the test until a GDB
    client connects.

    Args:
        tester: A ``TerminalTester`` returned by ``create_node`` identifying
                the target machine.
        port (int): TCP port the server should listen on.
        cpu (str, optional): Either the name of a specific CPU peripheral
                (e.g. ``"cpu"``, ``"seqcpu"``), the name of a CPU
                architecture cluster (e.g. ``"cortex-m33"``), or ``"all"``.
                Defaults to ``""``, which only works on platforms with a
                single CPU architecture; on heterogenous platforms (e.g.
                SiLabs sixG30x with a Cortex-M33 alongside a CV32E40P) the
                StartGdbServer command will fail with a list of valid
                choices.

    Raises:
        RuntimeError: If no machine is associated with the provided tester,
                      or if the underlying ``StartGdbServer`` monitor
                      command fails (e.g. port in use, or the ``cpu``
                      argument is missing/invalid on a heterogenous
                      platform).
    """
    assert isinstance(port, int), "port must be an int"
    assert isinstance(cpu, str), "cpu must be a str"

    name = get_machine_name_from_tester(tester)
    if name is None:
        fail("No machine associated with the provided tester")

    cmd = f"machine StartGdbServer {port} false"
    if cpu:
        cmd += f" {cpu}"

    execute_monitor_command(f'mach set "{name}"')
    execute_monitor_command(cmd)
    suffix = f" for cpu '{cpu}'" if cpu else ""
    debug_print(f"[{name}]:[GDB]: server started on port {port}{suffix}")

def wait_for_gdb_connection(tester, port, pause_to_wait=True, accept_running_server=True, timeout=None):
    """
    Block until a GDB client connects to the GDB server running on ``port``
    for the machine associated with ``tester``.

    This is the Python counterpart of the Renode RobotFramework
    ``WaitForGdbConnection`` keyword. The GDB server itself is *not* started
    by this helper; call :func:`start_gdb_server` first (or use the equivalent
    monitor command).

    Args:
        tester: A ``TerminalTester`` returned by ``create_node`` identifying
                the target machine.
        port (int): TCP port the GDB server is listening on.
        pause_to_wait (bool, optional): If True, pause the machine and request
                an emulation pause before waiting (matches the keyword's
                default). Defaults to True.
        accept_running_server (bool, optional): If True, return immediately
                when a client is already connected. Defaults to True.
        timeout (float or None, optional): Maximum number of seconds to wait.
                ``None`` (default) blocks indefinitely, matching the keyword.

    Raises:
        SystemExit: If no GDB server is running on ``port`` for that machine,
                    or if the wait times out.
    """
    assert isinstance(port, int), "port must be an int"
    assert isinstance(pause_to_wait, bool), "pause_to_wait must be a bool"
    assert isinstance(accept_running_server, bool), "accept_running_server must be a bool"
    assert timeout is None or isinstance(timeout, (int, float)), "timeout must be a number or None"

    machine = get_machine_from_tester(tester)
    if machine is None:
        fail("No machine associated with the provided tester")

    name = get_machine_name_from_tester(tester)
    imachine = machine.internal

    if pause_to_wait:
        imachine.PauseAndRequestEmulationPause()

    if accept_running_server and imachine.IsGdbConnectedToServer(port):
        debug_print(f"[{name}]:[GDB]: client already connected on port {port}")
        return

    print(f"[{name}]:[GDB]: awaiting connection on port {port}", flush=True)

    connected = threading.Event()

    def _on_connection(_stream):
        connected.set()

    # Python.NET does not auto-convert a Python callable into a typed
    # System.Action<T> when the target method is generic; construct the
    # delegate explicitly so AttachConnectionAcceptedListenerToGdbStub
    # binds to its Action<Stream> overload, and so Detach receives the same
    # delegate instance for the -= comparison to succeed.
    listener = Action[Stream](_on_connection)

    if not imachine.AttachConnectionAcceptedListenerToGdbStub(port, listener):
        fail(f"No GDB server running on port {port} for machine '{name}'")

    try:
        if not connected.wait(timeout=timeout):
            fail(f"Timed out after {timeout}s waiting for GDB connection on port {port} for machine '{name}'")
    finally:
        try:
            # The stub may have already torn itself down (e.g. on disconnect),
            # in which case detaching is a no-op; swallow any error so we
            # don't mask the original failure (or success).
            imachine.DetachConnectionAcceptedListenerFromGdbStub(port, listener)
        except Exception:
            pass

    debug_print(f"[{name}]:[GDB]: client connected on port {port}")

def write_line(target, line, log_write=True):
    """
    Sends a line of text to either a tester (simulation node) or a host process.

    Args:
        target: Either a TerminalTester object (returned by create_node) or 
                a subprocess.Popen object (returned by launch_host_process).
        line (str): The line of text to be sent.
        log_write (bool, optional): Whether to log the write operation. Defaults to True.

    Returns:
        None

    Raises:
        OSError: If the target is a process and has terminated or stdin is closed.

    Examples:
        # Send to simulation node
        ncp1 = test_lib.create_node(...)
        write_line(ncp1, "network status")
        
        # Send to host process  
        host1 = test_lib.launch_host_process(...)
        write_line(host1, "version")
    """

    name = ""
    
    # Check if it's a subprocess.Popen object (host process)
    if isinstance(target, subprocess.Popen):
        name = get_process_name_from_process(target)
        try:
            target.stdin.write(line + "\n")
            target.stdin.flush()
        except (OSError, BrokenPipeError) as e:
            fail(f"Failed to send command to process PID {target.pid}: {e}")
    else:
        # Assume it's a TerminalTester object (simulation node)
        name = get_machine_name_from_tester(target)
        try:
            result = target.WriteLine(line)
        except Exception as e:
            fail(f"Failed to send line to tester: {e}")
    if log_write:
        print(f"{ANSI_ORANGE}[{name}]:[SND]: {line}{ANSI_RESET}", flush=True)

def delay(secs):
    """
    Lets a specified number of seconds pass in the Renode simulation environment.

    Args:
        secs (float): The number of seconds to let pass in the simulation.

    Raises:
        Any exceptions raised by the underlying _e.RunFor or TimeInterval.FromSeconds methods.

    Example:
        delay(1.5)  # Lets 1.5 seconds pass in the simulation
    """
    _e.RunFor(TimeInterval.FromSeconds(secs))

def get_simulation_time():
    """
    Gets the current elapsed virtual time from the simulation.

    Returns:
        float: The elapsed simulation time in seconds.

    Example:
        current_time = get_simulation_time()
        print(f"Simulation has been running for {current_time:.6f} seconds")
    """
    if _machine_name_to_machine_mapping:
        # Get the first available machine
        machine_name, machine = next(iter(_machine_name_to_machine_mapping.items()))
        time_obj = machine.LocalTimeSource.ElapsedVirtualTime
        return float(time_obj.TotalSeconds)
    
    fail("Failed to get time, no machine available")
    return 0.0
            
def get_machine_from_name(machine_name):
    """
    Retrieve a machine object based on its name.

    Args:
        machine_name (str): The name of the machine to retrieve.

    Returns:
        object: The machine object associated with the given name.

    Raises:
        KeyError: If the machine_name does not exist in the mapping.
    """
    return _machine_name_to_machine_mapping[machine_name]

def get_process_from_name(process_name):
    """
    Retrieve a process object based on its name.

    Args:
        process_name (str): The name of the process to retrieve.

    Returns:
        subprocess.Popen: The process object associated with the given name.

    Raises:
        KeyError: If the process_name does not exist in the mapping.
    """
    return _process_name_to_process_mapping[process_name]

def terminate_process(process_name):
    """
    Terminates a process by name and removes it from the tracking dictionary.
    Also cleans up associated resources including reader threads (both stdout and stderr), 
    output buffers, and any downloaded binary files that are no longer in use.

    Args:
        process_name (str): The name of the process to terminate.

    Returns:
        None

    Raises:
        KeyError: If the process_name does not exist in the mapping.
    """
    process = _process_name_to_process_mapping[process_name]
    
    # Clean up the reader thread before terminating
    _cleanup_process_reader(process)
    
    # Clean up downloaded binary if there is one
    url, temp_file = _find_url_for_process(process)
    if url and temp_file:
        # Remove this process from the URL cache process set
        _url_cache[url]["processes"].discard(process)
        
        # If no more processes are using this cached file, we can delete it
        if not _url_cache[url]["processes"]:
            try:
                if os.path.exists(temp_file):
                    os.unlink(temp_file)
                    debug_print(f"Removed temporary binary: {temp_file}")
            except OSError as e:
                debug_print(f"Warning: Failed to remove temporary binary {temp_file}: {e}")
            
            # Remove from URL cache since file is deleted
            del _url_cache[url]
    
    # For cleanup situations, we want to terminate processes as quickly as possible
    # to prevent them from calling clock_gettime() after external control servers are gone
    try:
        # Close stdin first to prevent further input
        if process.stdin and not process.stdin.closed:
            try:
                process.stdin.close()
            except (BrokenPipeError, OSError):
                pass
        
        # Use SIGKILL immediately for faster termination during cleanup
        process.kill()
        process.wait(timeout=0.1)  # Should complete quickly with SIGKILL
        
    except Exception as e:
        debug_print(f"Error during termination of {process_name}: {e}")
    
    del _process_name_to_process_mapping[process_name]

def get_process_name_from_process(process):
    """
    Returns the name of a process given its process object.

    Args:
        process: The subprocess.Popen object to look up.

    Returns:
        str or None: The name of the process if found in the mapping, otherwise None.
    """
    for name, p in _process_name_to_process_mapping.items():
        if p == process:
            return name
    return None

def get_machine_name_from_machine(machine):
    """
    Returns the name of a machine given its machine object.

    Args:
        machine: The machine object to look up.

    Returns:
        str or None: The name of the machine if found in the mapping, otherwise None.
    """
    for name, m in _machine_name_to_machine_mapping.items():
        if m == machine:
            return name
    return None

def get_machine_name_from_tester(tester):
    """
    Returns the machine name associated with a given tester.

    Args:
        tester: An object or identifier returned by the create_node function.

    Returns:
        The name of the machine associated with the provided tester.

    Raises:
        KeyError: If the tester is not found in the mapping.
    """
    return get_machine_name_from_machine(_tester_to_machine_mapping[tester])

def get_machine_from_tester(tester):
    """
    Retrieve the machine associated with a given tester.

    Args:
        tester: An object or identifier returned by the create_node function.

    Returns:
        The machine associated with the provided tester, or None if the tester is not found in the mapping.
    """
    return _tester_to_machine_mapping.get(tester)

def create_socket(tester, port, interface):
    """
    Creates a server socket terminal in the emulation environment and connects it to a specified interface.

    Args:
        tester: An object or identifier returned by the create_node function.
        port (int): The port number on which to create the server socket.
        interface (str): The name of the interface on the sysbus to connect to the socket.

    Raises:
        Exception: If any of the underlying commands fail to execute.

    Side Effects:
        - Sets the current machine context in the emulation environment.
        - Creates a server socket terminal.
        - Connects the specified sysbus interface to the created socket terminal.
    """
    machine_name = get_machine_name_from_tester(tester)
    cli_name = f"cli_{machine_name}"
    execute_monitor_command(f"mach set \"{machine_name}\"")
    execute_monitor_command(f"emulation CreateServerSocketTerminal {port} \"{cli_name}\" false")
    execute_monitor_command(f"connector Connect sysbus.{interface} {cli_name}")

def create_pty_terminal(tester, interface):
    """
    Create a PTY (pseudo-terminal) terminal for UART communication in Renode emulation.
    
    This function sets up a UART PTY terminal that allows external applications to 
    communicate with the emulated system through a specified interface. The terminal
    is created with a unique name based on the machine name and connected to the
    specified UART interface.
    
    Args:
        tester: The tester object used to extract machine name information
        interface (str): The UART interface name to connect to (e.g., 'uart0', 'uart1')
    
    Returns:
        str: The file descriptor path (/tmp/sim_{machine_name}) that can be used
             to communicate with the PTY terminal
    
    Example:
        >>> fd_path = create_pty_terminal(my_tester, "uart0")
        >>> print(fd_path)  # /tmp/sim_machine_name
    """
    enable_cli_logging(tester, False)
    machine_name = get_machine_name_from_tester(tester)
    cli_name = f"cli_{machine_name}"
    fd_name = f"/tmp/sim_{machine_name}"
    execute_monitor_command(f"mach set \"{machine_name}\"")
    execute_monitor_command(f"emulation CreateUartPtyTerminal \"{cli_name}\" \"{fd_name}\" True")
    execute_monitor_command(f"connector Connect sysbus.{interface} {cli_name}")   
    return fd_name 

def create_virtual_time_host(tester, interface, node_id, port_offset=0, name=None):
    """
    Create a Renode OpenThread virtual-time coordinator and bind it to the RCP's spinel UART.

    This is the virtual-time counterpart of create_pty_terminal: instead of exposing the RCP UART
    as a PTY that a host process opens as its radio device, it attaches a VirtualTimePosixHost that
    (a) bridges spinel bytes to/from the RCP UART and (b) drives the host's clock as a Renode time
    sink over the OpenThread virtual-time socket. Launch the matching host with
    launch_host_process(..., virtual_time=True), passing PORT_OFFSET in env and forkpty-arg=<node_id>
    in the radio URL so the ports line up:
        - Renode listens on 9000 + port_offset*34
        - the host binds  18000 + port_offset*34 + node_id
    Each host must use a distinct port_offset so the simulator sockets do not collide.

    Args:
        tester: The tester object used to extract machine name information.
        interface (str): The RCP UART interface carrying spinel (e.g. 'usart0').
        node_id (int): OpenThread virtual-time node id (matches forkpty-arg in the radio URL).
        port_offset (int, optional): PORT_OFFSET for this host. Defaults to 0.
        name (str, optional): Name for the coordinator external. Defaults to "vt_<machine>".

    Returns:
        str: The name of the created virtual-time host external.
    """
    # The RCP UART carries binary spinel, not CLI text; silence the tester's CLI logging
    # so raw spinel bytes are not dumped as [CLI] output (mirrors create_pty_terminal).
    enable_cli_logging(tester, False)
    machine_name = get_machine_name_from_tester(tester)
    vt_name = name or f"vt_{machine_name}"
    execute_monitor_command(f"mach set \"{machine_name}\"")
    execute_monitor_command(f"emulation CreateVirtualTimeHost \"{vt_name}\" {node_id} {port_offset}")
    execute_monitor_command(f"connector Connect sysbus.{interface} {vt_name}")
    return vt_name

def debug_print(message, end=None):
    """
    Prints a debug message to the console if debugging is enabled.

    Args:
        message (str): The message to be printed for debugging purposes.
        end (str): The end of the message (optional).
    """
    if _debug_print:
        print(f"DEBUG: {message}", end=end, flush=True)

def enable_debug_prints(enable):
    """
    Enables or disables debug prints.

    Args:
        enable (bool): If True, enables debug prints; otherwise, disables them.
    """
    global _debug_print
    _debug_print = enable

def enable_cli_logging(target=None, enable=True):
    """
    Enable or disable line-by-line logging of all CLI output for a tester or
    host process.

    When enabled, every line received from the target is forwarded to stdout
    with its name as a prefix, regardless of whether a ``wait_for`` is
    currently in progress. This is independent from ``wait_for``, which only
    prints the single line that matched its pattern.

    For testers (simulation nodes), this attaches an extra ``CharReceived``
    listener to the raw UART; the ``TerminalTester`` keeps receiving the same
    characters and its matching behavior is unaffected.

    For host processes, the existing stdout/stderr reader threads print every
    line they read instead of going through the gated ``debug_print`` path.

    Args:
        target: A ``TerminalTester`` returned by ``create_node`` or a
                ``subprocess.Popen`` returned by ``launch_host_process``.
                If ``None``, the setting is applied to every currently
                tracked tester and host process and used as the default for
                ones created later.
        enable (bool, optional): ``True`` to enable, ``False`` to disable.
                                 Defaults to ``True``.
    """
    assert isinstance(enable, bool), "enable must be a bool"
    global _cli_logging_enabled

    if target is None:
        _cli_logging_enabled = enable
        for t in list(_tester_to_uart_mapping.keys()):
            enable_cli_logging(t, enable)
        for p in list(_process_name_to_process_mapping.values()):
            enable_cli_logging(p, enable)
        return

    if isinstance(target, subprocess.Popen):
        if enable:
            _process_cli_logging_enabled.add(target)
        else:
            _process_cli_logging_enabled.discard(target)
        return

    uart = _tester_to_uart_mapping.get(target)
    if uart is None:
        return

    if enable:
        if target in _uart_logger_callbacks:
            return
        name = get_machine_name_from_tester(target)
        buffer = bytearray()

        def _on_char(char):
            try:
                value = int(char) & 0xFF
                # Drop NUL (0x00) and CR (0x0D):
                #   - NUL is occasionally emitted by UART drivers during init
                #     or as padding; it has no display meaning in a CLI line.
                #   - CR alone is half of a CRLF line ending; we treat LF as
                #     the sole line terminator (matching the default
                #     EndLineOption.TreatLineFeedAsEndLine of TerminalTester),
                #     so dropping CR keeps "foo\r\n" from leaving a stray CR
                #     at the end of the printed line.
                if value in (0x00, 0x0D):
                    return
                # LF (0x0A) is the line terminator: flush whatever has
                # accumulated in `buffer` as one tagged line.
                if value == 0x0A:
                    if buffer:
                        text = buffer.decode("utf-8", errors="replace")
                        del buffer[:]
                        print(f"{ANSI_WHITE}[{name}]:[CLI]: {text}{ANSI_RESET}", flush=True)
                    return
                buffer.append(value)
            except Exception:
                # Never propagate exceptions back into the emulation thread.
                pass

        _uart_logger_buffers[target] = buffer
        _uart_logger_callbacks[target] = _on_char
        uart.CharReceived += _on_char
    else:
        callback = _uart_logger_callbacks.pop(target, None)
        if callback is not None:
            uart.CharReceived -= callback
        _uart_logger_buffers.pop(target, None)

def enable_output_flushing(enable):
    """
    Enables or disables periodic output flushing for host processes.
    
    When enabled, wait_for() will periodically send empty lines to host processes
    to trigger output flushing. This is useful as a workaround for Docker 
    environments where output buffering can cause delays.

    Args:
        enable (bool): If True, enables periodic output flushing; otherwise, disables it.
    """
    global _output_flushing_enabled
    _output_flushing_enabled = enable

def log_radio_activity_as_error():
    """
    Enable logging radio activity as errors in the Renode simulation environment.
    """
    for name, machine in _machine_name_to_machine_mapping.items():
        machine.sysbus.radio.LogBasicRadioActivityAsError = True
    
def set_log_file(filename, log_level=DEFAULT_LOG_LEVEL, flush_every_write=False):
    """
    Enables logging to a file. It enables logging for all peripherals of all nodes at the specified log level.

    Args:
        filename (str): The name of the file where all activity will be logged.
        log_level (int, optional): The logging level to set. Defaults to DEFAULT_LOG_LEVEL (1).
        flush_every_write (bool, optional): Whether to flush the log file after every write operation.
                                            Defaults to False.
    """
    abs_path = os.path.abspath(filename)
    if os.path.exists(abs_path):
        os.remove(abs_path)
    flush_str = "true" if flush_every_write else "false"
    result = execute_monitor_command(f"logFile @{abs_path} {flush_str}")
    result = execute_monitor_command(f"logLevel {log_level}")

def enable_console_logging(log_level=DEFAULT_LOG_LEVEL):
    """
    Stream Renode logs to the same stdout the Python script is running on.

    pyrenode3 loads Renode as a library and does not start the UI, so the
    `ConsoleBackend` (which prints to Console.Out) is never registered by
    default. This helper registers it explicitly and sets a global log level.

    Args:
        log_level (int, optional): Global log level to apply. Defaults to
            DEFAULT_LOG_LEVEL.
    """
    assert isinstance(log_level, int), "log_level must be an int"
    from Antmicro.Renode.Logging import Logger, ConsoleBackend
    Logger.AddBackend(ConsoleBackend.Instance, "console", True)
    execute_monitor_command(f"logLevel {log_level}")

def start_monitor(port=1234):
    """
    Expose an interactive Renode Monitor over a TCP (telnet) socket while the
    pyrenode3 test is running, so you can pause and inspect the emulation.

    Connect from another terminal with, for example:
        telnet 127.0.0.1 <port>      (or: nc 127.0.0.1 <port>)

    Handy commands once connected (the monitor runs on its own thread, so these
    work even while the Python side is blocked in a wait_for):
        pause                         # stop the emulation
        start                         # resume the emulation
        machine                       # list machines
        machine ElapsedVirtualTime    # get the current virtual time
        mach set "node1"              # select a machine
        sysbus.cpu PC                 # read the program counter
        sysbus.cpu IsHalted           # is the core halted?
        sysbus.cpu LogFunctionNames true
        peripherals                   # tree of peripherals
        help

    Args:
        port (int, optional): TCP port the monitor listens on. Defaults to 1234.

    Returns:
        The AntShell Shell instance backing the interactive monitor.
    """
    assert isinstance(port, int), "port must be an int"

    from Antmicro.Renode.Utilities import SocketIOSource
    from AntShell.Terminal import IOProvider, NavigableTerminalEmulator
    from AntShell import Prompt
    from Antmicro.Renode.UserInterface import ShellProvider
    from System import ConsoleColor

    monitor = _m.internal
    socket_source = SocketIOSource(port)
    io = IOProvider()
    io.Backend = socket_source

    shell = ShellProvider.GenerateShell(monitor)
    shell.Terminal = NavigableTerminalEmulator(io, socket_source)
    monitor.Interaction = shell.Writer
    try:
        monitor.MachineChanged += lambda emu: shell.SetPrompt(
            Prompt(f"({emu}) ", ConsoleColor.DarkYellow) if emu is not None else None)
    except Exception:
        pass

    threading.Thread(target=lambda: shell.Start(False), daemon=True).start()
    print(f"[MONITOR]: interactive monitor listening on port {port} "
          f"-- connect with: telnet 127.0.0.1 {port}", flush=True)
    return shell

def set_log_level(peripheral, log_level, node=None):
    """
    Sets the logging level for a specific peripheral of a node.

    Args:
        peripheral (str): The peripheral name to set the logging level for.
        log_level (int): The logging level to set.
        node (optional): A tester object returned by `create_node`. When
            provided the level is applied only to that node's peripheral.
            When omitted (or None), the level is applied to the current machine.
    """
    if node is not None:
        machine_name = get_machine_name_from_tester(node)
        execute_monitor_command(f"mach set \"{machine_name}\"")    
    execute_monitor_command(f"logLevel {log_level} {peripheral}")

def fail(message):
    """
    Fails the current test with an error message.

    Args:
        message (str): The error message to display.

    Raises:
        RuntimeError: If the test fails.
    """
    raise RuntimeError(f"Test failed: {message}")

def test_assert(condition, message):
    """
    Asserts a condition is true.
    """
    if not condition:
        fail(message)

def emulation():
    """
    Returns the current emulation environment.
    """
    return _e

def monitor():
    """
    Returns the current monitor instance.
    """
    return _m

def renode_base_path():
    """
    Returns the base path to the Renode repository as set by the RENODE_BASE_PATH environment variable.
    """
    return RENODE_BASE_PATH

def execute_monitor_command(command):
    """
    Executes a command on the monitor.

    Args:
        command (str): The command to execute on the monitor.

    Returns:
        str: The output of the command.

    Raises:
        RuntimeError: If the command fails.
    """
    output, err = _m.execute(command)
    if err:
        fail(f"Renode command '{command}' failed: {err}")
    return output

def read_byte(address):
    """
    Reads a byte from a given address in the system bus.
    """
    assert isinstance(address, int), "address must be int"
    return int(execute_monitor_command(f"sysbus ReadByte {address:#x}").strip(), 0)

def write_byte(address, value):
    """
    Writes a byte to a given address in the system bus.
    """
    assert isinstance(address, int), "address must be int"
    assert isinstance(value, int), "value must be int"
    execute_monitor_command(f"sysbus WriteByte {address:#x} {value:#x}")

def read_doubleword(address):
    """
    Reads a doubleword from a given address in the system bus.
    """
    assert isinstance(address, int), "address must be int"
    return int(execute_monitor_command(f"sysbus ReadDoubleWord {address:#x}").strip(), 0)

def write_doubleword(address, value):
    """
    Writes a doubleword to a given address in the system bus.
    """
    assert isinstance(address, int), "address must be int"
    assert isinstance(value, int), "value must be int"
    execute_monitor_command(f"sysbus WriteDoubleWord {address:#x} {value:#x}")

def read_register(peripheral, offset):
    """
    Reads a register from a given peripheral of a node.
    """
    assert isinstance(offset, int), "offset must be int"
    return int(execute_monitor_command(f"sysbus.{peripheral} ReadDoubleWord {offset}").strip(), 0)

def write_register(peripheral, offset, value):
    """
    Writes a register to a given peripheral of a node.
    """
    assert isinstance(offset, int), "offset must be int"
    assert isinstance(value, int), "value must be int"
    execute_monitor_command(f"sysbus.{peripheral} WriteDoubleWord {offset} {value}")

def add_function_trace(tester, targets, callback=None, num_args=4, cpu="cpu"):
    """
    Install CPU execution hooks that fire whenever the core reaches a given
    function/address, and dispatch each hit to a (pluggable) callback.

    This is a general-purpose tracing helper: point it at one or more symbols
    or raw addresses and get a callback every time execution passes through
    them. The default callback (example_trace_hook) prints a one-line trace
    including the function's first num_args integer arguments via debug_print;
    pass your own callback to inspect registers/memory, accumulate stats,
    write a log, etc.

    Args:
        tester: The TerminalTester returned by create_node, identifying the
            machine to hook.
        targets: What to hook. Accepts any of:
            - A dict mapping target -> label:
              {"my_func": "MY_FUNC", 0x2000abcd: "raw_addr"}
            - A list/tuple/set of targets: ["func1", "func2", 0x2000abcd]
            - A single target: "func1" or 0x2000abcd
            Each target is either:
            - a str symbol name, resolved to one or more addresses by reading
              the ELF's symbol table directly (falling back to Renode's
              in-memory lookup); a symbol may expand to several addresses, or
            - an int raw address, used as-is.
            When a label is not provided (list/single forms), it defaults to
            the symbol name or hex(address).
        callback (callable, optional): Called as callback(ctx) on every hook
            hit, where ctx is a dict (see _function_trace_hook for fields).
            Defaults to example_trace_hook, which prints the call with its
            arguments. Exceptions raised by the callback are caught and logged
            via debug_print so a faulty hook never crashes emulation.
        num_args (int, optional): Number of integer arguments the default/example
            callback should print, exposed to any callback via ctx["num_args"].
            Set this to the traced function's arity (extra slots would show
            stale register contents). For functions with different arities,
            make separate calls. Defaults to 4.
        cpu (str, optional): Name of the CPU to hook on (e.g. "cpu", "secpu").
            Defaults to "cpu".

    Examples:
        # Trace two functions; default hook prints up to 4 args each
        add_function_trace(tester, ["sl_foo", "sl_bar"])

        # A 2-argument function: print exactly its two args
        add_function_trace(tester, "sli_mac_lower_mac_send", num_args=2)

        # Trace with explicit labels and a custom hook (see example_trace_hook)
        add_function_trace(
            tester,
            {"GENERIC_PHY_CanModifyAck": "CanModifyAck"},
            callback=example_trace_hook,
        )

        # Trace a raw address on a secondary CPU
        add_function_trace(tester, {0x2000abcd: "isr"}, cpu="secpu")
    """
    assert isinstance(cpu, str), "cpu must be a str"
    assert isinstance(num_args, int) and num_args >= 0, "num_args must be a non-negative int"
    assert callback is None or callable(callback), "callback must be callable"

    if callback is None:
        callback = example_trace_hook

    # Normalize targets into a {target: label} dict.
    if isinstance(targets, dict):
        target_labels = dict(targets)
    elif isinstance(targets, (list, tuple, set, frozenset)):
        target_labels = {t: None for t in targets}
    else:
        target_labels = {targets: None}

    machine = _tester_to_machine_mapping[tester]
    machine_name = get_machine_name_from_tester(tester)
    mach_net = machine.internal
    bus = machine.sysbus.internal
    cpu_obj = getattr(machine.sysbus, cpu)
    cpu_net = cpu_obj.internal

    # Resolve symbol-name targets from the ELF file directly. Renode's in-memory
    # by-name symbol lookup can drop nested/overlapping symbols when the same ELF
    # is loaded more than once (the reset macro re-runs "sysbus LoadSymbolsFrom"),
    # so reading the ELF's .symtab is the reliable source. Falls back to the bus
    # lookup when the ELF path is unknown or the symbol isn't in the ELF.
    symbol_names = [t for t in target_labels if isinstance(t, str)]
    elf_path = _machine_name_to_elf_mapping.get(machine_name)
    elf_symbols = _resolve_symbols_from_elf(elf_path, symbol_names) if (elf_path and symbol_names) else {}

    for target, label in target_labels.items():
        if isinstance(target, int):
            addresses = [target]
            resolved_label = label if label is not None else hex(target)
        elif isinstance(target, str):
            addresses = list(elf_symbols.get(target, []))
            if not addresses:
                found, addresses_enum = bus.TryGetAllSymbolAddresses(target, context=cpu_net)
                addresses = [int(a) for a in addresses_enum] if (found and addresses_enum) else []
            if not addresses:
                debug_print(f"Warning: Symbol '{target}' not found, skipping trace")
                continue
            resolved_label = label if label is not None else target
        else:
            debug_print(f"Warning: trace target should be str or int, got {type(target)}")
            continue

        for addr in addresses:
            # The hook is invoked with (cpu, address) positional args, so swallow
            # them with *_a and keep everything else as keyword-only defaults;
            # otherwise the address would clobber the first non-* parameter.
            hook_action = CpuAddressHook(
                lambda *_a, n=machine_name, cn=cpu, l=resolved_label, a=addr, m=mach_net, cb=callback, na=num_args:
                    _function_trace_hook(n, cn, l, a, m, cb, na)
            )
            cpu_obj.AddHook(addr, hook_action)
            debug_print(f"Added trace '{resolved_label}' at {addr:#x} on {cpu} of {machine_name}")

def example_trace_hook(ctx):
    """
    Example custom trace callback for use with add_function_trace.

    This is also the default callback used by add_function_trace when none is
    supplied. It demonstrates how a hook can read the integer arguments passed
    to the traced function through the ctx["arg"] helper and print them, instead
    of just logging the bare event. ctx["arg"](n) returns the n-th integer
    argument (0-based) following the core's calling convention (ARM r0-r3,
    RISC-V a0-a7), so this works whether the hooked function takes ints,
    pointers, or handles. The number of arguments printed comes from
    ctx["num_args"] (the add_function_trace num_args parameter); slots beyond
    the function's real arity will simply show stale register contents.

    It also prints the call site (ctx["call_addr"]) annotated with the caller's
    symbol via ctx["symbol"], collapsing GCC optimization clones (.constprop,
    .isra, ...) to their base name.

    The ctx dict provides:
        machine (str), cpu (str), label (str), address (int),
        num_args (int): number of integer arguments to print,
        call_addr (int): caller's return address (ARM LR / RISC-V RA),
        t_us (float): virtual time in microseconds (or -1 if unavailable),
        read (callable): read(addr) -> int, reads a doubleword from the bus,
        reg (callable): reg(index) -> int, reads a raw CPU register,
        arg (callable): arg(n) -> int, reads the n-th integer argument,
        symbol (callable): symbol(addr) -> str, address to symbol name or None.

    Usage:
        # arity comes from num_args (defaults to 4)
        add_function_trace(tester, {"my_func": "MY_FUNC"}, num_args=2,
                           callback=example_trace_hook)
    """
    parts = []
    for n in range(ctx["num_args"]):
        try:
            parts.append(f"{ctx['arg'](n):#x}")
        except Exception as e:
            parts.append(f"<err:{e}>")
    args_str = ", ".join(parts)

    # Annotate the call address with the caller's symbol when resolvable.
    caller = ctx["symbol"](ctx["call_addr"]) if ctx["call_addr"] >= 0 else None
    if caller:
        # Collapse GCC optimization clones to the base name, keeping any
        # +offset suffix (e.g. "send_frame.constprop.0+0x2e" -> "send_frame+0x2e").
        # In C the only dots in a symbol come from these compiler decorations.
        name, sep, off = caller.partition("+")
        caller = name.split(".", 1)[0] + sep + off
    caller_str = f" ({caller})" if caller else ""

    # Prints e.g.:
    #   [TRACE] node1.cpu sl_foo(0x1, 0x2000abcd, 0x0, 0xA) @ 0x1041804 from 0x1040f72 (sl_bar+0x2e) t=1523.400us
    debug_print(f"[TRACE] {ctx['machine']}.{ctx['cpu']} "
                f"{ctx['label']}({args_str}) @ {ctx['address']:#x} "
                f"from {ctx['call_addr']:#x}{caller_str} t={ctx['t_us']:.3f}us")


def mark_test_runtime():
    """Check the virtual and real test runtime for performance benchmarking."""
    time_output = execute_monitor_command("machine ElapsedVirtualTime")
    debug_print(_format_elapsed_time_output(time_output))


########################################################################
# Internals
########################################################################

# Command-line argument storage
_cli_rng_seed = None
_cli_log_file = None

# Internal mappings
_machine_name_to_machine_mapping = {}
_machine_name_to_elf_mapping = {}
_tester_to_machine_mapping = {}
_process_name_to_process_mapping = {}

def _resolve_symbols_from_elf(elf_path, names):
    """
    Resolve symbol names to addresses by reading the ELF's .symtab directly.

    This bypasses Renode's in-memory symbol lookup, whose by-name map can drop
    nested/overlapping symbols when the same ELF is loaded more than once (e.g.
    when the reset macro re-runs "sysbus LoadSymbolsFrom"). Reading the ELF on
    disk always sees every defined symbol.

    Returns a dict mapping each requested name to a list of addresses (empty if
    the symbol is absent or the ELF can't be read).
    """
    result = {name: [] for name in names}
    if not names:
        return result
    try:
        from ELFSharp.ELF import ELFReader
        from ELFSharp.ELF.Sections import ISymbolTable
    except Exception as e:
        debug_print(f"Warning: ELFSharp unavailable for ELF symbol resolution: {e}")
        return result

    wanted = set(names)
    elf = None
    try:
        elf = ELFReader.Load(elf_path)
        # GetSections[ISymbolTable]() yields .symtab (and .dynsym if present)
        # typed so that .Entries is accessible. ISymbolEntry doesn't expose the
        # address (st_value); only the concrete SymbolEntry<T> does, so read it
        # reflectively to stay agnostic to 32- vs 64-bit ELF width.
        for symtab in elf.GetSections[ISymbolTable]():
            for entry in symtab.Entries:
                name = entry.Name
                if name not in wanted:
                    continue
                # Skip undefined symbols (SpecialSectionIndex.Undefined == 0).
                if int(entry.PointedSectionIndex) == 0:
                    continue
                value_prop = entry.GetType().GetProperty("Value")
                if value_prop is None:
                    continue
                # Clear the ARM Thumb bit if the toolchain set it on st_value.
                addr = int(value_prop.GetValue(entry)) & ~1
                if addr != 0 and addr not in result[name]:
                    result[name].append(addr)
    except Exception as e:
        debug_print(f"Warning: failed to read symbols from {elf_path}: {e}")
    finally:
        if elf is not None:
            try:
                elf.Dispose()
            except Exception:
                pass
    return result

def _function_trace_hook(machine_name, cpu, label, address, mach_net, callback, num_args=0):
    """
    Dispatcher invoked by every CpuAddressHook installed by
    add_function_trace. Builds the trace context and forwards it to the
    user callback, catching and logging (via debug_print) any exception so
    a faulty hook never crashes the emulation.

    The context dict passed to the callback provides:
        machine (str), cpu (str), label (str), address (int),
        num_args (int): the num_args value passed to add_function_trace,
        call_addr (int): the caller's return address from the link register
            (ARM LR / RISC-V RA), Thumb bit cleared, or -1 if unavailable,
        t_us (float): virtual time in microseconds (-1 if unavailable),
        read (callable): read(addr) -> int, reads a doubleword from the bus,
        reg (callable): reg(index) -> int, reads a raw CPU register by index,
        arg (callable): arg(n) -> int, reads the n-th integer function
            argument (0-based) following the core's calling convention
            (ARM AAPCS r0-r3, or RISC-V a0-a7),
        symbol (callable): symbol(addr) -> str, reverse-resolves an address to
            its containing symbol (e.g. "sl_foo" or "sl_foo+0x2e"), or None.
    """
    try:
        t_us = mach_net.ElapsedVirtualTime.TimeElapsed.TotalMicroseconds
    except Exception:
        t_us = -1

    cpu_wrapper = getattr(_machine_name_to_machine_mapping[machine_name].sysbus, cpu)
    # ARM cores expose LR; RISC-V cores expose RA. On ARM the first integer
    # arguments live in r0-r3 (register index 0) and the return address in LR
    # (r14, index 14); on RISC-V the args live in a0-a7 (== x10-x17, index 10)
    # and the return address in RA (x1, index 1).
    is_arm = hasattr(cpu_wrapper, "LR")
    arg_base = 0 if is_arm else 10
    link_index = 14 if is_arm else 1

    def read(addr):
        return int(mach_net.SystemBus.ReadDoubleWord(addr))

    def reg(index):
        return int(cpu_wrapper.GetRegister(index).RawValue)

    def arg(n):
        return int(cpu_wrapper.GetRegister(arg_base + n).RawValue)

    # Reverse address->symbol lookup. This uses Renode's by-address interval
    # map (not the by-name map worked around elsewhere), so it stays reliable.
    bus_net = mach_net.SystemBus
    cpu_net = cpu_wrapper.internal

    def symbol(addr):
        try:
            return bus_net.FindSymbolAt(addr, cpu_net)
        except Exception:
            return None

    # The hook fires at function entry, so the link register holds the address
    # to return to in the caller (clear the ARM Thumb bit for a plain address).
    try:
        call_addr = reg(link_index) & ~1
    except Exception:
        call_addr = -1

    ctx = {
        "machine": machine_name,
        "cpu": cpu,
        "label": label,
        "address": address,
        "num_args": num_args,
        "call_addr": call_addr,
        "t_us": t_us,
        "read": read,
        "reg": reg,
        "arg": arg,
        "symbol": symbol,
    }
    try:
        callback(ctx)
    except Exception as e:
        # Don't let a faulty hook crash emulation, but surface the error so
        # silent failures (e.g. a typo in a user callback) are diagnosable.
        debug_print(f"Warning: trace callback for '{label}' raised: {e!r}")

# CLI logging - per-tester subscriptions to the underlying UART CharReceived
# event and per-process opt-in for stdout/stderr. Used by enable_cli_logging()
# to print all CLI output, not just the matching line.
_tester_to_uart_mapping = {}
_uart_logger_callbacks = {}
_uart_logger_buffers = {}
_process_cli_logging_enabled = set()
_cli_logging_enabled = DEFAULT_CLI_LOGGING_ENABLED

# Output flushing control
_output_flushing_enabled = False

# Cleanup control
_cleanup_in_progress = False

# Process output management - threading infrastructure
_process_output_threads = {}  # process -> stdout thread
_process_stdout_buffers = {}  # process -> stdout buffer
_process_stderr_threads = {}  # process -> stderr thread
_process_stderr_buffers = {}  # process -> stderr buffer
_process_pty_masters = {}  # process -> master PTY fd (host interactive CLIs)
_process_reader_lock = threading.Lock()

# External control server management
_next_external_control_port = BASE_EXTERNAL_CONTROL_PORT + 1
_process_to_server_port = {}  # process -> port number
_active_servers = set()  # set of active server names

# Binary download management
_url_cache = {}  # url -> {"path": file_path, "processes": set_of_processes}

def _add_stubs(machine, function_stubs, elf_file=None, cpu="cpu"):
    """
    Add function stubs to a machine with configurable return values.
    
    Args:
        machine: The machine object to add stubs to.
        function_stubs: Can be any of these formats:
            - A list of function names: ["func1", "func2"] 
              (uses DEFAULT_STUB_RETURN_VALUE for all)
            - A dict mapping function names to return values: 
              {"func1": 0x42, "func2": 0x100, "func3": None}
            - A dict with detailed config per function:
              {"func1": {"return_value": 0x42}, "func2": {"return_value": 0x100}}
        elf_file (str, optional): Path to the ELF used to resolve symbol names
            directly (robust against Renode's by-name lookup dropping symbols
            after the ELF is loaded more than once). Falls back to the bus
            lookup when not provided or a symbol isn't in the ELF.
        cpu (str, optional): Name of the CPU to hook stubs on (e.g. "cpu", "secpu").
            Defaults to "cpu".
    
    Global Configuration:
        DEFAULT_STUB_RETURN_VALUE: Used when:
            - function_stubs is a list
            - a dict entry has None value  
            - a dict entry doesn't specify "return_value"
            Current value: 0 (can be modified globally)
    
    Examples:
        # Simple list - all functions return DEFAULT_STUB_RETURN_VALUE
        _add_stubs(machine, ["func1", "func2"])
        
        # To change global default for all subsequent calls:
        # DEFAULT_STUB_RETURN_VALUE = 0xFF
        
        # Dict with individual return values
        _add_stubs(machine, {"get_id": 0x1234, "check_status": 1, "init": 0})
        
        # Dict with detailed config (future-extensible)
        _add_stubs(machine, {
            "get_id": {"return_value": 0x1234}, 
            "init": {"return_value": 0}
        })
        
        # Mixed - some with values, some using global default
        _add_stubs(machine, {"special_func": 0x42, "normal_func": None})
        
        # Target a specific CPU
        _add_stubs(machine, {"se_func": 0xaaaa5555}, cpu="secpu")
    """
    if function_stubs is not None:
        # Handle different input formats
        if isinstance(function_stubs, list):
            # Convert list to dict with default return values
            stubs_dict = {func_name: DEFAULT_STUB_RETURN_VALUE for func_name in function_stubs}
        elif isinstance(function_stubs, dict):
            # Process dict entries to extract return values
            stubs_dict = {}
            for func_name, config in function_stubs.items():
                if config is None:
                    # None means use global default
                    ret_value = DEFAULT_STUB_RETURN_VALUE
                elif isinstance(config, dict):
                    # Detailed config: {"return_value": 0x42}
                    ret_value = config.get("return_value", DEFAULT_STUB_RETURN_VALUE)
                else:
                    # Direct value: "func": 0x42
                    ret_value = config
                stubs_dict[func_name] = ret_value
        else:
            debug_print(f"Warning: function_stubs should be list or dict, got {type(function_stubs)}")
            return

        bus = machine.sysbus.internal
        cpu_obj = getattr(machine.sysbus, cpu)
        cpu_net = cpu_obj.internal

        elf_symbols = _resolve_symbols_from_elf(elf_file, list(stubs_dict.keys())) if elf_file else {}

        for symbol, ret_value in stubs_dict.items():
            addresses = list(elf_symbols.get(symbol, []))
            if not addresses:
                found, addresses_enum = bus.TryGetAllSymbolAddresses(symbol, context=cpu_net)
                addresses = [int(a) for a in addresses_enum] if (found and addresses_enum) else []

            if addresses:
                for addr in addresses:
                    hook_action = CpuAddressHook(
                        lambda cpu, addr=addr, rv=ret_value: _skip_function_hook_with_return(cpu, addr, rv)
                    )
                    cpu_obj.AddHook(addr, hook_action)
                    debug_print(f"Added stub for '{symbol}' at 0x{addr:x} on {cpu} with return value {ret_value}")
            else:
                debug_print(f"Warning: Symbol '{symbol}' not found, skipping stub")

def _machine_name_from_cpu(cpu):
    name = str(cpu).split(": ")[1]
    name = name.split(".")[0]
    return name

def _cpu_name_from_cpu(cpu):
    # str(cpu) returns e.g. "[CPU: node1.secpu[2]]"
    parts = str(cpu).split(": ")[1]
    name = parts.split(".")[1]
    # Strip trailing bracket/index like "secpu[2]]" -> "secpu"
    bracket = name.find("[")
    if bracket != -1:
        name = name[:bracket]
    return name

def _skip_function_hook_with_return(cpu, addr, return_value):
    try:
        cpu_name = _cpu_name_from_cpu(cpu)
        cpu_wrapper = getattr(getattr(_e, _machine_name_from_cpu(cpu)).sysbus, cpu_name)
        reg_value = RegisterValue.Create(return_value, 32)

        if hasattr(cpu_wrapper, 'LR'):
            cpu_wrapper.SetRegister(0, reg_value)
            cpu_wrapper.PC = cpu_wrapper.LR
        else:
            cpu_wrapper.SetRegister(10, reg_value)
            cpu_wrapper.PC = cpu_wrapper.RA
    except Exception as e:
        print("Warning: Could not stub function at 0x{:x} with return value {}. Error: {}".format(addr, return_value, str(e)))

def _add_reset_macro(machine_name, elf_file):
    """
    Adds a reset macro for a specified machine.

    This function generates a reset macro that loads an ELF file into the system bus
    and sets the CPU vector table offset to the "__Vectors" symbol address from the
    loaded ELF file. The macro is added (but not executed) on the specified machine.

    Args:
        machine_name (str): The name of the machine to add the reset macro on.
        elf_file (str): The path to the ELF file to be loaded.

    Returns:
        None

    Note:
        This function relies on the global `_m` object to execute machine commands.
        The ELF file must contain a "__Vectors" symbol for proper vector table setup.
    """
    macro_reset_string = f"""macro reset
    \"\"\"
        sysbus LoadSymbolsFrom @{elf_file}
        cpu VectorTableOffset `sysbus GetSymbolAddress "__Vectors"`
    \"\"\"
    """
    execute_monitor_command(f"mach set \"{machine_name}\"")
    execute_monitor_command(f"{macro_reset_string}")

def _start_process_reader(process):
    """
    Starts reader threads for a process's stdout and stderr streams.
    
    Args:
        process: The subprocess.Popen object to start readers for
    """
    with _process_reader_lock:
        if process not in _process_output_threads:
            # Initialize the output buffer queues
            _process_stdout_buffers[process] = queue.Queue()
            _process_stderr_buffers[process] = queue.Queue()
            
            # Start reader thread for stdout
            if process.stdout:
                stdout_thread = threading.Thread(
                    target=_process_stream_reader,
                    args=(process, process.stdout, _process_stdout_buffers, "stdout"),
                    daemon=True
                )
                stdout_thread.start()
                _process_output_threads[process] = stdout_thread
            else:
                debug_print(f"Warning: No stdout available for process {process.pid}")
            
            # Start reader thread for stderr
            if process.stderr:
                stderr_thread = threading.Thread(
                    target=_process_stream_reader,
                    args=(process, process.stderr, _process_stderr_buffers, "stderr"),
                    daemon=True
                )
                stderr_thread.start()
                _process_stderr_threads[process] = stderr_thread
            else:
                debug_print(f"Warning: No stderr available for process {process.pid}")

def _cleanup_process_reader(process):
    """
    Cleans up the reader threads and buffers for a terminated process.

    Args:
        process: The subprocess.Popen object to clean up
    """
    with _process_reader_lock:
        # Clean up stdout thread
        if process in _process_output_threads:
            thread = _process_output_threads[process]
            thread.join(timeout=1.0)  # Wait up to 1 second
            del _process_output_threads[process]
        
        # Clean up stderr thread
        if process in _process_stderr_threads:
            thread = _process_stderr_threads[process]
            thread.join(timeout=1.0)  # Wait up to 1 second
            del _process_stderr_threads[process]
            
        # Clean up stdout buffer
        if process in _process_stdout_buffers:
            del _process_stdout_buffers[process]
        
        # Clean up stderr buffer
        if process in _process_stderr_buffers:
            del _process_stderr_buffers[process]

        master_fd = _process_pty_masters.pop(process, None)
        if master_fd is not None:
            try:
                os.close(master_fd)
            except OSError:
                pass

        # Drop CLI logging opt-in for this process
        _process_cli_logging_enabled.discard(process)

def _process_stream_reader(process, stream, buffer_dict, stream_name):
    """
    Thread function that continuously reads from a process stream and buffers output.
    
    Args:
        process: The subprocess.Popen object
        stream: The stream to read from (process.stdout or process.stderr)
        buffer_dict: The buffer dictionary to put data into (_process_stdout_buffers or _process_stderr_buffers)
        stream_name: Name of the stream for debugging ("stdout" or "stderr")
    """
    # Drain in large chunks (one read() syscall per chunk) and split into lines
    # locally. The stream is an unbuffered raw fd, so read(n) returns whatever is
    # currently available (>= 1 byte) without waiting to fill n, keeping latency
    # low while avoiding the byte-at-a-time cost of readline() on a raw stream.
    # Consumers (wait_for/assert_not_received) expect one logical line per queue
    # item, so complete lines are emitted individually and any trailing partial
    # line is held in `pending` until the next chunk (or EOF).
    pending = b""

    def _emit_line(text):
        if not text:
            return
        with _process_reader_lock:
            if not _cleanup_in_progress and text.strip():  # Skip empty/whitespace-only prints
                if process in _process_cli_logging_enabled:
                    process_name = get_process_name_from_process(process)
                    print(f"{ANSI_WHITE}[{process_name}]:[CLI]: {text.rstrip()}{ANSI_RESET}", flush=True)
            if process in buffer_dict:
                buffer_dict[process].put(text)

    try:
        while True:
            try:
                chunk = stream.read(65536)
            except (OSError, ValueError) as e:
                debug_print(f"Process {process.pid} {stream_name} reader error: {e}")
                break

            # EOF: the slave side of the PTY is fully closed (process exited).
            if not chunk:
                break

            if isinstance(chunk, str):
                chunk = chunk.encode("utf-8", errors="replace")
            pending += chunk

            # Peel off complete lines; keep any trailing partial line buffered.
            *lines, pending = pending.split(b"\n")
            for raw_line in lines:
                _emit_line(raw_line.decode("utf-8", errors="replace") + "\n")

        # Flush any trailing partial line (e.g. a prompt printed without a newline).
        if pending:
            _emit_line(pending.decode("utf-8", errors="replace"))

    except Exception as e:
        debug_print(f"Process {process.pid} {stream_name} reader thread crashed: {e}")

def _resolve_elf_path(elf_file):
    """
    Resolve an ELF reference to a local filesystem path.

    Renode can load an ELF directly from an http(s) URL, but the ELF-direct
    symbol resolution (_resolve_symbols_from_elf, via ELFSharp) and the reset
    macro's "sysbus LoadSymbolsFrom" need a real file on disk. When elf_file is
    a URL it is downloaded (and cached per-URL) and the local path is returned;
    otherwise elf_file is returned unchanged.

    Args:
        elf_file (str): A local path or an http(s) URL to an ELF file.

    Returns:
        str: A local filesystem path to the ELF file.
    """
    assert isinstance(elf_file, str), "elf_file must be a str"
    if elf_file.startswith(("http://", "https://")):
        return _download_binary_from_url(elf_file)
    return elf_file

def _download_binary_from_url(url):
    """
    Downloads a binary from a URL to a temporary file and makes it executable.
    Caches downloads to avoid downloading the same URL multiple times.
    Tracks which processes are using each cached file for proper cleanup.
    
    Args:
        url (str): The URL to download the binary from.
        
    Returns:
        str: Path to the downloaded temporary file.
        
    Raises:
        Exception: If the download fails.
    """
    global _url_cache
    
    # Check if we've already downloaded this URL
    if url in _url_cache:
        cached_info = _url_cache[url]
        cached_path = cached_info["path"]
        # Verify the cached file still exists
        if os.path.exists(cached_path):
            debug_print(f"Using cached binary from URL: {url} -> {cached_path}")
            return cached_path
        else:
            # Cached file was deleted, remove from cache
            debug_print(f"Cached binary no longer exists, re-downloading: {url}")
            del _url_cache[url]
    
    try:
        debug_print(f"Downloading binary from URL: {url}")
        
        # Extract filename from URL for better temp file naming
        url_parts = url.split('/')
        original_filename = url_parts[-1] if url_parts else "binary"
        
        # Create a temporary file with a meaningful prefix
        with tempfile.NamedTemporaryFile(delete=False, prefix=f"renode_{original_filename}_", suffix="") as temp_file:
            temp_path = temp_file.name
            
        # Download the file
        urllib.request.urlretrieve(url, temp_path)
        
        # Make the file executable
        current_permissions = os.stat(temp_path).st_mode
        os.chmod(temp_path, current_permissions | stat.S_IEXEC)
        
        # Cache the download with process tracking
        _url_cache[url] = {
            "path": temp_path,
            "processes": set()  # Will be populated when processes use this binary
        }
        
        debug_print(f"Binary downloaded and cached: {url} -> {temp_path}")
        return temp_path
        
    except urllib.error.URLError as e:
        fail(f"Failed to download binary from URL '{url}': Network error - {e}")
    except OSError as e:
        fail(f"Failed to download binary from URL '{url}': File system error - {e}")
    except Exception as e:
        fail(f"Failed to download binary from URL '{url}': {e}")

def _find_url_for_process(process):
    """
    Find the URL associated with a downloaded binary process by searching the URL cache.
    
    Args:
        process: The subprocess.Popen object to find URL for.
        
    Returns:
        tuple: (url, file_path) if found, (None, None) if not found.
    """
    for url, cached_info in _url_cache.items():
        if process in cached_info["processes"]:
            return url, cached_info["path"]
    return None, None

def _create_external_control_server_for_process(process_name):
    """
    Creates a dedicated external control server for a host process.
    Each server can only handle one connection, so each process needs its own server.
    
    Args:
        process_name (str): Name of the process that will use this server.
        
    Returns:
        int: Port number of the created server.
    """
    global _next_external_control_port, _active_servers
    
    port = _next_external_control_port
    _next_external_control_port += 1
    
    server_name = f"ext_ctrl_server_{process_name}_{port}"
    
    try:
        execute_monitor_command(f"emulation CreateExternalControlServer \"{server_name}\" {port}")
        _active_servers.add(server_name)
        debug_print(f"Created external control server '{server_name}' on port {port} for process '{process_name}'")
        return port
    except Exception as e:
        debug_print(f"Failed to create external control server for process '{process_name}': {e}")
        raise

def _format_elapsed_time_output(time_output):
    """Extract elapsed virtual/host time and cumulative load from Renode output."""
    fields = (
        "Elapsed Virtual Time:",
        "Elapsed Host Time:",
        "Cumulative load:",
    )
    lines = [""]
    for field in fields:
        for line in time_output.splitlines():
            if field not in line:
                continue
            cleaned = line.strip()
            if cleaned.startswith("[Domain = "):
                cleaned = cleaned[len("[Domain = "):]
            if cleaned.endswith("]"):
                cleaned = cleaned[:-1]
            lines.append(cleaned)
            break
    return "\n".join(lines)

def _cleanup_all_processes():
    """
    Cleanup function called at program exit to ensure proper teardown order.
    Terminates all tracked processes before the Python interpreter shuts down.
    This prevents host processes from trying to access Renode connections during teardown.
    """
    global _url_cache, _cleanup_in_progress
    
    # Set flag to suppress debug output from reader threads during cleanup
    _cleanup_in_progress = True
    
    process_names = list(_process_name_to_process_mapping.keys())  # Create a copy of the keys
    if process_names:
        debug_print(f"Cleaning up {len(process_names)} host processes at exit...")
        
        # First pass: Send SIGTERM and close stdin for graceful shutdown
        for process_name in process_names:
            try:
                process = _process_name_to_process_mapping[process_name]
                debug_print(f"Gracefully terminating host process: {process_name}")
                
                # Close stdin first to signal shutdown
                if process.stdin and not process.stdin.closed:
                    try:
                        process.stdin.close()
                    except (BrokenPipeError, OSError):
                        pass
                
                # Send SIGTERM for graceful shutdown
                process.terminate()
                
            except Exception as e:
                debug_print(f"Warning: Failed to gracefully terminate process '{process_name}': {e}")
        
        # Wait briefly for graceful shutdown
        time.sleep(0.2)
        
        # Second pass: Use SIGKILL for any remaining processes  
        remaining_processes = []
        for process_name in process_names:
            if process_name in _process_name_to_process_mapping:
                process = _process_name_to_process_mapping[process_name]
                if process.poll() is None:  # Still running
                    remaining_processes.append(process_name)
        
        if remaining_processes:
            debug_print(f"Force-killing {len(remaining_processes)} remaining processes...")
        
        for process_name in remaining_processes:
            try:
                debug_print(f"Force-killing host process: {process_name}")
                terminate_process(process_name)
            except Exception as e:
                debug_print(f"Warning: Failed to force-kill process '{process_name}': {e}")
    
    # Clean up cached downloaded files
    for url, cached_info in _url_cache.items():
        cached_path = cached_info["path"]
        try:
            if os.path.exists(cached_path):
                os.unlink(cached_path)
        except OSError as e:
            debug_print(f"Warning: Failed to remove cached binary {cached_path}: {e}")
    _url_cache.clear()

# Register cleanup function to run at program exit
atexit.register(_cleanup_all_processes)