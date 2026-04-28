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
#include <libubus.h>
#include <libubox/uloop.h>
#include "config.h"
#include "mstp.h"
#include "worker.h"
#include "ubus.h"

struct blob_buf b;

enum bridge_config_attr {
	BRIDGE_CONFIG_NAME,
	BRIDGE_CONFIG_PROTO,
	BRIDGE_CONFIG_FWD_DELAY,
	BRIDGE_CONFIG_HELLO_TIME,
	BRIDGE_CONFIG_MAX_AGE,
	BRIDGE_CONFIG_AGEING_TIME,
	__BRIDGE_CONFIG_MAX
};

static const struct blobmsg_policy bridge_config_policy[__BRIDGE_CONFIG_MAX] = {
	[BRIDGE_CONFIG_NAME] = { "name", BLOBMSG_TYPE_STRING },
	[BRIDGE_CONFIG_PROTO] = { "proto", BLOBMSG_TYPE_STRING },
	[BRIDGE_CONFIG_FWD_DELAY] = { "forward_delay", BLOBMSG_TYPE_INT32 },
	[BRIDGE_CONFIG_HELLO_TIME] = { "hello_time", BLOBMSG_TYPE_INT32 },
	[BRIDGE_CONFIG_MAX_AGE] = { "max_age", BLOBMSG_TYPE_INT32 },
	[BRIDGE_CONFIG_AGEING_TIME] = { "ageing_time", BLOBMSG_TYPE_INT32 },
};

static bool
ubus_set_bridge_config(struct blob_attr *attr)
{
	struct blob_attr *tb[__BRIDGE_CONFIG_MAX], *cur;
	struct bridge_config *cfg;
	CIST_BridgeConfig *bc;

	blobmsg_parse(bridge_config_policy, __BRIDGE_CONFIG_MAX, tb,
		      blobmsg_data(attr), blobmsg_len(attr));

	cur = tb[BRIDGE_CONFIG_NAME];
	if (!cur)
		return false;

	cfg = bridge_config_get(blobmsg_get_string(cur), true);

	bc = &cfg->config;
	bc->protocol_version = protoRSTP;
	bc->set_protocol_version = true;

	if ((cur = tb[BRIDGE_CONFIG_PROTO]) != NULL) {
		const char *proto = blobmsg_get_string(cur);

		if (!strcmp(proto, "mstp"))
			bc->protocol_version = protoMSTP;
		else if (!strcmp(proto, "stp"))
			bc->protocol_version = protoSTP;
	}

	if ((cur = tb[BRIDGE_CONFIG_FWD_DELAY]) != NULL) {
		bc->bridge_forward_delay = blobmsg_get_u32(cur);
		bc->set_bridge_forward_delay = true;
	}

	if ((cur = tb[BRIDGE_CONFIG_HELLO_TIME]) != NULL) {
		bc->bridge_hello_time = blobmsg_get_u32(cur);
		bc->set_bridge_hello_time = true;
	}

	if ((cur = tb[BRIDGE_CONFIG_AGEING_TIME]) != NULL) {
		bc->bridge_ageing_time = blobmsg_get_u32(cur);
		bc->set_bridge_ageing_time = true;
	}

	if ((cur = tb[BRIDGE_CONFIG_MAX_AGE]) != NULL) {
		bc->bridge_max_age = blobmsg_get_u32(cur);
		bc->set_bridge_max_age = true;
	}

	return true;
}

static int
ubus_add_bridge(struct ubus_context *ctx, struct ubus_object *obj,
		struct ubus_request_data *req, const char *method,
		struct blob_attr *msg)
{
	if (!ubus_set_bridge_config(msg))
		return UBUS_STATUS_INVALID_ARGUMENT;

	return 0;
}

enum bridge_state_attr {
	BRIDGE_STATE_NAME,
	BRIDGE_STATE_ENABLED,
	__BRIDGE_STATE_MAX
};

static const struct blobmsg_policy bridge_state_policy[__BRIDGE_STATE_MAX] = {
	[BRIDGE_STATE_NAME] = { "name", BLOBMSG_TYPE_STRING },
	[BRIDGE_STATE_ENABLED] = { "enabled", BLOBMSG_TYPE_BOOL },
};

