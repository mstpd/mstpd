/*
 * driver_deps.c    Driver-specific code.
 *
 *  This program is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU General Public License
 *  as published by the Free Software Foundation; either version
 *  2 of the License, or (at your option) any later version.
 *
 * Authors: Vitalii Demianets <vitas@nppfactor.kiev.ua>
 */

#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <asm/byteorder.h>

#include "log.h"
#include "mstp.h"

/*
 * Set new state (BR_STATE_xxx) for the given port and MSTI.
 * Return new actual state (BR_STATE_xxx) from driver.
 */
int driver_set_new_state(per_tree_port_t *ptp, int new_state)
{
    /* TODO: insert driver-specific code here */
    return new_state;
}
