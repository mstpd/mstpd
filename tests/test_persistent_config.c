/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Copyright (c) 2026 Weidmueller Interface GmbH & Co. KG */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <asm/byteorder.h>

#include "common.h"
#include "config_apply.h"
#include "persistent_config.h"

#ifndef EXAMPLE_CONFIG_FILE
#define EXAMPLE_CONFIG_FILE "tests/config/example-config.json"
#endif

/** Write JSON to a temporary file and load it as persistent configuration.
 * @param json JSON document to write and parse.
 * @return persistent_config_load() result, or -2 if temporary-file handling
 *         fails.
 */
static int load_json_string(const char *json)
{
    char path[] = "/tmp/mstpd-config-XXXXXX";
    int fd = mkstemp(path);
    if(fd < 0)
        return -2;

    FILE *file = fdopen(fd, "w");
    if(!file)
    {
        close(fd);
        unlink(path);
        return -2;
    }
    if(fputs(json, file) == EOF || fclose(file) != 0)
    {
        unlink(path);
        return -2;
    }

    int result = persistent_config_load(path);
    unlink(path);
    return result;
}

/** Look up a bridge tree by its MSTID.
 * @param br Bridge whose tree list is searched.
 * @param mstid MSTID in host byte order; 0 selects the CIST.
 * @return Matching tree, or NULL if the bridge has no such tree.
 */
static tree_t *find_tree_by_mstid(bridge_t *br, __u16 mstid)
{
    tree_t *tree;

    list_for_each_entry(tree, &br->trees, bridge_list)
        if(__be16_to_cpu(tree->MSTID) == mstid)
            return tree;
    return NULL;
}

/** Look up a port's per-tree port entry by its MSTID.
 * @param prt Port whose per-tree port list is searched.
 * @param mstid MSTID in host byte order; 0 selects the CIST.
 * @return Matching per-tree port, or NULL if the port has no such tree.
 */
static per_tree_port_t *find_ptp_by_mstid(port_t *prt, __u16 mstid)
{
    per_tree_port_t *ptp;

    list_for_each_entry(ptp, &prt->trees, port_list)
        if(__be16_to_cpu(ptp->MSTID) == mstid)
            return ptp;
    return NULL;
}

/** Verify the checked-in example parses and applies every parameter.
 * @param state CMocka state used to track and clean up created objects.
 */
