/* SPDX-License-Identifier: GPL-2.0-or-later */
/*****************************************************************************
  Copyright (c) 2006 EMC Corporation.
  Copyright (c) 2011 Factor-SPE

  Authors: Srinivas Aji <Aji_Srinivas@emc.com>
  Authors: Vitalii Demianets <dvitasgs@gmail.com>

******************************************************************************/

#ifndef EPOLL_LOOP_H
#define EPOLL_LOOP_H

#include <sys/epoll.h>
#include <errno.h>
#include <sys/time.h>

struct epoll_event_handler
{
    int fd;
    void *arg;
    void (*handler) (uint32_t events, struct epoll_event_handler * p);
    struct epoll_event *ref_ev; /* if set, epoll loop has reference to this,
                                   so mark that ref as NULL while freeing */
    int priv; /* flag used by epoll_timer */
};

int epoll_timer_init(struct epoll_event_handler* timer);
void epoll_timer_close(struct epoll_event_handler* timer);
void epoll_timer_start(struct epoll_event_handler* timer, int seconds);
int epoll_timer_expired(struct epoll_event_handler* timer);
int epoll_timer_active(struct epoll_event_handler* timer);

int init_epoll(void);

void clear_epoll(void);

int epoll_main_loop(volatile bool *quit);

int add_epoll(struct epoll_event_handler *h);

int remove_epoll(struct epoll_event_handler *h);

#endif /* EPOLL_LOOP_H */
