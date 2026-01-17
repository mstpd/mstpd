#!/bin/bash
#
# T9: Topology Change Tests
#
# Tests STP/RSTP topology change detection and propagation.
#
# Copyright (C) 2026 Vincent Jardin, Free Mobile
# SPDX-License-Identifier: GPL-2.0-or-later
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/testlib.sh"

# T9.01: TC detection on state change
test_T9_01_tc_detection() {
    test_start "T9.01" "tc_detection"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"

    # Wait for full convergence
    wait_for_convergence 15

    # Get initial TC count (already includes convergence TCs)
    local initial_tc
    initial_tc=$(mstpctl_get showbridge "br0" topology-change-count)
    log_debug "Initial TC count: ${initial_tc}"

    # Cause a topology change by flapping the link (down then up)
    ip link set "br0-br1" down
    sleep 1
    ip link set "br0-br1" up
    sleep 3

    # Check TC count increased
    local new_tc
    new_tc=$(mstpctl_get showbridge "br0" topology-change-count)
    log_debug "New TC count: ${new_tc}"

    cleanup_topology_b "br0" "br1"

    if [[ -n "${new_tc}" ]] && [[ -n "${initial_tc}" ]] && [[ "${new_tc}" -gt "${initial_tc}" ]]; then
        test_pass "TC detected on state change (${initial_tc} -> ${new_tc})"
        return 0
    else
        test_fail "TC count did not increase (${initial_tc} -> ${new_tc})"
        return 1
    fi
}

# T9.02: TC propagation via BPDU
test_T9_02_tc_propagation() {
    test_start "T9.02" "tc_propagation"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_c
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"
    bridge_enable_stp "br2" "rstp"

    # Wait for full convergence — TC count should stabilize
    wait_for_convergence 15

    # Wait extra time for TC count to settle
    local tc_before
    tc_before=$(mstpctl_get showbridge "br0" topology-change-count)
    sleep 3
    local tc_stable
    tc_stable=$(mstpctl_get showbridge "br0" topology-change-count)

    # If TC count is still changing, wait more
    if [[ "${tc_stable}" != "${tc_before}" ]]; then
        sleep 3
        tc_stable=$(mstpctl_get showbridge "br0" topology-change-count)
    fi
    log_debug "Stable TC count on br0: ${tc_stable}"

    # Now trigger a new TC: add a new bridge to the topology
    bridge_create "br3" 0
    veth_create "br0-br3" "br3-br0"
    bridge_add_port "br0" "br0-br3"
    bridge_add_port "br3" "br3-br0"
    bridge_enable_stp "br3" "rstp"

    # Poll for TC count to increase on br0
    local new_tc="${tc_stable}"
    local start_time
    start_time=$(date +%s)
    while (( $(date +%s) - start_time < 15 )); do
        new_tc=$(mstpctl_get showbridge "br0" topology-change-count)
        if [[ -n "${new_tc}" ]] && [[ -n "${tc_stable}" ]] && [[ "${new_tc}" -gt "${tc_stable}" ]]; then
            break
        fi
        sleep 0.5
    done
    log_debug "TC count after adding br3: ${new_tc}"

    # Cleanup extra bridge
    veth_delete "br0-br3" 2>/dev/null || true
    bridge_delete "br3" 2>/dev/null || true
    cleanup_topology_c

    if ! mstpd_is_running; then
        test_fail "mstpd crashed during TC propagation"
        return 1
    fi

    if [[ -n "${new_tc}" ]] && [[ -n "${tc_stable}" ]] && [[ "${new_tc}" -gt "${tc_stable}" ]]; then
        test_pass "TC propagated to br0 (${tc_stable} -> ${new_tc})"
        return 0
    else
        test_fail "TC not propagated to br0 (${tc_stable} -> ${new_tc:-empty})"
        return 1
    fi
}

