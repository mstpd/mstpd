/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Copyright (c) 2026 Weidmueller Interface GmbH & Co. KG */

#include <string.h>
#include <stdlib.h>
#include <math.h>

#include "json_utils.h"

/** Check whether a cJSON number is finite, non-negative, and integral.
 * @param field JSON value to inspect.
 * @return true for an unsigned integer value; otherwise false.
 */
static bool cjson_is_uint(cJSON *field)
{
    if(!cJSON_IsNumber(field))
        return false;

    double value = field->valuedouble;
    double integer_part;
    return isfinite(value) && value >= 0
        && modf(value, &integer_part) == 0;
}

field_result_t get_json_uint(cJSON *parent, const char *key,
                             unsigned int type_max, unsigned int *out)
{
    cJSON *field = cJSON_GetObjectItemCaseSensitive(parent, key);
    if(!field)
        return FIELD_ABSENT;
    if(!cjson_is_uint(field))
        return FIELD_INVALID;

    double value = field->valuedouble;
    *out = value > type_max ? type_max : (unsigned int)value;
    return FIELD_VALID;
}

field_result_t get_json_protocol_version(cJSON *parent, const char *key,
                                         protocol_version_t *out)
{
    cJSON *field = cJSON_GetObjectItemCaseSensitive(parent, key);
    if(!field)
        return FIELD_ABSENT;
    if(!cJSON_IsString(field))
        return FIELD_INVALID;

    const char *value = field->valuestring;
    if(!strcmp(value, "stp"))
        *out = protoSTP;
    else if(!strcmp(value, "rstp"))
        *out = protoRSTP;
    else if(!strcmp(value, "mstp"))
        *out = protoMSTP;
    else
        return FIELD_INVALID;

    return FIELD_VALID;
}

field_result_t get_json_bool(cJSON *parent, const char *key, bool *out)
{
    cJSON *field = cJSON_GetObjectItemCaseSensitive(parent, key);
    if(!field)
        return FIELD_ABSENT;
    if(!cJSON_IsBool(field))
        return FIELD_INVALID;

    *out = cJSON_IsTrue(field);
    return FIELD_VALID;
}

field_result_t get_json_admin_p2p(cJSON *parent, const char *key,
                                  admin_p2p_t *out)
{
    cJSON *field = cJSON_GetObjectItemCaseSensitive(parent, key);
    if(!field)
        return FIELD_ABSENT;
    if(!cJSON_IsString(field))
        return FIELD_INVALID;

    const char *value = field->valuestring;
    if(!strcmp(value, "auto"))
        *out = p2pAuto;
    else if(!strcmp(value, "yes"))
        *out = p2pForceTrue;
    else if(!strcmp(value, "no"))
        *out = p2pForceFalse;
    else
        return FIELD_INVALID;

    return FIELD_VALID;
}

bool parse_index_list(cJSON *list_json, unsigned int min_index,
                      unsigned int max_index, unsigned int value,
                      __u16 *array)
{
    if(!cJSON_IsArray(list_json))
        return false;

    cJSON *item;
    cJSON_ArrayForEach(item, list_json)
    {
        if(!cJSON_IsString(item))
            return false;

        const char *s = item->valuestring;
        char *end;
        long first = strtol(s, &end, 10);
        if(end == s || first < min_index || first > max_index)
            return false;

        long last = first;
        if(*end == '-')
        {
            char *end2;
            last = strtol(end + 1, &end2, 10);
            if(end2 == end + 1 || *end2 != '\0'
               || last < min_index || last > max_index)
                return false;
        }
        else if(*end != '\0')
            return false;

        if(first > last)
        {
            long tmp = first;
            first = last;
            last = tmp;
        }

        long idx;
        for(idx = first; idx <= last; ++idx)
            array[idx] = (__u16)value;
    }
    return true;
}
