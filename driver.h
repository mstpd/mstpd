/*
 * driver.h    Driver-specific code.
 *
 *  This program is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU General Public License
 *  as published by the Free Software Foundation; either version
 *  2 of the License, or (at your option) any later version.
 *
 * Authors: Vitalii Demianets <vitas@nppfactor.kiev.ua>
 */

#ifndef _MSTP_DRIVER_H
#define _MSTP_DRIVER_H

int driver_set_new_state(per_tree_port_t *ptp, int new_state);

#endif /* _MSTP_DRIVER_H */
