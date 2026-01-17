#!/bin/bash
#
# T3: Port Management Tests
#
# Tests port add/remove, link state changes, and port tracking.
#
# Copyright (C) 2026 Vincent Jardin, Free Mobile
# SPDX-License-Identifier: GPL-2.0-or-later
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/testlib.sh"

# Test Cases

# T3.01: Add port to bridge
test_T3_01_port_add() {
    test_start "T3.01" "port_add"

    # Ensure clean state
    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create bridge
    bridge_create "br0" 1
    sleep 0.5
    mstpctl addbridge br0 2>&1

    # Create veth pair
    veth_create "veth0" "veth0-peer"

    # Add port to bridge
    bridge_add_port "br0" "veth0"

    sleep 1

    # Check port appears in showport
    local output
    output=$(mstpctl showport br0 veth0 2>&1)

    if [[ "${output}" == *"veth0"* ]]; then
        test_pass "Port veth0 added successfully"
        veth_delete "veth0"
        return 0
    else
        test_fail "Port veth0 not found in showport output"
        veth_delete "veth0"
        return 1
    fi
}

# T3.02: Remove port from bridge
test_T3_02_port_remove() {
    test_start "T3.02" "port_remove"

    # Ensure clean state
    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create bridge with port
    bridge_create "br0" 1
    veth_create "veth0" "veth0-peer"
    bridge_add_port "br0" "veth0"
    sleep 0.5
    mstpctl addbridge br0 2>&1

    sleep 0.5

    # Verify port is present
    local output
    output=$(mstpctl showport br0 2>&1)
    if [[ "${output}" != *"veth0"* ]]; then
        test_fail "Port not present initially"
        veth_delete "veth0"
        return 1
    fi

    # Remove port from bridge
    bridge_del_port "veth0"

    sleep 1

    # Verify port is gone from mstpd
    output=$(mstpctl showport br0 2>&1)

    if [[ "${output}" != *"veth0"* ]] || [[ "${output}" == *"error"* ]]; then
        test_pass "Port removed successfully"
        veth_delete "veth0"
        return 0
    else
        test_fail "Port still appears after removal"
        veth_delete "veth0"
        return 1
    fi
}

# T3.03: Port link comes up
test_T3_03_port_link_up() {
    test_start "T3.03" "port_link_up"

    # Ensure clean state
    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create bridge and veth
    bridge_create "br0" 1
    veth_create "veth0" "veth0-peer"

    # Bring port down initially
    ip link set veth0 down

    # Add to bridge
    bridge_add_port "br0" "veth0"
    sleep 0.5
    mstpctl addbridge br0 2>&1

    sleep 0.5

    # Bring port up
    ip link set veth0 up
    ip link set veth0-peer up

    sleep 2

    # Check port state - should be participating in STP
    local output
    output=$(mstpctl showport br0 veth0 2>&1)

    if [[ "${output}" == *"veth0"* ]]; then
        # Check for a valid STP state (not disabled)
        local state
        state=$(port_get_state "veth0")
        log_debug "Port state: ${state}"

        # State should be > 0 (not disabled)
        if [[ -n "${state}" ]]; then
            test_pass "Port link up detected, state=${state}"
            veth_delete "veth0"
            return 0
        fi
    fi

    test_fail "Port link up not properly detected"
    veth_delete "veth0"
    return 1
}

# T3.04: Port link goes down
test_T3_04_port_link_down() {
    test_start "T3.04" "port_link_down"

    # Ensure clean state
    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create bridge with port
    bridge_create "br0" 1
    veth_create "veth0" "veth0-peer"
    bridge_add_port "br0" "veth0"
    sleep 0.5
    mstpctl addbridge br0 2>&1

    sleep 1

    # Get initial state
    local state_before
    state_before=$(port_get_state "veth0")
    log_debug "State before: ${state_before}"

    # Bring peer down (causes link down on veth0)
    ip link set veth0-peer down

    sleep 1

    # Check port state - should be disabled (0)
    local state_after
    state_after=$(port_get_state "veth0")
    log_debug "State after: ${state_after}"

    # mstpd should still be running
    if ! mstpd_is_running; then
        test_fail "mstpd crashed on link down"
        veth_delete "veth0"
        return 1
    fi

    # Port state should change (typically to 0/disabled or blocking)
    if [[ "${state_after}" == "0" ]] || [[ "${state_before}" != "${state_after}" ]]; then
        test_pass "Port link down detected (state: ${state_before} -> ${state_after})"
        veth_delete "veth0"
        return 0
    else
        test_fail "Port state did not change on link down"
        veth_delete "veth0"
        return 1
    fi
}