static void example_json_config(void **state)
{
    bridge_t *br;
    port_t *ports[4];
    CIST_BridgeStatus bridge_status;
    CIST_PortStatus port_status;
    MSTI_BridgeStatus msti_bridge_status;
    MSTI_PortStatus msti_port_status;
    tree_t *tree;
    per_tree_port_t *ptp;
    __u16 mstids[MAX_IMPLEMENTATION_MSTIS];
    int num_mstis;
    int i;

    assert_int_equal(persistent_config_load(EXAMPLE_CONFIG_FILE), 0);
    /* Names must match the JSON keys: br-test with ports br-testp1..p4 */
    assert_int_equal(alloc_bridge_ports(state, &br, "br-test",
                                        0x200000000001, &ports, 4), 0);

    /* Bridge first, so the configured MSTIs exist before port settings */
    persistent_config_apply_to_bridge(br);
    for(i = 0; i < 4; ++i)
        persistent_config_apply_to_port(ports[i]);

    /* Bridge CIST parameters */
    MSTP_IN_get_cist_bridge_status(br, &bridge_status);
    assert_int_equal(bridge_status.protocol_version, protoMSTP);
    assert_int_equal(GET_PRIORITY_FROM_IDENTIFIER(bridge_status.bridge_id),
                     0x40);
    assert_int_equal(bridge_status.bridge_max_age, 24);
    assert_int_equal(bridge_status.bridge_forward_delay, 18);
    assert_int_equal(bridge_status.bridge_hello_time, 2);
    assert_int_equal(bridge_status.tx_hold_count, 4);
    assert_int_equal(bridge_status.Ageing_Time, 600);

    /* Bridge MSTP parameters */
    assert_int_equal(bridge_status.max_hops, 30);
    assert_int_equal(strncmp((const char *)br->MstConfigId.s.configuration_name,
                             "mstpd-example", CONFIGURATION_NAME_LEN), 0);
    assert_int_equal(__be16_to_cpu(br->MstConfigId.s.revision_level), 1);

    /* Check range edges, single VIDs and gaps between the configured lists */
    assert_int_equal(br->vid2fid[1], 1);
    assert_int_equal(br->vid2fid[10], 1);
    assert_int_equal(br->vid2fid[11], 0);
    assert_int_equal(br->vid2fid[20], 2);
    assert_int_equal(br->vid2fid[29], 2);
    assert_int_equal(br->vid2fid[30], 0);
    assert_int_equal(br->vid2fid[100], 2);
    assert_int_equal(__be16_to_cpu(br->fid2mstid[0]), 0);
    assert_int_equal(__be16_to_cpu(br->fid2mstid[1]), 1);
    assert_int_equal(__be16_to_cpu(br->fid2mstid[2]), 2);

    /* The CIST (0) plus both MSTIs from "mstp.msti" must exist */
    assert_true(MSTP_IN_get_mstilist(br, &num_mstis, mstids));
    assert_int_equal(num_mstis, 3);
    assert_int_equal(mstids[0], 0);
    assert_int_equal(mstids[1], 1);
    assert_int_equal(mstids[2], 2);

    /* Per-MSTI bridge priorities; identifiers store priority << 4 */
    tree = find_tree_by_mstid(br, 1);
    assert_non_null(tree);
    MSTP_IN_get_msti_bridge_status(tree, &msti_bridge_status);
    assert_int_equal(GET_PRIORITY_FROM_IDENTIFIER(msti_bridge_status.bridge_id),
                     0x70);
    tree = find_tree_by_mstid(br, 2);
    assert_non_null(tree);
    MSTP_IN_get_msti_bridge_status(tree, &msti_bridge_status);
    assert_int_equal(GET_PRIORITY_FROM_IDENTIFIER(msti_bridge_status.bridge_id),
                     0x90);

    /* br-testp1: uplink with explicit costs and priorities */
    MSTP_IN_get_cist_port_status(ports[0], &port_status);
    assert_int_equal(GET_PRIORITY_FROM_IDENTIFIER(port_status.port_id), 0x40);
    assert_int_equal(port_status.admin_external_port_path_cost, 40000);
    assert_int_equal(port_status.admin_internal_port_path_cost, 30000);
    assert_int_equal(port_status.admin_p2p, p2pForceTrue);
    assert_false(port_status.auto_edge_port);
    assert_true(port_status.network_port);
    assert_false(port_status.admin_edge_port);

    /* br-testp1: per-MSTI port priority and internal cost */
    ptp = find_ptp_by_mstid(ports[0], 1);
    assert_non_null(ptp);
    MSTP_IN_get_msti_port_status(ptp, &msti_port_status);
    assert_int_equal(GET_PRIORITY_FROM_IDENTIFIER(msti_port_status.port_id),
                     0x60);
    assert_int_equal(msti_port_status.admin_internal_port_path_cost, 50000);
    ptp = find_ptp_by_mstid(ports[0], 2);
    assert_non_null(ptp);
    MSTP_IN_get_msti_port_status(ptp, &msti_port_status);
    assert_int_equal(GET_PRIORITY_FROM_IDENTIFIER(msti_port_status.port_id),
                     0xA0);
    assert_int_equal(msti_port_status.admin_internal_port_path_cost, 60000);

    /* br-testp2: restricted boundary port */
    MSTP_IN_get_cist_port_status(ports[1], &port_status);
    assert_true(port_status.restricted_role);
    assert_true(port_status.restricted_tcn);
    /* dont-txmt isn't part of CIST_PortStatus */
    assert_true(ports[1]->dontTxmtBpdu);
    /* Unset fields keep their defaults */
    assert_int_equal(port_status.admin_p2p, p2pAuto);
    assert_true(port_status.auto_edge_port);

    /* br-testp3: guarded edge port */
    MSTP_IN_get_cist_port_status(ports[2], &port_status);
    assert_int_equal(port_status.admin_p2p, p2pForceFalse);
    assert_true(port_status.admin_edge_port);
    assert_true(port_status.bpdu_guard_port);
    assert_false(port_status.bpdu_filter_port);

    /* br-testp4: filtered edge port */
    MSTP_IN_get_cist_port_status(ports[3], &port_status);
    assert_true(port_status.admin_edge_port);
    assert_true(port_status.bpdu_filter_port);
    assert_false(port_status.bpdu_guard_port);
}

