/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Copyright (c) 2026 Weidmueller Interface GmbH & Co. KG */
/*
 * persistent_config.h  Persistent JSON configuration for bridges and ports
 *
 * Stores the configuration loaded from a JSON file for newly created
 * bridges/ports. Reload replaces the stored configuration only; reapply
 * also applies it to existing bridges/ports.
 */

#ifndef PERSISTENT_CONFIG_H
#define PERSISTENT_CONFIG_H

#include "mstp.h"

#define MSTPD_ETC_CONFIG_FILE "/etc/mstpd/config.json"
#define MSTPD_LIB_CONFIG_FILE "/usr/lib/mstpd/config.json"

/** Resolve an explicit configuration path or select a default path.
 * @param path Explicit path to use; NULL or an empty string selects a default.
 * @return The explicit path, the first readable default path, or NULL if no
 *         default configuration file is readable.
 */
const char *persistent_config_resolve(const char *path);

/** Load, validate, and store configuration from a JSON file.
 * @param path Path to the configuration file.
 * @return 0 if the configuration was loaded; -1 if the file is missing,
 *         unreadable, or invalid. On failure, the stored configuration is
 *         unchanged.
 */
int persistent_config_load(const char *path);

#endif /* PERSISTENT_CONFIG_H */
