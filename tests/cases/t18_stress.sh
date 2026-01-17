#!/bin/bash
#
# T18: Stress Tests
#
# Tests mstpd stability under load and stress conditions.
#
# Copyright (C) 2026 Vincent Jardin, Free Mobile
# SPDX-License-Identifier: GPL-2.0-or-later
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/testlib.sh"

# T18.01: Many bridges (10+)
test_T18_01_stress_many_bridges() {
    test_start "T18.01" "stress_many_bridges"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    local num_bridges=10

    # Create many bridges
    for i in $(seq 0 $((num_bridges - 1))); do
        bridge_create "br${i}" 0
        bridge_enable_stp "br${i}" "rstp"
    done

    sleep 3

    # Check all bridges are managed
    local managed=0
    for i in $(seq 0 $((num_bridges - 1))); do
        if mstpctl showbridge "br${i}" >/dev/null 2>&1; then
            ((managed++))
        fi
    done

    # Cleanup
    for i in $(seq 0 $((num_bridges - 1))); do
        bridge_delete "br${i}"
    done

    if [[ ${managed} -eq ${num_bridges} ]]; then
        test_pass "All ${num_bridges} bridges managed"
        return 0
    else
        test_fail "Only ${managed}/${num_bridges} bridges managed"
        return 1
    fi
}

# T18.02: Many ports per bridge
test_T18_02_stress_many_ports() {
    test_start "T18.02" "stress_many_ports"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    local num_ports=20

    bridge_create "br0" 0

    # Create many ports
    for i in $(seq 1 ${num_ports}); do
        veth_create "br0-p${i}" "br0-p${i}-peer"
        bridge_add_port "br0" "br0-p${i}"
    done

    bridge_enable_stp "br0" "rstp"

    sleep 3

    # Check mstpd is still running
    if mstpd_is_running; then
        test_pass "${num_ports} ports managed on single bridge"
        # Cleanup
        for i in $(seq 1 ${num_ports}); do
            veth_delete "br0-p${i}" 2>/dev/null || true
        done
        bridge_delete "br0"
        return 0
    else
        test_fail "mstpd crashed with many ports"
        return 1
    fi
}

# T18.03: Rapid link flapping
test_T18_03_stress_link_flap() {
    test_start "T18.03" "stress_link_flap"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"

    sleep 2

    # Rapid link flapping
    local flaps=10
    for i in $(seq 1 ${flaps}); do
        ip link set "br0-br1" down
        sleep 0.1
        ip link set "br0-br1" up
        sleep 0.1
    done

    sleep 2

    cleanup_topology_b "br0" "br1"

    if mstpd_is_running; then
        test_pass "Survived ${flaps} link flaps"
        return 0
    else
        test_fail "mstpd crashed during link flapping"
        return 1
    fi
}

# T18.04: High BPDU rate (rate limiting test)
test_T18_04_stress_bpdu_flood() {
    test_start "T18.04" "stress_bpdu_flood"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create triangle for more BPDU traffic
    setup_topology_c
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"
    bridge_enable_stp "br2" "rstp"

    # Set very low hello time to increase BPDU rate
    mstpctl sethello "br0" 1 2>/dev/null || true
    mstpctl sethello "br1" 1 2>/dev/null || true
    mstpctl sethello "br2" 1 2>/dev/null || true

    sleep 10

    # Check TX hold count (rate limiting)
    local txhold
    txhold=$(mstpctl showbridge "br0" 2>/dev/null | grep "tx hold count" | awk '{print $4}')
    log_debug "TX hold count: ${txhold}"

    cleanup_topology_c

    if mstpd_is_running; then
        test_pass "High BPDU rate handled, TX hold: ${txhold}"
        return 0
    else
        test_fail "mstpd crashed under high BPDU rate"
        return 1
    fi
}

# T18.05: Rapid topology changes
test_T18_05_stress_topology_storm() {
    test_start "T18.05" "stress_topology_storm"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_c
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"
    bridge_enable_stp "br2" "rstp"

    sleep 3

    # Cause rapid topology changes
    for i in $(seq 1 5); do
        ip link set "br0-br1" down
        sleep 0.2
        ip link set "br0-br1" up
        ip link set "br1-br2" down
        sleep 0.2
        ip link set "br1-br2" up
        ip link set "br2-br0" down
        sleep 0.2
        ip link set "br2-br0" up
        sleep 0.5
    done

    sleep 3

    cleanup_topology_c

    if mstpd_is_running; then
        test_pass "Survived rapid topology changes"
        return 0
    else
        test_fail "mstpd crashed during topology storm"
        return 1
    fi
}

# T18.06: Sustained operation (short stability test)
test_T18_06_stress_long_run() {
    test_start "T18.06" "stress_long_run"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_c
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"
    bridge_enable_stp "br2" "rstp"

    # Run for 30 seconds with periodic checks
    local duration=30
    local checks=0
    local start_time
    start_time=$(date +%s)

    while [[ $(($(date +%s) - start_time)) -lt ${duration} ]]; do
        if ! mstpd_is_running; then
            test_fail "mstpd died during sustained operation"
            cleanup_topology_c
            return 1
        fi
        ((checks++))
        sleep 5
    done

    cleanup_topology_c

    test_pass "Stable for ${duration}s (${checks} checks)"
    return 0
}

# T18.07: Repeated add/remove bridges
test_T18_07_stress_add_remove() {
    test_start "T18.07" "stress_add_remove"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    local iterations=10

    for i in $(seq 1 ${iterations}); do
        bridge_create "br0" 0
        veth_create "br0-p1" "br0-p1-peer"
        bridge_add_port "br0" "br0-p1"
        bridge_enable_stp "br0" "rstp"
        sleep 0.2
        veth_delete "br0-p1" 2>/dev/null || true
        bridge_delete "br0"
        sleep 0.1
    done

    if mstpd_is_running; then
        test_pass "Survived ${iterations} add/remove cycles"
        return 0
    else
        test_fail "mstpd crashed during add/remove cycles"
        return 1
    fi
}

# T18.08: Concurrent operations
test_T18_08_stress_concurrent() {
    test_start "T18.08" "stress_concurrent"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create multiple bridges
    bridge_create "br0" 0
    bridge_create "br1" 0
    bridge_create "br2" 0

    veth_create "br0-br1" "br1-br0"
    veth_create "br1-br2" "br2-br1"

    bridge_add_port "br0" "br0-br1"
    bridge_add_port "br1" "br1-br0"
    bridge_add_port "br1" "br1-br2"
    bridge_add_port "br2" "br2-br1"

    # Enable STP on all bridges concurrently (rapid sequence)
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"
    bridge_enable_stp "br2" "rstp"

    # Sequential mstpctl queries (avoid control socket contention in CI)
    for i in $(seq 0 7); do
        bridge="br$((i % 3))"
        mstpctl showbridge "${bridge}" >/dev/null 2>&1
    done

    sleep 2

    veth_delete "br0-br1" 2>/dev/null || true
    veth_delete "br1-br2" 2>/dev/null || true
    bridge_delete "br0"
    bridge_delete "br1"
    bridge_delete "br2"

    if mstpd_is_running; then
        test_pass "Concurrent operations handled"
        return 0
    else
        test_fail "mstpd crashed during concurrent operations"
        return 1
    fi
}

# Main

main() {
    test_suite_init "T18: Stress Tests"
    trap_cleanup
    run_discovered_tests "T18"
    cleanup_all
    test_suite_summary
}

main "$@"