/** Verify apply is a no-op when no matching bridge configuration exists.
 * @param state CMocka state used to track and clean up created objects.
 */
static void apply_skips_unconfigured_bridge(void **state)
{
    bridge_t *br;
    CIST_BridgeStatus status;

    assert_int_equal(load_json_string(
        "{\"bridges\":{\"configured\":{"
        "\"force-protocol-version\":\"stp\"}}}"), 0);
    assert_int_equal(alloc_bridge_ports(state, &br, "unconfigured",
                                        0x200000000001, NULL, 0), 0);

    MSTP_IN_get_cist_bridge_status(br, &status);
    protocol_version_t initial_version = status.protocol_version;
    persistent_config_apply_to_bridge(br);
    MSTP_IN_get_cist_bridge_status(br, &status);
    assert_int_equal(status.protocol_version, initial_version);
}

/** Verify apply is a no-op when no matching port configuration exists.
 * @param state CMocka state used to track and clean up created objects.
 */
static void apply_skips_unconfigured_port(void **state)
{
    bridge_t *br;
    port_t *ports[1];
    CIST_PortStatus status;

    assert_int_equal(load_json_string(
        "{\"bridges\":{\"br0\":{\"ports\":{"
        "\"other-port\":{\"admin-edge-port\":true}}}}}"), 0);
    assert_int_equal(alloc_bridge_ports(state, &br, "br0",
                                        0x200000000001, &ports, 1), 0);

    persistent_config_apply_to_bridge(br);
    persistent_config_apply_to_port(ports[0]);
    MSTP_IN_get_cist_port_status(ports[0], &status);
    assert_false(status.admin_edge_port);
}

/** Verify omitted optional values parse and retain their defaults.
 * @param state CMocka state used to track and clean up created objects.
 */
static void missing_optional_values_use_defaults(void **state)
{
    bridge_t *br;
    port_t *ports[1];
    CIST_BridgeStatus bridge_status;
    CIST_PortStatus port_status;

    assert_int_equal(load_json_string(
        "{\"bridges\":{\"br0\":{\"ports\":{\"br0p1\":{}}}}}"), 0);
    assert_int_equal(alloc_bridge_ports(state, &br, "br0",
                                        0x200000000001, &ports, 1), 0);
    persistent_config_apply_to_bridge(br);
    persistent_config_apply_to_port(ports[0]);

    MSTP_IN_get_cist_bridge_status(br, &bridge_status);
    assert_int_equal(bridge_status.bridge_max_age, 20);
    assert_int_equal(bridge_status.bridge_forward_delay, 15);
    assert_int_equal(bridge_status.bridge_hello_time, 2);
    assert_int_equal(bridge_status.tx_hold_count, 6);
    assert_int_equal(bridge_status.max_hops, 20);

    MSTP_IN_get_cist_port_status(ports[0], &port_status);
    assert_int_equal(port_status.admin_external_port_path_cost, 0);
    assert_int_equal(port_status.admin_p2p, p2pAuto);
    assert_false(port_status.admin_edge_port);

    assert_int_equal(load_json_string("{\"bridges\":{\"br-empty\":{}}}"), 0);
    assert_int_equal(load_json_string("{\"bridges\":{}}"), 0);
}

