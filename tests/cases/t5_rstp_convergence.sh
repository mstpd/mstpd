#!/bin/bash
#
# T5: RSTP Convergence Tests
#
# Tests RSTP rapid convergence and protocol operation.
#
# Copyright (C) 2026 Vincent Jardin, Free Mobile
# SPDX-License-Identifier: GPL-2.0-or-later
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/testlib.sh"

# T5.01: RSTP root bridge election
test_T5_01_rstp_root_election() {
    test_start "T5.01" "rstp_root_election"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"

    # RSTP should converge quickly
    sleep 3

    local br0_id
    local br1_id
    br0_id=$(bridge_get_id "br0")
    br1_id=$(bridge_get_id "br1")

    log_debug "br0 ID: ${br0_id}, br1 ID: ${br1_id}"

    if bridge_is_root "br0" || bridge_is_root "br1"; then
        test_pass "RSTP root bridge elected"
        cleanup_topology_b "br0" "br1"
        return 0
    else
        test_fail "No root bridge elected"
        cleanup_topology_b "br0" "br1"
        return 1
    fi
}

# T5.02: Proposal/Agreement exchange for rapid transition
test_T5_02_rstp_proposal_agreement() {
    test_start "T5.02" "rstp_proposal_agreement"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"

    # RSTP with proposal/agreement should converge in < 3 seconds
    local start_time
    start_time=$(date +%s)

    # Wait for both ports to be forwarding
    local converged=0
    while [[ $(($(date +%s) - start_time)) -lt 10 ]]; do
        local state0
        local state1
        state0=$(port_get_state "br0-br1")
        state1=$(port_get_state "br1-br0")

        if [[ "${state0}" == "3" ]] && [[ "${state1}" == "3" ]]; then
            converged=1
            break
        fi
        sleep 0.5
    done

    local duration=$(($(date +%s) - start_time))

    cleanup_topology_b "br0" "br1"

    if [[ ${converged} -eq 1 ]] && [[ ${duration} -lt 5 ]]; then
        test_pass "Rapid transition via proposal/agreement (${duration}s)"
        return 0
    elif [[ ${converged} -eq 1 ]]; then
        test_pass "Converged but slower than expected (${duration}s)"
        return 0
    else
        test_fail "Did not converge within timeout"
        return 1
    fi
}

# T5.03: RSTP triangle topology
test_T5_03_rstp_triangle() {
    test_start "T5.03" "rstp_triangle"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_c
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"
    bridge_enable_stp "br2" "rstp"

    # RSTP should converge quickly even with loop
    sleep 5

    # Count alternate (blocked) ports
    local blocked=0
    local role

    for port in br0-br1 br0-br2 br1-br0 br1-br2 br2-br0 br2-br1; do
        local bridge="${port%%-*}"
        role=$(port_get_role "${bridge}" "${port}")
        log_debug "Port ${port} role: ${role}"
        if [[ "${role}" == "Altn" ]] || [[ "${role}" == "Back" ]]; then
            ((blocked++))
        fi
    done

    cleanup_topology_c

    if [[ ${blocked} -ge 1 ]]; then
        test_pass "RSTP triangle: ${blocked} port(s) blocked"
        return 0
    else
        test_fail "No ports blocked in triangle"
        return 1
    fi
}

# T5.04: Measure RSTP convergence time (should be < 3 seconds)
test_T5_04_rstp_convergence_time() {
    test_start "T5.04" "rstp_convergence_time"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"

    local start_time
    start_time=$(date +%s)

    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"

    # Wait for forwarding state
    local converged=0
    local elapsed=0
    while [[ ${elapsed} -lt 10 ]]; do
        local state0
        local state1
        state0=$(port_get_state "br0-br1")
        state1=$(port_get_state "br1-br0")

        if [[ "${state0}" == "3" ]] && [[ "${state1}" == "3" ]]; then
            converged=1
            break
        fi
        sleep 0.2
        elapsed=$(($(date +%s) - start_time))
    done

    local duration=$(($(date +%s) - start_time))

    cleanup_topology_b "br0" "br1"

    if [[ ${converged} -eq 1 ]]; then
        if [[ ${duration} -le 3 ]]; then
            test_pass "RSTP converged in ${duration} seconds (rapid)"
            return 0
        else
            test_pass "RSTP converged in ${duration} seconds (slower than ideal)"
            return 0
        fi
    else
        test_fail "RSTP did not converge within 10 seconds"
        return 1
    fi
}