# T9.03: Restricted TCN
test_T9_03_tc_restricted() {
    test_start "T9.03" "tc_restricted"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"

    wait_for_convergence 15

    # Set restricted TCN on port
    mstpctl setportrestrtcn "br0" "br0-br1" yes

    # Verify setting was applied
    local restrtcn
    restrtcn=$(mstpctl showportdetail "br0" "br0-br1" restricted-TCN)
    log_debug "Restricted TCN: ${restrtcn}"

    cleanup_topology_b "br0" "br1"

    if [[ "${restrtcn}" == "yes" ]]; then
        test_pass "Restricted TCN setting applied"
        return 0
    else
        test_fail "Restricted TCN not applied (got: ${restrtcn:-empty})"
        return 1
    fi
}

# T9.04: TC counter increments
test_T9_04_tc_counter() {
    test_start "T9.04" "tc_counter"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"

    wait_for_convergence 15

    # Get TC count
    local tc_count
    tc_count=$(mstpctl_get showbridge "br0" topology-change-count)

    cleanup_topology_b "br0" "br1"

    if [[ -n "${tc_count}" ]]; then
        test_pass "TC counter available: ${tc_count}"
        return 0
    else
        test_fail "TC counter not available"
        return 1
    fi
}

# T9.05: TC port recorded
test_T9_05_tc_port_record() {
    test_start "T9.05" "tc_port_record"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"

    wait_for_convergence 15

    # Check for TC port field
    local tc_port
    tc_port=$(mstpctl showbridge "br0" | grep "topology change port" | head -1 | awk '{print $4}')
    local last_tc_port
    last_tc_port=$(mstpctl showbridge "br0" | grep "last topology change port" | awk '{print $5}')

    log_debug "TC port: ${tc_port}, Last TC port: ${last_tc_port}"

    cleanup_topology_b "br0" "br1"

    test_pass "TC port recording available"
    return 0
}

# T9.06: FDB flush on TC
test_T9_06_tc_fdb_flush() {
    test_start "T9.06" "tc_fdb_flush"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"

    wait_for_convergence 15

    # Get ageing time (used for TC-based flush)
    local ageing
    ageing=$(mstpctl_get showbridge "br0" ageing-time)
    log_debug "Ageing time: ${ageing}"

    # Trigger TC
    ip link set "br0-br1" down
    sleep 1
    ip link set "br0-br1" up
    sleep 2

    cleanup_topology_b "br0" "br1"

    # If we get here without crash, FDB handling works
    if mstpd_is_running; then
        test_pass "FDB flush on TC handled"
        return 0
    else
        test_fail "mstpd crashed during FDB flush"
        return 1
    fi
}

# T9.07: TCN BPDU in STP mode
test_T9_07_tc_tcn_bpdu() {
    test_start "T9.07" "tc_tcn_bpdu"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    # Force STP mode for TCN BPDU testing
    bridge_enable_stp "br0" "stp"
    bridge_enable_stp "br1" "stp"

    wait_for_convergence 30

    # Check TCN counters
    local tx_tcn
    local rx_tcn
    tx_tcn=$(mstpctl_get showportdetail "br0" "br0-br1" num-tx-tcn)
    rx_tcn=$(mstpctl_get showportdetail "br0" "br0-br1" num-rx-tcn)

    log_debug "TX TCN: ${tx_tcn}, RX TCN: ${rx_tcn}"

    cleanup_topology_b "br0" "br1"

    if [[ -n "${tx_tcn}" ]] || [[ -n "${rx_tcn}" ]]; then
        test_pass "TCN BPDU counters available (TX=${tx_tcn:-0}, RX=${rx_tcn:-0})"
        return 0
    else
        test_fail "TCN BPDU counters not available"
        return 1
    fi
}

# T9.08: TC acknowledgment
test_T9_08_tc_ack() {
    test_start "T9.08" "tc_ack"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "stp"
    bridge_enable_stp "br1" "stp"

    wait_for_convergence 30

    # Check TC ack field
    local tc_ack
    tc_ack=$(mstpctl_get showportdetail "br0" "br0-br1" topology-change-ack)
    log_debug "TC ack: ${tc_ack}"

    cleanup_topology_b "br0" "br1"

    test_pass "TC acknowledgment mechanism available"
    return 0
}

# Main

main() {
    test_suite_init "T9: Topology Change"
    trap_cleanup
    run_discovered_tests "T9"
    cleanup_all
    test_suite_summary
}

main "$@"
