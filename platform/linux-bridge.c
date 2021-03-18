/*
 * linux-bridge.c   Linux bridging backend for mstpd
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *
 * Authors: Pavel Šimerda <code@simerda.eu>
 * Authors: Jonas Gorski <jonas.gorski@bisdn.de>
 */

#include <errno.h>

#include <linux/netlink.h>
#include <linux/if_bridge.h>

#include "libnetlink.h"
#include "bridge_ctl.h"
#include "log.h"

#include "platform.h"

#define VID_COUNT 4096

static struct rtnl_handle *get_rtnl_handle(void)
{
    /* TODO: We should instead build a singleton instance here. */
    return &rth_state;
}

static int port_update(unsigned ifindex, __u8 state)
{
    struct rtnl_handle *rth = get_rtnl_handle();
    struct {
        struct nlmsghdr n;
        struct ifinfomsg ifi;
        char buf[256];
    } req = {};

    req.n.nlmsg_len = NLMSG_LENGTH(sizeof req.ifi);
    req.n.nlmsg_flags = NLM_F_REQUEST | NLM_F_REPLACE;
    req.n.nlmsg_type = RTM_SETLINK;
    req.ifi.ifi_family = AF_BRIDGE;
    req.ifi.ifi_index = ifindex;

    addattr8(&req.n, sizeof(req.buf), IFLA_PROTINFO, state);

    return rtnl_talk(rth, &req.n, 0, 0, NULL, NULL, NULL);
}

#ifdef RTM_GETVLAN
static int vlan_update(unsigned ifindex, __u16 vid,
#ifdef HAVE_EXPERIMENTAL_KERNEL_VID_FID_SID_STATE_RELATION
                       __u16 fid, __u16 mstid,
#endif
                       __u8 state)
{
    struct rtnl_handle *rth = get_rtnl_handle();
    struct {
        struct nlmsghdr n;
        struct br_vlan_msg bvm;
        char buf[256];
    } req = {};
    char entry_buf[256] = {};
    struct rtattr *rta = (void *)entry_buf;
    struct bridge_vlan_info vlan_info = {
        .vid = vid,
        .flags = BRIDGE_VLAN_INFO_ONLY_OPTS,
    };
    struct rtattr *nest;

    req.n.nlmsg_len = NLMSG_LENGTH(sizeof req.bvm);
    req.n.nlmsg_flags = NLM_F_REQUEST | NLM_F_REPLACE;
    req.n.nlmsg_type = RTM_NEWVLAN;
    req.bvm.family = AF_BRIDGE;
    req.bvm.ifindex = ifindex;

    rta->rta_type = BRIDGE_VLANDB_ENTRY;
    rta->rta_len = RTA_LENGTH(0);

    nest = rta_nest(rta, sizeof(entry_buf), BRIDGE_VLANDB_ENTRY);
    if (vid)
        rta_addattr_l(rta, sizeof(entry_buf), BRIDGE_VLANDB_ENTRY_INFO, &vlan_info, sizeof(vlan_info));
#ifdef HAVE_EXPERIMENTAL_KERNEL_VID_FID_SID_STATE_RELATION
    if (fid)
        rta_addattr16(rta, sizeof(entry_buf), BRIDGE_VLANDB_ENTRY_FID, fid);
    if (mstid)
        rta_addattr16(rta, sizeof(entry_buf), BRIDGE_VLANDB_ENTRY_SID, mstid);
#endif
    if (state)
        rta_addattr8(rta, sizeof(entry_buf), BRIDGE_VLANDB_ENTRY_STATE, state);
    rta_nest_end(rta, nest);

    addraw_l(&req.n, sizeof(req.buf), RTA_DATA(rta), RTA_PAYLOAD(rta));

    return rtnl_talk(rth, &req.n, 0, 0, NULL, NULL, NULL);
}
#endif

#ifdef HAVE_EXPERIMENTAL_KERNEL_VID_FID_SID_STATE_RELATION
#else
__u16 vid2mstid[VID_COUNT] = {};
#endif

int bridge_port_vlan_configure(unsigned ifindex, __u16 vid, __u16 fid, __u16 mstid)
{
    INFO("[linux-bridge] port %d vid %d fid %d mstid %d", ifindex, vid, fid, mstid);
#ifdef RTM_GETVLAN
#ifdef HAVE_EXPERIMENTAL_KERNEL_VID_FID_SID_STATE_RELATION
    return vlan_update(ifindex, vid, fid, mstid, 0);
#else
    vid2mstid[vid] = mstid;
    return 0;
#endif
#else
    return -ENOTSUP;
#endif
}

int bridge_port_tree_set_state(unsigned ifindex, __u16 mstid, __u8 state)
{
    INFO("[linux-bridge] port %d mstid %d state %d", ifindex, mstid, state);
    if (mstid == 0)
        return port_update(ifindex, state);
#ifdef RTM_GETVLAN
#ifdef HAVE_EXPERIMENTAL_KERNEL_VID_FID_SID_STATE_RELATION
    return vlan_update(ifindex, 0, 0, mstid, state);
#else
    int vid;
    int ret = 0;

    for (vid = 1; ret == 0 && vid < VID_COUNT; vid++)
        if (vid2mstid[vid] == mstid)
            ret = vlan_update(ifindex, vid, state);
    return ret;
#endif
#else
    return -ENOTSUP;
#endif
}
