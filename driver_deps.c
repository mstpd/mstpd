/*
 * driver_deps.c    Driver-specific code.
 *
 *  This program is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU General Public License
 *  as published by the Free Software Foundation; either version
 *  2 of the License, or (at your option) any later version.
 *
 * Authors: Vitalii Demianets <dvitasgs@gmail.com>
 */

#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <asm/byteorder.h>

#include "log.h"
#include "mstp.h"

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
    /* TODO: insert driver-specific code here */
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
