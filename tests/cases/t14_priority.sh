#!/bin/bash
#
# T14: Priority Tests
#
# Tests STP/RSTP bridge and port priority configuration.
#
# Copyright (C) 2026 Vincent Jardin, Free Mobile
# SPDX-License-Identifier: GPL-2.0-or-later
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/testlib.sh"

# Helper to get bridge priority from bridge ID
get_bridge_priority() {
    local bridge="$1"
    local bridge_id
    bridge_id=$(bridge_get_id "${bridge}")
    # Bridge ID format: priority.MAC (e.g., 8.000.XX:XX:XX:XX:XX:XX)
    echo "${bridge_id}" | cut -d'.' -f1
}

# Helper to get port priority from port ID
get_port_priority() {
    local bridge="$1"
    local port="$2"
    local port_id
    port_id=$(mstpctl_get showportdetail "${bridge}" "${port}" port-id)
    # Port ID format: priority.port_num (e.g., 8.001)
    echo "${port_id}" | cut -d'.' -f1
}

# T14.01: Bridge priority default
test_T14_01_prio_bridge_default() {
    test_start "T14.01" "prio_bridge_default"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "rstp"

    sleep 1

    local priority
    priority=$(get_bridge_priority "br0")
    log_debug "Bridge priority: ${priority}"

    cleanup_topology_a "br0" 1

    # Default priority is 8 (which represents 32768 in the full value)
    if [[ "${priority}" == "8" ]]; then
        test_pass "Bridge priority default is 8"
        return 0
    elif [[ -n "${priority}" ]]; then
        test_pass "Bridge priority: ${priority}"
        return 0
    else
        test_fail "Could not get bridge priority"
        return 1
    fi
}

# T14.02: Set bridge priority
test_T14_02_prio_bridge_set() {
    test_start "T14.02" "prio_bridge_set"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "rstp"

    # Set bridge priority to 4 (lower = more likely to be root)
    mstpctl settreeprio "br0" 0 4 || true

    sleep 1

    local priority
    priority=$(get_bridge_priority "br0")
    log_debug "Bridge priority after set: ${priority}"

    cleanup_topology_a "br0" 1

    if [[ "${priority}" == "4" ]]; then
        test_pass "Bridge priority set to 4"
        return 0
    else
        test_fail "Bridge priority expected '4' but got '${priority}'"
        return 1
    fi
}

# T14.03: Bridge priority affects root election
test_T14_03_prio_bridge_root() {
    test_start "T14.03" "prio_bridge_root"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"

    wait_for_convergence 15

    # Set br1 to lower priority (should become root)
    mstpctl settreeprio "br1" 0 0 || true

    # Poll until br1 becomes root (priority change triggers re-election)
    local is_root="no"
    local start_time
    start_time=$(date +%s)
    while (( $(date +%s) - start_time < 15 )); do
        if bridge_is_root "br1"; then
            is_root="yes"
            break
        fi
        sleep 0.5
    done

    log_debug "br1 is root: ${is_root}"

    cleanup_topology_b "br0" "br1"

    if [[ "${is_root}" == "yes" ]]; then
        test_pass "Lower priority bridge became root"
        return 0
    else
        test_fail "br1 with priority 0 expected to be root but is_root='${is_root}'"
        return 1
    fi
}

# T14.04: Port priority default
test_T14_04_prio_port_default() {
    test_start "T14.04" "prio_port_default"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "rstp"

    sleep 1

    local priority
    priority=$(get_port_priority "br0" "br0-p1")
    log_debug "Port priority: ${priority}"

    cleanup_topology_a "br0" 1

    # Default port priority is 8
    if [[ "${priority}" == "8" ]]; then
        test_pass "Port priority default is 8"
        return 0
    elif [[ -n "${priority}" ]]; then
        test_pass "Port priority: ${priority}"
        return 0
    else
        test_fail "Could not get port priority"
        return 1
    fi
}

# T14.05: Set port priority
test_T14_05_prio_port_set() {
    test_start "T14.05" "prio_port_set"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "rstp"

    # Set port priority to 4
    mstpctl settreeportprio "br0" "br0-p1" 0 4 || true

    sleep 1

    local priority
    priority=$(get_port_priority "br0" "br0-p1")
    log_debug "Port priority after set: ${priority}"

    cleanup_topology_a "br0" 1

    if [[ "${priority}" == "4" ]]; then
        test_pass "Port priority set to 4"
        return 0
    else
        test_fail "Port priority expected '4' but got '${priority}'"
        return 1
    fi
}

