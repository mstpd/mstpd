#!/bin/bash
#
# MSTPD Test Runner
# Run all or selected test suites
#
# Copyright (C) 2026 Vincent Jardin, Free Mobile
# SPDX-License-Identifier: GPL-2.0-or-later
#

# Don't use set -e as cleanup commands may fail benignly

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_CASES_DIR="${SCRIPT_DIR}/cases"
TEST_RESULTS_DIR="${SCRIPT_DIR}/results"
TEST_LIB_DIR="${SCRIPT_DIR}/lib"

# Source the test library
source "${TEST_LIB_DIR}/testlib.sh"

# Available test suites
declare -A TEST_SUITES=(
    ["T1"]="t1_daemon_lifecycle.sh"
    ["T2"]="t2_bridge_management.sh"
    ["T3"]="t3_port_management.sh"
    ["T4"]="t4_stp_convergence.sh"
    ["T5"]="t5_rstp_convergence.sh"
    ["T6"]="t6_mstp_basic.sh"
    ["T7"]="t7_port_roles.sh"
    ["T8"]="t8_port_states.sh"
    ["T9"]="t9_topology_change.sh"
    ["T10"]="t10_edge_ports.sh"
    ["T11"]="t11_bpdu_guard.sh"
    ["T12"]="t12_bridge_assurance.sh"
    ["T13"]="t13_path_cost.sh"
    ["T14"]="t14_priority.sh"
    ["T15"]="t15_timers.sh"
    ["T16"]="t16_protocol_migration.sh"
    ["T17"]="t17_statistics.sh"
    ["T18"]="t18_stress.sh"
    ["T19"]="t19_error_handling.sh"
    ["T20"]="t20_cli.sh"
)

# Phase definitions
declare -A PHASES=(
    ["phase1"]="T1 T2 T3 T20"
    ["phase2"]="T4 T5 T7 T8"
    ["phase3"]="T9 T10 T11 T13 T14 T15"
    ["phase4"]="T6 T12 T16"
    ["phase5"]="T17 T18 T19"
)

# Functions

usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [SUITE...]

Run MSTPD test suites.

Options:
    -h, --help          Show this help message
    -l, --list          List available test suites
    -p, --phase PHASE   Run all suites in a phase (phase1-phase5)
    -a, --all           Run all available test suites
    -v, --verbose       Increase verbosity (can be used multiple times)
    -c, --clean         Clean up test environment before running
    -k, --keep          Keep test environment after tests (don't cleanup)
    -t, --timeout SEC   Set test timeout (default: 60)
    --no-color          Disable colored output
    --tap               Enable TAP (Test Anything Protocol) output
    --junit FILE        Write JUnit XML output to FILE

Suites:
    T1      Daemon Lifecycle tests
    T2      Bridge Management tests
    T3      Port Management tests
    T20     CLI (mstpctl) tests

Phases:
    phase1  Core tests (T1, T2, T3, T20) - CI basic validation
    phase2  STP/RSTP tests (T4, T5, T7, T8) - Protocol correctness
    phase3  Feature tests (T9-T15) - Feature coverage
    phase4  Advanced tests (T6, T12, T16) - MSTP and interop
    phase5  Stability tests (T17-T19) - Production readiness

Examples:
    $(basename "$0") T1              Run Daemon Lifecycle tests
    $(basename "$0") T1 T2           Run T1 and T2 suites
    $(basename "$0") -p phase1       Run all Phase 1 tests
    $(basename "$0") -a              Run all available tests
    $(basename "$0") -v -v T1        Run T1 with maximum verbosity

EOF
}

list_suites() {
    echo "Available test suites:"
    echo ""
    for suite in "${!TEST_SUITES[@]}"; do
        local script="${TEST_SUITES[$suite]}"
        if [[ -f "${TEST_CASES_DIR}/${script}" ]]; then
            echo "  ${suite}  ${script} [available]"
        else
            echo "  ${suite}  ${script} [not implemented]"
        fi
    done | sort
    echo ""
    echo "Phases:"
    for phase in "${!PHASES[@]}"; do
        echo "  ${phase}: ${PHASES[$phase]}"
    done | sort
}

