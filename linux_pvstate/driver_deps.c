/*
 * driver_deps.c    Propagate MSTI port states to Linux Per VLAN STP states
 *
 *  This program is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU General Public License
 *  as published by the Free Software Foundation; either version
 *  2 of the License, or (at your option) any later version.
 *
 * Authors: Vitalii Demianets <dvitasgs@gmail.com>
 * Authors: Jonas Gorski <jonas.gorski@bisdn.de> -- Set Linux Per VLAN state
 */

#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <asm/byteorder.h>

#include <linux/if_bridge.h>

#include "bridge_ctl.h"
#include "libnetlink.h"
#include "log.h"
#include "mstp.h"

static int br_set_vlan_state(struct rtnl_handle *rth, unsigned ifindex, __u16 vid, __u8 state)
{
    struct
    {
        struct nlmsghdr n;
        struct br_vlan_msg bvm;
        char buf[256];
    } req;
    char entry_buf[256];
    struct rtattr *rta = (void *)entry_buf;
    struct bridge_vlan_info vlan_info;
    struct rtattr *nest;

    memset(&req, 0, sizeof(req));

    req.n.nlmsg_len = NLMSG_LENGTH(sizeof(struct br_vlan_msg));
    req.n.nlmsg_flags = NLM_F_REQUEST | NLM_F_REPLACE;
    req.n.nlmsg_type = RTM_NEWVLAN;
    req.bvm.family = AF_BRIDGE;
    req.bvm.ifindex = ifindex;

    rta->rta_type = BRIDGE_VLANDB_ENTRY;
    rta->rta_len = RTA_LENGTH(0);

    vlan_info.vid = vid;
    vlan_info.flags = BRIDGE_VLAN_INFO_ONLY_OPTS;

    nest = rta_nest(rta, sizeof(entry_buf), BRIDGE_VLANDB_ENTRY);
    rta_addattr_l(rta, sizeof(entry_buf), BRIDGE_VLANDB_ENTRY_INFO, &vlan_info, sizeof(vlan_info));
    rta_addattr8(rta, sizeof(entry_buf), BRIDGE_VLANDB_ENTRY_STATE, state);

    rta_nest_end(rta, nest);

    addraw_l(&req.n, sizeof(req.buf), RTA_DATA(rta), RTA_PAYLOAD(rta));

    return rtnl_talk(rth, &req.n, 0, 0, NULL, NULL, NULL);
}


/* Initialize driver objects & states */
int driver_mstp_init()
{
    return 0;
}

/* Cleanup driver objects & states */
void driver_mstp_fini()
{

}

/* Driver hook that is called before a bridge is created */
bool driver_create_bridge(bridge_t *br, __u8 *macaddr)
{
    return true;
}

/* Driver hook that is called before a port is created */
bool driver_create_port(port_t *prt, __u16 portno)
{
    return true;
}

/* Driver hook that is called when a bridge is deleted */
void driver_delete_bridge(bridge_t *br)
{

}

/* Driver hook that is called when a port is deleted */
void driver_delete_port(port_t *prt)
{

}


/*
 * Set new state (BR_STATE_xxx) for the given port and MSTI.
 * Return new actual state (BR_STATE_xxx) from driver.
 */
int driver_set_new_state(per_tree_port_t *ptp, int new_state)
{
    port_t *prt = ptp->port;
    bridge_t *br = prt->bridge;
    int i;

    /* CIST will already be handled by common code */
    if(0 == ptp->MSTID)
        return new_state;

    /* There is no MSTID -> VID mapping, so for now check all possible VIDs.
     * This is probably not the most efficient, but at least a constant, and
     * checking 4k should not take that long.
     *
     * The mapping is VID -> FID -> MSTID, so let's go that way.
     */
    for (i = 1; i <= MAX_VID; i++)
    {
        __u16 fid = br->vid2fid[i];

        if (br->fid2mstid[fid] != ptp->MSTID)
            continue;

        if (0 > br_set_vlan_state(&rth_state, prt->sysdeps.if_index, i, new_state))
            ERROR_MSTINAME(br, prt, ptp, "Couldn't set kernel if %i vid %i bridge state %i",
                          prt->sysdeps.if_index, i, new_state);
    }

    return new_state;
}

bool driver_create_msti(bridge_t *br, __u16 mstid)
{
    /* TODO: send "create msti" command to driver */
    return true;
}

bool driver_delete_msti(bridge_t *br, __u16 mstid)
{
    /* TODO: send "delete msti" command to driver */
    return true;
}

void driver_flush_all_fids(per_tree_port_t *ptp)
{
    /* TODO: do real flushing.
     * Make it asynchronous, with completion function calling
     * MSTP_IN_all_fids_flushed(ptp)
     */
    MSTP_IN_all_fids_flushed(ptp);
}

/*
 * Set new ageing time (in seconds) for the port.
 * Return new actual ageing time from driver (the ageing timer granularity
 *  in the hardware can be more than 1 sec)
 */
unsigned int driver_set_ageing_time(port_t *prt, unsigned int ageingTime)
{
    /* TODO: do set new ageing time */
    return ageingTime;
}
