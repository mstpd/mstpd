/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Copyright (c) 2026 Weidmueller Interface GmbH & Co. KG */
/* Applies stored JSON configuration to bridges and ports. */

#include <string.h>
#include <asm/byteorder.h>

#include "config_apply.h"
#include "driver.h"
#include "log.h"

static LIST_HEAD(bridge_configs);

void free_port_cfg(stored_port_cfg_t *port_cfg)
{
    stored_msti_port_cfg_t *msti_cfg, *tmp;

    list_for_each_entry_safe(msti_cfg, tmp, &port_cfg->mstis, list)
    {
        list_del(&msti_cfg->list);
        free(msti_cfg);
    }
    free(port_cfg);
}

void free_bridge_cfg(stored_bridge_cfg_t *br_cfg)
{
    stored_msti_bridge_cfg_t *msti_cfg, *tmp_msti;
    stored_port_cfg_t *port_cfg, *tmp_port;

    list_for_each_entry_safe(msti_cfg, tmp_msti, &br_cfg->mstis, list)
    {
        list_del(&msti_cfg->list);
        free(msti_cfg);
    }
    list_for_each_entry_safe(port_cfg, tmp_port, &br_cfg->ports, list)
    {
        list_del(&port_cfg->list);
        free_port_cfg(port_cfg);
    }
    free(br_cfg);
}

void free_configs(struct list_head *list)
{
    stored_bridge_cfg_t *br_cfg, *tmp;

    list_for_each_entry_safe(br_cfg, tmp, list, list)
        free_bridge_cfg(br_cfg);
    INIT_LIST_HEAD(list);
}

void replace_configs(struct list_head *new_configs)
{
    free_configs(&bridge_configs);
    list_splice_init(new_configs, &bridge_configs);
}

/** Find a stored bridge configuration by interface name.
 * @param name Bridge interface name to match.
 * @return Matching configuration, or NULL if none is stored.
 */
static stored_bridge_cfg_t *find_stored_bridge(const char *name)
{
    stored_bridge_cfg_t *br_cfg;

    list_for_each_entry(br_cfg, &bridge_configs, list)
        if(!strcmp(br_cfg->name, name))
            return br_cfg;
    return NULL;
}

/** Find a stored port configuration within a bridge configuration.
 * @param br_cfg Bridge configuration whose ports are searched.
 * @param name Port interface name to match.
 * @return Matching port configuration, or NULL if none is stored.
 */
static stored_port_cfg_t *find_stored_port(stored_bridge_cfg_t *br_cfg,
                                           const char *name)
{
    stored_port_cfg_t *port_cfg;

    list_for_each_entry(port_cfg, &br_cfg->ports, list)
        if(!strcmp(port_cfg->name, name))
            return port_cfg;
    return NULL;
}

/** Find a bridge tree by host-order MSTID.
 * @param br Bridge whose trees are searched.
 * @param mstid MSTID to find.
 * @return Matching tree, or NULL if the bridge has no such tree.
 */
static tree_t *find_tree(bridge_t *br, __u16 mstid)
{
    tree_t *tree;
    __be16 wanted = __cpu_to_be16(mstid);

    list_for_each_entry(tree, &br->trees, bridge_list)
        if(tree->MSTID == wanted)
            return tree;
    return NULL;
}

/** Find a per-tree port by host-order MSTID.
 * @param prt Port whose tree ports are searched.
 * @param mstid MSTID to find.
 * @return Matching per-tree port, or NULL if the port has no such tree.
 */
static per_tree_port_t *find_ptp(port_t *prt, __u16 mstid)
{
    per_tree_port_t *ptp;
    __be16 wanted = __cpu_to_be16(mstid);

    list_for_each_entry(ptp, &prt->trees, port_list)
        if(ptp->MSTID == wanted)
            return ptp;
    return NULL;
}

