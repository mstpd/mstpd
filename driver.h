/*
 * driver.h    Driver-specific code.
 *
 *  This program is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU General Public License
 *  as published by the Free Software Foundation; either version
 *  2 of the License, or (at your option) any later version.
 *
 * Authors: Vitalii Demianets <dvitasgs@gmail.com>
 */

#ifndef _MSTP_DRIVER_H
#define _MSTP_DRIVER_H

int driver_set_new_state(per_tree_port_t *ptp, int new_state);
void driver_flush_all_fids(per_tree_port_t *ptp);
unsigned int driver_set_ageing_time(port_t *prt, unsigned int ageingTime);
bool driver_create_msti(bridge_t *br, __u16 mstid);
bool driver_delete_msti(bridge_t *br, __u16 mstid);
int driver_mstp_init();
void driver_mstp_fini();
bool driver_create_bridge(bridge_t *br, __u8 *macaddr);
bool driver_create_port(port_t *prt, __u16 portno);
void driver_delete_bridge(bridge_t *br);
void driver_delete_port(port_t *prt);

#endif /* _MSTP_DRIVER_H */
