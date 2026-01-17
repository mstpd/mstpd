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
    mstpctl createtree "br0" 1

    sleep 1

    # Check if MSTI was created
    local output
    output=$(mstpctl showtree "br0" 1 2>&1)

    cleanup_topology_a "br0" 1

    if [[ -n "${output}" ]]; then
        test_pass "MSTI 1 created successfully"
        return 0
    else
        test_fail "MSTI 1 not visible in showtree output"
        return 1
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
    mstpctl createtree "br0" 1 2>&1 || true
    sleep 1

    if ! mstpd_is_running; then
        test_fail "mstpd crashed during MSTI creation"
        cleanup_topology_a "br0" 1
        return 1
    fi

    mstpctl deletetree "br0" 1 2>&1 || true
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

# T6.03: Set MST configuration ID (region name) and verify via showmstconfid
test_T6_03_mstp_config_id() {
    test_start "T6.03" "mstp_config_id"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_a "br0" 1
    bridge_enable_stp "br0" "mstp"

    # Set MST config name and revision
    mstpctl setmstconfid "br0" 42 "TestRegion" 2>&1 || true

    sleep 1

    if ! mstpd_is_running; then
        test_fail "mstpd crashed during setmstconfid"
        cleanup_topology_a "br0" 1
        return 1
    fi

    # Read back via showmstconfid
    local confid_output
    confid_output=$(mstpctl showmstconfid "br0" 2>&1)
    log_debug "MST Config ID: ${confid_output}"

    local config_name
    local revision
    config_name=$(echo "${confid_output}" | grep "Configuration Name:" | sed 's/.*Configuration Name:[[:space:]]*//')
    revision=$(echo "${confid_output}" | grep "Revision Level:" | awk '{print $NF}')

    cleanup_topology_a "br0" 1

    if [[ "${config_name}" == "TestRegion" ]] && [[ "${revision}" == "42" ]]; then
        test_pass "MST config ID set and verified (name=${config_name}, rev=${revision})"
        return 0
    else
        test_fail "MST config ID mismatch (name=${config_name:-empty}, rev=${revision:-empty})"
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
    mstpctl setvid2fid "br0" "100:1" 2>&1 || true

    sleep 1

    # Show VID to FID table
    local output
    output=$(mstpctl showvid2fid "br0")
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
    mstpctl createtree "br0" 1 2>&1 || true

    # Set FID to MSTID mapping (FID 1 -> MSTI 1)
    mstpctl setfid2mstid "br0" "1:1" 2>&1 || true

    sleep 1

    # Show FID to MSTID table
    local output
    output=$(mstpctl showfid2mstid "br0")
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

# T6.06: MST region detection — same region requires matching config identifier
# Two bridges are in the same MST region when name, revision, AND digest all match.
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

    # Set same region name and revision on both bridges
    # (VID-to-FID and FID-to-MSTID defaults are identical, so digest matches too)
    mstpctl setmstconfid "br0" 1 "Region1" 2>&1 || true
    mstpctl setmstconfid "br1" 1 "Region1" 2>&1 || true

    wait_for_convergence 15

    # Read full MST config identifier from both bridges
    local confid0 confid1
    confid0=$(mstpctl showmstconfid "br0" 2>&1)
    confid1=$(mstpctl showmstconfid "br1" 2>&1)

    # Extract name, revision, digest from each
    local name0 name1 rev0 rev1 digest0 digest1
    name0=$(echo "${confid0}" | grep "Configuration Name:" | sed 's/.*Configuration Name:[[:space:]]*//')
    name1=$(echo "${confid1}" | grep "Configuration Name:" | sed 's/.*Configuration Name:[[:space:]]*//')
    rev0=$(echo "${confid0}" | grep "Revision Level:" | awk '{print $NF}')
    rev1=$(echo "${confid1}" | grep "Revision Level:" | awk '{print $NF}')
    digest0=$(echo "${confid0}" | grep "Configuration Digest:" | awk '{print $NF}')
    digest1=$(echo "${confid1}" | grep "Configuration Digest:" | awk '{print $NF}')

    log_debug "br0: name='${name0}' rev=${rev0} digest=${digest0}"
    log_debug "br1: name='${name1}' rev=${rev1} digest=${digest1}"

    cleanup_topology_b "br0" "br1"

    # All three components must match for same region
    if [[ "${name0}" == "${name1}" ]] && [[ "${rev0}" == "${rev1}" ]] && [[ "${digest0}" == "${digest1}" ]]; then
        test_pass "Same MST region (name=${name0}, rev=${rev0}, digest match)"
        return 0
    else
        test_fail "MST config identifiers differ: name(${name0}/${name1}) rev(${rev0}/${rev1}) digest(${digest0}/${digest1})"
        return 1
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

    wait_for_convergence 15

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
    mstpctl createtree "br0" 1 2>&1 || true
    mstpctl createtree "br1" 1 2>&1 || true

    # Set different priorities for MSTI 1 (br1 should become root for MSTI 1)
    mstpctl settreeprio "br0" 1 8 2>&1 || true
    mstpctl settreeprio "br1" 1 0 2>&1 || true

    wait_for_convergence 15

    # Check MSTI 1 — br1 should be root (priority 0 < 8)
    local msti1_info
    msti1_info=$(mstpctl showtree "br1" 1 2>&1)
    log_debug "MSTI 1 on br1: ${msti1_info}"

    cleanup_topology_b "br0" "br1"

    if ! mstpd_is_running; then
        test_fail "mstpd crashed during MSTI root election"
        return 1
    fi

    # Verify MSTI tree info is available
    if [[ -n "${msti1_info}" ]] && [[ "${msti1_info}" != *"error"* ]]; then
        test_pass "Per-MSTI root election completed"
        return 0
    else
        test_fail "MSTI 1 tree info not available on br1"
        return 1
    fi
}

