#!/bin/bash

# Comprehensive Echidna Test Runner
# Runs all working Echidna fuzzing tests for the lend.fam protocol

set -e

ECHIDNA_DIR="echidna"
RESULTS_DIR="echidna/results"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create results directory
mkdir -p "$RESULTS_DIR"

echo -e "${BLUE}🔍 Echidna Fuzzing Test Suite for lend.fam Protocol${NC}"
echo -e "${BLUE}====================================================${NC}"
echo "Results will be saved to: $RESULTS_DIR"
echo ""

# Function to run a single test
run_test() {
    local test_file=$1
    local contract_name=$2
    local test_name=$3
    local test_limit=$4
    
    echo -e "${YELLOW}🧪 Running $test_name...${NC}"
    
    # Check if file exists
    if [ ! -f "$test_file" ]; then
        echo -e "${RED}❌ Test file not found: $test_file${NC}"
        return 1
    fi
    
    # Run the test
    local cmd="echidna $test_file --contract $contract_name --test-limit $test_limit"
    echo "   Command: $cmd"
    
    if eval "$cmd" > "$RESULTS_DIR/${test_name}.txt" 2>&1; then
        # Parse results
        local violations=$(grep -c "failed!💥\|falsified!" "$RESULTS_DIR/${test_name}.txt" 2>/dev/null || echo "0")
        local passing=$(grep -c "passing" "$RESULTS_DIR/${test_name}.txt" 2>/dev/null || echo "0")
        
        if [ "$violations" -gt 0 ]; then
            echo -e "${RED}   🚨 Found $violations property violations!${NC}"
            echo -e "${GREEN}   ✅ $passing properties passing${NC}"
            echo -e "${GREEN}✅ $test_name completed with findings${NC}"
        else
            echo -e "${GREEN}   ✅ All $passing properties passing${NC}"
            echo -e "${GREEN}✅ $test_name completed successfully${NC}"
        fi
        return 0
    else
        # Check error type
        if grep -q "Couldn't compile\|compilation\|Error:" "$RESULTS_DIR/${test_name}.txt" 2>/dev/null; then
            echo -e "${RED}❌ $test_name failed to compile${NC}"
        else
            echo -e "${RED}❌ $test_name runtime error${NC}"
        fi
        return 1
    fi
}

# Clear previous results
echo -e "${BLUE}🧹 Cleaning previous results...${NC}"
rm -f "$RESULTS_DIR"/*.txt

# Track results
declare -a successful_tests=()
declare -a failed_tests=()
total_violations=0
total_passing=0

echo ""
echo -e "${BLUE}🚀 RUNNING CORE FUZZING TESTS${NC}"
echo -e "${BLUE}==============================${NC}"

# Core working tests
tests=(
    "EchidnaLendingManager.sol:EchidnaLendingManager:lending-manager:5000"
    "EchidnaEpochManager.sol:EchidnaEpochManager:epoch-manager:5000"
    "EchidnaMathematicalInvariants.sol:EchidnaMathematicalInvariants:mathematical-invariants:3000"
    "EchidnaCollectionsVault.sol:EchidnaCollectionsVault:collections-vault:5000"
    "EchidnaBasicVault.sol:EchidnaBasicVault:basic-vault:3000"
    "EchidnaMerkleClaimTest.sol:EchidnaMerkleClaimTest:merkle-claim:3000"
)

# Run each test
for test_spec in "${tests[@]}"; do
    IFS=':' read -r test_file contract_name test_name test_limit <<< "$test_spec"
    echo ""
    
    if run_test "$ECHIDNA_DIR/$test_file" "$contract_name" "$test_name" "$test_limit"; then
        successful_tests+=("$test_name")
        
        # Count violations and passing for this test
        violations=$(grep -c "failed!💥\|falsified!" "$RESULTS_DIR/${test_name}.txt" 2>/dev/null || echo "0")
        passing=$(grep -c "passing" "$RESULTS_DIR/${test_name}.txt" 2>/dev/null || echo "0")
        total_violations=$((total_violations + violations))
        total_passing=$((total_passing + passing))
    else
        failed_tests+=("$test_name")
    fi
    
    echo -e "${BLUE}📝 Results saved to: $RESULTS_DIR/${test_name}.txt${NC}"
done

echo ""
echo -e "${BLUE}📊 FINAL SUMMARY${NC}"
echo -e "${BLUE}=================${NC}"

# Print individual test results
echo ""
echo "Test Results:"
for test_name in "${successful_tests[@]}"; do
    violations=$(grep -c "failed!💥\|falsified!" "$RESULTS_DIR/${test_name}.txt" 2>/dev/null || echo "0")
    passing=$(grep -c "passing" "$RESULTS_DIR/${test_name}.txt" 2>/dev/null || echo "0")
    
    if [ "$violations" -gt 0 ]; then
        echo -e "  ${GREEN}✅${NC} $test_name: $passing passing, ${RED}$violations violations${NC}"
    else
        echo -e "  ${GREEN}✅${NC} $test_name: $passing passing, no violations"
    fi
done

for test_name in "${failed_tests[@]}"; do
    echo -e "  ${RED}❌${NC} $test_name: compilation/runtime error"
done

echo ""
echo -e "${BLUE}📈 OVERALL STATISTICS:${NC}"
echo "  Tests Run: ${#tests[@]}"
echo "  Successful: ${#successful_tests[@]}"
echo "  Failed: ${#failed_tests[@]}"
echo "  Total Properties Passing: $total_passing"
echo "  Total Violations Found: $total_violations"

# Security summary
if [ "$total_violations" -gt 0 ]; then
    echo ""
    echo -e "${RED}🚨 SECURITY FINDINGS:${NC}"
    echo -e "${RED}   $total_violations property violations detected!${NC}"
    echo -e "${RED}   These indicate potential vulnerabilities in the smart contracts.${NC}"
    echo ""
    echo -e "${YELLOW}🔍 To view specific violations:${NC}"
    echo "   grep -A 3 -B 1 'failed!💥\\|falsified!' $RESULTS_DIR/*.txt"
    echo ""
    echo -e "${YELLOW}📋 Violations by test:${NC}"
    for test_name in "${successful_tests[@]}"; do
        violations=$(grep -c "failed!💥\|falsified!" "$RESULTS_DIR/${test_name}.txt" 2>/dev/null || echo "0")
        if [ "$violations" -gt 0 ]; then
            echo "   $test_name: $violations violations"
            # Show the specific failed properties
            grep "failed!💥\|falsified!" "$RESULTS_DIR/${test_name}.txt" | head -3 | sed 's/^/     /'
        fi
    done
else
    echo ""
    echo -e "${GREEN}✅ NO VIOLATIONS FOUND${NC}"
    echo -e "${GREEN}   All property tests passed successfully!${NC}"
fi

echo ""
echo -e "${BLUE}📁 Detailed Results:${NC}"
for result_file in "$RESULTS_DIR"/*.txt; do
    if [ -f "$result_file" ]; then
        echo "   cat $(basename "$result_file")"
    fi
done

echo ""
echo -e "${GREEN}🎯 FUZZING COMPLETE!${NC}"
echo "The Echidna fuzzing test suite has completed."

if [ "$total_violations" -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Action required: Review and fix the identified property violations.${NC}"
else
    echo -e "${GREEN}✅ All tests passed - protocol appears secure under current test scenarios.${NC}"
fi

echo ""
echo -e "${BLUE}Happy fuzzing! 🚀${NC}"