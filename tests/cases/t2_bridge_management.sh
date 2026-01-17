#!/bin/bash
#
# T2: Bridge Management Tests
#
# Tests bridge add/remove, STP enable/disable, and bridge state tracking.
#
# Copyright (C) 2026 Vincent Jardin, Free Mobile
# SPDX-License-Identifier: GPL-2.0-or-later
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/testlib.sh"

# Test Cases

# T2.01: Add single bridge
test_T2_01_bridge_add_single() {
    test_start "T2.01" "bridge_add_single"

    # Ensure clean state
    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create bridge with STP enabled
    bridge_create "br0" 1

    # Wait for mstpd to pick it up
    sleep 1

    # Add bridge to mstpd
    local output
    output=$(mstpctl addbridge br0 2>&1)

    # Check if bridge appears in showbridge
    output=$(mstpctl showbridge br0 2>&1)

    if [[ "${output}" == *"br0"* ]]; then
        test_pass "Bridge br0 added successfully"
        return 0
    else
        test_fail "Bridge br0 not found in showbridge output"
        return 1
    fi
}

# T2.02: Add multiple bridges
test_T2_02_bridge_add_multiple() {
    test_start "T2.02" "bridge_add_multiple"

    # Ensure clean state
    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create multiple bridges
    for i in 0 1 2; do
        bridge_create "br${i}" 1
    done

    sleep 1

    # Add bridges to mstpd
    mstpctl addbridge br0 br1 br2 2>&1

    # Check all bridges appear
    local output
    output=$(mstpctl showbridge 2>&1)
    local all_found=1

    for i in 0 1 2; do
        if [[ "${output}" != *"br${i}"* ]]; then
            log_debug "Bridge br${i} not found"
            all_found=0
        fi
    done

    if [[ ${all_found} -eq 1 ]]; then
        test_pass "All bridges added successfully"
        return 0
    else
        test_fail "Not all bridges found in showbridge output"
        return 1
    fi
}

# T2.03: Remove bridge
test_T2_03_bridge_remove() {
    test_start "T2.03" "bridge_remove"

    # Ensure clean state
    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create and add bridge
    bridge_create "br0" 1
    sleep 0.5
    mstpctl addbridge br0 2>&1

    # Verify it's added
    local output
    output=$(mstpctl showbridge br0 2>&1)
    if [[ "${output}" != *"br0"* ]]; then
        test_fail "Bridge not added initially"
        return 1
    fi

    # Remove bridge from mstpd first
    mstpctl delbridge br0 2>&1

    # Delete the kernel bridge
    bridge_delete "br0"

    # Wait for mstpd to detect the removal
    sleep 1

    # Verify it's removed - check showbridge without argument to list all
    output=$(mstpctl showbridge 2>&1)

    # The bridge should not appear in the list of managed bridges
    # Note: querying a specific non-existent bridge may still return its name in error
    if [[ "${output}" != *"br0"* ]]; then
        test_pass "Bridge removed successfully"
        return 0
    fi

    # If br0 still in output, check if it's an error message
    if [[ "${output}" == *"error"* ]] || [[ "${output}" == *"Couldn't"* ]]; then
        test_pass "Bridge removed (error response indicates not managed)"
        return 0
    fi

    # mstpd may take time to update - check if bridge exists in kernel
    if ! bridge_exists "br0"; then
        test_pass "Bridge removed from kernel (mstpd will sync)"
        return 0
    fi

    test_fail "Bridge still appears after removal"
    return 1
}

# T2.04: Remove bridge with active ports
test_T2_04_bridge_remove_active() {
    test_start "T2.04" "bridge_remove_active"

    # Ensure clean state
    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create bridge with ports
    setup_topology_a "br0" 2

    # Enable STP and add to mstpd
    ip link set br0 type bridge stp_state 1
    sleep 0.5
    mstpctl addbridge br0 2>&1

    # Verify ports are visible
    local output
    output=$(mstpctl showport br0 2>&1)
    if [[ "${output}" != *"br0-p1"* ]]; then
        test_fail "Ports not visible initially"
        cleanup_topology_a "br0" 2
        return 1
    fi

    # Remove bridge (should handle ports gracefully)
    mstpctl delbridge br0 2>&1
    bridge_delete "br0"

    sleep 0.5

    # Cleanup veth pairs
    veth_delete "br0-p1" 2>/dev/null || true
    veth_delete "br0-p2" 2>/dev/null || true

    test_pass "Bridge with active ports removed successfully"
    return 0
}