run_suite() {
    local suite="$1"
    local script="${TEST_SUITES[$suite]}"
    local script_path="${TEST_CASES_DIR}/${script}"

    if [[ ! -f "${script_path}" ]]; then
        log_skip "Suite ${suite}: ${script} not implemented"
        return 2
    fi

    log_info "Running test suite: ${suite} (${script})"

    # Run the test script
    if bash "${script_path}"; then
        return 0
    else
        return 1
    fi
}

# Main

main() {
    local suites_to_run=()
    local do_cleanup=1
    local keep_env=0
    local run_all=0

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -l|--list)
                list_suites
                exit 0
                ;;
            -p|--phase)
                shift
                local phase="$1"
                if [[ -z "${PHASES[$phase]:-}" ]]; then
                    echo "Unknown phase: ${phase}"
                    exit 1
                fi
                for suite in ${PHASES[$phase]}; do
                    suites_to_run+=("${suite}")
                done
                ;;
            -a|--all)
                run_all=1
                ;;
            -v|--verbose)
                ((VERBOSE++))
                export VERBOSE
                ;;
            -c|--clean)
                do_cleanup=1
                ;;
            -k|--keep)
                keep_env=1
                ;;
            -t|--timeout)
                shift
                export TEST_TIMEOUT="$1"
                ;;
            --no-color)
                RED=''
                GREEN=''
                YELLOW=''
                BLUE=''  # Used by testlib.sh
                NC=''
                export RED GREEN YELLOW BLUE NC
                ;;
            --tap)
                export TAP_OUTPUT=1
                ;;
            --junit)
                shift
                export JUNIT_OUTPUT="$1"
                ;;
            -*)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                suites_to_run+=("$1")
                ;;
        esac
        shift
    done

    # Check for root
    check_root

    # Check prerequisites
    if ! check_prerequisites; then
        echo "Prerequisites check failed"
        exit 1
    fi

    # If --all, add all available suites
    if [[ ${run_all} -eq 1 ]]; then
        suites_to_run=()
        for suite in "${!TEST_SUITES[@]}"; do
            suites_to_run+=("${suite}")
        done
    fi

    # If no suites specified, show usage
    if [[ ${#suites_to_run[@]} -eq 0 ]]; then
        usage
        exit 1
    fi

    # Sort suites
    mapfile -t suites_to_run < <(printf '%s\n' "${suites_to_run[@]}" | sort -V)

    # Setup results directory
    mkdir -p "${TEST_RESULTS_DIR}"
    rm -f "${TEST_RESULTS_DIR}/results.log"

    # Initial cleanup
    if [[ ${do_cleanup} -eq 1 ]]; then
        log_info "Performing initial cleanup"
        cleanup_all
    fi

    # Register cleanup handler
    if [[ ${keep_env} -eq 0 ]]; then
        trap_cleanup
    fi

    # Print header
    echo ""
    echo "=============================================="
    echo "MSTPD Test Runner"
    echo "Date: $(date)"
    echo "Suites: ${suites_to_run[*]}"
    echo "=============================================="

    # Run test suites
    local total_passed=0
    local total_failed=0
    local total_skipped=0

    for suite in "${suites_to_run[@]}"; do
        echo ""
        log_info "=============================================="
        log_info "Suite: ${suite}"
        log_info "=============================================="

        run_suite "${suite}"
        local rc=$?
        if [[ ${rc} -eq 0 ]]; then
            ((total_passed++)) || true
        elif [[ ${rc} -eq 2 ]]; then
            ((total_skipped++)) || true
        else
            ((total_failed++)) || true
        fi

        # Cleanup between suites
        if [[ ${keep_env} -eq 0 ]]; then
            cleanup_all
        fi
    done

    # Print summary
    echo ""
    echo "=============================================="
    echo "Overall Summary"
    echo "=============================================="
    echo "Suites Run:     ${#suites_to_run[@]}"
    echo -e "Suites Passed:  ${GREEN}${total_passed}${NC}"
    echo -e "Suites Failed:  ${RED}${total_failed}${NC}"
    echo -e "Suites Skipped: ${YELLOW}${total_skipped}${NC}"
    echo "=============================================="
    echo "Results saved to: ${TEST_RESULTS_DIR}/results.log"
    echo "=============================================="

    # Exit with appropriate code
    if [[ ${total_failed} -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

main "$@"
