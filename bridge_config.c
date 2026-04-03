/*
 * ustp - OpenWrt STP/RSTP/MSTP daemon
 * Copyright (C) 2021 Felix Fietkau <nbd@nbd.name>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2
 * as published by the Free Software Foundation
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 */
#include <string.h>

#include <libubox/avl-cmp.h>
#include <libubox/utils.h>

#include "bridge_config.h"

AVL_TREE(bridge_config, avl_strcmp, false, NULL);

static uint32_t bridge_config_timestamp(void)
{
    struct timespec ts;

    clock_gettime(CLOCK_MONOTONIC, &ts);

    return ts.tv_sec;
}

struct bridge_config *bridge_config_get(const char *name, bool create)
{
    struct bridge_config *cfg;
    char *name_buf;

    cfg = avl_find_element(&bridge_config, name, cfg, node);
    if(cfg)
        goto out;

    if(!create)
        return NULL;

    cfg = calloc_a(sizeof(*cfg), &name_buf, strlen(name) + 1);
    cfg->node.key = strcpy(name_buf, name);
    avl_insert(&bridge_config, &cfg->node);

out:
    cfg->timestamp = bridge_config_timestamp();

    return cfg;
}

