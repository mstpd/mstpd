#!/bin/bash
#
# MSTPD Test Library
# Common functions for all test scripts
#
# Copyright (C) 2026 Vincent Jardin, Free Mobile
# SPDX-License-Identifier: GPL-2.0-or-later
#

# Exit on undefined variables
set -u

# Configuration

# Paths - resolve absolute paths properly
_TESTLIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_PROJECT_DIR="$(cd "${_TESTLIB_DIR}/../.." && pwd)"

_INSTALL_DIR="${_PROJECT_DIR}/_install/sbin"
MSTPD_BIN="${MSTPD_BIN:-${_INSTALL_DIR}/mstpd}"
MSTPCTL_BIN="${MSTPCTL_BIN:-${_INSTALL_DIR}/mstpctl}"
MSTPD_PID_FILE="${MSTPD_PID_FILE:-${_PROJECT_DIR}/_install/var/run/mstpd.pid}"
TEST_RESULTS_DIR="${TEST_RESULTS_DIR:-${_TESTLIB_DIR}/../results}"
TEST_LOG_DIR="${TEST_LOG_DIR:-${TEST_RESULTS_DIR}/logs}"

# Ensure PID file directory exists
mkdir -p "$(dirname "${MSTPD_PID_FILE}")" 2>/dev/null || true
MSTPD_PID_FILE="${MSTPD_PID_FILE:-/tmp/mstpd-test.pid}"

# Test settings
TEST_TIMEOUT="${TEST_TIMEOUT:-60}"
CONVERGENCE_TIMEOUT="${CONVERGENCE_TIMEOUT:-10}"
VERBOSE="${VERBOSE:-0}"

# Timing constants (use these instead of magic sleep values)
SLEEP_BRIEF="${SLEEP_BRIEF:-0.2}"           # Brief pause for state changes
SLEEP_SHORT="${SLEEP_SHORT:-0.5}"           # Short wait for daemon/process
SLEEP_MEDIUM="${SLEEP_MEDIUM:-1}"           # Medium wait for convergence start
SLEEP_LONG="${SLEEP_LONG:-2}"               # Long wait for STP operations
SLEEP_CONVERGENCE="${SLEEP_CONVERGENCE:-5}" # Wait for full STP convergence

# Setup/teardown hooks
_SUITE_SETUP_FUNC=""
_SUITE_TEARDOWN_FUNC=""
_TEST_SETUP_FUNC=""
_TEST_TEARDOWN_FUNC=""

# Output format options
TAP_OUTPUT="${TAP_OUTPUT:-0}"        # Set to 1 for TAP output
JUNIT_OUTPUT="${JUNIT_OUTPUT:-}"     # Set to file path for JUnit XML output
_TAP_TEST_NUM=0
_JUNIT_RESULTS=()
_JUNIT_SUITE_NAME=""
_JUNIT_SUITE_START=""
_JUNIT_FAILURES=0

# Color codes for output (can be disabled via NO_COLOR or --no-color)
if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
else
    RED="${RED-\033[0;31m}"
    GREEN="${GREEN-\033[0;32m}"
    YELLOW="${YELLOW-\033[0;33m}"
    BLUE="${BLUE-\033[0;34m}"
    NC="${NC-\033[0m}"
fi

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Current test info
CURRENT_TEST_ID=""
CURRENT_TEST_NAME=""
TEST_START_TIME=""

# Logging Functions

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $*"
}

log_debug() {
    if [[ "${VERBOSE}" -ge 1 ]]; then
        echo -e "[DEBUG] $*"
    fi
}

log_trace() {
    if [[ "${VERBOSE}" -ge 2 ]]; then
        echo -e "[TRACE] $*"
    fi
}

# Test Framework Functions

# Initialize test suite
test_suite_init() {
    local suite_name="$1"

    mkdir -p "${TEST_RESULTS_DIR}" "${TEST_LOG_DIR}"

    echo "=============================================="
    echo "Test Suite: ${suite_name}"
    echo "Date: $(date)"
    echo "=============================================="

    TESTS_RUN=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    TESTS_SKIPPED=0

    # Reset TAP counter
    tap_reset

    # Initialize JUnit suite
    junit_start_suite "${suite_name}"
}

# Start a test
test_start() {
    local test_id="$1"
    local test_name="$2"

    CURRENT_TEST_ID="${test_id}"
    CURRENT_TEST_NAME="${test_name}"
    TEST_START_TIME=$(date +%s.%N)

    ((TESTS_RUN++))

    echo ""
    echo "----------------------------------------------"
    echo "Test ${test_id}: ${test_name}"
    echo "----------------------------------------------"
}