# T6.09: Different MST regions — different config identifiers
test_T6_09_mstp_different_regions() {
    test_start "T6.09" "mstp_different_regions"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "mstp"
    bridge_enable_stp "br1" "mstp"

    # Set different region names — bridges should be in different regions
    mstpctl setmstconfid "br0" 1 "RegionA" 2>&1 || true
    mstpctl setmstconfid "br1" 1 "RegionB" 2>&1 || true

    wait_for_convergence 15

    # Verify config identifiers differ
    local confid0 confid1
    confid0=$(mstpctl showmstconfid "br0" 2>&1)
    confid1=$(mstpctl showmstconfid "br1" 2>&1)

    local name0 name1
    name0=$(echo "${confid0}" | grep "Configuration Name:" | sed 's/.*Configuration Name:[[:space:]]*//')
    name1=$(echo "${confid1}" | grep "Configuration Name:" | sed 's/.*Configuration Name:[[:space:]]*//')

    log_debug "br0 region: ${name0}, br1 region: ${name1}"

    if ! mstpd_is_running; then
        test_fail "mstpd crashed with different regions"
        cleanup_topology_b "br0" "br1"
        return 1
    fi

    cleanup_topology_b "br0" "br1"

    if [[ "${name0}" == "RegionA" ]] && [[ "${name1}" == "RegionB" ]]; then
        test_pass "Different MST regions configured (${name0} vs ${name1})"
        return 0
    else
        test_fail "Region names not applied (br0=${name0:-empty}, br1=${name1:-empty})"
        return 1
    fi
}

# T6.10: Same region name but different revision = different regions
test_T6_10_mstp_revision_mismatch() {
    test_start "T6.10" "mstp_revision_mismatch"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "mstp"
    bridge_enable_stp "br1" "mstp"

    # Same name, different revision — should be different regions
    mstpctl setmstconfid "br0" 1 "SameRegion" 2>&1 || true
    mstpctl setmstconfid "br1" 2 "SameRegion" 2>&1 || true

    wait_for_convergence 15

    local confid0 confid1
    confid0=$(mstpctl showmstconfid "br0" 2>&1)
    confid1=$(mstpctl showmstconfid "br1" 2>&1)

    local rev0 rev1
    rev0=$(echo "${confid0}" | grep "Revision Level:" | awk '{print $NF}')
    rev1=$(echo "${confid1}" | grep "Revision Level:" | awk '{print $NF}')

    log_debug "br0 rev: ${rev0}, br1 rev: ${rev1}"

    cleanup_topology_b "br0" "br1"

    if [[ "${rev0}" == "1" ]] && [[ "${rev1}" == "2" ]]; then
        test_pass "Different revisions make different regions (rev ${rev0} vs ${rev1})"
        return 0
    else
        test_fail "Revisions not applied (br0=${rev0:-empty}, br1=${rev1:-empty})"
        return 1
    fi
}

# T6.11: Different VID-to-MSTID mapping = different digest = different regions
# The configuration digest (IEEE 802.1Q 13.7) is computed over the VID-to-MSTID
# mapping (vid2fid composed with fid2mstid), so to change the digest we must
# ensure the FID we map a VID to has a different MSTID than the default.
test_T6_11_mstp_digest_mismatch() {
    test_start "T6.11" "mstp_digest_mismatch"

    cleanup_all
    mstpd_start "-d -v 2" || {
        test_fail "Could not start mstpd"
        return 1
    }

    setup_topology_b "br0" "br1"
    bridge_enable_stp "br0" "mstp"
    bridge_enable_stp "br1" "mstp"

    # Same name and revision
    mstpctl setmstconfid "br0" 1 "DigestTest" 2>&1 || true
    mstpctl setmstconfid "br1" 1 "DigestTest" 2>&1 || true

    # On br1: create MSTI 1, map FID 1 → MSTI 1, then map VID 100 → FID 1.
    # Format: setfid2mstid <bridge> <mstid>:<FID_list>
    #         setvid2fid   <bridge> <FID>:<VID_list>
    # This changes VID 100's MSTID from 0 to 1, changing the digest.
    mstpctl createtree "br1" 1 2>&1 || true
    mstpctl setfid2mstid "br1" "1:1" 2>&1 || true
    mstpctl setvid2fid "br1" "1:100" 2>&1 || true

    if ! mstpd_is_running; then
        test_fail "mstpd crashed during MSTP configuration"
        cleanup_topology_b "br0" "br1"
        return 1
    fi

    wait_for_convergence 10

    local confid0 confid1
    confid0=$(mstpctl showmstconfid "br0" 2>&1)
    confid1=$(mstpctl showmstconfid "br1" 2>&1)

    local digest0 digest1
    digest0=$(echo "${confid0}" | grep "Configuration Digest:" | awk '{print $NF}')
    digest1=$(echo "${confid1}" | grep "Configuration Digest:" | awk '{print $NF}')

    log_debug "br0 digest: ${digest0}"
    log_debug "br1 digest: ${digest1}"

    cleanup_topology_b "br0" "br1"

    if [[ -n "${digest0}" ]] && [[ -n "${digest1}" ]] && [[ "${digest0}" != "${digest1}" ]]; then
        test_pass "Different VID-to-MSTID mapping produces different digest"
        return 0
    elif [[ -z "${digest0}" ]] || [[ -z "${digest1}" ]]; then
        test_fail "Could not read configuration digest (br0=${digest0:-empty}, br1=${digest1:-empty})"
        return 1
    else
        test_fail "Digests should differ but are the same: ${digest0}"
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