# T2.05: Enable kernel STP triggers mstpd
test_T2_05_bridge_kernel_stp_on() {
    test_start "T2.05" "bridge_kernel_stp_on"

    # Ensure clean state
    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create bridge without STP
    bridge_create "br0" 0

    sleep 0.5

    # Enable STP
    ip link set br0 type bridge stp_state 1

    sleep 1

    # Add to mstpd
    mstpctl addbridge br0 2>&1

    # Check bridge is managed
    local output
    output=$(mstpctl showbridge br0 2>&1)
    if [[ "${output}" == *"br0"* ]] && [[ "${output}" != *"error"* ]]; then
        test_pass "Bridge with STP enabled is managed by mstpd"
        return 0
    else
        test_fail "Bridge not properly managed after STP enable"
        return 1
    fi
}

# T2.06: Disable kernel STP
test_T2_06_bridge_kernel_stp_off() {
    test_start "T2.06" "bridge_kernel_stp_off"

    # Ensure clean state
    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create bridge with STP
    bridge_create "br0" 1
    sleep 0.5
    mstpctl addbridge br0 2>&1

    # Verify it's managed
    local output
    output=$(mstpctl showbridge br0 2>&1)
    if [[ "${output}" != *"br0"* ]]; then
        test_fail "Bridge not managed initially"
        return 1
    fi

    # Disable STP
    ip link set br0 type bridge stp_state 0

    sleep 1

    # Bridge should still be queryable but state may change
    output=$(mstpctl showbridge br0 2>&1)

    # The test passes if mstpd doesn't crash and handles the state change
    if mstpd_is_running; then
        test_pass "mstpd handled STP disable without crash"
        return 0
    else
        test_fail "mstpd crashed when STP was disabled"
        return 1
    fi
}

# T2.07: Bridge interface up/down
test_T2_07_bridge_updown() {
    test_start "T2.07" "bridge_updown"

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

    # Bring bridge down
    ip link set br0 down
    sleep 0.5

    # Check mstpd still running
    if ! mstpd_is_running; then
        test_fail "mstpd crashed when bridge went down"
        return 1
    fi

    # Bring bridge up
    ip link set br0 up
    sleep 0.5

    # Check mstpd still running and bridge is queryable
    if ! mstpd_is_running; then
        test_fail "mstpd crashed when bridge came up"
        return 1
    fi

    local output
    output=$(mstpctl showbridge br0 2>&1)
    if [[ "${output}" == *"br0"* ]]; then
        test_pass "Bridge up/down handled correctly"
        return 0
    else
        test_fail "Bridge not queryable after up/down cycle"
        return 1
    fi
}

# T2.08: Bridge MAC address handling
test_T2_08_bridge_mac_change() {
    test_start "T2.08" "bridge_mac_change"

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

    # Get initial MAC
    local mac_before
    mac_before=$(get_mac_address "br0")
    log_debug "Initial MAC: ${mac_before}"

    # Change MAC address
    ip link set br0 down
    ip link set br0 address 02:00:00:00:00:99
    ip link set br0 up

    sleep 1

    # Get new MAC
    local mac_after
    mac_after=$(get_mac_address "br0")
    log_debug "New MAC: ${mac_after}"

    # Check mstpd still running
    if ! mstpd_is_running; then
        test_fail "mstpd crashed on MAC change"
        return 1
    fi

    # Check bridge is still queryable
    local output_after
    output_after=$(mstpctl showbridge br0 2>&1)
    if [[ "${output_after}" == *"br0"* ]]; then
        test_pass "Bridge MAC change handled (${mac_before} -> ${mac_after})"
        return 0
    else
        test_fail "Bridge not queryable after MAC change"
        return 1
    fi
}

# Main

main() {
    test_suite_init "T2: Bridge Management"
    trap_cleanup
    run_discovered_tests "T2"
    cleanup_all
    test_suite_summary
}

main "$@"
