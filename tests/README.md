# MSTPD Test Framework

[![MSTPD Tests](https://github.com/vjardin/mstpd/actions/workflows/test.yml/badge.svg)](https://github.com/vjardin/mstpd/actions/workflows/test.yml)

Standalone test framework for mstpd (Multiple Spanning Tree Protocol Daemon).

## Requirements

- Linux kernel with bridge support
- iproute2 (ip, bridge commands)
- bash 4.0+
- Built mstpd and mstpctl binaries in project root

For unprivileged execution:
- Linux kernel with user namespace support
- `kernel.unprivileged_userns_clone=1` sysctl setting

## Running Tests

### Unprivileged Mode (Recommended)

Uses Linux user namespaces to run tests without root:

```
./tests/run_tests_unpriv.sh -p phase1
```

If user namespaces are not available, enable them:

```
sudo sysctl -w kernel.unprivileged_userns_clone=1
```

### Privileged Mode

Run directly with root privileges:

```
sudo ./tests/run_tests.sh -p phase1
```

### Command Line Options

```
Usage: run_tests.sh [OPTIONS] [SUITE...]

Options:
    -h, --help          Show help message
    -l, --list          List available test suites
    -p, --phase PHASE   Run all suites in a phase (phase1-phase5)
    -a, --all           Run all available test suites
    -v, --verbose       Increase verbosity
    -k, --keep          Keep test environment after tests
    --no-color          Disable colored output
    --tap               Enable TAP (Test Anything Protocol) output
    --junit FILE        Write JUnit XML output to FILE
```

### Examples

```
# Run Phase 1 tests (core functionality)
./tests/run_tests_unpriv.sh -p phase1

# Run specific suites
./tests/run_tests_unpriv.sh T1 T2

# Run single suite with verbose output
./tests/run_tests_unpriv.sh -v T1

# List available suites
./tests/run_tests_unpriv.sh -l
```

## Test Phases

Phase 1 - Core Tests (CI basic validation):
- T1: Daemon Lifecycle
- T2: Bridge Management
- T3: Port Management
- T20: CLI (mstpctl)

Phase 2-5: See ci-test.md for complete test plan.

## Writing New Tests

### Test File Template

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/testlib.sh"

test_TX_01_test_name() {
    test_start "TX.01" "test_name"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Test logic here

    if [[ condition ]]; then
        test_pass "Success message"
        return 0
    else
        test_fail "Failure message"
        return 1
    fi
}

test_TX_02_another_test() {
    test_start "TX.02" "another_test"
    # ...
}

main() {
    test_suite_init "TX: Test Suite Name"
    trap_cleanup
    run_discovered_tests "TX"   # Auto-discovers test_TX_* functions
    cleanup_all
    test_suite_summary
}

main "$@"
```

Tests are auto-discovered by naming convention: functions matching `test_TX_##_*`
are found and executed in order by `run_discovered_tests "TX"`.

### Key Helper Functions

```bash
# Logging
log_info "message"
log_debug "message"
log_error "message"

# Test control
test_start "ID" "name"
test_pass "message"
test_fail "message"
test_skip "message"
run_discovered_tests "suite_id"    # Auto-run test_XX_* functions

# Daemon control
mstpd_start "args"
mstpd_stop
mstpd_is_running

# Bridge operations
bridge_create "name" stp_enabled
bridge_delete "name"
bridge_add_port "bridge" "port"

# Network helpers
veth_create "name"
veth_delete "name"

# Topology setup (manual)
setup_topology_a "bridge" num_ports
setup_topology_b "br0" "br1"
setup_topology_c "br0" "br1" "br2"
cleanup_topology_a "bridge" num_ports
cleanup_topology_b "br0" "br1"
cleanup_topology_c "br0" "br1" "br2"

# Topology wrappers (setup, run test, cleanup automatically)
with_topology_a "bridge" num_ports test_func [args...]
with_topology_b "br0" "br1" test_func [args...]
with_topology_c "br0" "br1" "br2" test_func [args...]

# Setup/teardown hooks
register_suite_setup func    # Called once before all tests
register_suite_teardown func # Called once after all tests
register_test_setup func     # Called before each test
register_test_teardown func  # Called after each test
clear_hooks                  # Reset all hooks

# Cleanup
cleanup_all
trap_cleanup
```

### Timing Constants

Use these instead of hardcoded sleep values:

```bash
SLEEP_BRIEF=0.2        # Brief pause for state changes
SLEEP_SHORT=0.5        # Short wait for daemon/process
SLEEP_MEDIUM=1         # Medium wait for convergence start
SLEEP_LONG=2           # Long wait for STP operations
SLEEP_CONVERGENCE=5    # Wait for full STP convergence
```

Override via environment: `SLEEP_CONVERGENCE=10 ./run_tests.sh T4`

## CI Integration

```bash
# Basic CI run
make clean && make
./tests/run_tests_unpriv.sh -p phase1

# With JUnit XML output (for CI systems like GitHub Actions)
./tests/run_tests.sh --junit results.xml T1 T2 T3

# With TAP output
./tests/run_tests.sh --tap T1
```

Exit code 0 means all tests passed.

GitHub Actions workflow is included in `.github/workflows/test.yml` with:
- Parallel test phases using matrix strategy
- JUnit XML reporting for test result visualization
- Automatic artifact upload for test logs