# Mark test as passed
test_pass() {
    local msg="${1:-}"
    local end_time
    local duration
    end_time=$(date +%s.%N)
    duration=$(echo "${end_time} - ${TEST_START_TIME}" | bc 2>/dev/null || echo "?")

    ((TESTS_PASSED++))
    log_pass "${CURRENT_TEST_ID}: ${CURRENT_TEST_NAME} (${duration}s)"
    [[ -n "${msg}" ]] && log_info "  ${msg}"

    # Record result
    echo "PASS ${CURRENT_TEST_ID} ${CURRENT_TEST_NAME} ${duration}s ${msg}" >> "${TEST_RESULTS_DIR}/results.log"

    # TAP output
    tap_ok "${CURRENT_TEST_ID} ${CURRENT_TEST_NAME}"

    # JUnit output
    junit_add_result "pass" "${CURRENT_TEST_ID} ${CURRENT_TEST_NAME}" "${duration}" "${msg}"
}

# Mark test as failed
test_fail() {
    local msg="${1:-}"
    local end_time
    local duration
    end_time=$(date +%s.%N)
    duration=$(echo "${end_time} - ${TEST_START_TIME}" | bc 2>/dev/null || echo "?")

    ((TESTS_FAILED++))
    log_fail "${CURRENT_TEST_ID}: ${CURRENT_TEST_NAME} (${duration}s)"
    [[ -n "${msg}" ]] && log_info "  Reason: ${msg}"

    # Record result
    echo "FAIL ${CURRENT_TEST_ID} ${CURRENT_TEST_NAME} ${duration}s ${msg}" >> "${TEST_RESULTS_DIR}/results.log"

    # TAP output
    tap_not_ok "${CURRENT_TEST_ID} ${CURRENT_TEST_NAME}" "${msg}"

    # JUnit output
    junit_add_result "fail" "${CURRENT_TEST_ID} ${CURRENT_TEST_NAME}" "${duration}" "${msg}"
}

# Mark test as skipped
test_skip() {
    local msg="${1:-}"

    ((TESTS_SKIPPED++))
    ((TESTS_RUN--))  # Don't count skipped tests in total run
    log_skip "${CURRENT_TEST_ID}: ${CURRENT_TEST_NAME}"
    [[ -n "${msg}" ]] && log_info "  Reason: ${msg}"

    # Record result
    echo "SKIP ${CURRENT_TEST_ID} ${CURRENT_TEST_NAME} ${msg}" >> "${TEST_RESULTS_DIR}/results.log"

    # TAP output
    tap_skip "${CURRENT_TEST_ID} ${CURRENT_TEST_NAME}" "${msg}"

    # JUnit output
    junit_add_result "skip" "${CURRENT_TEST_ID} ${CURRENT_TEST_NAME}" "0" "${msg}"
}

# Print test suite summary
test_suite_summary() {
    echo ""
    echo "=============================================="
    echo "Test Suite Summary"
    echo "=============================================="
    echo "Tests Run:     ${TESTS_RUN}"
    echo -e "Tests Passed:  ${GREEN}${TESTS_PASSED}${NC}"
    echo -e "Tests Failed:  ${RED}${TESTS_FAILED}${NC}"
    echo -e "Tests Skipped: ${YELLOW}${TESTS_SKIPPED}${NC}"
    echo "=============================================="

    # Write JUnit XML if output file specified
    junit_write_suite

    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    fi
}

# Hook Registration Functions

register_suite_setup() {
    _SUITE_SETUP_FUNC="$1"
}

register_suite_teardown() {
    _SUITE_TEARDOWN_FUNC="$1"
}

register_test_setup() {
    _TEST_SETUP_FUNC="$1"
}

register_test_teardown() {
    _TEST_TEARDOWN_FUNC="$1"
}

# Clear all hooks (call at start of suite)
clear_hooks() {
    _SUITE_SETUP_FUNC=""
    _SUITE_TEARDOWN_FUNC=""
    _TEST_SETUP_FUNC=""
    _TEST_TEARDOWN_FUNC=""
}

# Test Auto-Discovery

# Run all test functions matching the suite pattern
# Usage: run_discovered_tests "T1"
run_discovered_tests() {
    local suite_id="$1"
    local pattern="^test_${suite_id}_[0-9]"

    # Call suite setup if registered
    if [[ -n "${_SUITE_SETUP_FUNC}" ]]; then
        ${_SUITE_SETUP_FUNC}
    fi

    # Discover and run tests in sorted order
    for func in $(compgen -A function | grep -E "${pattern}" | sort -V); do
        ${func}
    done

    # Call suite teardown if registered
    if [[ -n "${_SUITE_TEARDOWN_FUNC}" ]]; then
        ${_SUITE_TEARDOWN_FUNC}
    fi
}

# TAP (Test Anything Protocol) Output Functions

tap_plan() {
    local count="$1"
    [[ "${TAP_OUTPUT}" -eq 1 ]] && echo "1..${count}"
}

tap_ok() {
    local desc="$1"
    ((_TAP_TEST_NUM++)) || true
    [[ "${TAP_OUTPUT}" -eq 1 ]] && echo "ok ${_TAP_TEST_NUM} - ${desc}"
}

tap_not_ok() {
    local desc="$1"
    local reason="${2:-}"
    ((_TAP_TEST_NUM++)) || true
    if [[ "${TAP_OUTPUT}" -eq 1 ]]; then
        echo "not ok ${_TAP_TEST_NUM} - ${desc}"
        [[ -n "${reason}" ]] && echo "# ${reason}"
    fi
}

