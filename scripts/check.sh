#!/usr/bin/env bash
#
# check.sh - Quality check script for OCR Cards to Excel
#
# Usage:
#   bash scripts/check.sh          # Run all checks
#   bash scripts/check.sh --html   # Only HTML validation
#   bash scripts/check.sh --verbose # Detailed output
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VERBOSE=false
HTML_ONLY=false
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --html-only|--html)
            HTML_ONLY=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: bash scripts/check.sh [--verbose] [--html-only]"
            exit 1
            ;;
    esac
done

# Helper functions
print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}ℹ️  $1${NC}"
    fi
}

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Test result tracking
test_start() {
    ((TESTS_TOTAL++))
    print_info "Running: $1"
}

test_pass() {
    ((TESTS_PASSED++))
    print_success "$1"
}

test_fail() {
    ((TESTS_FAILED++))
    print_error "$1"
}

test_skip() {
    ((TESTS_SKIPPED++))
    print_warning "$1 (skipped)"
}

# ============================================
# CHECK 1: Environment
# ============================================

check_environment() {
    print_header "1. Environment Check"

    test_start "Project root exists"
    if [ -d "$PROJECT_ROOT" ]; then
        test_pass "Project root found: $PROJECT_ROOT"
    else
        test_fail "Project root not found"
        exit 1
    fi

    test_start "index_v5.html exists"
    if [ -f "$PROJECT_ROOT/index_v5.html" ]; then
        test_pass "index_v5.html found"
    else
        test_fail "index_v5.html not found"
        exit 1
    fi

    test_start "docs/ directory exists"
    if [ -d "$PROJECT_ROOT/docs" ]; then
        test_pass "docs/ directory found"
    else
        test_fail "docs/ directory not found"
    fi
}

# ============================================
# CHECK 2: HTML Validation
# ============================================

check_html_validation() {
    print_header "2. HTML Validation"

    test_start "HTML5 syntax check"

    # Simple validation: check for basic structure
    local html_file="$PROJECT_ROOT/index_v5.html"
    local errors=0

    # Check for <!DOCTYPE html>
    if ! grep -q "<!DOCTYPE html>" "$html_file"; then
        print_error "Missing DOCTYPE declaration"
        ((errors++))
    fi

    # Check for <html> tag
    if ! grep -q "<html" "$html_file"; then
        print_error "Missing <html> tag"
        ((errors++))
    fi

    # Check for <head> tag
    if ! grep -q "<head>" "$html_file"; then
        print_error "Missing <head> tag"
        ((errors++))
    fi

    # Check for <body> tag
    if ! grep -q "<body>" "$html_file"; then
        print_error "Missing <body> tag"
        ((errors++))
    fi

    # Check for charset
    if ! grep -q 'charset="UTF-8"' "$html_file"; then
        print_warning "UTF-8 charset not found or incorrect format"
    fi

    if [ $errors -eq 0 ]; then
        test_pass "HTML5 structure is valid"
    else
        test_fail "HTML5 validation failed with $errors errors"
    fi

    # Check for common mistakes
    test_start "Check for common HTML issues"
    local issues=0

    # Check for unclosed tags (basic check)
    local open_divs=$(grep -o "<div" "$html_file" | wc -l)
    local close_divs=$(grep -o "</div>" "$html_file" | wc -l)

    if [ "$open_divs" -ne "$close_divs" ]; then
        print_warning "Possible unclosed <div> tags: $open_divs open, $close_divs closed"
        ((issues++))
    fi

    if [ $issues -eq 0 ]; then
        test_pass "No common HTML issues found"
    else
        test_fail "Found $issues HTML issues"
    fi
}

# ============================================
# CHECK 3: JavaScript Syntax
# ============================================

check_javascript() {
    print_header "3. JavaScript Syntax Check"

    test_start "Extract and check JavaScript"

    # Extract JavaScript from HTML
    local js_temp="/tmp/ocr_js_check_$$.js"
    sed -n '/<script>/,/<\/script>/p' "$PROJECT_ROOT/index_v5.html" | \
        sed '/<script>/d; /<\/script>/d' > "$js_temp"

    # Check if Node.js is available for syntax check
    if command -v node &> /dev/null; then
        print_info "Using Node.js for syntax validation"

        # Try to parse JavaScript
        if node -c "$js_temp" 2>/dev/null; then
            test_pass "JavaScript syntax is valid"
        else
            test_fail "JavaScript syntax errors found"
            if [ "$VERBOSE" = true ]; then
                node -c "$js_temp" 2>&1
            fi
        fi
    else
        test_skip "JavaScript syntax check (Node.js not available)"
    fi

    rm -f "$js_temp"

    # Check for common JavaScript issues
    test_start "Check for console.log statements"
    local console_logs=$(grep -c "console.log" "$PROJECT_ROOT/index_v5.html" || true)

    if [ "$console_logs" -gt 5 ]; then
        print_warning "Found $console_logs console.log statements (consider removing in production)"
    else
        test_pass "Console.log usage is acceptable ($console_logs found)"
    fi

    # Check for TODO comments
    test_start "Check for TODO comments"
    local todos=$(grep -c "TODO" "$PROJECT_ROOT/index_v5.html" || true)

    if [ "$todos" -gt 0 ]; then
        print_info "Found $todos TODO comments"
        if [ "$VERBOSE" = true ]; then
            grep -n "TODO" "$PROJECT_ROOT/index_v5.html" || true
        fi
    fi
}