static int
ubus_bridge_state(struct ubus_context *ctx, struct ubus_object *obj,
		  struct ubus_request_data *req, const char *method,
		  struct blob_attr *msg)
{
	struct blob_attr *tb[__BRIDGE_STATE_MAX];
	struct bridge_config *cfg;
	const char *bridge_name;
	struct worker_event ev = {};

	blobmsg_parse(bridge_state_policy, __BRIDGE_STATE_MAX, tb,
		      blobmsg_data(msg), blobmsg_len(msg));

	if (!tb[BRIDGE_STATE_NAME] || !tb[BRIDGE_STATE_ENABLED])
		return UBUS_STATUS_INVALID_ARGUMENT;

	bridge_name = blobmsg_get_string(tb[BRIDGE_STATE_NAME]);
	ev.bridge_idx = if_nametoindex(bridge_name);
	if (!ev.bridge_idx)
		return UBUS_STATUS_NOT_FOUND;

	if (blobmsg_get_bool(tb[BRIDGE_STATE_ENABLED])) {
		cfg = bridge_config_get(bridge_name, false);
		if (!cfg)
			return UBUS_STATUS_NOT_FOUND;

		ev.type = WORKER_EV_BRIDGE_ADD;
		ev.bridge_config = cfg->config;
	} else {
		ev.type = WORKER_EV_BRIDGE_REMOVE;
	}

	worker_queue_event(&ev);

	return 0;
}

static const struct ubus_method ustp_methods[] = {
	UBUS_METHOD("add_bridge", ubus_add_bridge, bridge_config_policy),
	UBUS_METHOD("bridge_state", ubus_bridge_state, bridge_state_policy),
};

static struct ubus_object_type ustp_object_type =
	UBUS_OBJECT_TYPE("ustp", ustp_methods);

static struct ubus_object ustp_object = {
	.name = "ustp",
	.type = &ustp_object_type,
	.methods = ustp_methods,
	.n_methods = ARRAY_SIZE(ustp_methods),
};

static int
netifd_device_cb(struct ubus_context *ctx, struct ubus_object *obj,
		 struct ubus_request_data *req, const char *method,
		 struct blob_attr *msg)
{
	if (strcmp(method, "stp_init") != 0)
		return 0;

	ubus_set_bridge_config(msg);

	return 0;
}

static struct ubus_auto_conn conn;
static struct ubus_subscriber netifd_sub;

static void netifd_sub_cb(struct uloop_timeout *t)
{
	uint32_t id;

	if (ubus_lookup_id(&conn.ctx, "network.device", &id) != 0 ||
	    ubus_subscribe(&conn.ctx, &netifd_sub, id) != 0) {
		uloop_timeout_set(t, 1000);
		return;
	}

	blob_buf_init(&b, 0);
	ubus_invoke(&conn.ctx, id, "stp_init", b.head, NULL, NULL, 1000);
}

static struct uloop_timeout netifd_sub_timer = {
	.cb = netifd_sub_cb,
};

static void
netifd_device_remove_cb(struct ubus_context *ctx,
			struct ubus_subscriber *obj, uint32_t id)
{
	uloop_timeout_set(&netifd_sub_timer, 1000);
}

static struct ubus_subscriber netifd_sub = {
	.cb = netifd_device_cb,
	.remove_cb = netifd_device_remove_cb,
};

static void
ubus_connect_handler(struct ubus_context *ctx)
{
	ubus_add_object(ctx, &ustp_object);
	ubus_register_subscriber(ctx, &netifd_sub);
	uloop_timeout_set(&netifd_sub_timer, 1);
}

void ustp_ubus_init(void)
{
	conn.cb = ubus_connect_handler;
	ubus_auto_connect(&conn);
}

void ustp_ubus_exit(void)
{
	uint32_t id;

	ubus_remove_object(&conn.ctx, &ustp_object);
	ubus_unregister_subscriber(&conn.ctx, &netifd_sub);
	blob_buf_init(&b, 0);
	if (ubus_lookup_id(&conn.ctx, "network.device", &id) == 0)
		ubus_invoke(&conn.ctx, id, "stp_init", b.head, NULL, NULL, 1000);
	ubus_auto_shutdown(&conn);
}
