/*****************************************************************************
  Copyright (c) 2006 EMC Corporation.

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
  Authors: Stephen Hemminger <shemminger@linux-foundation.org>

******************************************************************************/

/* #define PACKET_DEBUG */

#include <string.h>
#include <unistd.h>
#include <stdbool.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <linux/if_packet.h>
#include <linux/filter.h>
#include <asm/byteorder.h>

#include "epoll_loop.h"
#include "netif_utils.h"
#include "bridge_ctl.h"
#include "packet.h"
#include "log.h"

static struct epoll_event_handler packet_event;

#ifdef PACKET_DEBUG
static void dump_packet(const unsigned char *buf, int cc)
{
    int i, j;
    for(i = 0; i < cc; i += 16)
    {
        for(j = 0; j < 16 && i + j < cc; ++j)
            printf(" %02x", buf[i + j]);
        printf("\n");
    }
    printf("\n");
    fflush(stdout);
}
#endif

/*
 * To send/receive Spanning Tree packets we use PF_PACKET because
 * it allows the filtering we want but gives raw data
 */
void packet_send(int ifindex, const struct iovec *iov, int iov_count, int len)
{
    int l;
    struct sockaddr_ll sl =
    {
        .sll_family = AF_PACKET,
        .sll_protocol = __constant_cpu_to_be16(ETH_P_802_2),
        .sll_ifindex = ifindex,
        .sll_halen = ETH_ALEN,
    };

    if(iov_count > 0 && iov[0].iov_len > ETH_ALEN)
        memcpy(&sl.sll_addr, iov[0].iov_base, ETH_ALEN);

    struct msghdr msg =
    {
        .msg_name = &sl,
        .msg_namelen = sizeof(sl),
        .msg_iov = (struct iovec *)iov,
        .msg_iovlen = iov_count,
        .msg_control = NULL,
        .msg_controllen = 0,
        .msg_flags = 0,
    };

#ifdef PACKET_DEBUG
    printf("Transmit Dst index %d %02x:%02x:%02x:%02x:%02x:%02x\n",
           sl.sll_ifindex,
           sl.sll_addr[0], sl.sll_addr[1], sl.sll_addr[2],
           sl.sll_addr[3], sl.sll_addr[4], sl.sll_addr[5]);
    {
        int i;
        for(i = 0; i < iov_count; ++i)
            dump_packet(iov[i].iov_base, iov[i].iov_len);
    }
#endif

    l = sendmsg(packet_event.fd, &msg, 0);

    if(l < 0)
    {
        if(errno != EWOULDBLOCK)
            ERROR("send failed: %m");
    }
    else if(l != len)
        ERROR("short write in sendto: %d instead of %d", l, len);
}

static void packet_rcv(uint32_t events, struct epoll_event_handler *h)
{
    int cc;
    unsigned char buf[2048];
    struct sockaddr_ll sl;
    socklen_t salen = sizeof sl;

    cc = recvfrom(h->fd, &buf, sizeof(buf), 0, (struct sockaddr *) &sl, &salen);
    if(cc <= 0)
    {
        ERROR("recvfrom failed: %m");
        return;
    }

#ifdef PACKET_DEBUG
    printf("Receive Src ifindex %d %02x:%02x:%02x:%02x:%02x:%02x\n",
           sl.sll_ifindex,
           sl.sll_addr[0], sl.sll_addr[1], sl.sll_addr[2],
           sl.sll_addr[3], sl.sll_addr[4], sl.sll_addr[5]);

    dump_packet(buf, cc);
#endif
    printf("sll_ifindex = %d and cc = %d\n", sl.sll_ifindex, cc);
    bridge_bpdu_rcv(sl.sll_ifindex, buf, cc);
}

/* Berkeley Packet filter code to filter out spanning tree packets.
   from tcpdump -s 1152 -dd stp
 */
static struct sock_filter stp_filter[] = {
    { 0x28, 0, 0, 0x0000000c },
    { 0x25, 3, 0, 0x000005dc },
    { 0x30, 0, 0, 0x0000000e },
    { 0x15, 0, 1, 0x00000042 },
    { 0x6, 0, 0, 0x00000480 },
    { 0x6, 0, 0, 0x00000000 },
};

/*
 * Open up a raw packet socket to catch all 802.2 packets.
 * and install a packet filter to only see STP (SAP 42)
 *
 * Since any bridged devices are already in promiscious mode
 * no need to add multicast address.
 */
int packet_sock_init(void)
{
    int s;
    struct sock_fprog prog =
    {
        .len = sizeof(stp_filter) / sizeof(stp_filter[0]),
        .filter = stp_filter,
    };

    s = socket(PF_PACKET, SOCK_RAW, htons(ETH_P_802_2));
    if(s < 0)
    {
        ERROR("socket failed: %m");
        return -1;
    }

    if(setsockopt(s, SOL_SOCKET, SO_ATTACH_FILTER, &prog, sizeof(prog)) < 0)
        ERROR("setsockopt packet filter failed: %m");
    else if(fcntl(s, F_SETFL, O_NONBLOCK) < 0)
        ERROR("fcntl set nonblock failed: %m");
    else
    {
        packet_event.fd = s;
        packet_event.handler = packet_rcv;

        if(0 == add_epoll(&packet_event))
            return 0;
    }

    close(s);
    return -1;
}