tap_skip() {
    local desc="$1"
    local reason="${2:-}"
    ((_TAP_TEST_NUM++)) || true
    [[ "${TAP_OUTPUT}" -eq 1 ]] && echo "ok ${_TAP_TEST_NUM} - ${desc} # SKIP ${reason}"
}

tap_reset() {
    _TAP_TEST_NUM=0
}

# JUnit XML Output Functions

junit_start_suite() {
    local name="$1"
    _JUNIT_SUITE_NAME="${name}"
    _JUNIT_SUITE_START=$(date +%s.%N)
    _JUNIT_RESULTS=()
    _JUNIT_FAILURES=0
}

junit_add_result() {
    local status="$1"  # pass, fail, skip
    local name="$2"
    local time="$3"
    local message="${4:-}"

    # Escape XML special characters in message
    message=$(echo "${message}" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')

    _JUNIT_RESULTS+=("${status}|${name}|${time}|${message}")
    if [[ "${status}" == "fail" ]]; then
        ((_JUNIT_FAILURES++)) || true
    fi
}

junit_write_suite() {
    [[ -z "${JUNIT_OUTPUT}" ]] && return

    local end_time
    local total_time
    end_time=$(date +%s.%N)
    total_time=$(echo "${end_time} - ${_JUNIT_SUITE_START}" | bc 2>/dev/null || echo "0")

    local num_tests=${#_JUNIT_RESULTS[@]}
    local num_skipped=0

    # Count skipped tests
    for result in "${_JUNIT_RESULTS[@]}"; do
        if [[ "${result}" == skip\|* ]]; then
            ((num_skipped++)) || true
        fi
    done

    # Write XML header
    cat > "${JUNIT_OUTPUT}" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="${_JUNIT_SUITE_NAME}" tests="${num_tests}" failures="${_JUNIT_FAILURES}" skipped="${num_skipped}" time="${total_time}">
EOF

    # Write test cases
    for result in "${_JUNIT_RESULTS[@]}"; do
        local status name time message
        IFS='|' read -r status name time message <<< "${result}"

        echo "  <testcase name=\"${name}\" time=\"${time}\">" >> "${JUNIT_OUTPUT}"

        case "${status}" in
            fail)
                echo "    <failure message=\"${message}\"/>" >> "${JUNIT_OUTPUT}"
                ;;
            skip)
                echo "    <skipped message=\"${message}\"/>" >> "${JUNIT_OUTPUT}"
                ;;
        esac

        echo "  </testcase>" >> "${JUNIT_OUTPUT}"
    done

    echo "</testsuite>" >> "${JUNIT_OUTPUT}"
}

# Assert functions
assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-Values not equal}"

    if [[ "${expected}" == "${actual}" ]]; then
        log_debug "Assert OK: '${expected}' == '${actual}'"
        return 0
    else
        log_debug "Assert FAIL: expected '${expected}', got '${actual}'"
        test_fail "${msg}: expected '${expected}', got '${actual}'"
        return 1
    fi
}

assert_ne() {
    local not_expected="$1"
    local actual="$2"
    local msg="${3:-Values should not be equal}"

    if [[ "${not_expected}" != "${actual}" ]]; then
        log_debug "Assert OK: '${not_expected}' != '${actual}'"
        return 0
    else
        log_debug "Assert FAIL: '${actual}' should not equal '${not_expected}'"
        test_fail "${msg}: '${actual}' should not equal '${not_expected}'"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-String not found}"

    if [[ "${haystack}" == *"${needle}"* ]]; then
        log_debug "Assert OK: found '${needle}'"
        return 0
    else
        log_debug "Assert FAIL: '${needle}' not found in output"
        test_fail "${msg}: '${needle}' not found"
        return 1
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-String should not be found}"

    if [[ "${haystack}" != *"${needle}"* ]]; then
        log_debug "Assert OK: '${needle}' not found (expected)"
        return 0
    else
        log_debug "Assert FAIL: '${needle}' found but should not be"
        test_fail "${msg}: '${needle}' found but should not be"
        return 1
    fi
}

assert_true() {
    local condition="$1"
    local msg="${2:-Condition should be true}"

    if eval "${condition}"; then
        log_debug "Assert OK: condition true"
        return 0
    else
        log_debug "Assert FAIL: condition false"
        test_fail "${msg}"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local msg="${2:-File should exist}"

    if [[ -f "${file}" ]]; then
        log_debug "Assert OK: file '${file}' exists"
        return 0
    else
        log_debug "Assert FAIL: file '${file}' does not exist"
        test_fail "${msg}: '${file}' does not exist"
        return 1
    fi
}

assert_file_not_exists() {
    local file="$1"
    local msg="${2:-File should not exist}"

    if [[ ! -f "${file}" ]]; then
        log_debug "Assert OK: file '${file}' does not exist"
        return 0
    else
        log_debug "Assert FAIL: file '${file}' exists but should not"
        test_fail "${msg}: '${file}' exists but should not"
        return 1
    fi
}

