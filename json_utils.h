/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Copyright (c) 2026 Weidmueller Interface GmbH & Co. KG */
#ifndef JSON_UTILS_H
#define JSON_UTILS_H

#include <cjson/cJSON.h>

#include "mstp.h"

typedef enum { FIELD_ABSENT, FIELD_VALID, FIELD_INVALID } field_result_t;

/** Parse a JSON number as an unsigned integer.
 *
 * @param parent JSON object containing the field.
 * @param key Field name to look up.
 * @param type_max Maximum value representable by the destination type; larger
 *                 valid values are clamped to this maximum.
 * @param[out] out Receives the parsed or clamped value when the field is valid.
 * @return FIELD_ABSENT if the key is missing, FIELD_INVALID if its value is
 *         not a non-negative integer, or FIELD_VALID on success.
 */
field_result_t get_json_uint(cJSON *parent, const char *key,
                             unsigned int type_max, unsigned int *out);

/** Parse a JSON string as an STP protocol version.
 *
 * @param parent JSON object containing the field.
 * @param key Field name to look up.
 * @param[out] out Receives the protocol version when the value is recognized.
 * @return FIELD_ABSENT if the key is missing, FIELD_INVALID if the value is
 *         not "stp", "rstp", or "mstp", or FIELD_VALID on success.
 */
field_result_t get_json_protocol_version(cJSON *parent, const char *key,
                                         protocol_version_t *out);

/** Parse a JSON boolean.
 *
 * @param parent JSON object containing the field.
 * @param key Field name to look up.
 * @param[out] out Receives the boolean value when the field is valid.
 * @return FIELD_ABSENT if the key is missing, FIELD_INVALID if it is not a
 *         JSON boolean, or FIELD_VALID on success.
 */
field_result_t get_json_bool(cJSON *parent, const char *key, bool *out);

/** Parse a JSON string as an administrative point-to-point mode.
 *
 * @param parent JSON object containing the field.
 * @param key Field name to look up.
 * @param[out] out Receives p2pAuto, p2pForceTrue, or p2pForceFalse.
 * @return FIELD_ABSENT if the key is missing, FIELD_INVALID if the value is
 *         not "auto", "yes", or "no", or FIELD_VALID on success.
 */
field_result_t get_json_admin_p2p(cJSON *parent, const char *key,
                                  admin_p2p_t *out);

/** Apply numeric indexes or inclusive ranges from a JSON string array.
 *
 * Each array element must be "N" or "N-M" and both endpoints must be within
 * the supplied bounds. Descending ranges are accepted and applied ascending.
 *
 * @param list_json JSON array containing index strings.
 * @param min_index Lowest allowed index.
 * @param max_index Highest allowed index.
 * @param value Value to store at each selected index.
 * @param[out] array Destination array indexed by the parsed numbers.
 * @return true if all elements were valid and applied; false for a wrong JSON
 *         type, malformed range, or out-of-bounds index.
 */
bool parse_index_list(cJSON *list_json, unsigned int min_index,
                      unsigned int max_index, unsigned int value,
                      __u16 *array);

#endif /* JSON_UTILS_H */
