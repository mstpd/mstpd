/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Copyright (c) 2026 Weidmueller Interface GmbH & Co. KG */
#ifndef CONFIG_APPLY_H
#define CONFIG_APPLY_H

#include <net/if.h>

#include "list.h"
#include "mstp.h"

typedef struct
{
    struct list_head list;
    __u16 mstid;
    __u8 bridge_priority;
} stored_msti_bridge_cfg_t;

typedef struct
{
    struct list_head list;
    __u16 mstid;
    MSTI_PortConfig cfg;
} stored_msti_port_cfg_t;

typedef struct
{
    struct list_head list;
    char name[IFNAMSIZ];
    bool set_port_priority;
    __u8 port_priority;
    CIST_PortConfig cist_cfg;
    bool set_cist_internal_port_path_cost;
    __u32 cist_admin_internal_port_path_cost;
    struct list_head mstis;
} stored_port_cfg_t;

typedef struct
{
    struct list_head list;
    char name[IFNAMSIZ];
    bool set_bridge_priority;
    __u8 bridge_priority;
    CIST_BridgeConfig cist_cfg;
    bool set_mst_config_id;
    __u16 mst_config_id_revision;
    __u8 mst_config_id_name[CONFIGURATION_NAME_LEN];
    bool set_vid2fid;
    __u16 vid2fid[MAX_VID + 1];
    bool set_fid2mstid;
    __u16 fid2mstid[MAX_FID + 1];
    struct list_head mstis;
    struct list_head ports;
} stored_bridge_cfg_t;

/** Free a stored port configuration and all of its MSTI entries.
 * @param port_cfg Port configuration to release; must not be NULL.
 */
void free_port_cfg(stored_port_cfg_t *port_cfg);

/** Free a stored bridge configuration, including its ports and MSTIs.
 * @param br_cfg Bridge configuration to release; must not be NULL.
 */
void free_bridge_cfg(stored_bridge_cfg_t *br_cfg);

/** Free all bridge configurations linked from a list head.
 * @param list List head containing stored_bridge_cfg_t entries,
 * which will be freed. The list head is left initialized and empty.
 */
void free_configs(struct list_head *list);

/** Replace the active stored configuration with a newly parsed list.
 * @param new_configs List head containing the replacement configurations,
 * which will be emptied.
 */
void replace_configs(struct list_head *new_configs);

/** Apply stored configuration to one bridge.
 * @param br Bridge receiving the currently stored configuration.
 * @return Nothing; does nothing when no configuration exists for the bridge.
 */
void persistent_config_apply_to_bridge(bridge_t *br);

/** Apply stored configuration to one port.
 * @param prt Port receiving the currently stored configuration.
 * @return Nothing; does nothing when no configuration exists for its bridge
 *         or port name.
 */
void persistent_config_apply_to_port(port_t *prt);

#endif /* CONFIG_APPLY_H */
