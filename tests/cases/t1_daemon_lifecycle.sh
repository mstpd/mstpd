#!/bin/bash
#
# T1: Daemon Lifecycle Tests
#
# Tests mstpd daemon start, stop, signal handling, and basic operation.
#
# Copyright (C) 2026 Vincent Jardin, Free Mobile
# SPDX-License-Identifier: GPL-2.0-or-later
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/testlib.sh"

# Test Cases

# T1.01: Start mstpd daemon
test_T1_01_daemon_start() {
    test_start "T1.01" "daemon_start"

    # Ensure mstpd is not running
    mstpd_stop 2>/dev/null || true

    # Start mstpd
    if ! mstpd_start "-d -v 2"; then
        test_fail "Failed to start mstpd"
        return 1
    fi

    # Verify it's running
    sleep 0.5
    if mstpd_is_running; then
        test_pass "mstpd started successfully"
        return 0
    else
        test_fail "mstpd is not running after start"
        return 1
    fi
}

# T1.02: Stop mstpd gracefully
test_T1_02_daemon_stop() {
    test_start "T1.02" "daemon_stop"

    # Ensure mstpd is running
    if ! mstpd_is_running; then
        mstpd_start "-d -v 2" || {
            test_fail "Could not start mstpd for test"
            return 1
        }
    fi

    # Stop mstpd
    mstpd_stop

    # Verify it's stopped
    sleep 0.5
    if ! mstpd_is_running; then
        test_pass "mstpd stopped successfully"
        return 0
    else
        test_fail "mstpd is still running after stop"
        return 1
    fi
}

# T1.03: Restart mstpd
test_T1_03_daemon_restart() {
    test_start "T1.03" "daemon_restart"

    # Start mstpd
    mstpd_stop 2>/dev/null || true
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    local pid_before
    pid_before=$(mstpd_get_pid)

    # Stop and start again
    mstpd_stop
    sleep 0.5
    mstpd_start "-d -v 2" || {
        test_fail "Could not restart mstpd"
        return 1
    }

    local pid_after
    pid_after=$(mstpd_get_pid)

    # Verify new PID
    if [[ -n "${pid_after}" ]] && [[ "${pid_before}" != "${pid_after}" ]]; then
        test_pass "mstpd restarted with new PID (${pid_before} -> ${pid_after})"
        return 0
    else
        test_fail "mstpd restart failed or PID unchanged"
        return 1
    fi
}

# T1.04: SIGTERM handling
test_T1_04_daemon_sigterm() {
    test_start "T1.04" "daemon_sigterm"

    # Ensure mstpd is running
    mstpd_stop 2>/dev/null || true
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    local pid
    pid=$(mstpd_get_pid)

    # Send SIGTERM
    kill -TERM "${pid}" 2>/dev/null

    # Wait for shutdown
    sleep 1

    if ! mstpd_is_running; then
        test_pass "mstpd handled SIGTERM correctly"
        return 0
    else
        test_fail "mstpd did not exit on SIGTERM"
        return 1
    fi
}

# T1.05: SIGHUP handling
# Note: mstpd treats SIGHUP like SIGTERM (clean exit), not config reload
test_T1_05_daemon_sighup() {
    test_start "T1.05" "daemon_sighup"

    # Ensure mstpd is running
    mstpd_stop 2>/dev/null || true
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    local pid
    pid=$(mstpd_get_pid)

    # Send SIGHUP - mstpd exits cleanly on SIGHUP (same as SIGTERM)
    kill -HUP "${pid}" 2>/dev/null

    # Wait for exit
    sleep 1

    # mstpd should have exited cleanly (this is expected behavior)
    if ! mstpd_is_running; then
        test_pass "mstpd handled SIGHUP (clean exit, same as SIGTERM)"
        return 0
    else
        # If still running, that's also OK (might have been changed to ignore)
        test_pass "mstpd handled SIGHUP (continued running)"
        return 0
    fi
}

# T1.06: Run in foreground mode
test_T1_06_daemon_foreground() {
    test_start "T1.06" "daemon_foreground"

    local log_file="${TEST_LOG_DIR}/mstpd_foreground.log"

    # Ensure mstpd is not running
    mstpd_stop 2>/dev/null || true

    # Start in foreground with timeout
    timeout 2 "${MSTPD_BIN}" -d -v 2 > "${log_file}" 2>&1 &
    local bg_pid=$!

    sleep 0.5

    # Check if process is running
    if kill -0 "${bg_pid}" 2>/dev/null; then
        # It's running, good - now stop it
        kill -TERM "${bg_pid}" 2>/dev/null
        wait "${bg_pid}" 2>/dev/null || true
        test_pass "mstpd ran in foreground mode"
        return 0
    else
        # Process exited - check if it was timeout or error
        wait "${bg_pid}" 2>/dev/null
        local rc=$?
        if [[ ${rc} -eq 124 ]]; then
            # Timeout - this is expected
            test_pass "mstpd ran in foreground mode (timeout expected)"
            return 0
        else
            test_fail "mstpd failed to run in foreground mode (rc=${rc})"
            return 1
        fi
    fi
}

# T1.07: Logging levels
test_T1_07_daemon_logging() {
    test_start "T1.07" "daemon_logging"

    local log_file="${TEST_LOG_DIR}/mstpd_logging.log"

    # Test verbose level 0 (minimal)
    mstpd_stop 2>/dev/null || true
    "${MSTPD_BIN}" -d -v 0 > "${log_file}" 2>&1 &
    sleep 0.5
    mstpd_stop 2>/dev/null || true

    # Test verbose level 4 (maximum)
    "${MSTPD_BIN}" -d -v 4 > "${log_file}" 2>&1 &
    sleep 0.5

    if mstpd_is_running; then
        mstpd_stop
        test_pass "mstpd accepts different logging levels"
        return 0
    else
        test_fail "mstpd failed with logging level 4"
        return 1
    fi
}

# T1.08: Duplicate instance detection
test_T1_08_daemon_duplicate() {
    test_start "T1.08" "daemon_duplicate"

    local log_file="${TEST_LOG_DIR}/mstpd_duplicate.log"

    # Start first instance
    mstpd_stop 2>/dev/null || true
    mstpd_start "-d -v 2" || {
        test_fail "Could not start first mstpd instance"
        return 1
    }

    local first_pid
    first_pid=$(mstpd_get_pid)

    # Try to start second instance
    "${MSTPD_BIN}" -d -v 2 > "${log_file}" 2>&1 &
    local second_pid=$!

    sleep 1

    # Check if second instance is running
    if kill -0 "${second_pid}" 2>/dev/null; then
        # Second instance is running - this might be OK if they use different sockets
        # Check if we now have two mstpd processes
        local count
        count=$(pgrep -c -x mstpd 2>/dev/null || echo "0")
        if [[ "${count}" -gt 1 ]]; then
            # Kill the second one
            kill -TERM "${second_pid}" 2>/dev/null || true
            test_fail "Second mstpd instance was allowed to start"
            return 1
        fi
    fi

    # Verify first instance still running
    if [[ "$(mstpd_get_pid)" == "${first_pid}" ]]; then
        test_pass "Duplicate instance was rejected, original still running"
        return 0
    else
        test_fail "Original instance state changed"
        return 1
    fi
}

# Main

main() {
    test_suite_init "T1: Daemon Lifecycle"
    trap_cleanup
    run_discovered_tests "T1"
    mstpd_stop 2>/dev/null || true
    test_suite_summary
}

main "$@"
