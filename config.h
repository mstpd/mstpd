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
#ifndef __CONFIG_H
#define __CONFIG_H

#include <libubox/avl.h>
#include <stdint.h>
#include "mstp.h"

extern struct avl_tree bridge_config;

struct bridge_config {
	struct avl_node node;
	uint32_t timestamp;
	CIST_BridgeConfig config;
};

struct bridge_config *bridge_config_get(const char *name, bool create);
void bridge_config_expire(void);

#endif
