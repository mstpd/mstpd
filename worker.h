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
#ifndef __WORKER_H
#define __WORKER_H

#include "mstp.h"

enum worker_event_type {
	WORKER_EV_SHUTDOWN,
	WORKER_EV_RECV_PACKET,
	WORKER_EV_BRIDGE_EVENT,
	WORKER_EV_BRIDGE_ADD,
	WORKER_EV_BRIDGE_REMOVE,
	WORKER_EV_ONE_SECOND,
};

struct worker_event {
	enum worker_event_type type;

	int bridge_idx;
	CIST_BridgeConfig bridge_config;
};

int worker_init(void);
void worker_cleanup(void);
void worker_queue_event(struct worker_event *ev);

#endif