/** Verify missing or wrongly typed required JSON objects are rejected.
 * @param state CMocka test state; unused by this test.
 */
static void missing_required_objects_are_rejected(void **state)
{
    (void)state;
    assert_int_not_equal(load_json_string("{}"), 0);
    assert_int_not_equal(load_json_string("{\"bridges\":null}"), 0);
    assert_int_not_equal(load_json_string(
        "{\"bridges\":{\"br0\":null}}"), 0);
    assert_int_not_equal(load_json_string(
        "{\"bridges\":{\"br0\":{\"ports\":{\"eth0\":null}}}}"), 0);
}

static void free_configs_leaves_reusable_empty_list(void **state)
{
    (void)state;
    LIST_HEAD(configs);

    for(int count = 0; count <= 3; ++count)
    {
        for(int i = 0; i < count; ++i)
        {
            stored_bridge_cfg_t *br_cfg = calloc(1, sizeof(*br_cfg));
            assert_non_null(br_cfg);
            INIT_LIST_HEAD(&br_cfg->mstis);
            INIT_LIST_HEAD(&br_cfg->ports);
            list_add_tail(&br_cfg->list, &configs);
        }

        free_configs(&configs);
        assert_ptr_equal(configs.next, &configs);
        assert_ptr_equal(configs.prev, &configs);
        free_configs(&configs);
    }
}

static void replacing_configs_discards_old_entries(void **state)
{
    bridge_t *br, *removed;
    CIST_BridgeStatus status;

    assert_int_equal(load_json_string(
        "{\"bridges\":{\"br0\":{\"force-protocol-version\":\"stp\"},"
        "\"removed\":{\"force-protocol-version\":\"stp\"}}}"), 0);
    assert_int_equal(alloc_bridge_ports(state, &br, "br0",
                                        0x200000000001, NULL, 0), 0);
    assert_int_equal(alloc_bridge_ports(state, &removed, "removed",
                                        0x200000000002, NULL, 0), 0);
    MSTP_IN_get_cist_bridge_status(removed, &status);
    protocol_version_t initial_version = status.protocol_version;

    persistent_config_apply_to_bridge(br);
    MSTP_IN_get_cist_bridge_status(br, &status);
    assert_int_equal(status.protocol_version, protoSTP);

    assert_int_equal(load_json_string(
        "{\"bridges\":{\"br0\":{\"force-protocol-version\":\"rstp\"}}}"), 0);
    persistent_config_apply_to_bridge(br);
    MSTP_IN_get_cist_bridge_status(br, &status);
    assert_int_equal(status.protocol_version, protoRSTP);
    persistent_config_apply_to_bridge(removed);
    MSTP_IN_get_cist_bridge_status(removed, &status);
    assert_int_equal(status.protocol_version, initial_version);

    assert_int_equal(load_json_string("{\"bridges\":{}}"), 0);
    assert_int_equal(load_json_string("{\"bridges\":{}}"), 0);
    assert_int_equal(load_json_string(
        "{\"bridges\":{\"br0\":{\"force-protocol-version\":\"stp\"}}}"), 0);
    persistent_config_apply_to_bridge(br);
    MSTP_IN_get_cist_bridge_status(br, &status);
    assert_int_equal(status.protocol_version, protoSTP);
    assert_int_equal(load_json_string("{\"bridges\":{}}"), 0);
}

/** Verify out-of-range bridge, port, FID, and MSTID values are rejected.
 * @param state CMocka test state; unused by this test.
 */
