#!/bin/bash
#
# T20: CLI (mstpctl) Tests
#
# Tests the mstpctl command-line interface.
#
# Copyright (C) 2026 Vincent Jardin, Free Mobile
# SPDX-License-Identifier: GPL-2.0-or-later
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/testlib.sh"

# Test Cases

# T20.01: showbridge command
test_T20_01_cli_showbridge() {
    test_start "T20.01" "cli_showbridge"

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

    wait_for_bridge "br0"

    # Test showbridge with specific bridge
    local output
    output=$(mstpctl showbridge br0 2>&1)

    if [[ "${output}" == *"br0"* ]]; then
        # Check for expected fields
        local has_fields=0
        if [[ "${output}" == *"enabled"* ]] || [[ "${output}" == *"bridge id"* ]] || [[ "${output}" == *"designated"* ]]; then
            has_fields=1
        fi

        if [[ ${has_fields} -eq 1 ]]; then
            test_pass "showbridge displays bridge information"
            return 0
        else
            test_fail "showbridge output missing expected fields"
            return 1
        fi
    fi

    test_fail "showbridge failed to display bridge info"
    return 1
}

# T20.02: showport command
test_T20_02_cli_showport() {
    test_start "T20.02" "cli_showport"

    # Ensure clean state
    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create bridge with ports
    setup_topology_a "br0" 2
    ip link set br0 type bridge stp_state 1
    sleep 0.5
    mstpctl addbridge br0 2>&1

    wait_for_bridge "br0"

    # Test showport for all ports
    local output
    output=$(mstpctl showport br0 2>&1)

    if [[ "${output}" == *"br0-p1"* ]] && [[ "${output}" == *"br0-p2"* ]]; then
        test_pass "showport displays all ports"
        cleanup_topology_a "br0" 2
        return 0
    fi

    # Test showport for specific port
    output=$(mstpctl showport br0 br0-p1 2>&1)

    if [[ "${output}" == *"br0-p1"* ]]; then
        test_pass "showport displays specific port"
        cleanup_topology_a "br0" 2
        return 0
    fi

    test_fail "showport failed to display port info"
    cleanup_topology_a "br0" 2
    return 1
}

# T20.03: showportdetail command
test_T20_03_cli_showportdetail() {
    test_start "T20.03" "cli_showportdetail"

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

    wait_for_bridge "br0"

    # Test showportdetail
    local output
    output=$(mstpctl showportdetail br0 veth0 2>&1)

    if [[ "${output}" == *"veth0"* ]]; then
        # Check for detailed fields
        local detail_found=0
        for field in "enabled" "role" "state" "path cost" "admin-edge" "auto-edge" "point-to-point"; do
            if [[ "${output}" == *"${field}"* ]]; then
                detail_found=1
                break
            fi
        done

        if [[ ${detail_found} -eq 1 ]]; then
            test_pass "showportdetail displays detailed port information"
            veth_delete "veth0"
            return 0
        else
            test_fail "showportdetail missing expected detail fields"
            veth_delete "veth0"
            return 1
        fi
    fi

    test_fail "showportdetail failed"
    veth_delete "veth0"
    return 1
}

# T20.04: showtree command
test_T20_04_cli_showtree() {
    test_start "T20.04" "cli_showtree"

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

    wait_for_bridge "br0"

    # Test showtree for CIST (mstid 0)
    local output
    output=$(mstpctl showtree br0 0 2>&1)

    # showtree should show CIST info or indicate it's the default tree
    if [[ "${output}" == *"br0"* ]] || [[ "${output}" == *"CIST"* ]] || [[ "${output}" == *"0"* ]]; then
        test_pass "showtree displays tree information"
        return 0
    fi

    test_fail "showtree did not display tree information"
    return 1
}

# T20.05: Set commands
test_T20_05_cli_set_commands() {
    test_start "T20.05" "cli_set_commands"

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

    wait_for_bridge "br0"

    local all_passed=1
    local actual

    # Test setforcevers and read back
    mstpctl setforcevers br0 rstp
    actual=$(mstpctl_get showbridge br0 force-protocol-version)
    if [[ "${actual}" != "rstp" ]]; then
        log_debug "setforcevers: expected rstp, got ${actual}"
        all_passed=0
    fi

    # Timer values must satisfy: 2*(fdelay-1) >= maxage >= 2*(hello+1)
    # Hello is fixed at 2 (IEEE 802.1Q), so: 2*(fdelay-1) >= maxage >= 6
    # Use: maxage=12, fdelay=8 → 2*(8-1)=14 >= 12 >= 6 ✓
    # Order: lower maxage first (default 20), then fdelay.

    # Test setmaxage and read back (set first — default fdelay=15, 2*(15-1)=28 >= 12 ✓)
    mstpctl setmaxage br0 12
    actual=$(mstpctl_get showbridge br0 max-age)
    if [[ "${actual}" != "12" ]]; then
        log_debug "setmaxage: expected 12, got ${actual}"
        all_passed=0
    fi

    # Test setfdelay and read back (now maxage=12, 2*(8-1)=14 >= 12 ✓)
    mstpctl setfdelay br0 8
    actual=$(mstpctl_get showbridge br0 forward-delay)
    if [[ "${actual}" != "8" ]]; then
        log_debug "setfdelay: expected 8, got ${actual}"
        all_passed=0
    fi

    # Test sethello — IEEE 802.1Q mandates hello time = 2, so only 2 is accepted
    mstpctl sethello br0 2
    actual=$(mstpctl_get showbridge br0 hello-time)
    if [[ "${actual}" != "2" ]]; then
        log_debug "sethello: expected 2, got ${actual}"
        all_passed=0
    fi

    # Test setportadminedge and read back
    mstpctl setportadminedge br0 veth0 yes
    actual=$(mstpctl_get showportdetail br0 veth0 admin-edge-port)
    if [[ "${actual}" != "yes" ]]; then
        log_debug "setportadminedge: expected yes, got ${actual}"
        all_passed=0
    fi

    # Test setportautoedge and read back
    mstpctl setportautoedge br0 veth0 yes
    actual=$(mstpctl_get showportdetail br0 veth0 auto-edge-port)
    if [[ "${actual}" != "yes" ]]; then
        log_debug "setportautoedge: expected yes, got ${actual}"
        all_passed=0
    fi

    # Test setbpduguard and read back
    mstpctl setbpduguard br0 veth0 yes
    actual=$(mstpctl_get showportdetail br0 veth0 bpdu-guard-port)
    if [[ "${actual}" != "yes" ]]; then
        log_debug "setbpduguard: expected yes, got ${actual}"
        all_passed=0
    fi

    veth_delete "veth0"

    if [[ ${all_passed} -eq 1 ]]; then
        test_pass "All set commands applied and verified"
        return 0
    else
        test_fail "Some set commands not applied correctly"
        return 1
    fi
}