void persistent_config_apply_to_bridge(bridge_t *br)
{
    stored_bridge_cfg_t *br_cfg = find_stored_bridge(br->sysdeps.name);
    if(!br_cfg)
        return;

    if(0 != MSTP_IN_set_cist_bridge_config(br, &br_cfg->cist_cfg))
        ERROR_BRNAME(br, "Couldn't apply stored bridge configuration");

    if(br_cfg->set_bridge_priority
       && 0 != MSTP_IN_set_msti_bridge_config(GET_CIST_TREE(br),
                                              br_cfg->bridge_priority))
        ERROR_BRNAME(br, "Couldn't apply stored bridge priority");

    if(br_cfg->set_mst_config_id)
        MSTP_IN_set_mst_config_id(br, br_cfg->mst_config_id_revision,
                                  br_cfg->mst_config_id_name);
    else
    {
        MSTP_BridgeDefaultConfig *defaults = malloc(sizeof(*defaults));
        if(!defaults)
        {
            ERROR_BRNAME(br, "Out of memory");
            return;
        }
        MSTP_IN_get_bridge_default_config(defaults, br->sysdeps.macaddr);
        MSTP_IN_set_mst_config_id(br, defaults->mst_config_id_revision,
                                  defaults->mst_config_id_name);
        free(defaults);
    }

    if(br_cfg->set_vid2fid && !MSTP_IN_set_all_vids2fids(br, br_cfg->vid2fid))
        ERROR_BRNAME(br, "Couldn't apply stored vid2fid table");

    stored_msti_bridge_cfg_t *msti_cfg;
    list_for_each_entry(msti_cfg, &br_cfg->mstis, list)
    {
        tree_t *tree = find_tree(br, msti_cfg->mstid);
        if(!tree)
        {
            if(!driver_create_msti(br, msti_cfg->mstid)
               || !MSTP_IN_create_msti(br, msti_cfg->mstid))
            {
                ERROR_BRNAME(br, "Couldn't create stored MSTI %hu",
                             msti_cfg->mstid);
                continue;
            }
            tree = find_tree(br, msti_cfg->mstid);
        }
        if(tree && 0 != MSTP_IN_set_msti_bridge_config(
                       tree, msti_cfg->bridge_priority))
            ERROR_BRNAME(br, "Couldn't apply stored priority for MSTI %hu",
                        msti_cfg->mstid);
    }

    if(br_cfg->set_fid2mstid
       && !MSTP_IN_set_all_fids2mstids(br, br_cfg->fid2mstid))
        ERROR_BRNAME(br, "Couldn't apply stored fid2mstid table");
}

void persistent_config_apply_to_port(port_t *prt)
{
    stored_bridge_cfg_t *br_cfg =
        find_stored_bridge(prt->bridge->sysdeps.name);
    if(!br_cfg)
        return;

    stored_port_cfg_t *port_cfg = find_stored_port(br_cfg,
                                                   prt->sysdeps.name);
    if(!port_cfg)
        return;

    if(0 != MSTP_IN_set_cist_port_config(prt, &port_cfg->cist_cfg))
        ERROR_PRTNAME(prt, "Couldn't apply stored port configuration");

    if(port_cfg->set_port_priority || port_cfg->set_cist_internal_port_path_cost)
    {
        MSTI_PortConfig cfg = { 0 };
        if(port_cfg->set_port_priority)
        {
            cfg.port_priority = port_cfg->port_priority;
            cfg.set_port_priority = true;
        }
        if(port_cfg->set_cist_internal_port_path_cost)
        {
            cfg.admin_internal_port_path_cost =
                port_cfg->cist_admin_internal_port_path_cost;
            cfg.set_admin_internal_port_path_cost = true;
        }
        if(0 != MSTP_IN_set_msti_port_config(GET_CIST_PTP_FROM_PORT(prt),
                                             &cfg))
            ERROR_PRTNAME(prt, "Couldn't apply stored CIST port priority/"
                         "cost");
    }

    stored_msti_port_cfg_t *msti_cfg;
    list_for_each_entry(msti_cfg, &port_cfg->mstis, list)
    {
        per_tree_port_t *ptp = find_ptp(prt, msti_cfg->mstid);
        if(!ptp)
        {
            ERROR_PRTNAME(prt, "Stored MSTI %hu doesn't exist on this "
                         "bridge", msti_cfg->mstid);
            continue;
        }
        if(0 != MSTP_IN_set_msti_port_config(ptp, &msti_cfg->cfg))
            ERROR_PRTNAME(prt, "Couldn't apply stored port configuration "
                         "for MSTI %hu", msti_cfg->mstid);
    }
}
