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

#include "config.h"

AVL_TREE(bridge_config, avl_strcmp, false, NULL);

static uint32_t bridge_config_timestamp(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);

	return ts.tv_sec;
}

struct bridge_config *
bridge_config_get(const char *name, bool create)
{
	struct bridge_config *cfg;
	char *name_buf;

	cfg = avl_find_element(&bridge_config, name, cfg, node);
	if (cfg)
		goto out;

	if (!create)
		return NULL;

	cfg = calloc_a(sizeof(*cfg), &name_buf, strlen(name) + 1);
	cfg->node.key = strcpy(name_buf, name);
	avl_insert(&bridge_config, &cfg->node);

out:
	cfg->timestamp = bridge_config_timestamp();

	return cfg;
}

void bridge_config_expire(void)
{
	struct bridge_config *cfg, *tmp;
	uint32_t ts;

	ts = bridge_config_timestamp();
	avl_for_each_element_safe(&bridge_config, cfg, node, tmp) {
		if (ts - cfg->timestamp < 60)
			continue;

		avl_delete(&bridge_config, &cfg->node);
		free(cfg);
	}
}