assert_process_running() {
    local process="$1"
    local msg="${2:-Process should be running}"

    if pgrep -x "${process}" > /dev/null 2>&1; then
        log_debug "Assert OK: process '${process}' is running"
        return 0
    else
        log_debug "Assert FAIL: process '${process}' is not running"
        test_fail "${msg}: '${process}' is not running"
        return 1
    fi
}

assert_process_not_running() {
    local process="$1"
    local msg="${2:-Process should not be running}"

    if ! pgrep -x "${process}" > /dev/null 2>&1; then
        log_debug "Assert OK: process '${process}' is not running"
        return 0
    else
        log_debug "Assert FAIL: process '${process}' is running but should not be"
        test_fail "${msg}: '${process}' is running but should not be"
        return 1
    fi
}

# MSTPD Helper Functions

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This test must be run as root"
        exit 1
    fi
}

# Install bridge-stp to /sbin/ so the kernel can find it.
# The build must have been configured with --sbindir pointing to _install/sbin
# and `make install` must have been run. bridge-stp's internal paths then
# reference _install/sbin/mstpd and _install/sbin/mstpctl which exist.
_BRIDGE_STP_BACKUP=""
install_bridge_stp() {
    local bridge_stp="/sbin/bridge-stp"
    local installed_stp="${_INSTALL_DIR}/bridge-stp"

    # Already installed by us — nothing to do
    if [[ -f "${bridge_stp}" ]] && cmp -s "${bridge_stp}" "${installed_stp}" 2>/dev/null; then
        return 0
    fi

    # Verify the build installed bridge-stp
    if [[ ! -x "${installed_stp}" ]]; then
        log_debug "WARNING: ${installed_stp} not found — run: ./configure --sbindir=\${PWD}/_install/sbin && make && make install"
        return 1
    fi

    # Save existing /sbin/bridge-stp if present (only on first install)
    if [[ -f "${bridge_stp}" ]] && [[ -z "${_BRIDGE_STP_BACKUP}" ]]; then
        _BRIDGE_STP_BACKUP="${bridge_stp}.mstpd-test-backup"
        cp "${bridge_stp}" "${_BRIDGE_STP_BACKUP}"
    fi

    # Copy bridge-stp to /sbin/ where the kernel expects it
    cp "${installed_stp}" "${bridge_stp}"
    chmod 755 "${bridge_stp}"
    log_debug "Installed ${installed_stp} to ${bridge_stp}"
}

# Remove installed bridge-stp and restore any backup
remove_bridge_stp() {
    local bridge_stp="/sbin/bridge-stp"

    if [[ -n "${_BRIDGE_STP_BACKUP}" ]] && [[ -f "${_BRIDGE_STP_BACKUP}" ]]; then
        mv "${_BRIDGE_STP_BACKUP}" "${bridge_stp}"
        _BRIDGE_STP_BACKUP=""
        log_debug "Restored original bridge-stp"
    elif [[ -f "${bridge_stp}" ]]; then
        rm -f "${bridge_stp}"
        log_debug "Removed test bridge-stp"
    fi
}

# Check prerequisites
check_prerequisites() {
    local missing=""

    # Check for required tools
    for tool in ip bridge timeout; do
        if ! command -v "${tool}" &> /dev/null; then
            missing="${missing} ${tool}"
        fi
    done

    # Check for mstpd binary
    if [[ ! -x "${MSTPD_BIN}" ]]; then
        missing="${missing} mstpd(${MSTPD_BIN})"
    fi

    # Check for mstpctl binary
    if [[ ! -x "${MSTPCTL_BIN}" ]]; then
        missing="${missing} mstpctl(${MSTPCTL_BIN})"
    fi

    # Check for kernel modules
    if ! modprobe -n bridge 2>/dev/null; then
        missing="${missing} bridge-module"
    fi

    if [[ -n "${missing}" ]]; then
        echo "Missing prerequisites:${missing}"
        return 1
    fi

    # Install test bridge-stp for kernel user STP support
    install_bridge_stp

    return 0
}

# Start mstpd daemon
mstpd_start() {
    local args_str="${1:--d -v 2}"
    local log_file="${TEST_LOG_DIR}/mstpd.log"
    local -a args
    local pid

    read -ra args <<< "${args_str}"
    log_debug "Starting mstpd with args: ${args_str}"

    # Kill any existing instance
    mstpd_stop 2>/dev/null || true

    # Start mstpd (disown to suppress shell "Killed" messages on stop)
    "${MSTPD_BIN}" "${args[@]}" > "${log_file}" 2>&1 &
    pid=$!
    disown "${pid}" 2>/dev/null || true

    # Wait for daemon to start
    sleep 0.5

    if kill -0 "${pid}" 2>/dev/null; then
        log_debug "mstpd started with PID ${pid}"
        return 0
    else
        log_debug "mstpd failed to start"
        return 1
    fi
}

