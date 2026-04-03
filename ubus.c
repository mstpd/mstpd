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
#include <sys/epoll.h>
#include "bridge_config.h"
#include "mstp.h"
#include "bridge_track.h"
#include "ubus.h"
#include "epoll_loop.h"
#include "log.h"

struct blob_buf b;
static struct ubus_context *ctx = NULL;
static struct epoll_event_handler ubus_epoll_handler;
static bool netifd_subscribed = false;

enum bridge_config_attr {
    BRIDGE_CONFIG_NAME,
    BRIDGE_CONFIG_PROTO,
    BRIDGE_CONFIG_FWD_DELAY,
    BRIDGE_CONFIG_MAX_AGE,
    BRIDGE_CONFIG_AGEING_TIME,
    __BRIDGE_CONFIG_MAX
};

static const struct blobmsg_policy bridge_config_policy[__BRIDGE_CONFIG_MAX] = {
    [BRIDGE_CONFIG_NAME] = { "name", BLOBMSG_TYPE_STRING },
    [BRIDGE_CONFIG_PROTO] = { "proto", BLOBMSG_TYPE_STRING },
    [BRIDGE_CONFIG_FWD_DELAY] = { "forward_delay", BLOBMSG_TYPE_INT32 },
    [BRIDGE_CONFIG_MAX_AGE] = { "max_age", BLOBMSG_TYPE_INT32 },
    [BRIDGE_CONFIG_AGEING_TIME] = { "ageing_time", BLOBMSG_TYPE_INT32 },
};

static bool ubus_set_bridge_config(struct blob_attr *attr)
{
    struct blob_attr *tb[__BRIDGE_CONFIG_MAX], *cur;
    struct bridge_config *cfg;
    CIST_BridgeConfig *bc;

    blobmsg_parse(bridge_config_policy, __BRIDGE_CONFIG_MAX, tb,
                  blobmsg_data(attr), blobmsg_len(attr));

    cur = tb[BRIDGE_CONFIG_NAME];
    if(!cur)
        return false;

    cfg = bridge_config_get(blobmsg_get_string(cur), true);

    bc = &cfg->config;
    bc->protocol_version = protoRSTP;
    bc->set_protocol_version = true;

    if((cur = tb[BRIDGE_CONFIG_PROTO]) != NULL)
    {
        const char *proto = blobmsg_get_string(cur);

        if(!strcmp(proto, "mstp"))
            bc->protocol_version = protoMSTP;
        else if(!strcmp(proto, "stp"))
            bc->protocol_version = protoSTP;
    }

    if((cur = tb[BRIDGE_CONFIG_FWD_DELAY]) != NULL)
    {
        bc->bridge_forward_delay = blobmsg_get_u32(cur);
        bc->set_bridge_forward_delay = true;
    }

    if((cur = tb[BRIDGE_CONFIG_AGEING_TIME]) != NULL)
    {
        bc->bridge_ageing_time = blobmsg_get_u32(cur);
        bc->set_bridge_ageing_time = true;
    }

    if((cur = tb[BRIDGE_CONFIG_MAX_AGE]) != NULL)
    {
        bc->bridge_max_age = blobmsg_get_u32(cur);
        bc->set_bridge_max_age = true;
    }

    return true;
}

static int ubus_add_bridge(struct ubus_context *ctx, struct ubus_object *obj,
                           struct ubus_request_data *req, const char *method,
                           struct blob_attr *msg)
{
    struct blob_attr *tb[__BRIDGE_CONFIG_MAX];
    struct bridge_config *cfg;
    const char *bridge_name;
    unsigned int br_idx = 0;
    if(!ubus_set_bridge_config(msg))
        return UBUS_STATUS_INVALID_ARGUMENT;
    
    blobmsg_parse(bridge_config_policy, __BRIDGE_CONFIG_MAX, tb,
                  blobmsg_data(msg), blobmsg_len(msg));

    bridge_name = blobmsg_get_string(tb[BRIDGE_CONFIG_NAME]);
    br_idx = if_nametoindex(bridge_name);
    if(!br_idx)
        return UBUS_STATUS_NOT_FOUND;
    cfg = bridge_config_get(bridge_name, false);
    if(!cfg)
        return UBUS_STATUS_NOT_FOUND;

    bridge_create(br_idx, &cfg->config);

    return 0;
}

enum bridge_delete_attr {
    BRIDGE_DELETE_NAME,
    __BRIDGE_DELETE_MAX
};

static const struct blobmsg_policy bridge_delete_policy[__BRIDGE_DELETE_MAX] = {
    [BRIDGE_DELETE_NAME] = { "name", BLOBMSG_TYPE_STRING },
};

