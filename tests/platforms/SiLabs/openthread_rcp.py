import os

import test_lib
from common import openthread_lib

################################################
# Globals
################################################

QUANTUM_TIME = 0.000050
DEBUG = True

################################################
# Utility functions
################################################

def wait_for_boot(node):
    test_lib.wait_for(node, "RCP version: SL-OPENTHREAD/")
    # ot-cli prints "> " with no trailing newline, so test_lib's readline()-based
    # wait_for cannot observe the prompt. Probe readiness with a command that
    # produces a newline-terminated "Done" instead.
    test_lib.write_line(node, "version")
    test_lib.wait_for(node, "Done")

def parse_arguments():
    boards, uarts, elfs = test_lib.parse_arguments()
    rcp_board = boards[0]
    rcp_uart = uarts[0]
    rcp_elf = elfs[0]
    host_binary = elfs[1]
    return rcp_board, rcp_uart, rcp_elf, host_binary

def create_node(name, board, rcp_elf, rcp_uart, node_id, port_offset, host_binary):
    """Emulate an RCP and launch its OpenThread host in Renode virtual-time mode.

    The host (built with OPENTHREAD_POSIX_VIRTUAL_TIME) advances its clock as a Renode
    time sink over the virtual-time socket instead of the LD_PRELOAD time shim, so simulation 
    time cannot leak while the host does real work. The /dev/null radio URL only satisfies
    HdlcInterface::Init; all spinel traffic is bridged over the virtual-time socket by the
    coordinator. forkpty-arg carries the node id; PORT_OFFSET keeps each host's sockets
    from colliding.
    """
    rcp = test_lib.create_node(name, board, rcp_elf, rcp_uart)
    test_lib.create_virtual_time_host(rcp, rcp_uart, node_id=node_id, port_offset=port_offset)

    env = os.environ.copy()
    env["PORT_OFFSET"] = str(port_offset)
    radio_url = f"spinel+hdlc+uart:///dev/null?forkpty-arg={node_id}"
    host = test_lib.launch_host_process(host_binary,
                                        f"host{node_id}",
                                        ["-v", radio_url],
                                        env=env,
                                        virtual_time=True)
    wait_for_boot(host)
    # Enable runtime logging to get CLI messages such as "Role detached -> child"
    openthread_lib.set_log_level(host, 3)
    return host

################################################
# Test
################################################

rcp_board, rcp_uart, rcp_elf, host_binary = parse_arguments()
test_lib.create_emulation(debug=DEBUG, quantum_time=QUANTUM_TIME)

# Each host gets a distinct PORT_OFFSET so their virtual-time sockets don't collide.
host1 = create_node("rcp1", rcp_board, rcp_elf, rcp_uart, node_id=1, port_offset=0,
                    host_binary=host_binary)
host2 = create_node("rcp2", rcp_board, rcp_elf, rcp_uart, node_id=2, port_offset=1,
                    host_binary=host_binary)

network_key, channel, panid = openthread_lib.leader_start(host1)
# No CSL receiver support in posix ot-cli application
openthread_lib.router_start(host2, network_key, channel, panid, csl_enabled=False)

openthread_lib.ping_test(host1, host2)
openthread_lib.ping_test(host2, host1)

openthread_lib.coaps_test(host1, host2)