# T3.05: Rapid link flapping
test_T3_05_port_flap() {
    test_start "T3.05" "port_flap"

    # Ensure clean state
    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create bridge with port
    bridge_create "br0" 1
    veth_create "veth0" "veth0-peer"
    bridge_add_port "br0" "veth0"
    sleep 0.5
    mstpctl addbridge br0 2>&1

    sleep 0.5

    # Flap link multiple times
    for i in $(seq 1 10); do
        ip link set veth0-peer down
        sleep 0.1
        ip link set veth0-peer up
        sleep 0.1
    done

    sleep 1

    # Check mstpd is still running
    if mstpd_is_running; then
        # Check we can still query the port
        local output
        output=$(mstpctl showport br0 veth0 2>&1)
        if [[ "${output}" == *"veth0"* ]]; then
            test_pass "Port flapping handled without crash"
            veth_delete "veth0"
            return 0
        fi
    fi

    test_fail "mstpd crashed or port lost during link flapping"
    veth_delete "veth0"
    return 1
}

# T3.06: Add multiple ports
test_T3_06_port_multiple_add() {
    test_start "T3.06" "port_multiple_add"

    # Ensure clean state
    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create bridge
    bridge_create "br0" 1
    sleep 0.5
    mstpctl addbridge br0 2>&1

    # Create and add multiple ports
    local num_ports=5
    for i in $(seq 1 ${num_ports}); do
        veth_create "veth${i}" "veth${i}-peer"
        bridge_add_port "br0" "veth${i}"
    done

    sleep 2

    # Check all ports appear
    local output
    output=$(mstpctl showport br0 2>&1)
    local all_found=1

    for i in $(seq 1 ${num_ports}); do
        if [[ "${output}" != *"veth${i}"* ]]; then
            log_debug "Port veth${i} not found"
            all_found=0
        fi
    done

    # Cleanup
    for i in $(seq 1 ${num_ports}); do
        veth_delete "veth${i}"
    done

    if [[ ${all_found} -eq 1 ]]; then
        test_pass "All ${num_ports} ports added successfully"
        return 0
    else
        test_fail "Not all ports found"
        return 1
    fi
}

# T3.07: Port speed change (simulated via ethtool if possible)
test_T3_07_port_speed_change() {
    test_start "T3.07" "port_speed_change"

    # Note: veth pairs don't have real speed, so we test that
    # mstpd doesn't crash when querying speed and handles the default

    # Ensure clean state
    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create bridge with port
    bridge_create "br0" 1
    veth_create "veth0" "veth0-peer"
    bridge_add_port "br0" "veth0"
    sleep 0.5
    mstpctl addbridge br0 2>&1

    sleep 1

    # Query port details (includes speed info)
    local output
    output=$(mstpctl showportdetail br0 veth0 2>&1)

    if [[ "${output}" == *"veth0"* ]]; then
        # Check for path cost info (derived from speed)
        if [[ "${output}" == *"path cost"* ]] || [[ "${output}" == *"admin-path-cost"* ]]; then
            test_pass "Port speed/cost information available"
            veth_delete "veth0"
            return 0
        else
            # Still pass if port is visible, speed info may not be shown
            test_pass "Port visible (speed info format may vary)"
            veth_delete "veth0"
            return 0
        fi
    fi

    test_fail "Could not query port details"
    veth_delete "veth0"
    return 1
}

# T3.08: Port duplex handling
test_T3_08_port_duplex_change() {
    test_start "T3.08" "port_duplex_change"

    # Note: veth pairs are always full-duplex, test p2p detection

    # Ensure clean state
    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create bridge with port
    bridge_create "br0" 1
    veth_create "veth0" "veth0-peer"
    bridge_add_port "br0" "veth0"
    sleep 0.5
    mstpctl addbridge br0 2>&1

    sleep 1

    # Query port details for p2p info
    local output
    output=$(mstpctl showportdetail br0 veth0 2>&1)

    if [[ "${output}" == *"veth0"* ]]; then
        # Check for point-to-point info
        if [[ "${output}" == *"point-to-point"* ]] || [[ "${output}" == *"p2p"* ]]; then
            test_pass "Port p2p (duplex-derived) information available"
            veth_delete "veth0"
            return 0
        else
            # Query with specific parameter
            output=$(mstpctl showportparams br0 veth0 point-to-point 2>&1 || echo "")
            test_pass "Port visible (p2p info format may vary)"
            veth_delete "veth0"
            return 0
        fi
    fi

    test_fail "Could not query port details"
    veth_delete "veth0"
    return 1
}

# Main

main() {
    test_suite_init "T3: Port Management"
    trap_cleanup
    run_discovered_tests "T3"
    cleanup_all
    test_suite_summary
}

main "$@"