static int ubus_delete_bridge(struct ubus_context *ctx, struct ubus_object *obj,
                              struct ubus_request_data *req, const char *method,
                              struct blob_attr *msg)
{
    struct blob_attr *tb[__BRIDGE_DELETE_MAX];
    const char *bridge_name;
    unsigned int br_idx = 0;

    blobmsg_parse(bridge_delete_policy, __BRIDGE_DELETE_MAX, tb,
                  blobmsg_data(msg), blobmsg_len(msg));

    if(!tb[BRIDGE_DELETE_NAME])
        return UBUS_STATUS_INVALID_ARGUMENT;

    bridge_name = blobmsg_get_string(tb[BRIDGE_DELETE_NAME]);
    br_idx = if_nametoindex(bridge_name);
    if(!br_idx)
        return UBUS_STATUS_NOT_FOUND;

    bridge_delete(br_idx);

    return 0;
}

static const struct ubus_method mstpd_methods[] = {
    UBUS_METHOD("add_bridge", ubus_add_bridge, bridge_config_policy),
    UBUS_METHOD("delete_bridge", ubus_delete_bridge, bridge_delete_policy),
};

static struct ubus_object_type mstpd_object_type =
    UBUS_OBJECT_TYPE("mstpd", mstpd_methods);

static struct ubus_object mstpd_object = {
    .name = "mstpd",
    .type = &mstpd_object_type,
    .methods = mstpd_methods,
    .n_methods = ARRAY_SIZE(mstpd_methods),
};

static int netifd_device_cb(struct ubus_context *ctx, struct ubus_object *obj,
                            struct ubus_request_data *req, const char *method,
                            struct blob_attr *msg)
{
    if(strcmp(method, "stp_init") != 0)
        return 0;

    ubus_set_bridge_config(msg);

    return 0;
}

static struct ubus_subscriber netifd_sub = {
    .cb = netifd_device_cb,
};

static void try_subscribe_netifd(void)
{
    uint32_t id;

    if(!ctx || netifd_subscribed)
        return;

    if(ubus_lookup_id(ctx, "network.device", &id) != 0)
        return;

    if(ubus_subscribe(ctx, &netifd_sub, id) != 0)
        return;

    netifd_subscribed = true;

    /* Request initial configuration */
    blob_buf_init(&b, 0);
    ubus_invoke(ctx, id, "stp_init", b.head, NULL, NULL, 1000);
}

static void ubus_epoll_cb(uint32_t events, struct epoll_event_handler *h)
{
    if(!ctx)
        return;

    ubus_handle_event(ctx);

    if(!netifd_subscribed)
        try_subscribe_netifd();
}

static bool mstpd_ubus_connect(void)
{
    if(ctx)
        return true;

    ctx = ubus_connect(NULL);
    if(!ctx)
    {
        ERROR("Failed to connect to ubus");
        return false;
    }

    if(ubus_add_object(ctx, &mstpd_object) != 0)
    {
        ERROR("Failed to add ubus object");
        ubus_free(ctx);
        ctx = NULL;
        return false;
    }

    if(ubus_register_subscriber(ctx, &netifd_sub) != 0)
    {
        ERROR("Failed to register ubus subscriber");
        ubus_remove_object(ctx, &mstpd_object);
        ubus_free(ctx);
        ctx = NULL;
        return false;
    }

    ubus_epoll_handler.fd = ctx->sock.fd;
    ubus_epoll_handler.handler = ubus_epoll_cb;
    if(add_epoll(&ubus_epoll_handler) != 0)
    {
        ERROR("Failed to add ubus fd to epoll");
        ubus_unregister_subscriber(ctx, &netifd_sub);
        ubus_remove_object(ctx, &mstpd_object);
        ubus_free(ctx);
        ctx = NULL;
        return false;
    }

    INFO("Connected to ubus");

    try_subscribe_netifd();

    return true;
}

void mstpd_ubus_init(void)
{
    mstpd_ubus_connect();
}

void mstpd_ubus_exit(void)
{
    uint32_t id;

    if(!ctx)
        return;

    remove_epoll(&ubus_epoll_handler);

    if(netifd_subscribed)
        ubus_unregister_subscriber(ctx, &netifd_sub);

    ubus_remove_object(ctx, &mstpd_object);

    /* Notify netifd that we're shutting down */
    blob_buf_init(&b, 0);
    if(ubus_lookup_id(ctx, "network.device", &id) == 0)
        ubus_invoke(ctx, id, "stp_init", b.head, NULL, NULL, 1000);

    ubus_free(ctx);
    ctx = NULL;
}