static void out_of_range_bridge_and_port_values_are_rejected(void **state)
{
    (void)state;
    const char *invalid_configs[] = {
        "{\"bridges\":{\"br0\":{\"bridge-priority\":16}}}",
        "{\"bridges\":{\"br0\":{\"bridge-max-age\":5}}}",
        "{\"bridges\":{\"br0\":{\"bridge-max-age\":40}}}",
        "{\"bridges\":{\"br0\":{\"bridge-forward-delay\":3}}}",
        "{\"bridges\":{\"br0\":{\"hello-time\":1}}}",
        "{\"bridges\":{\"br0\":{\"tx-hold-count\":11}}}",
        "{\"bridges\":{\"br0\":{\"ageing-time\":9}}}",
        "{\"bridges\":{\"br0\":{\"mstp\":{\"max-hops\":5}}}}",
        "{\"bridges\":{\"br0\":{\"mstp\":{\"msti\":{"
            "\"1\":{\"bridge-priority\":16}}}}}}",
        "{\"bridges\":{\"br0\":{\"ports\":{\"eth0\":{"
            "\"port-priority\":16}}}}}",
        "{\"bridges\":{\"br0\":{\"ports\":{\"eth0\":{"
            "\"admin-external-cost\":200000001}}}}}",
        "{\"bridges\":{\"br0\":{\"ports\":{\"eth0\":{"
            "\"admin-point-to-point\":\"invalid\"}}}}}",
        "{\"bridges\":{\"br0\":{\"ports\":{\"eth0\":{\"mstp\":{"
            "\"cist-admin-internal-cost\":200000001}}}}}}",
        "{\"bridges\":{\"br0\":{\"ports\":{\"eth0\":{\"mstp\":{"
            "\"msti\":{\"1\":{\"port-priority\":16}}}}}}}}",
        "{\"bridges\":{\"br0\":{\"ports\":{\"eth0\":{\"mstp\":{"
            "\"msti\":{\"1\":{\"admin-internal-cost\":200000001}}}}}}}}",
        "{\"bridges\":{\"br0\":{\"mstp\":{\"vid2fid\":[{"
            "\"fid\":4096,\"vids\":[\"1\"]}]}}}}",
        "{\"bridges\":{\"br0\":{\"mstp\":{\"fid2mstid\":[{"
            "\"mstid\":4095,\"fids\":[\"1\"]}]}}}}"
    };
    size_t i;

    for(i = 0; i < sizeof(invalid_configs) / sizeof(invalid_configs[0]); ++i)
    {
        if(0 == load_json_string(invalid_configs[i]))
            fail_msg("out-of-range JSON case %zu was accepted", i);
    }

    assert_int_equal(load_json_string("{\"bridges\":{}}"), 0);
}

/** Run all persistent-configuration parser and apply tests.
 * @param argc Number of command-line arguments supplied by the C runtime.
 * @param argv Command-line argument vector supplied by the C runtime.
 * @return CMocka test-suite result; zero indicates success.
 */
int main(int argc, char *argv[])
{
    const struct CMUnitTest tests[] = {
        cmocka_unit_test(free_configs_leaves_reusable_empty_list),
        cmocka_unit_test_setup_teardown(replacing_configs_discards_old_entries,
                                        prepare_test, teardown_test),
        cmocka_unit_test_setup_teardown(example_json_config, prepare_test,
                                        teardown_test),
        cmocka_unit_test_setup_teardown(apply_skips_unconfigured_bridge,
                        prepare_test, teardown_test),
        cmocka_unit_test_setup_teardown(apply_skips_unconfigured_port,
                        prepare_test, teardown_test),
        cmocka_unit_test_setup_teardown(missing_optional_values_use_defaults,
                                        prepare_test, teardown_test),
        cmocka_unit_test_setup_teardown(missing_required_objects_are_rejected,
                                        prepare_test, teardown_test),
        cmocka_unit_test_setup_teardown(
            out_of_range_bridge_and_port_values_are_rejected,
            prepare_test, teardown_test),
    };

    return cmocka_run_group_tests(tests, NULL, NULL);
}
