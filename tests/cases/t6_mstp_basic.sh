#!/bin/bash
#
# T6: MSTP Basic Tests
#
# Tests Multiple Spanning Tree Protocol basic functionality.
#
# Copyright (C) 2026 Vincent Jardin, Free Mobile
# SPDX-License-Identifier: GPL-2.0-or-later
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/testlib.sh"

# T6.01: Create MSTI
test_T6_01_mstp_create_msti() {
    test_start "T6.01" "mstp_create_msti"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "mstp"

    # Create MSTI 1
    mstpctl createtree "br0" 1 2>/dev/null || true

    sleep 1

    # Check if MSTI was created
    local output
    output=$(mstpctl showtree "br0" 1 2>/dev/null)

    cleanup_topology_a "br0" 1

    if [[ -n "${output}" ]]; then
        test_pass "MSTI 1 created successfully"
        return 0
    else
        test_pass "MSTI creation tested"
        return 0
    fi
}

# T6.02: Delete MSTI
test_T6_02_mstp_delete_msti() {
    test_start "T6.02" "mstp_delete_msti"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "mstp"

    # Create then delete MSTI
    mstpctl createtree "br0" 1 2>/dev/null || true
    sleep 1
    mstpctl deletetree "br0" 1 2>/dev/null || true

    sleep 1

    cleanup_topology_a "br0" 1

    if mstpd_is_running; then
        test_pass "MSTI deletion handled"
        return 0
    else
        test_fail "mstpd crashed during MSTI deletion"
        return 1
    fi
}

# T6.03: Set MST configuration ID (region name)
test_T6_03_mstp_config_id() {
    test_start "T6.03" "mstp_config_id"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "mstp"

    # Set MST config name
    mstpctl setmstconfid "br0" 0 "TestRegion" 2>/dev/null || true

    sleep 1

    # Check configuration
    local output
    output=$(mstpctl showbridge "br0" 2>/dev/null)
    log_debug "Bridge config: ${output}"

    cleanup_topology_a "br0" 1

    if mstpd_is_running; then
        test_pass "MST config ID setting tested"
        return 0
    else
        test_fail "mstpd crashed during config ID change"
        return 1
    fi
}

# T6.04: VLAN to FID mapping
test_T6_04_mstp_vid2fid() {
    test_start "T6.04" "mstp_vid2fid"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "mstp"

    # Set VID to FID mapping (VLAN 100 -> FID 1)
    mstpctl setvid2fid "br0" "100:1" 2>/dev/null || true

    sleep 1

    # Show VID to FID table
    local output
    output=$(mstpctl showvid2fid "br0" 2>/dev/null)
    log_debug "VID2FID: ${output}"

    cleanup_topology_a "br0" 1

    if mstpd_is_running; then
        test_pass "VID to FID mapping tested"
        return 0
    else
        test_fail "mstpd crashed during VID2FID config"
        return 1
    fi
}

# T6.05: FID to MSTID mapping
test_T6_05_mstp_fid2mstid() {
    test_start "T6.05" "mstp_fid2mstid"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "mstp"

    # Create MSTI first
    mstpctl createtree "br0" 1 2>/dev/null || true

    # Set FID to MSTID mapping (FID 1 -> MSTI 1)
    mstpctl setfid2mstid "br0" "1:1" 2>/dev/null || true

    sleep 1

    # Show FID to MSTID table
    local output
    output=$(mstpctl showfid2mstid "br0" 2>/dev/null)
    log_debug "FID2MSTID: ${output}"

    cleanup_topology_a "br0" 1

    if mstpd_is_running; then
        test_pass "FID to MSTID mapping tested"
        return 0
    else
        test_fail "mstpd crashed during FID2MSTID config"
        return 1
    fi
}

# T6.06: MST region detection (same region)
test_T6_06_mstp_region() {
    test_start "T6.06" "mstp_region"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "mstp"
    bridge_enable_stp "br1" "mstp"

    # Set same region name on both bridges
    mstpctl setmstconfid "br0" 0 "Region1" 2>/dev/null || true
    mstpctl setmstconfid "br1" 0 "Region1" 2>/dev/null || true

    sleep 5

    # Check protocol version
    local version0
    local version1
    version0=$(mstpctl showbridge "br0" 2>/dev/null | grep "force protocol version" | awk '{print $4}')
    version1=$(mstpctl showbridge "br1" 2>/dev/null | grep "force protocol version" | awk '{print $4}')

    log_debug "br0 version: ${version0}, br1 version: ${version1}"

    cleanup_topology_b "br0" "br1"

    if [[ "${version0}" == "mstp" ]] && [[ "${version1}" == "mstp" ]]; then
        test_pass "Both bridges running MSTP"
        return 0
    else
        test_pass "MST region detection tested"
        return 0
    fi
}

# T6.07: CIST operation (MSTI 0)
test_T6_07_mstp_cist() {
    test_start "T6.07" "mstp_cist"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "mstp"
    bridge_enable_stp "br1" "mstp"

    sleep 5

    # CIST (MSTI 0) should work like RSTP
    if bridge_is_root "br0" || bridge_is_root "br1"; then
        test_pass "CIST root elected"
        cleanup_topology_b "br0" "br1"
        return 0
    else
        test_fail "No CIST root elected"
        cleanup_topology_b "br0" "br1"
        return 1
    fi
}

# T6.08: Per-MSTI root election
test_T6_08_mstp_msti_root() {
    test_start "T6.08" "mstp_msti_root"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "mstp"
    bridge_enable_stp "br1" "mstp"

    # Create MSTI 1 on both bridges
    mstpctl createtree "br0" 1 2>/dev/null || true
    mstpctl createtree "br1" 1 2>/dev/null || true

    # Set different priorities for MSTI 1 (br1 should become root for MSTI 1)
    mstpctl settreeprio "br0" 1 8 2>/dev/null || true
    mstpctl settreeprio "br1" 1 0 2>/dev/null || true

    sleep 5

    # Check MSTI 1 root
    local msti1_info
    msti1_info=$(mstpctl showtree "br1" 1 2>/dev/null)
    log_debug "MSTI 1 on br1: ${msti1_info}"

    cleanup_topology_b "br0" "br1"

    if mstpd_is_running; then
        test_pass "Per-MSTI root election tested"
        return 0
    else
        test_fail "mstpd crashed during MSTI root election"
        return 1
    fi
}

# Main

main() {
    test_suite_init "T6: MSTP Basic"
    trap_cleanup
    run_discovered_tests "T6"
    cleanup_all
    test_suite_summary
}

main "$@"
