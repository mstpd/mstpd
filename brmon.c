/* SPDX-License-Identifier: GPL-2.0-or-later */
/*
 * brmon.c      RTnetlink listener.
 *
 * Authors: Stephen Hemminger <shemminger@osdl.org>
 * Modified by Srinivas Aji <Aji_Srinivas@emc.com>
 *    for use in RSTP daemon. - 2006-09-01
 * Modified by Vitalii Demianets <dvitasgs@gmail.com>
 *    for use in MSTP daemon. - 2011-07-18
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <linux/if_bridge.h>
#include <linux/rtnetlink.h>

#include <libmnl/libmnl.h>

#include "log.h"
#include "bridge_ctl.h"
#include "netif_utils.h"
#include "epoll_loop.h"

/* RFC 2863 operational status */
enum
{
    IF_OPER_UNKNOWN,
    IF_OPER_NOTPRESENT,
    IF_OPER_DOWN,
    IF_OPER_LOWERLAYERDOWN,
    IF_OPER_TESTING,
    IF_OPER_DORMANT,
    IF_OPER_UP,
};

/* link modes */
enum
{
    IF_LINK_MODE_DEFAULT,
    IF_LINK_MODE_DORMANT, /* limit upward transition to dormant */
};

static const char *port_states[] =
{
    [BR_STATE_DISABLED] = "disabled",
    [BR_STATE_LISTENING] = "listening",
    [BR_STATE_LEARNING] = "learning",
    [BR_STATE_FORWARDING] = "forwarding",
    [BR_STATE_BLOCKING] = "blocking",
};

static struct mnl_socket *mnl;
static struct epoll_event_handler br_handler;

static struct mnl_socket *mnl_state;
static int state_seq;

static int mnl_talk(struct mnl_socket *nl, struct nlmsghdr *msg,
                    struct nlmsghdr **answer)
{
    char buf[MNL_SOCKET_BUFFER_SIZE];
    unsigned int seq = ++state_seq;
    int ret;

    msg->nlmsg_seq = seq;
    if(!answer)
        msg->nlmsg_flags |= NLM_F_ACK;

    if(mnl_socket_sendto(nl, msg, msg->nlmsg_len) < 0)
    {
        ERROR("mnl_socket_sendto failed: %m");
        return -1;
    }

    ret = mnl_socket_recvfrom(nl, buf, sizeof(*buf));
    if(ret < 0)
    {
        ERROR("mnl_socket_recvfrom failed: %m");
        return -1;
    }

    if(mnl_cb_run(buf, ret, seq, mnl_socket_get_portid(nl), NULL, NULL) < 0)
    {
        ERROR("mnl_cb_run failed: %m");
        return -1;
    }

    if(answer)
    {
        *answer = malloc(msg->nlmsg_len);
        memcpy(*answer, buf, msg->nlmsg_len);
    }

    return 0;
}

int br_set_state(unsigned ifindex, __u8 state)
{
    char buf[MNL_SOCKET_BUFFER_SIZE];
    struct ifinfomsg *ifi;
    struct nlmsghdr *n;

    n = mnl_nlmsg_put_header(buf);
    n->nlmsg_flags = NLM_F_REQUEST | NLM_F_REPLACE;
    n->nlmsg_type = RTM_SETLINK;
    ifi = mnl_nlmsg_put_extra_header(n, sizeof(*ifi));
    ifi->ifi_family = AF_BRIDGE;
    ifi->ifi_index = ifindex;

    mnl_attr_put_u8(n, IFLA_PROTINFO, state);

    return mnl_talk(mnl_state, n, NULL);
}

static const enum mnl_attr_data_type link_policy[IFLA_MAX + 1] =
{
    [IFLA_ADDRESS] = MNL_TYPE_BINARY,
    [IFLA_IFNAME] = MNL_TYPE_STRING,
    [IFLA_MTU] = MNL_TYPE_U32,
    [IFLA_MASTER] = MNL_TYPE_U32,
    [IFLA_PROTINFO] = MNL_TYPE_U8,
    [IFLA_OPERSTATE] = MNL_TYPE_U8,
};

static int link_attr_cb(const struct nlattr *attr, void *data)
{
    const struct nlattr **tb = data;
    int type = mnl_attr_get_type(attr);

    if(mnl_attr_type_valid(attr, IFLA_MAX) < 0)
        return MNL_CB_OK;

    if(mnl_attr_validate(attr, link_policy[type]) < 0)
        return MNL_CB_ERROR;

    tb[type] = attr;
    return MNL_CB_OK;
}

