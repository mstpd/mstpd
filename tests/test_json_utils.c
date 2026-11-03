/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Copyright (c) 2026 Weidmueller Interface GmbH & Co. KG */

#include <string.h>
#include <limits.h>

#include "common.h"
#include "json_utils.h"

/** Test unsigned JSON number parsing, missing/invalid values, and clamping.
 * @param state CMocka test state; unused by this test.
 */
static void json_uint_values(void **state)
{
    cJSON *root = cJSON_Parse(
        "{\"valid\":42,\"negative\":-1,\"fraction\":1.5,"
        "\"string\":\"7\",\"large\":4294967296}");
    unsigned int value = 77;

    (void)state;
    assert_non_null(root);
    assert_int_equal(get_json_uint(root, "valid", UINT_MAX, &value),
                     FIELD_VALID);
    assert_int_equal(value, 42);
    assert_int_equal(get_json_uint(root, "valid", 10, &value), FIELD_VALID);
    assert_int_equal(value, 10);

    value = 77;
    assert_int_equal(get_json_uint(root, "missing", UINT_MAX, &value),
                     FIELD_ABSENT);
    assert_int_equal(value, 77);
    assert_int_equal(get_json_uint(root, "negative", UINT_MAX, &value),
                     FIELD_INVALID);
    assert_int_equal(get_json_uint(root, "fraction", UINT_MAX, &value),
                     FIELD_INVALID);
    assert_int_equal(get_json_uint(root, "string", UINT_MAX, &value),
                     FIELD_INVALID);
    assert_int_equal(get_json_uint(root, "large", UINT_MAX, &value),
                     FIELD_VALID);
    assert_int_equal(value, UINT_MAX);
    cJSON_Delete(root);
}

/** Test supported, invalid, and absent protocol-version fields.
 * @param state CMocka test state; unused by this test.
 */
static void protocol_version_values(void **state)
{
    cJSON *root = cJSON_Parse(
        "{\"stp\":\"stp\",\"rstp\":\"rstp\",\"mstp\":\"mstp\","
        "\"invalid\":\"bad\",\"number\":1}");
    protocol_version_t version = protoMSTP;

    (void)state;
    assert_non_null(root);
    assert_int_equal(get_json_protocol_version(root, "stp", &version),
                     FIELD_VALID);
    assert_int_equal(version, protoSTP);
    assert_int_equal(get_json_protocol_version(root, "rstp", &version),
                     FIELD_VALID);
    assert_int_equal(version, protoRSTP);
    assert_int_equal(get_json_protocol_version(root, "mstp", &version),
                     FIELD_VALID);
    assert_int_equal(version, protoMSTP);
    assert_int_equal(get_json_protocol_version(root, "invalid", &version),
                     FIELD_INVALID);
    assert_int_equal(get_json_protocol_version(root, "number", &version),
                     FIELD_INVALID);
    assert_int_equal(get_json_protocol_version(root, "missing", &version),
                     FIELD_ABSENT);
    cJSON_Delete(root);
}

/** Test JSON boolean conversion and type handling.
 * @param state CMocka test state; unused by this test.
 */
static void boolean_values(void **state)
{
    cJSON *root = cJSON_Parse(
        "{\"true\":true,\"false\":false,\"number\":1}");
    bool value = false;

    (void)state;
    assert_non_null(root);
    assert_int_equal(get_json_bool(root, "true", &value), FIELD_VALID);
    assert_true(value);
    assert_int_equal(get_json_bool(root, "false", &value), FIELD_VALID);
    assert_false(value);
    assert_int_equal(get_json_bool(root, "number", &value), FIELD_INVALID);
    assert_int_equal(get_json_bool(root, "missing", &value), FIELD_ABSENT);
    cJSON_Delete(root);
}

/** Test administrative point-to-point string conversions and errors.
 * @param state CMocka test state; unused by this test.
 */
static void admin_p2p_values(void **state)
{
    cJSON *root = cJSON_Parse(
        "{\"auto\":\"auto\",\"yes\":\"yes\",\"no\":\"no\","
        "\"invalid\":\"sometimes\",\"number\":1}");
    admin_p2p_t value = p2pForceTrue;

    (void)state;
    assert_non_null(root);
    assert_int_equal(get_json_admin_p2p(root, "auto", &value), FIELD_VALID);
    assert_int_equal(value, p2pAuto);
    assert_int_equal(get_json_admin_p2p(root, "yes", &value), FIELD_VALID);
    assert_int_equal(value, p2pForceTrue);
    assert_int_equal(get_json_admin_p2p(root, "no", &value), FIELD_VALID);
    assert_int_equal(value, p2pForceFalse);
    assert_int_equal(get_json_admin_p2p(root, "invalid", &value),
                     FIELD_INVALID);
    assert_int_equal(get_json_admin_p2p(root, "number", &value),
                     FIELD_INVALID);
    assert_int_equal(get_json_admin_p2p(root, "missing", &value),
                     FIELD_ABSENT);
    cJSON_Delete(root);
}

/** Test parsing of individual indexes, ranges, and invalid index arrays.
 * @param state CMocka test state; unused by this test.
 */
static void index_list_values(void **state)
{
    cJSON *valid = cJSON_Parse("[\"1\",\"3-5\",\"7-6\"]");
    cJSON *invalid = cJSON_Parse("[\"1\",\"3-x\"]");
    cJSON *out_of_bounds = cJSON_Parse("[\"1-9\"]");
    cJSON *wrong_type = cJSON_Parse("[1]");
    __u16 values[10] = { 0 };

    (void)state;
    assert_non_null(valid);
    assert_non_null(invalid);
    assert_non_null(out_of_bounds);
    assert_non_null(wrong_type);
    assert_true(parse_index_list(valid, 1, 8, 12, values));
    assert_int_equal(values[0], 0);
    assert_int_equal(values[1], 12);
    assert_int_equal(values[2], 0);
    assert_int_equal(values[3], 12);
    assert_int_equal(values[4], 12);
    assert_int_equal(values[5], 12);
    assert_int_equal(values[6], 12);
    assert_int_equal(values[7], 12);
    assert_false(parse_index_list(invalid, 1, 8, 1, values));
    assert_false(parse_index_list(out_of_bounds, 1, 8, 1, values));
    assert_false(parse_index_list(wrong_type, 1, 8, 1, values));
    assert_false(parse_index_list(NULL, 1, 8, 1, values));

    cJSON_Delete(valid);
    cJSON_Delete(invalid);
    cJSON_Delete(out_of_bounds);
    cJSON_Delete(wrong_type);
}

/** Run all JSON utility unit tests.
 * @param argc Number of command-line arguments supplied by the C runtime.
 * @param argv Command-line argument vector supplied by the C runtime.
 * @return CMocka test-suite result; zero indicates success.
 */
int main(int argc, char *argv[])
{
    const struct CMUnitTest tests[] = {
        cmocka_unit_test(json_uint_values),
        cmocka_unit_test(protocol_version_values),
        cmocka_unit_test(boolean_values),
        cmocka_unit_test(admin_p2p_values),
        cmocka_unit_test(index_list_values),
    };

    return cmocka_run_group_tests(tests, NULL, NULL);
}
