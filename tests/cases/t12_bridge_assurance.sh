#!/bin/bash
#
# T12: Bridge Assurance Tests
#
# Tests Bridge Assurance (network port) feature.
#
# Copyright (C) 2026 Vincent Jardin, Free Mobile
# SPDX-License-Identifier: GPL-2.0-or-later
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/testlib.sh"

# T12.01: Enable network port (Bridge Assurance)
test_T12_01_ba_network_port() {
    test_start "T12.01" "ba_network_port"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"

    wait_for_convergence 15

    # Enable network port (Bridge Assurance)
    mstpctl setportnetwork "br0" "br0-br1" yes

    local network_port
    network_port=$(mstpctl_get showportdetail "br0" "br0-br1" network-port)
    log_debug "Network port: ${network_port}"

    cleanup_topology_b "br0" "br1"

    if [[ "${network_port}" == "yes" ]]; then
        test_pass "Network port enabled"
        return 0
    else
        test_fail "Network port not enabled (got: ${network_port:-empty})"
        return 1
    fi
}

# T12.02: No BPDUs received - port blocked
test_T12_02_ba_bpdu_timeout() {
    test_start "T12.02" "ba_bpdu_timeout"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Single bridge with network port (no peer to send BPDUs)
    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "rstp"

    # Enable network port
    mstpctl setportnetwork "br0" "br0-p1" yes

    # Wait for BA timeout (3 * hello = 6 seconds typically)
    sleep 8

    # Check BA inconsistent flag
    local ba_inconsistent
    ba_inconsistent=$(mstpctl_get showportdetail "br0" "br0-p1" ba-inconsistent)
    log_debug "BA inconsistent: ${ba_inconsistent}"

    cleanup_topology_a "br0" 1

    if [[ "${ba_inconsistent}" == "yes" ]]; then
        test_pass "BA detected no BPDUs - port inconsistent"
        return 0
    else
        test_fail "BA inconsistent not set (got: ${ba_inconsistent:-empty})"
        return 1
    fi
}

# T12.03: BPDUs resume - port unblocked
test_T12_03_ba_bpdu_resume() {
    test_start "T12.03" "ba_bpdu_resume"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"

    # Enable network port on both ends
    mstpctl setportnetwork "br0" "br0-br1" yes
    mstpctl setportnetwork "br1" "br1-br0" yes

    wait_for_convergence 15

    # Both should be receiving BPDUs, so BA should be consistent
    local ba_inconsistent
    ba_inconsistent=$(mstpctl_get showportdetail "br0" "br0-br1" ba-inconsistent)
    log_debug "BA inconsistent: ${ba_inconsistent}"

    cleanup_topology_b "br0" "br1"

    if [[ "${ba_inconsistent}" == "no" ]]; then
        test_pass "BA consistent with BPDUs flowing"
        return 0
    else
        test_fail "BA inconsistent should be no (got: ${ba_inconsistent:-empty})"
        return 1
    fi
}

# T12.04: Both sides enabled
test_T12_04_ba_both_sides() {
    test_start "T12.04" "ba_both_sides"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"

    # Enable network port on both ends
    mstpctl setportnetwork "br0" "br0-br1" yes
    mstpctl setportnetwork "br1" "br1-br0" yes

    wait_for_convergence 15

    # Check both ports
    local np0
    local np1
    np0=$(mstpctl_get showportdetail "br0" "br0-br1" network-port)
    np1=$(mstpctl_get showportdetail "br1" "br1-br0" network-port)

    log_debug "Network port br0: ${np0}, br1: ${np1}"

    cleanup_topology_b "br0" "br1"

    if [[ "${np0}" == "yes" ]] && [[ "${np1}" == "yes" ]]; then
        test_pass "Bridge Assurance enabled on both sides"
        return 0
    else
        test_fail "Network port not enabled on both sides (br0=${np0:-empty}, br1=${np1:-empty})"
        return 1
    fi
}

# T12.05: Only one side enabled
test_T12_05_ba_one_side() {
    test_start "T12.05" "ba_one_side"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"

    # Enable network port only on one side
    mstpctl setportnetwork "br0" "br0-br1" yes

    wait_for_convergence 15

    # Check status
    local np0
    local np1
    np0=$(mstpctl_get showportdetail "br0" "br0-br1" network-port)
    np1=$(mstpctl_get showportdetail "br1" "br1-br0" network-port)

    log_debug "Network port br0: ${np0}, br1: ${np1}"

    cleanup_topology_b "br0" "br1"

    if [[ "${np0}" == "yes" ]] && [[ "${np1}" == "no" ]]; then
        test_pass "Bridge Assurance enabled on one side only"
        return 0
    else
        test_fail "Unexpected network port state (br0=${np0:-empty}, br1=${np1:-empty})"
        return 1
    fi
}

# Main

main() {
    test_suite_init "T12: Bridge Assurance"
    trap_cleanup
    run_discovered_tests "T12"
    cleanup_all
    test_suite_summary
}

main "$@"
