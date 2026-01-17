#!/bin/bash
#
# MSTPD Test Runner - Unprivileged Mode
#
# Uses Linux user namespaces to run network tests without root.
# Requires: kernel.unprivileged_userns_clone=1
#
# Copyright (C) 2026 Vincent Jardin, Free Mobile
# SPDX-License-Identifier: GPL-2.0-or-later
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if we're already in a user namespace with appropriate permissions
check_namespace_caps() {
    # Check if we can create network interfaces
    if ip link add test-cap-check type dummy 2>/dev/null; then
        ip link del test-cap-check 2>/dev/null
        return 0
    fi
    return 1
}

# Check if unprivileged user namespaces are available
check_userns_available() {
    if [[ -f /proc/sys/kernel/unprivileged_userns_clone ]]; then
        if [[ $(cat /proc/sys/kernel/unprivileged_userns_clone) -eq 1 ]]; then
            return 0
        fi
    fi
    # Try alternative check
    if unshare --user --map-root-user true 2>/dev/null; then
        return 0
    fi
    return 1
}

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [SUITE...]

Run MSTPD tests in an unprivileged user namespace.

This script creates an isolated network namespace where you have
full control over network interfaces without needing root.

Options:
    -h, --help      Show this help message
    All other options are passed to run_tests.sh

Requirements:
    - Linux kernel with user namespace support
    - kernel.unprivileged_userns_clone=1 (or equivalent)

To enable unprivileged user namespaces (as root):
    sysctl -w kernel.unprivileged_userns_clone=1
    # Or permanently in /etc/sysctl.conf

Examples:
    $(basename "$0") -p phase1     Run Phase 1 tests
    $(basename "$0") T1            Run T1 suite only
    $(basename "$0") -l            List available suites

EOF
}

# Main entry point
main() {
    # Show help if requested
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        usage
        exit 0
    fi

    # Check if we already have capabilities (running as root or in namespace)
    if check_namespace_caps; then
        echo "[INFO] Already have network capabilities, running tests directly"
        exec "${SCRIPT_DIR}/run_tests.sh" "$@"
    fi

    # Check if user namespaces are available
    if ! check_userns_available; then
        echo "[ERROR] Unprivileged user namespaces not available."
        echo ""
        echo "Options to fix:"
        echo "  1. Run as root: sudo ./tests/run_tests.sh $*"
        echo "  2. Enable user namespaces: sudo sysctl -w kernel.unprivileged_userns_clone=1"
        echo ""
        exit 1
    fi

    echo "[INFO] Creating unprivileged user/network namespace..."
    echo ""

    # Use unshare to create new user, network, and mount namespaces
    # --user: Create new user namespace
    # --net: Create new network namespace
    # --mount: Create new mount namespace (needed for sysfs)
    # --map-root-user: Map current user to root in namespace
    exec unshare --user --net --mount --map-root-user -- /bin/bash -c '
        # Mount new sysfs for bridge access
        mount -t sysfs none /sys 2>/dev/null || true
        # Run the tests
        exec "$@"
    ' -- "${SCRIPT_DIR}/run_tests.sh" "$@"
}

main "$@"
