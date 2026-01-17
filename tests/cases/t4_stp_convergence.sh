#!/bin/bash
#
# T4: STP Convergence Tests
#
# Tests basic STP protocol operation and convergence.
#
# Copyright (C) 2026 Vincent Jardin, Free Mobile
# SPDX-License-Identifier: GPL-2.0-or-later
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/testlib.sh"

# T4.01: Root bridge election
test_T4_01_stp_root_election() {
    test_start "T4.01" "stp_root_election"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create two bridges - br0 with lower MAC should become root
    setup_topology_b "br0" "br1"

    # Enable STP on both bridges (force STP mode, not RSTP)
    bridge_enable_stp "br0" "stp"
    bridge_enable_stp "br1" "stp"

    # Wait for convergence
    sleep 5

    # Get bridge IDs
    local br0_id
    local br1_id
    br0_id=$(bridge_get_id "br0")
    br1_id=$(bridge_get_id "br1")

    log_debug "br0 ID: ${br0_id}, br1 ID: ${br1_id}"

    # One of them must be root
    if bridge_is_root "br0" || bridge_is_root "br1"; then
        test_pass "Root bridge elected successfully"
        cleanup_topology_b "br0" "br1"
        return 0
    else
        test_fail "No root bridge elected"
        cleanup_topology_b "br0" "br1"
        return 1
    fi
}

# T4.02: Single bridge is always root
test_T4_02_stp_single_bridge() {
    test_start "T4.02" "stp_single_bridge"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create single bridge with ports
    setup_topology_a "br0" 2

    # Enable STP
    bridge_enable_stp "br0" "stp"

    sleep 2

    # Single bridge must be root
    if bridge_is_root "br0"; then
        test_pass "Single bridge is root"
        cleanup_topology_a "br0" 2
        return 0
    else
        test_fail "Single bridge is not root"
        cleanup_topology_a "br0" 2
        return 1
    fi
}

# T4.03: Two bridges, one link - roles assigned
test_T4_03_stp_two_bridges() {
    test_start "T4.03" "stp_two_bridges"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "stp"
    bridge_enable_stp "br1" "stp"

    # Wait for convergence
    sleep 5

    # Check port roles
    local br0_port_role
    local br1_port_role
    br0_port_role=$(port_get_role "br0" "br0-br1")
    br1_port_role=$(port_get_role "br1" "br1-br0")

    log_debug "br0-br1 role: ${br0_port_role}, br1-br0 role: ${br1_port_role}"

    # One should be Designated (Desg), one should be Root
    if [[ "${br0_port_role}" == "Desg" && "${br1_port_role}" == "Root" ]] ||
       [[ "${br0_port_role}" == "Root" && "${br1_port_role}" == "Desg" ]]; then
        test_pass "Port roles assigned correctly (Desg/Root)"
        cleanup_topology_b "br0" "br1"
        return 0
    fi

    test_fail "Port roles not assigned correctly: br0=${br0_port_role}, br1=${br1_port_role}"
    cleanup_topology_b "br0" "br1"
    return 1
}

# T4.04: Triangle topology - one port blocked
test_T4_04_stp_triangle() {
    test_start "T4.04" "stp_triangle"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_c
    bridge_enable_stp "br0" "stp"
    bridge_enable_stp "br1" "stp"
    bridge_enable_stp "br2" "stp"

    # Wait for STP convergence (longer for STP)
    sleep 10

    # Count blocked ports (Alternate role = blocked in STP terms)
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

    # In a triangle, at least one port should be blocked to prevent loop
    if [[ ${blocked} -ge 1 ]]; then
        test_pass "Triangle topology: ${blocked} port(s) blocked"
        cleanup_topology_c
        return 0
    else
        test_fail "No ports blocked in triangle - loop not prevented"
        cleanup_topology_c
        return 1
    fi
}

# T4.05: Square topology - dual loop prevented
test_T4_05_stp_square() {
    test_start "T4.05" "stp_square"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create square topology: br0-br1-br3-br2-br0
    bridge_create "br0" 0
    bridge_create "br1" 0
    bridge_create "br2" 0
    bridge_create "br3" 0

    veth_create "br0-br1" "br1-br0"
    bridge_add_port "br0" "br0-br1"
    bridge_add_port "br1" "br1-br0"

    veth_create "br1-br3" "br3-br1"
    bridge_add_port "br1" "br1-br3"
    bridge_add_port "br3" "br3-br1"

    veth_create "br3-br2" "br2-br3"
    bridge_add_port "br3" "br3-br2"
    bridge_add_port "br2" "br2-br3"

    veth_create "br2-br0" "br0-br2"
    bridge_add_port "br2" "br2-br0"
    bridge_add_port "br0" "br0-br2"

    bridge_enable_stp "br0" "stp"
    bridge_enable_stp "br1" "stp"
    bridge_enable_stp "br2" "stp"
    bridge_enable_stp "br3" "stp"

    # Wait for convergence
    sleep 10

    # Count blocked ports
    local blocked=0
    local role

    for port in br0-br1 br0-br2 br1-br0 br1-br3 br2-br0 br2-br3 br3-br1 br3-br2; do
        local bridge="${port%%-*}"
        role=$(port_get_role "${bridge}" "${port}")
        if [[ "${role}" == "Altn" ]] || [[ "${role}" == "Back" ]]; then
            ((blocked++))
        fi
    done

    # Cleanup
    veth_delete "br0-br1" 2>/dev/null || true
    veth_delete "br1-br3" 2>/dev/null || true
    veth_delete "br3-br2" 2>/dev/null || true
    veth_delete "br2-br0" 2>/dev/null || true
    bridge_delete "br0"
    bridge_delete "br1"
    bridge_delete "br2"
    bridge_delete "br3"

    # In a square, at least one port should be blocked
    if [[ ${blocked} -ge 1 ]]; then
        test_pass "Square topology: ${blocked} port(s) blocked"
        return 0
    else
        test_fail "No ports blocked in square - loop not prevented"
        return 1
    fi
}