# T20.06: Commands without daemon
test_T20_06_cli_no_daemon() {
    test_start "T20.06" "cli_no_daemon"

    # Ensure mstpd is NOT running
    mstpd_stop
    sleep 0.5

    # Try to run a command
    local output
    output=$(mstpctl showbridge 2>&1)

    # Should return an error
    if [[ "${output}" == *"error"* ]] || [[ "${output}" == *"connect"* ]] || [[ "${output}" == *"failed"* ]] || [[ "${output}" == *"refused"* ]]; then
        test_pass "mstpctl returns error when daemon not running"
        return 0
    fi

    # Check return code
    mstpctl showbridge > /dev/null 2>&1
    local rc=$?

    if [[ ${rc} -ne 0 ]]; then
        test_pass "mstpctl returns non-zero exit code when daemon not running"
        return 0
    fi

    test_fail "mstpctl did not indicate daemon is not running"
    return 1
}

# T20.07: Help output
test_T20_07_cli_help() {
    test_start "T20.07" "cli_help"

    # Test help/usage output
    local output
    output=$("${MSTPCTL_BIN}" 2>&1 || true)

    # Should show usage information
    if [[ "${output}" == *"Usage"* ]] || [[ "${output}" == *"usage"* ]] || [[ "${output}" == *"command"* ]] || [[ "${output}" == *"showbridge"* ]]; then
        test_pass "mstpctl shows usage information"
        return 0
    fi

    # Try with -h flag
    output=$("${MSTPCTL_BIN}" -h 2>&1 || true)

    if [[ "${output}" == *"Usage"* ]] || [[ "${output}" == *"usage"* ]] || [[ "${output}" == *"help"* ]]; then
        test_pass "mstpctl -h shows help"
        return 0
    fi

    # Try with --help
    output=$("${MSTPCTL_BIN}" --help 2>&1 || true)

    if [[ "${output}" == *"Usage"* ]] || [[ "${output}" == *"usage"* ]]; then
        test_pass "mstpctl --help shows help"
        return 0
    fi

    test_fail "mstpctl does not show usage information"
    return 1
}

# T20.08: Invalid commands handling
test_T20_08_cli_invalid() {
    test_start "T20.08" "cli_invalid_commands"

    # Start daemon for this test
    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    # Create bridge
    bridge_create "br0" 1
    sleep 0.5
    mstpctl addbridge br0 2>&1

    local all_ok=1

    # Test invalid bridge name — should fail or return empty
    local output
    output=$(mstpctl showbridge nonexistent_bridge 2>&1)
    local rc=$?
    if [[ ${rc} -eq 0 ]] && [[ -n "${output}" ]] && [[ "${output}" != *"error"* ]]; then
        log_debug "Invalid bridge not rejected (rc=${rc})"
        all_ok=0
    fi

    # Test invalid port name
    output=$(mstpctl showport br0 nonexistent_port 2>&1)
    rc=$?
    if [[ ${rc} -eq 0 ]] && [[ -n "${output}" ]] && [[ "${output}" != *"error"* ]]; then
        log_debug "Invalid port not rejected (rc=${rc})"
        all_ok=0
    fi

    # Test invalid command — should return non-zero or show usage
    output=$("${MSTPCTL_BIN}" invalidcommand 2>&1)
    rc=$?
    if [[ ${rc} -eq 0 ]]; then
        log_debug "Invalid command not rejected (rc=${rc})"
        all_ok=0
    fi

    # Daemon must not crash
    if ! mstpd_is_running; then
        test_fail "mstpd crashed on invalid command"
        return 1
    fi

    if [[ ${all_ok} -eq 1 ]]; then
        test_pass "Invalid commands properly rejected"
        return 0
    else
        test_fail "Some invalid commands not properly rejected"
        return 1
    fi
}

# Main

main() {
    test_suite_init "T20: CLI (mstpctl)"
    trap_cleanup
    run_discovered_tests "T20"
    cleanup_all
    test_suite_summary
}

main "$@"
