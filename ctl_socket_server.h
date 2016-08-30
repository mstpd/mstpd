/*****************************************************************************
  Copyright (c) 2006 EMC Corporation.
  Copyright (c) 2011 Factor-SPE

  This program is free software; you can redistribute it and/or modify it
  under the terms of the GNU General Public License as published by the Free
  Software Foundation; either version 2 of the License, or (at your option)
  any later version.

  This program is distributed in the hope that it will be useful, but WITHOUT
  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
  more details.

  You should have received a copy of the GNU General Public License along with
  this program; if not, write to the Free Software Foundation, Inc., 59
  Temple Place - Suite 330, Boston, MA  02111-1307, USA.

  The full GNU General Public License is included in this distribution in the
  file called LICENSE.

  Authors: Srinivas Aji <Aji_Srinivas@emc.com>
  Authors: Vitalii Demianets <dvitasgs@gmail.com>

******************************************************************************/

#ifndef CTL_SOCKET_SERVER_H
#define CTL_SOCKET_SERVER_H

int ctl_socket_init(void);
void ctl_socket_cleanup(void);

extern int ctl_in_handler;
void _ctl_err_log(char *fmt, ...);

#define ctl_err_log(_fmt...) ({ if (ctl_in_handler) _ctl_err_log(_fmt); })

#endif /* CTL_SOCKET_SERVER_H */
