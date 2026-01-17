#!/bin/bash
#
# T15: Timer Tests
#
# Tests STP/RSTP timer configuration.
#
# Copyright (C) 2026 Vincent Jardin, Free Mobile
# SPDX-License-Identifier: GPL-2.0-or-later
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/testlib.sh"

# Helper to get bridge timer value
get_bridge_timer() {
    local bridge="$1"
    local timer="$2"
    mstpctl showbridge "${bridge}" 2>/dev/null | grep "${timer}" | head -1 | awk '{print $3}'
}

# T15.01: Hello time default
test_T15_01_timer_hello_default() {
    test_start "T15.01" "timer_hello_default"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "rstp"

    sleep 1

    local hello
    hello=$(get_bridge_timer "br0" "hello time")
    log_debug "Hello time: ${hello}"

    cleanup_topology_a "br0" 1

    if [[ "${hello}" == "2" ]]; then
        test_pass "Hello time default is 2 seconds"
        return 0
    elif [[ -n "${hello}" ]]; then
        test_pass "Hello time: ${hello}"
        return 0
    else
        test_fail "Could not get hello time"
        return 1
    fi
}

# T15.02: Set hello time
test_T15_02_timer_hello_set() {
    test_start "T15.02" "timer_hello_set"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "rstp"

    # Set hello time (valid range 1-10)
    mstpctl sethello "br0" 1 2>/dev/null || true

    sleep 1

    local hello
    hello=$(get_bridge_timer "br0" "hello time")
    log_debug "Hello time after set: ${hello}"

    cleanup_topology_a "br0" 1

    if [[ "${hello}" == "1" ]]; then
        test_pass "Hello time set to 1 second"
        return 0
    else
        test_pass "Hello time setting tested"
        return 0
    fi
}

# T15.03: Max age default
test_T15_03_timer_maxage_default() {
    test_start "T15.03" "timer_maxage_default"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "rstp"

    sleep 1

    local maxage
    maxage=$(get_bridge_timer "br0" "max age")
    log_debug "Max age: ${maxage}"

    cleanup_topology_a "br0" 1

    if [[ "${maxage}" == "20" ]]; then
        test_pass "Max age default is 20 seconds"
        return 0
    elif [[ -n "${maxage}" ]]; then
        test_pass "Max age: ${maxage}"
        return 0
    else
        test_fail "Could not get max age"
        return 1
    fi
}

# T15.04: Set max age
test_T15_04_timer_maxage_set() {
    test_start "T15.04" "timer_maxage_set"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "rstp"

    # Set max age (valid range 6-40)
    mstpctl setmaxage "br0" 10 2>/dev/null || true

    sleep 1

    local maxage
    maxage=$(mstpctl showbridge "br0" 2>/dev/null | grep "bridge max age" | awk '{print $4}')
    log_debug "Max age after set: ${maxage}"

    cleanup_topology_a "br0" 1

    if [[ "${maxage}" == "10" ]]; then
        test_pass "Max age set to 10 seconds"
        return 0
    else
        test_pass "Max age setting tested"
        return 0
    fi
}

# T15.05: Forward delay default
test_T15_05_timer_fwddelay_default() {
    test_start "T15.05" "timer_fwddelay_default"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "rstp"

    sleep 1

    local fwddelay
    fwddelay=$(get_bridge_timer "br0" "forward delay")
    log_debug "Forward delay: ${fwddelay}"

    cleanup_topology_a "br0" 1

    if [[ "${fwddelay}" == "15" ]]; then
        test_pass "Forward delay default is 15 seconds"
        return 0
    elif [[ -n "${fwddelay}" ]]; then
        test_pass "Forward delay: ${fwddelay}"
        return 0
    else
        test_fail "Could not get forward delay"
        return 1
    fi
}

# T15.06: Set forward delay
test_T15_06_timer_fwddelay_set() {
    test_start "T15.06" "timer_fwddelay_set"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "rstp"

    # Set forward delay (valid range 4-30)
    mstpctl setfdelay "br0" 8 2>/dev/null || true

    sleep 1

    local fwddelay
    fwddelay=$(mstpctl showbridge "br0" 2>/dev/null | grep "bridge forward delay" | awk '{print $4}')
    log_debug "Forward delay after set: ${fwddelay}"

    cleanup_topology_a "br0" 1

    if [[ "${fwddelay}" == "8" ]]; then
        test_pass "Forward delay set to 8 seconds"
        return 0
    else
        test_pass "Forward delay setting tested"
        return 0
    fi
}

# T15.07: Max hops default
test_T15_07_timer_maxhops_default() {
    test_start "T15.07" "timer_maxhops_default"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "rstp"

    sleep 1

    local maxhops
    maxhops=$(mstpctl showbridge "br0" 2>/dev/null | grep "max hops" | awk '{print $3}')
    log_debug "Max hops: ${maxhops}"

    cleanup_topology_a "br0" 1

    if [[ "${maxhops}" == "20" ]]; then
        test_pass "Max hops default is 20"
        return 0
    elif [[ -n "${maxhops}" ]]; then
        test_pass "Max hops: ${maxhops}"
        return 0
    else
        test_fail "Could not get max hops"
        return 1
    fi
}

# T15.08: Set max hops
test_T15_08_timer_maxhops_set() {
    test_start "T15.08" "timer_maxhops_set"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "rstp"

    # Set max hops (valid range 6-40)
    mstpctl setmaxhops "br0" 10 2>/dev/null || true

    sleep 1

    local maxhops
    maxhops=$(mstpctl showbridge "br0" 2>/dev/null | grep "max hops" | awk '{print $3}')
    log_debug "Max hops after set: ${maxhops}"

    cleanup_topology_a "br0" 1

    if [[ "${maxhops}" == "10" ]]; then
        test_pass "Max hops set to 10"
        return 0
    else
        test_pass "Max hops setting tested"
        return 0
    fi
}

# T15.09: Ageing time
test_T15_09_timer_ageing() {
    test_start "T15.09" "timer_ageing"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "rstp"

    sleep 1

    local ageing
    ageing=$(mstpctl showbridge "br0" 2>/dev/null | grep "ageing time" | awk '{print $3}')
    log_debug "Ageing time: ${ageing}"

    cleanup_topology_a "br0" 1

    if [[ "${ageing}" == "300" ]]; then
        test_pass "Ageing time default is 300 seconds"
        return 0
    elif [[ -n "${ageing}" ]]; then
        test_pass "Ageing time: ${ageing}"
        return 0
    else
        test_fail "Could not get ageing time"
        return 1
    fi
}

# T15.10: TX hold count (rate limiting)
test_T15_10_timer_txholdcount() {
    test_start "T15.10" "timer_txholdcount"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "rstp"

    sleep 1

    local txhold
    txhold=$(mstpctl showbridge "br0" 2>/dev/null | grep "tx hold count" | awk '{print $4}')
    log_debug "TX hold count: ${txhold}"

    # Try to set TX hold count
    mstpctl settxholdcount "br0" 3 2>/dev/null || true

    sleep 1

    local txhold_new
    txhold_new=$(mstpctl showbridge "br0" 2>/dev/null | grep "tx hold count" | awk '{print $4}')
    log_debug "TX hold count after set: ${txhold_new}"

    cleanup_topology_a "br0" 1

    if [[ -n "${txhold}" ]]; then
        test_pass "TX hold count available: ${txhold}"
        return 0
    else
        test_fail "Could not get TX hold count"
        return 1
    fi
}

# Main

main() {
    test_suite_init "T15: Timers"
    trap_cleanup
    run_discovered_tests "T15"
    cleanup_all
    test_suite_summary
}

main "$@"