# Stop mstpd daemon
mstpd_stop() {
    log_debug "Stopping mstpd"

    # Try graceful shutdown first
    if [[ -f "${MSTPD_PID_FILE}" ]]; then
        local pid
        pid=$(cat "${MSTPD_PID_FILE}" 2>/dev/null)
        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            kill -TERM "${pid}" 2>/dev/null
            sleep 0.5
        fi
    fi

    # Force kill any remaining instances
    pkill -9 -x mstpd 2>/dev/null || true
    # Wait for killed processes to avoid shell "Killed" messages
    wait 2>/dev/null || true

    # Wait until no mstpd process remains
    local attempts=0
    while pgrep -x mstpd > /dev/null 2>&1 && [[ ${attempts} -lt 10 ]]; do
        sleep 0.2
        ((attempts++)) || true
    done

    # Clean up PID file
    rm -f "${MSTPD_PID_FILE}" 2>/dev/null || true
    return 0
}

# Check if mstpd is running
mstpd_is_running() {
    pgrep -x mstpd > /dev/null 2>&1
}

# Get mstpd PID
mstpd_get_pid() {
    pgrep -x mstpd 2>/dev/null | head -1
}

# Run mstpctl command
mstpctl() {
    log_trace "mstpctl $*"
    "${MSTPCTL_BIN}" "$@" 2>&1
}

# Query a single parameter from mstpctl (stderr suppressed for clean output)
mstpctl_get() {
    "${MSTPCTL_BIN}" "$@" 2>/dev/null
}

# Get port role from mstpctl (Root, Designated, Alternate, Backup, Disabled)
port_get_role() {
    local bridge="$1"
    local port="$2"
    mstpctl_get showportdetail "${bridge}" "${port}" role
}

# Get port STP state from mstpctl (discarding, learning, forwarding)
port_get_stp_state() {
    local bridge="$1"
    local port="$2"
    mstpctl_get showportdetail "${bridge}" "${port}" state
}

# Get bridge ID from mstpctl
bridge_get_id() {
    local bridge="$1"
    mstpctl_get showbridge "${bridge}" bridge-id
}

# Get designated root from mstpctl
bridge_get_designated_root() {
    local bridge="$1"
    mstpctl_get showbridge "${bridge}" designated-root
}

# Check if bridge is root bridge
bridge_is_root() {
    local bridge="$1"
    local bridge_id
    local designated_root
    bridge_id=$(bridge_get_id "${bridge}")
    designated_root=$(bridge_get_designated_root "${bridge}")
    [[ "${bridge_id}" == "${designated_root}" ]]
}

