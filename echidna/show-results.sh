#!/bin/bash

# Simple Results Viewer for Echidna Tests

echo "🔍 Echidna Test Results Summary"
echo "==============================="
echo ""

RESULTS_DIR="echidna/results"

if [ ! -d "$RESULTS_DIR" ]; then
    echo "❌ No results directory found. Run ./echidna/run-echidna-tests.sh first."
    exit 1
fi

echo "📊 Test Results:"
echo ""

total_tests=0
violations_found=0

for result_file in "$RESULTS_DIR"/*.txt; do
    if [ -f "$result_file" ]; then
        test_name=$(basename "$result_file" .txt)
        total_tests=$((total_tests + 1))
        
        # Check if test ran successfully
        if grep -q "passing\|failed!💥\|falsified!" "$result_file" 2>/dev/null; then
            # Count violations and passing properties
            violations=$(grep -c "failed!💥\|falsified!" "$result_file" 2>/dev/null || echo "0")
            passing=$(grep -c "passing" "$result_file" 2>/dev/null || echo "0")
            
            if [ "$violations" -gt 0 ]; then
                echo "✅ $test_name: $passing passing, 🚨 $violations violations"
                violations_found=$((violations_found + violations))
            else
                echo "✅ $test_name: $passing passing, no violations"
            fi
        else
            echo "❌ $test_name: failed to run"
        fi
    fi
done

echo ""
echo "📈 Summary:"
echo "  Total Tests: $total_tests"
echo "  Total Violations Found: $violations_found"

if [ "$violations_found" -gt 0 ]; then
    echo ""
    echo "🚨 PROPERTY VIOLATIONS DETECTED!"
    echo "These indicate potential security issues in the smart contracts:"
    echo ""
    
    for result_file in "$RESULTS_DIR"/*.txt; do
        if [ -f "$result_file" ]; then
            test_name=$(basename "$result_file" .txt)
            violations=$(grep -c "failed!💥\|falsified!" "$result_file" 2>/dev/null || echo "0")
            
            if [ "$violations" -gt 0 ]; then
                echo "📋 $test_name violations:"
                grep "failed!💥\|falsified!" "$result_file" 2>/dev/null | head -3 | sed 's/^/   /'
                echo ""
            fi
        fi
    done
    
    echo "💡 To view full details: cat $RESULTS_DIR/[test-name].txt"
else
    echo ""
    echo "✅ All tests passed successfully!"
fi

echo ""
echo "🎯 Fuzzing complete!"