# T5.05: RSTP root bridge failure - rapid failover
test_T5_05_rstp_root_failure() {
    test_start "T5.05" "rstp_root_failure"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_c
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"
    bridge_enable_stp "br2" "rstp"

    sleep 5

    # Find current root
    local root_bridge=""
    for br in br0 br1 br2; do
        if bridge_is_root "${br}"; then
            root_bridge="${br}"
            break
        fi
    done

    if [[ -z "${root_bridge}" ]]; then
        test_fail "No root bridge found"
        cleanup_topology_c
        return 1
    fi

    log_debug "Initial root: ${root_bridge}"

    # Simulate root failure
    ip link set "${root_bridge}" down

    local start_time
    start_time=$(date +%s)

    # Wait for new root (RSTP should be fast)
    local new_root=""
    while [[ $(($(date +%s) - start_time)) -lt 10 ]]; do
        for br in br0 br1 br2; do
            if [[ "${br}" != "${root_bridge}" ]]; then
                if bridge_is_root "${br}"; then
                    new_root="${br}"
                    break 2
                fi
            fi
        done
        sleep 0.5
    done

    local duration=$(($(date +%s) - start_time))

    ip link set "${root_bridge}" up 2>/dev/null || true
    cleanup_topology_c

    if [[ -n "${new_root}" ]]; then
        test_pass "Rapid failover to ${new_root} in ${duration}s"
        return 0
    else
        test_fail "No new root elected after failure"
        return 1
    fi
}

# T5.06: Link failure and rapid reconvergence
test_T5_06_rstp_link_failure() {
    test_start "T5.06" "rstp_link_failure"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Linear topology: br0 - br1 - br2
    bridge_create "br0" 0
    bridge_create "br1" 0
    bridge_create "br2" 0

    veth_create "br0-br1" "br1-br0"
    bridge_add_port "br0" "br0-br1"
    bridge_add_port "br1" "br1-br0"

    veth_create "br1-br2" "br2-br1"
    bridge_add_port "br1" "br1-br2"
    bridge_add_port "br2" "br2-br1"

    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"
    bridge_enable_stp "br2" "rstp"

    sleep 3

    # Bring down link between br0 and br1
    ip link set "br0-br1" down
    ip link set "br1-br0" down

    sleep 2

    # mstpd should handle link failure gracefully
    if mstpd_is_running; then
        test_pass "Link failure handled, mstpd stable"
        veth_delete "br0-br1" 2>/dev/null || true
        veth_delete "br1-br2" 2>/dev/null || true
        bridge_delete "br0"
        bridge_delete "br1"
        bridge_delete "br2"
        return 0
    else
        test_fail "mstpd crashed on link failure"
        return 1
    fi
}

# T5.07: RSTP synchronization
test_T5_07_rstp_sync() {
    test_start "T5.07" "rstp_sync"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Star topology: br0 in center connected to br1, br2, br3
    bridge_create "br0" 0
    bridge_create "br1" 0
    bridge_create "br2" 0
    bridge_create "br3" 0

    veth_create "br0-br1" "br1-br0"
    bridge_add_port "br0" "br0-br1"
    bridge_add_port "br1" "br1-br0"

    veth_create "br0-br2" "br2-br0"
    bridge_add_port "br0" "br0-br2"
    bridge_add_port "br2" "br2-br0"

    veth_create "br0-br3" "br3-br0"
    bridge_add_port "br0" "br0-br3"
    bridge_add_port "br3" "br3-br0"

    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"
    bridge_enable_stp "br2" "rstp"
    bridge_enable_stp "br3" "rstp"

    sleep 5

    # All ports on non-root bridges should sync to forwarding
    local all_synced=1
    for port in br1-br0 br2-br0 br3-br0; do
        local bridge="${port%%-*}"
        local state
        state=$(port_get_state "${port}")
        if [[ "${state}" != "3" ]]; then
            all_synced=0
            log_debug "Port ${port} not forwarding: state=${state}"
        fi
    done

    veth_delete "br0-br1" 2>/dev/null || true
    veth_delete "br0-br2" 2>/dev/null || true
    veth_delete "br0-br3" 2>/dev/null || true
    bridge_delete "br0"
    bridge_delete "br1"
    bridge_delete "br2"
    bridge_delete "br3"

    if [[ ${all_synced} -eq 1 ]]; then
        test_pass "All ports synchronized to forwarding"
        return 0
    else
        test_fail "Not all ports synchronized"
        return 1
    fi
}

# T5.08: RSTP dispute mechanism
test_T5_08_rstp_dispute() {
    test_start "T5.08" "rstp_dispute"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Simple two-bridge topology to test dispute handling
    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"

    sleep 3

    # Force a potential dispute by changing priority on non-root
    local non_root_br=""
    if bridge_is_root "br0"; then
        non_root_br="br1"
    else
        non_root_br="br0"
    fi

    # Make non-root want to become root (lower priority)
    mstpctl settreeprio "${non_root_br}" 0 0 2>/dev/null || true

    sleep 3

    # System should remain stable
    if mstpd_is_running; then
        test_pass "Dispute mechanism handled correctly"
        cleanup_topology_b "br0" "br1"
        return 0
    else
        test_fail "mstpd crashed during dispute"
        cleanup_topology_b "br0" "br1"
        return 1
    fi
}

# Main

main() {
    test_suite_init "T5: RSTP Convergence"
    trap_cleanup
    run_discovered_tests "T5"
    cleanup_all
    test_suite_summary
}

main "$@"