# Wait for STP convergence (all ports in stable state)
wait_for_convergence() {
    local timeout="${1:-${CONVERGENCE_TIMEOUT}}"
    local start_time
    local current_time
    local stable

    log_debug "Waiting for STP convergence (timeout=${timeout}s)"

    start_time=$(date +%s)
    while true; do
        stable=1
        # Check all bridge ports are not in listening/learning for too long
        for br in $(ip -o link show type bridge 2>/dev/null | awk -F': ' '{print $2}'); do
            for port in /sys/class/net/"${br}"/brif/*; do
                [[ -e "${port}" ]] || continue
                port=$(basename "${port}")
                local state
                state=$(port_get_state "${port}")
                # State 2 = learning, allow briefly during convergence
                if [[ "${state}" == "2" ]]; then
                    stable=0
                fi
            done
        done

        if [[ ${stable} -eq 1 ]]; then
            log_debug "STP converged"
            return 0
        fi

        current_time=$(date +%s)
        if (( current_time - start_time >= timeout )); then
            log_debug "Timeout waiting for convergence"
            return 1
        fi

        sleep 0.5
    done
}

# Enable STP on bridge and add to mstpd
# Setting stp_state=1 triggers the kernel to call /sbin/bridge-stp.
# If bridge-stp returns 0, kernel sets stp_state=2 (BR_USER_STP).
bridge_enable_stp() {
    local bridge="$1"
    local mode="${2:-rstp}"

    # Ensure bridge-stp is installed (idempotent)
    install_bridge_stp

    # Bring bridge up before enabling STP
    ip link set "${bridge}" up

    ip link set "${bridge}" type bridge stp_state 1
    sleep 0.2

    # Verify kernel transitioned to user STP mode
    local state
    state=$(cat "/sys/class/net/${bridge}/bridge/stp_state" 2>/dev/null)
    if [[ "${state}" != "2" ]]; then
        log_debug "WARNING: bridge ${bridge} stp_state=${state}, expected 2 (BR_USER_STP)"
        log_debug "Ensure /sbin/bridge-stp exists and returns 0"
    fi

    mstpctl addbridge "${bridge}" || true
    mstpctl setforcevers "${bridge}" "${mode}" || true

    # Wait until mstpd actually manages the bridge
    wait_for_bridge "${bridge}" 5
}

# Wait until mstpd reports the bridge via showbridge (polls with timeout)
wait_for_bridge() {
    local bridge="$1"
    local timeout="${2:-5}"
    local start_time
    start_time=$(date +%s)

    while true; do
        if mstpctl showbridge "${bridge}" 2>/dev/null | grep -q "${bridge}"; then
            log_debug "Bridge ${bridge} visible to mstpd"
            return 0
        fi

        if (( $(date +%s) - start_time >= timeout )); then
            log_debug "Timeout waiting for mstpd to manage ${bridge}"
            return 1
        fi
        sleep "${SLEEP_BRIEF}"
    done
}

# Network Setup Functions

# Create a bridge
# stp: 0=off, 1=enable (kernel calls /sbin/bridge-stp to decide kernel vs user STP)
# Note: stp_state=2 (BR_USER_STP) cannot be set directly; it is set by the kernel
# when /sbin/bridge-stp returns 0. Use bridge_enable_stp() after creation instead.
bridge_create() {
    local name="$1"
    local stp="${2:-0}"

    log_debug "Creating bridge ${name} (stp=${stp})"

    ip link add "${name}" type bridge || true
    if [[ "${stp}" != "0" ]]; then
        # Bridge must be up for kernel to invoke /sbin/bridge-stp
        ip link set "${name}" up
    fi
    ip link set "${name}" type bridge stp_state "${stp}"

    return 0
}

# Delete a bridge
bridge_delete() {
    local name="$1"

    log_debug "Deleting bridge ${name}"

    ip link set "${name}" down 2>/dev/null || true
    ip link del "${name}" 2>/dev/null || true

    return 0
}

# Check if bridge exists
bridge_exists() {
    local name="$1"

    [[ -d "/sys/class/net/${name}/bridge" ]]
}

# Get bridge STP state
bridge_get_stp_state() {
    local name="$1"

    cat "/sys/class/net/${name}/bridge/stp_state" 2>/dev/null
}

# Create a veth pair
veth_create() {
    local name="$1"
    local peer="${2:-${name}-peer}"

    log_debug "Creating veth pair ${name} <-> ${peer}"

    ip link add "${name}" type veth peer name "${peer}" 2>/dev/null || true
    ip link set "${name}" up
    ip link set "${peer}" up

    return 0
}

# Delete a veth pair
veth_delete() {
    local name="$1"

    log_debug "Deleting veth ${name}"

    ip link del "${name}" 2>/dev/null || true

    return 0
}

# Add port to bridge
bridge_add_port() {
    local bridge="$1"
    local port="$2"

    log_debug "Adding port ${port} to bridge ${bridge}"

    ip link set "${port}" master "${bridge}"

    return $?
}

# Remove port from bridge
bridge_del_port() {
    local port="$1"

    log_debug "Removing port ${port} from bridge"

    ip link set "${port}" nomaster

    return $?
}

# Set link state
link_set_state() {
    local name="$1"
    local state="$2"  # up or down

    log_debug "Setting ${name} ${state}"

    ip link set "${name}" "${state}"

    return $?
}

# Get port state from sysfs
port_get_state() {
    local port="$1"

    cat "/sys/class/net/${port}/brport/state" 2>/dev/null
}

# Verify port state matches between sysfs (kernel) and mstpctl (mstpd).
# Maps mstpctl state names to sysfs numeric values.
# Returns 0 if consistent, 1 if mismatch.
port_verify_state() {
    local bridge="$1"
    local port="$2"

    local sysfs_state
    sysfs_state=$(port_get_state "${port}")

    local mstpctl_state
    mstpctl_state=$(port_get_stp_state "${bridge}" "${port}")

    # Map mstpctl state name to sysfs numeric
    local expected_sysfs=""
    case "${mstpctl_state}" in
        discarding) expected_sysfs="1" ;;
        learning)   expected_sysfs="2" ;;
        forwarding) expected_sysfs="3" ;;
        *)          expected_sysfs="" ;;
    esac

    if [[ -z "${expected_sysfs}" ]]; then
        log_debug "port_verify_state: unknown mstpctl state '${mstpctl_state}' for ${port}"
        return 1
    fi

    if [[ "${sysfs_state}" == "${expected_sysfs}" ]]; then
        log_trace "port_verify_state: ${port} consistent (sysfs=${sysfs_state}, mstpctl=${mstpctl_state})"
        return 0
    else
        log_debug "port_verify_state: ${port} MISMATCH sysfs=${sysfs_state} vs mstpctl=${mstpctl_state} (expected sysfs=${expected_sysfs})"
        return 1
    fi
}

# Wait for port state
wait_for_port_state() {
    local port="$1"
    local expected_state="$2"
    local timeout="${3:-${CONVERGENCE_TIMEOUT}}"

    log_debug "Waiting for ${port} to reach state ${expected_state} (timeout=${timeout}s)"

    local start_time
    local state
    local current_time
    start_time=$(date +%s)
    while true; do
        state=$(port_get_state "${port}")
        if [[ "${state}" == "${expected_state}" ]]; then
            log_debug "Port ${port} reached state ${expected_state}"
            return 0
        fi

        current_time=$(date +%s)
        if (( current_time - start_time >= timeout )); then
            log_debug "Timeout waiting for ${port} state ${expected_state}, current: ${state}"
            return 1
        fi

        sleep 0.5
    done
}

# Wait for a port to reach a specific role (Root, Desg, Altn, Back, Disa)
wait_for_port_role() {
    local bridge="$1"
    local port="$2"
    local expected_role="$3"
    local timeout="${4:-${CONVERGENCE_TIMEOUT}}"

    log_debug "Waiting for ${port} to reach role ${expected_role} (timeout=${timeout}s)"

    local start_time role
    start_time=$(date +%s)
    while true; do
        role=$(port_get_role "${bridge}" "${port}")
        if [[ "${role}" == "${expected_role}" ]]; then
            log_debug "Port ${port} reached role ${expected_role}"
            return 0
        fi

        if (( $(date +%s) - start_time >= timeout )); then
            log_debug "Timeout waiting for ${port} role ${expected_role}, current: ${role}"
            return 1
        fi

        sleep 0.5
    done
}

# Wait for any port in a list to reach one of the given roles.
# Usage: wait_for_any_role "role1|role2" timeout port1:bridge1 port2:bridge2 ...
# Returns 0 and prints the matching port name, or 1 on timeout.
wait_for_any_role() {
    local roles="$1"
    local timeout="$2"
    shift 2

    log_debug "Waiting for any port to reach role [${roles}] (timeout=${timeout}s)"

    local start_time
    start_time=$(date +%s)
    while true; do
        for entry in "$@"; do
            local port="${entry%%:*}"
            local bridge="${entry##*:}"
            local role
            role=$(port_get_role "${bridge}" "${port}")
            if [[ -n "${role}" ]] && [[ "${roles}" == *"${role}"* ]]; then
                log_debug "Port ${port} has role ${role}"
                echo "${port}"
                return 0
            fi
        done

        if (( $(date +%s) - start_time >= timeout )); then
            log_debug "Timeout waiting for any port to reach role [${roles}]"
            return 1
        fi

        sleep 0.5
    done
}

# Wait for STP/RSTP convergence across all bridges.
# Converged when: at least one port forwarding (3), no ports learning (2)
# or disabled (0), and stable for 2 consecutive checks.
wait_for_convergence() {
    local timeout="${1:-${CONVERGENCE_TIMEOUT}}"

    log_debug "Waiting for convergence (timeout=${timeout}s)"

    local start_time stable_count=0
    start_time=$(date +%s)
    while true; do
        local has_forwarding=0
        local has_transitional=0
        local port_count=0
        local fwd_count=0

        for br in $(ip -o link show type bridge 2>/dev/null | awk -F': ' '{print $2}'); do
            for port_path in /sys/class/net/"${br}"/brif/*; do
                [[ -e "${port_path}" ]] || continue
                local port state
                port=$(basename "${port_path}")
                state=$(port_get_state "${port}")
                ((port_count++)) || true
                case "${state}" in
                    3) has_forwarding=1; ((fwd_count++)) || true ;;
                    0|2) has_transitional=1 ;;  # disabled or learning = not settled
                esac
            done
        done

        # Converged: forwarding ports exist, no transitional ports, stable twice
        if [[ ${has_forwarding} -eq 1 ]] && [[ ${has_transitional} -eq 0 ]] && [[ ${port_count} -gt 0 ]]; then
            ((stable_count++)) || true
            if [[ ${stable_count} -ge 2 ]]; then
                log_debug "Convergence reached (${fwd_count}/${port_count} forwarding)"
                return 0
            fi
        else
            stable_count=0
        fi

        if (( $(date +%s) - start_time >= timeout )); then
            log_debug "Timeout waiting for convergence (fwd=${fwd_count}/${port_count}, transitional=${has_transitional})"
            return 1
        fi

        sleep 0.5
    done
}

# Test Topology Setup Functions

# Setup Topology A: Single bridge with ports
setup_topology_a() {
    local bridge="${1:-br0}"
    local num_ports="${2:-2}"

    log_info "Setting up Topology A: single bridge with ${num_ports} ports"

    bridge_create "${bridge}" 0

    for i in $(seq 1 "${num_ports}"); do
        veth_create "${bridge}-p${i}" "${bridge}-p${i}-peer"
        bridge_add_port "${bridge}" "${bridge}-p${i}"
    done

    return 0
}

# Cleanup Topology A
cleanup_topology_a() {
    local bridge="${1:-br0}"
    local num_ports="${2:-2}"

    log_info "Cleaning up Topology A"

    for i in $(seq 1 "${num_ports}"); do
        veth_delete "${bridge}-p${i}" 2>/dev/null || true
    done

    bridge_delete "${bridge}"

    return 0
}

# Setup Topology B: Two bridges connected
setup_topology_b() {
    local br0="${1:-br0}"
    local br1="${2:-br1}"

    log_info "Setting up Topology B: two bridges connected"

    bridge_create "${br0}" 0
    bridge_create "${br1}" 0

    # Create connection between bridges
    veth_create "${br0}-${br1}" "${br1}-${br0}"
    bridge_add_port "${br0}" "${br0}-${br1}"
    bridge_add_port "${br1}" "${br1}-${br0}"

    return 0
}

# Cleanup Topology B
cleanup_topology_b() {
    local br0="${1:-br0}"
    local br1="${2:-br1}"

    log_info "Cleaning up Topology B"

    veth_delete "${br0}-${br1}" 2>/dev/null || true
    bridge_delete "${br0}"
    bridge_delete "${br1}"

    return 0
}

# Setup Topology C: Triangle (3 bridges, loop)
setup_topology_c() {
    local br0="${1:-br0}"
    local br1="${2:-br1}"
    local br2="${3:-br2}"

    log_info "Setting up Topology C: triangle (3 bridges with loop)"

    bridge_create "${br0}" 0
    bridge_create "${br1}" 0
    bridge_create "${br2}" 0

    # br0 <-> br1
    veth_create "${br0}-${br1}" "${br1}-${br0}"
    bridge_add_port "${br0}" "${br0}-${br1}"
    bridge_add_port "${br1}" "${br1}-${br0}"

    # br1 <-> br2
    veth_create "${br1}-${br2}" "${br2}-${br1}"
    bridge_add_port "${br1}" "${br1}-${br2}"
    bridge_add_port "${br2}" "${br2}-${br1}"

    # br2 <-> br0
    veth_create "${br2}-${br0}" "${br0}-${br2}"
    bridge_add_port "${br2}" "${br2}-${br0}"
    bridge_add_port "${br0}" "${br0}-${br2}"

    return 0
}

# Cleanup Topology C
cleanup_topology_c() {
    local br0="${1:-br0}"
    local br1="${2:-br1}"
    local br2="${3:-br2}"

    log_info "Cleaning up Topology C"

    veth_delete "${br0}-${br1}" 2>/dev/null || true
    veth_delete "${br1}-${br2}" 2>/dev/null || true
    veth_delete "${br2}-${br0}" 2>/dev/null || true

    bridge_delete "${br0}"
    bridge_delete "${br1}"
    bridge_delete "${br2}"

    return 0
}

# Topology Wrapper Functions
# These wrappers handle setup, STP enable, test execution, and cleanup

# Run a test function with Topology A
# Usage: with_topology_a "br0" 2 my_test_func [args...]
with_topology_a() {
    local bridge="$1"
    local num_ports="$2"
    local test_func="$3"
    shift 3

    setup_topology_a "${bridge}" "${num_ports}"
    bridge_enable_stp "${bridge}" "rstp"

    ${test_func} "$@"
    local rc=$?

    cleanup_topology_a "${bridge}" "${num_ports}"
    return ${rc}
}

# Run a test function with Topology B
# Usage: with_topology_b "br0" "br1" my_test_func [args...]
with_topology_b() {
    local br0="$1"
    local br1="$2"
    local test_func="$3"
    shift 3

    setup_topology_b "${br0}" "${br1}"
    bridge_enable_stp "${br0}" "rstp"
    bridge_enable_stp "${br1}" "rstp"

    ${test_func} "$@"
    local rc=$?

    cleanup_topology_b "${br0}" "${br1}"
    return ${rc}
}

# Run a test function with Topology C
# Usage: with_topology_c "br0" "br1" "br2" my_test_func [args...]
with_topology_c() {
    local br0="$1"
    local br1="$2"
    local br2="$3"
    local test_func="$4"
    shift 4

    setup_topology_c "${br0}" "${br1}" "${br2}"
    bridge_enable_stp "${br0}" "rstp"
    bridge_enable_stp "${br1}" "rstp"
    bridge_enable_stp "${br2}" "rstp"

    ${test_func} "$@"
    local rc=$?

    cleanup_topology_c "${br0}" "${br1}" "${br2}"
    return ${rc}
}

# Cleanup Functions

# Global cleanup function
cleanup_all() {
    log_info "Performing global cleanup"

    # Stop mstpd
    mstpd_stop 2>/dev/null || true

    # Delete test bridges (br0-br9)
    for i in $(seq 0 9); do
        bridge_delete "br${i}" 2>/dev/null || true
    done

    # Delete any leftover veth pairs
    for iface in $(ip -o link show type veth 2>/dev/null | awk -F': ' '{print $2}' | grep -E '^br[0-9]' || true); do
        ip link del "${iface}" 2>/dev/null || true
    done

    return 0
}

# Final cleanup — called only on exit, not between tests
final_cleanup() {
    cleanup_all
    remove_bridge_stp 2>/dev/null || true
}

# Register cleanup on exit (uses final_cleanup to also restore bridge-stp)
trap_cleanup() {
    trap final_cleanup EXIT INT TERM
}

# Utility Functions

# Wait for a condition with timeout
wait_for() {
    local condition="$1"
    local timeout="${2:-${TEST_TIMEOUT}}"
    local interval="${3:-0.5}"
    local start_time
    local current_time

    start_time=$(date +%s)
    while true; do
        if eval "${condition}"; then
            return 0
        fi

        current_time=$(date +%s)
        if (( current_time - start_time >= timeout )); then
            return 1
        fi

        sleep "${interval}"
    done
}

# Run command with timeout
run_with_timeout() {
    local timeout="$1"
    shift

    timeout "${timeout}" "$@"
    return $?
}

# Get interface MAC address
get_mac_address() {
    local iface="$1"

    cat "/sys/class/net/${iface}/address" 2>/dev/null
}

# Generate random bridge name
random_bridge_name() {
    echo "br-test-$$-${RANDOM}"
}