# T4.06: Linear chain of bridges
test_T4_06_stp_linear() {
    test_start "T4.06" "stp_linear"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create linear chain: br0 - br1 - br2
    bridge_create "br0" 0
    bridge_create "br1" 0
    bridge_create "br2" 0

    veth_create "br0-br1" "br1-br0"
    bridge_add_port "br0" "br0-br1"
    bridge_add_port "br1" "br1-br0"

    veth_create "br1-br2" "br2-br1"
    bridge_add_port "br1" "br1-br2"
    bridge_add_port "br2" "br2-br1"

    bridge_enable_stp "br0" "stp"
    bridge_enable_stp "br1" "stp"
    bridge_enable_stp "br2" "stp"

    # Wait for convergence
    sleep 8

    # In a linear topology with no loops, all ports should be forwarding
    # (Root or Designated, no Alternate)
    local all_forwarding=1
    local role

    for port in br0-br1 br1-br0 br1-br2 br2-br1; do
        local bridge="${port%%-*}"
        role=$(port_get_role "${bridge}" "${port}")
        log_debug "Port ${port} role: ${role}"
        if [[ "${role}" == "Altn" ]] || [[ "${role}" == "Back" ]]; then
            all_forwarding=0
        fi
    done

    # Cleanup
    veth_delete "br0-br1" 2>/dev/null || true
    veth_delete "br1-br2" 2>/dev/null || true
    bridge_delete "br0"
    bridge_delete "br1"
    bridge_delete "br2"

    if [[ ${all_forwarding} -eq 1 ]]; then
        test_pass "Linear topology: all ports forwarding (no loops)"
        return 0
    else
        test_fail "Linear topology has blocked ports (unexpected)"
        return 1
    fi
}

# T4.07: Measure convergence time
test_T4_07_stp_convergence_time() {
    test_start "T4.07" "stp_convergence_time"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"

    local start_time
    start_time=$(date +%s)

    bridge_enable_stp "br0" "stp"
    bridge_enable_stp "br1" "stp"

    # Wait for forwarding state (state 3)
    local converged=0
    local elapsed=0
    while [[ ${elapsed} -lt 60 ]]; do
        local state0
        local state1
        state0=$(port_get_state "br0-br1")
        state1=$(port_get_state "br1-br0")

        if [[ "${state0}" == "3" ]] && [[ "${state1}" == "3" ]]; then
            converged=1
            break
        fi
        sleep 1
        elapsed=$(($(date +%s) - start_time))
    done

    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))

    cleanup_topology_b "br0" "br1"

    if [[ ${converged} -eq 1 ]]; then
        # STP convergence should be < 50 seconds
        if [[ ${duration} -lt 50 ]]; then
            test_pass "STP converged in ${duration} seconds"
            return 0
        else
            test_fail "STP convergence too slow: ${duration} seconds"
            return 1
        fi
    else
        test_fail "STP did not converge within 60 seconds"
        return 1
    fi
}

# T4.08: Root bridge failure and new election
test_T4_08_stp_root_failure() {
    test_start "T4.08" "stp_root_failure"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create triangle topology
    setup_topology_c
    bridge_enable_stp "br0" "stp"
    bridge_enable_stp "br1" "stp"
    bridge_enable_stp "br2" "stp"

    # Wait for initial convergence
    sleep 10

    # Find current root
    local root_bridge=""
    for br in br0 br1 br2; do
        if bridge_is_root "${br}"; then
            root_bridge="${br}"
            break
        fi
    done

    if [[ -z "${root_bridge}" ]]; then
        test_fail "No root bridge found initially"
        cleanup_topology_c
        return 1
    fi

    log_debug "Initial root bridge: ${root_bridge}"

    # Simulate root failure by bringing it down
    ip link set "${root_bridge}" down

    # Wait for new root election
    sleep 15

    # Check that a new root was elected from remaining bridges
    local new_root=""
    for br in br0 br1 br2; do
        if [[ "${br}" != "${root_bridge}" ]]; then
            if bridge_is_root "${br}"; then
                new_root="${br}"
                break
            fi
        fi
    done

    # Restore for cleanup
    ip link set "${root_bridge}" up 2>/dev/null || true
    cleanup_topology_c

    if [[ -n "${new_root}" ]]; then
        test_pass "New root elected (${root_bridge} -> ${new_root})"
        return 0
    else
        test_fail "No new root elected after failure"
        return 1
    fi
}

# Main

main() {
    test_suite_init "T4: STP Convergence"
    trap_cleanup
    run_discovered_tests "T4"
    cleanup_all
    test_suite_summary
}

main "$@"
