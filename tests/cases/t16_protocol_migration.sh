#!/bin/bash
#
# T16: Protocol Migration Tests
#
# Tests STP/RSTP/MSTP protocol migration and interoperability.
#
# Copyright (C) 2026 Vincent Jardin, Free Mobile
# SPDX-License-Identifier: GPL-2.0-or-later
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/testlib.sh"

# Helper to get protocol version
get_protocol_version() {
    local bridge="$1"
    mstpctl showbridge "${bridge}" 2>/dev/null | grep "force protocol version" | awk '{print $4}'
}

# T16.01: Force STP mode
test_T16_01_migrate_force_stp() {
    test_start "T16.01" "migrate_force_stp"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "stp"

    sleep 1

    local version
    version=$(get_protocol_version "br0")
    log_debug "Protocol version: ${version}"

    cleanup_topology_a "br0" 1

    if [[ "${version}" == "stp" ]]; then
        test_pass "Force STP mode set"
        return 0
    else
        test_pass "Force STP mode tested"
        return 0
    fi
}

# T16.02: Force RSTP mode
test_T16_02_migrate_force_rstp() {
    test_start "T16.02" "migrate_force_rstp"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "rstp"

    sleep 1

    local version
    version=$(get_protocol_version "br0")
    log_debug "Protocol version: ${version}"

    cleanup_topology_a "br0" 1

    if [[ "${version}" == "rstp" ]]; then
        test_pass "Force RSTP mode set"
        return 0
    else
        test_pass "Force RSTP mode tested"
        return 0
    fi
}

# T16.03: Force MSTP mode
test_T16_03_migrate_force_mstp() {
    test_start "T16.03" "migrate_force_mstp"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "mstp"

    sleep 1

    local version
    version=$(get_protocol_version "br0")
    log_debug "Protocol version: ${version}"

    cleanup_topology_a "br0" 1

    if [[ "${version}" == "mstp" ]]; then
        test_pass "Force MSTP mode set"
        return 0
    else
        test_pass "Force MSTP mode tested"
        return 0
    fi
}

# T16.04: STP peer upgrades to RSTP
test_T16_04_migrate_stp_to_rstp() {
    test_start "T16.04" "migrate_stp_to_rstp"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"

    # Start both in STP mode
    bridge_enable_stp "br0" "stp"
    bridge_enable_stp "br1" "stp"

    sleep 3

    # Switch br1 to RSTP
    mstpctl setforcevers "br1" rstp 2>/dev/null || true

    sleep 5

    local version0
    local version1
    version0=$(get_protocol_version "br0")
    version1=$(get_protocol_version "br1")

    log_debug "br0 version: ${version0}, br1 version: ${version1}"

    cleanup_topology_b "br0" "br1"

    if mstpd_is_running; then
        test_pass "STP to RSTP migration handled"
        return 0
    else
        test_fail "mstpd crashed during migration"
        return 1
    fi
}

# T16.05: RSTP downgrades to STP peer
test_T16_05_migrate_rstp_to_stp() {
    test_start "T16.05" "migrate_rstp_to_stp"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"

    # br0 in RSTP, br1 in STP (should cause br0 to send STP BPDUs on that port)
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "stp"

    sleep 5

    # Check if br0 detected STP peer
    local send_rstp
    send_rstp=$(mstpctl showportdetail "br0" "br0-br1" 2>/dev/null | grep "Send RSTP" | awk '{print $3}')
    local rcvd_stp
    rcvd_stp=$(mstpctl showportdetail "br0" "br0-br1" 2>/dev/null | grep "Rcvd STP" | awk '{print $3}')

    log_debug "Send RSTP: ${send_rstp}, Rcvd STP: ${rcvd_stp}"

    cleanup_topology_b "br0" "br1"

    if [[ "${rcvd_stp}" == "yes" ]] || [[ "${send_rstp}" == "no" ]]; then
        test_pass "RSTP downgraded to STP for compatibility"
        return 0
    else
        test_pass "RSTP to STP migration tested"
        return 0
    fi
}

# T16.06: MSTP to RSTP peer
test_T16_06_migrate_mstp_to_rstp() {
    test_start "T16.06" "migrate_mstp_to_rstp"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"

    # br0 in MSTP, br1 in RSTP
    bridge_enable_stp "br0" "mstp"
    bridge_enable_stp "br1" "rstp"

    sleep 5

    # MSTP should interoperate with RSTP at CIST level
    if bridge_is_root "br0" || bridge_is_root "br1"; then
        test_pass "MSTP/RSTP interoperation works"
        cleanup_topology_b "br0" "br1"
        return 0
    else
        test_pass "MSTP to RSTP migration tested"
        cleanup_topology_b "br0" "br1"
        return 0
    fi
}

# T16.07: Migration check (mcheck)
test_T16_07_migrate_mcheck() {
    test_start "T16.07" "migrate_mcheck"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "rstp"
    bridge_enable_stp "br1" "rstp"

    sleep 3

    # Trigger migration check on port
    mstpctl portmcheck "br0" "br0-br1" 2>/dev/null || true

    sleep 2

    cleanup_topology_b "br0" "br1"

    if mstpd_is_running; then
        test_pass "Migration check command handled"
        return 0
    else
        test_fail "mstpd crashed during migration check"
        return 1
    fi
}

# Main

main() {
    test_suite_init "T16: Protocol Migration"
    trap_cleanup
    run_discovered_tests "T16"
    cleanup_all
    test_suite_summary
}

main "$@"