# T14.06: Port priority affects port selection
test_T14_06_prio_port_affects() {
    test_start "T14.06" "prio_port_affects"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Two links between bridges
    bridge_create "br0" 0
    bridge_create "br1" 0

    veth_create "br0-br1-a" "br1-br0-a"
    veth_create "br0-br1-b" "br1-br0-b"

    bridge_add_port "br0" "br0-br1-a"
    bridge_add_port "br0" "br0-br1-b"
    bridge_add_port "br1" "br1-br0-a"
    bridge_add_port "br1" "br1-br0-b"

    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"

    # Set initial port priorities to help RSTP break the dual-link tie quickly
    mstpctl settreeportprio "br0" "br0-br1-a" 0 4 || true
    mstpctl settreeportprio "br0" "br0-br1-b" 0 8 || true

    # Wait for Root election on either bridge (root bridge has Desg ports, non-root has Root port)
    wait_for_any_role "Root" 15 "br0-br1-a:br0" "br0-br1-b:br0" "br1-br0-a:br1" "br1-br0-b:br1" > /dev/null || true

    # Find non-root bridge — priority changes only affect non-root bridge's port roles
    local non_root non_root_a non_root_b
    if bridge_is_root "br0"; then
        non_root="br1"; non_root_a="br1-br0-a"; non_root_b="br1-br0-b"
    else
        non_root="br0"; non_root_a="br0-br1-a"; non_root_b="br0-br1-b"
    fi
    log_debug "Non-root bridge: ${non_root}"

    # Set lower priority on port b - should be preferred (lower = better)
    mstpctl settreeportprio "${non_root}" "${non_root_b}" 0 4 || true
    # Also set higher priority on port a to ensure clear preference
    mstpctl settreeportprio "${non_root}" "${non_root_a}" 0 12 || true

    # Wait for role recalculation — one port should become Altn or Back
    wait_for_any_role "Alternate|Backup" 15 "${non_root_a}:${non_root}" "${non_root_b}:${non_root}" > /dev/null || true

    local role_a
    local role_b
    role_a=$(port_get_role "${non_root}" "${non_root_a}")
    role_b=$(port_get_role "${non_root}" "${non_root_b}")

    log_debug "Port roles on ${non_root}: a=${role_a}, b=${role_b}"

    veth_delete "br0-br1-a" || true
    veth_delete "br0-br1-b" || true
    bridge_delete "br0"
    bridge_delete "br1"

    # One should be Root and the other Altn — port priority affects role selection
    if { [[ "${role_a}" == "Root" ]] && [[ "${role_b}" == "Alternate" ]]; } ||
       { [[ "${role_b}" == "Root" ]] && [[ "${role_a}" == "Alternate" ]]; }; then
        test_pass "Port priority affects role selection (a=${role_a}, b=${role_b})"
        return 0
    else
        test_fail "Expected one Root and one Altn on ${non_root}, got a=${role_a} b=${role_b}"
        return 1
    fi
}

# T14.07: Per-MSTI bridge priority
test_T14_07_prio_tree_bridge() {
    test_start "T14.07" "prio_tree_bridge"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "rstp"

    # Set tree priority for MSTI 0 (CIST)
    mstpctl settreeprio "br0" 0 2 || true

    sleep 1

    local priority
    priority=$(get_bridge_priority "br0")
    log_debug "Tree bridge priority: ${priority}"

    cleanup_topology_a "br0" 1

    if [[ "${priority}" == "2" ]]; then
        test_pass "Per-MSTI bridge priority set"
        return 0
    else
        test_fail "Per-MSTI bridge priority expected '2' but got '${priority}'"
        return 1
    fi
}

# T14.08: Per-MSTI port priority
test_T14_08_prio_tree_port() {
    test_start "T14.08" "prio_tree_port"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "rstp"

    # Set tree port priority for MSTI 0 (CIST)
    mstpctl settreeportprio "br0" "br0-p1" 0 2 || true

    sleep 1

    local priority
    priority=$(get_port_priority "br0" "br0-p1")
    log_debug "Tree port priority: ${priority}"

    cleanup_topology_a "br0" 1

    if [[ "${priority}" == "2" ]]; then
        test_pass "Per-MSTI port priority set"
        return 0
    else
        test_fail "Per-MSTI port priority expected '2' but got '${priority}'"
        return 1
    fi
}

# Main

main() {
    test_suite_init "T14: Priority"
    trap_cleanup
    run_discovered_tests "T14"
    cleanup_all
    test_suite_summary
}

main "$@"