static int link_cb(const struct nlmsghdr *n, void *data)
{
    struct ifinfomsg *ifi = mnl_nlmsg_get_payload(n);
    struct nlattr * tb[IFLA_MAX + 1] = { };
    char b1[IFNAMSIZ];
    int af_family;
    bool newlink;
    int br_index;

    if(n->nlmsg_type == NLMSG_DONE)
        return 0;

    if(mnl_nlmsg_get_payload_len(n) < sizeof(*ifi))
    {
        return -1;
    }

    af_family = ifi->ifi_family;

    if(af_family != AF_BRIDGE && af_family != AF_UNSPEC)
        return 0;

    if(n->nlmsg_type != RTM_NEWLINK && n->nlmsg_type != RTM_DELLINK)
        return 0;

    mnl_attr_parse(n, sizeof(*ifi), link_attr_cb, tb);

    /* Check if we got this from bonding */
    if(tb[IFLA_MASTER] && af_family != AF_BRIDGE)
        return 0;

    if(tb[IFLA_IFNAME] == NULL)
    {
        ERROR("BUG: nil ifname");
        return -1;
    }

    if(n->nlmsg_type == RTM_DELLINK)
        LOG("Deleted ");

    LOG("%d: %s ", ifi->ifi_index, mnl_attr_get_str(tb[IFLA_IFNAME]));

    if(tb[IFLA_OPERSTATE])
    {
        __u8 state = mnl_attr_get_u8(tb[IFLA_OPERSTATE]);
        switch (state)
        {
            case IF_OPER_UNKNOWN:
                LOG("Unknown ");
                break;
            case IF_OPER_NOTPRESENT:
                LOG("Not Present ");
                break;
            case IF_OPER_DOWN:
                LOG("Down ");
                break;
            case IF_OPER_LOWERLAYERDOWN:
                LOG("Lowerlayerdown ");
                break;
            case IF_OPER_TESTING:
                LOG("Testing ");
                break;
            case IF_OPER_DORMANT:
                LOG("Dormant ");
                break;
            case IF_OPER_UP:
                LOG("Up ");
                break;
            default:
                LOG("State(%d) ", state);
        }
    }

    if(tb[IFLA_MTU])
        LOG("mtu %u ", mnl_attr_get_u32(tb[IFLA_MTU]));

    if(tb[IFLA_MASTER])
    {
        LOG("master %s ",
                if_indextoname(mnl_attr_get_u32(tb[IFLA_MASTER]), b1));
    }

    if(tb[IFLA_PROTINFO])
    {
        uint8_t state = mnl_attr_get_u8(tb[IFLA_PROTINFO]);
        if(state <= BR_STATE_BLOCKING)
            LOG("state %s", port_states[state]);
        else
            LOG("state (%d)", state);
    }

    newlink = (n->nlmsg_type == RTM_NEWLINK);

    if(tb[IFLA_MASTER])
        br_index = mnl_attr_get_u32(tb[IFLA_MASTER]);
    else if(is_bridge((char*)mnl_attr_get_str(tb[IFLA_IFNAME])))
        br_index = ifi->ifi_index;
    else
        br_index = -1;

    bridge_notify(br_index, ifi->ifi_index, newlink, ifi->ifi_flags);

    return 0;
}

static int br_linkdump(struct mnl_socket *mnl, int family)
{
    char buf[MNL_SOCKET_DUMP_SIZE];
    unsigned int seq, portid;
    struct nlmsghdr *nlh;
    struct ifinfomsg *ifm;
    int ret;

    nlh = mnl_nlmsg_put_header(buf);
    nlh->nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP;
    nlh->nlmsg_type = RTM_GETLINK;
    nlh->nlmsg_seq = seq = time(NULL);
    ifm = mnl_nlmsg_put_extra_header(nlh, sizeof(*ifm));
    ifm->ifi_family = family;

    portid = mnl_socket_get_portid(mnl);

    ret = mnl_socket_sendto(mnl, nlh, nlh->nlmsg_len);
    if(ret < 0)
    {
        ERROR("Cannot send dump request: %m");
        return -1;
    }

    ret = mnl_socket_recvfrom(mnl, buf, sizeof(buf));
    while (ret > 0)
    {
        ret = mnl_cb_run(buf, ret, seq, portid, link_cb, NULL);
        if(ret <= MNL_CB_STOP)
            break;

        ret = mnl_socket_recvfrom(mnl, buf, sizeof(buf));
    }

    if(ret == -1)
    {
        ERROR("Failed receiving dump request: %m");
        return -1;
    }

    return 0;
}

static inline void br_ev_handler(uint32_t events, struct epoll_event_handler *h)
{
    char buf[MNL_SOCKET_BUFFER_SIZE];
    int ret;

    INFO("rcv messages");

    ret = mnl_socket_recvfrom(mnl, buf, sizeof(buf));
    while(ret > 0)
    {
        ret = mnl_cb_run(buf, ret, 0, 0, link_cb, NULL);
        if(ret <= MNL_CB_STOP)
            break;

        ret = mnl_socket_recvfrom(mnl, buf, sizeof(buf));
    }

    if(ret == -1)
    {
        ERROR("Error on bridge monitoring socket: %m");
    }
}

int init_bridge_ops(void)
{
    int fd;

    mnl = mnl_socket_open(NETLINK_ROUTE);
    if(mnl == NULL)
    {
        ERROR("Couldn't open rtnl socket for monitoring");
        return -1;
    }

    if(mnl_socket_bind(mnl, RTMGRP_LINK, MNL_SOCKET_AUTOPID) < 0)
    {
        ERROR("Couldn't bind rtnl socket for monitoring to RTMGRP_LINK: %m");
        return -1;
    }

    mnl_state = mnl_socket_open(NETLINK_ROUTE);
    if(mnl_state == NULL)
    {
        ERROR("Couldn't open rtnl socket for setting state");
        return -1;
    }

    if(mnl_socket_bind(mnl_state, 0, MNL_SOCKET_AUTOPID) < 0)
    {
        ERROR("Couldn't bind rtnl socket for setting state: %m");
        return -1;
    }

    if(br_linkdump(mnl, PF_BRIDGE) < 0)
    {
        ERROR("Cannot send dump request: %m");
        return -1;
    }

    fd = mnl_socket_get_fd(mnl);
    state_seq = time(NULL);

    if(fcntl(fd, F_SETFL, O_NONBLOCK) < 0)
    {
        ERROR("Error setting O_NONBLOCK: %m");
        return -1;
    }

    br_handler.fd = fd;
    br_handler.arg = NULL;
    br_handler.handler = br_ev_handler;

    if(add_epoll(&br_handler) < 0)
        return -1;

    return 0;
}