# ============================================
# CHECK 4: Dependencies Check
# ============================================

check_dependencies() {
    print_header "4. Dependencies Check"

    test_start "External libraries loaded"

    local html_file="$PROJECT_ROOT/index_v5.html"

    # Check Tesseract.js
    if grep -q "tesseract.min.js" "$html_file"; then
        test_pass "Tesseract.js is included"
    else
        test_fail "Tesseract.js not found"
    fi

    # Check XLSX.js
    if grep -q "xlsx.full.min.js" "$html_file"; then
        test_pass "XLSX.js is included"
    else
        test_fail "XLSX.js not found"
    fi

    # Check ONNX Runtime (for v5)
    if grep -q "ort.min.js" "$html_file"; then
        test_pass "ONNX Runtime Web is included"
    else
        test_warning "ONNX Runtime Web not found (optional for v5)"
    fi
}

# ============================================
# CHECK 5: Documentation
# ============================================

check_documentation() {
    print_header "5. Documentation Check"

    test_start "docs/architecture.md exists"
    if [ -f "$PROJECT_ROOT/docs/architecture.md" ]; then
        test_pass "architecture.md found"
    else
        test_fail "architecture.md not found"
    fi

    test_start "docs/ai-coding.md exists"
    if [ -f "$PROJECT_ROOT/docs/ai-coding.md" ]; then
        test_pass "ai-coding.md found"
    else
        test_fail "ai-coding.md not found"
    fi

    test_start "docs/decisions/ exists"
    if [ -d "$PROJECT_ROOT/docs/decisions" ]; then
        local adr_count=$(find "$PROJECT_ROOT/docs/decisions" -name "*.md" | wc -l)
        test_pass "decisions/ found with $adr_count ADRs"
    else
        test_warning "decisions/ directory not found"
    fi

    test_start "docs/runbooks/testing.md exists"
    if [ -f "$PROJECT_ROOT/docs/runbooks/testing.md" ]; then
        test_pass "testing.md runbook found"
    else
        test_fail "testing.md not found"
    fi

    test_start "claude.md exists"
    if [ -f "$PROJECT_ROOT/claude.md" ] || git show origin/main:claude.md &>/dev/null; then
        test_pass "claude.md found"
    else
        test_warning "claude.md not found (should be in main branch)"
    fi
}

# ============================================
# CHECK 6: File Size Check
# ============================================

check_file_sizes() {
    print_header "6. File Size Check"

    test_start "index_v5.html size"
    local size=$(stat -f%z "$PROJECT_ROOT/index_v5.html" 2>/dev/null || stat -c%s "$PROJECT_ROOT/index_v5.html" 2>/dev/null)
    local size_kb=$((size / 1024))

    if [ "$size_kb" -lt 100 ]; then
        test_pass "index_v5.html size: ${size_kb}KB (good)"
    elif [ "$size_kb" -lt 200 ]; then
        test_pass "index_v5.html size: ${size_kb}KB (acceptable)"
    else
        test_warning "index_v5.html size: ${size_kb}KB (consider optimization)"
    fi
}

# ============================================
# CHECK 7: Security Check
# ============================================

check_security() {
    print_header "7. Security Check"

    local html_file="$PROJECT_ROOT/index_v5.html"

    test_start "Check for eval() usage"
    if grep -q "eval(" "$html_file"; then
        test_fail "Found eval() usage (security risk)"
    else
        test_pass "No eval() usage found"
    fi

    test_start "Check for innerHTML with user input"
    local innerHTML_count=$(grep -c "innerHTML" "$html_file" || true)
    if [ "$innerHTML_count" -gt 20 ]; then
        print_warning "High usage of innerHTML ($innerHTML_count times) - review for XSS risks"
    else
        test_pass "innerHTML usage is acceptable"
    fi

    test_start "Check for external script sources"
    if grep -q "http://" "$html_file"; then
        print_warning "Found http:// links (prefer https://)"
    else
        test_pass "All external resources use https:// or are local"
    fi
}

# ============================================
# Main execution
# ============================================

main() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   OCR Cards to Excel - Quality Check  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""

    cd "$PROJECT_ROOT"

    # Run checks
    check_environment

    if [ "$HTML_ONLY" = true ]; then
        check_html_validation
    else
        check_html_validation
        check_javascript
        check_dependencies
        check_documentation
        check_file_sizes
        check_security
    fi

    # Print summary
    print_header "Summary"

    echo ""
    echo -e "Total tests:   ${BLUE}$TESTS_TOTAL${NC}"
    echo -e "Passed:        ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed:        ${RED}$TESTS_FAILED${NC}"
    echo -e "Skipped:       ${YELLOW}$TESTS_SKIPPED${NC}"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║         ✅ ALL CHECKS PASSED ✅        ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
        echo ""
        exit 0
    else
        echo -e "${RED}╔════════════════════════════════════════╗${NC}"
        echo -e "${RED}║      ❌ SOME CHECKS FAILED ❌         ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}Fix the issues above and run again.${NC}"
        echo ""
        exit 1
    fi
}

# Run main
main