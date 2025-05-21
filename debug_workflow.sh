#!/bin/bash

set -e

echo "🔍 Debug Workflow Tool"

# Tạo thư mục báo cáo
mkdir -p reports

# Khởi tạo file báo cáo
init_report() {
  echo "## Kết quả kiểm tra tự động" > reports/analysis_results.md
  echo "### Thời gian kiểm tra: $(date)" >> reports/analysis_results.md
  echo "" >> reports/analysis_results.md

  # Lấy thông tin commits
  echo "### Commits:" >> reports/analysis_results.md
  git log --pretty=format:"- %h: %s" -n 5 >> reports/analysis_results.md
  echo "" >> reports/analysis_results.md

  # Lấy thông tin file thay đổi
  echo "### Files thay đổi:" >> reports/analysis_results.md
  git diff --name-only HEAD~1 HEAD >> reports/analysis_results.md 2>/dev/null || echo "Không thể lấy danh sách file thay đổi" >> reports/analysis_results.md
  echo "" >> reports/analysis_results.md

  # Tổng hợp kết quả kiểm tra
  echo "### Kết quả kiểm tra:" >> reports/analysis_results.md
}

# Cài đặt dependencies
setup_dependencies() {
  echo "🔍 Cài đặt dependencies"
  flutter pub get
}

# Tạo models và locale
generate_code() {
  echo "🔍 Tạo models và locale"
  flutter pub run build_runner build --delete-conflicting-outputs
  # flutter pub run bin/generate.dart
}

# Phân tích code
analyze_code() {
  echo "🔍 Phân tích code"
  if flutter analyze > /dev/null 2>&1; then
    echo "✅ **Phân tích code**: Passed" | tee -a reports/analysis_results.md
  else
    echo "❌ **Phân tích code**: Failed" | tee -a reports/analysis_results.md
  fi
}

# Kiểm tra lỗi chính tả
check_spelling() {
  echo "🔍 Kiểm tra lỗi chính tả"
  spelling_errors=$(grep -r -i "\b\(recieve\|lenght\|heigth\|widht\|paramater\|cancle\|retreive\|occured\)\b" --include="*.dart" lib/ || echo "")
  if [ -n "$spelling_errors" ]; then
    echo "⚠️ **Lỗi chính tả**: Tìm thấy" | tee -a reports/analysis_results.md
    echo "$spelling_errors"
  else
    echo "✅ **Lỗi chính tả**: Không tìm thấy" | tee -a reports/analysis_results.md
  fi
}

# Kiểm tra quy tắc đặt tên
check_naming_conventions() {
  echo "🔍 Kiểm tra quy tắc đặt tên"
  class_naming=$(grep -r "class [a-z]" --include="*.dart" lib/ || echo "")
  if [ -n "$class_naming" ]; then
    echo "⚠️ **Quy tắc đặt tên lớp**: Tìm thấy lớp không tuân theo UpperCamelCase" | tee -a reports/analysis_results.md
    echo "$class_naming"
  else
    echo "✅ **Quy tắc đặt tên lớp**: OK" | tee -a reports/analysis_results.md
  fi

  variable_naming=$(grep -r "final [A-Z]" --include="*.dart" lib/ || echo "")
  if [ -n "$variable_naming" ]; then
    echo "⚠️ **Quy tắc đặt tên biến**: Tìm thấy biến không tuân theo lowerCamelCase" | tee -a reports/analysis_results.md
    echo "$variable_naming"
  else
    echo "✅ **Quy tắc đặt tên biến**: OK" | tee -a reports/analysis_results.md
  fi
}

# Kiểm tra commented-out code
check_commented_code() {
  echo "🔍 Kiểm tra commented-out code"
  commented_code=$(grep -r "//.*\(return\|if\|}\|{\|for\|while\)" --include="*.dart" lib/ | wc -l)
  if [ $commented_code -gt 0 ]; then
    echo "⚠️ **Commented-out code**: $commented_code dòng tiềm năng" | tee -a reports/analysis_results.md
  else
    echo "✅ **Commented-out code**: Không tìm thấy" | tee -a reports/analysis_results.md
  fi
}

# Kiểm tra print statements
check_print_statements() {
  echo "🔍 Kiểm tra print statements"
  result=$(grep -r "print(" --include="*.dart" lib/ || echo "")
  if [ -n "$result" ]; then
    echo "❌ **Print statements**: Tìm thấy" | tee -a reports/analysis_results.md
    echo "$result"
  else
    echo "✅ **Print statements**: Không tìm thấy" | tee -a reports/analysis_results.md
  fi
}

# Kiểm tra switch cases
check_switch_cases() {
  echo "🔍 Kiểm tra switch cases"
  switches=$(grep -r "switch" --include="*.dart" lib/ | wc -l)
  defaults=$(grep -r "default:" --include="*.dart" lib/ | wc -l)
  if [ $switches -gt $defaults ]; then
    echo "⚠️ **Switch cases**: Không phải tất cả switch statements đều có default case ($defaults/$switches)" | tee -a reports/analysis_results.md
  else
    echo "✅ **Switch cases**: Tất cả switch statements đều có default case" | tee -a reports/analysis_results.md
  fi
}

# Kiểm tra độ dài dòng code
check_line_length() {
  echo "🔍 Kiểm tra độ dài dòng code"
  long_lines=$(grep -r ".\{100,\}" --include="*.dart" lib/ | wc -l)
  if [ $long_lines -gt 0 ]; then
    echo "⚠️ **Long lines**: $long_lines dòng dài hơn 100 ký tự" | tee -a reports/analysis_results.md
  else
    echo "✅ **Line length**: Tất cả các dòng đều trong giới hạn" | tee -a reports/analysis_results.md
  fi
}

# Kiểm tra package imports
check_package_imports() {
  echo "🔍 Kiểm tra package imports"
  result=$(grep -r "import '\.\./" --include="*.dart" lib/ || echo "")
  if [ -n "$result" ]; then
    echo "❌ **Relative imports**: Tìm thấy" | tee -a reports/analysis_results.md
    echo "$result"
  else
    echo "✅ **Package imports**: OK" | tee -a reports/analysis_results.md
  fi
}

# Kiểm tra flutter_lints
check_flutter_lints() {
  echo "🔍 Kiểm tra flutter_lints"
  if grep -q "flutter_lints" pubspec.yaml; then
    echo "✅ **flutter_lints**: Có trong pubspec.yaml" | tee -a reports/analysis_results.md
  else
    echo "❌ **flutter_lints**: Không tìm thấy trong pubspec.yaml" | tee -a reports/analysis_results.md
  fi
}

# Chạy tests
run_tests() {
  echo "🔍 Chạy tests"
  if flutter test --coverage > /dev/null 2>&1; then
    echo "✅ **Tests**: Passed" | tee -a reports/analysis_results.md
  else
    echo "❌ **Tests**: Failed" | tee -a reports/analysis_results.md
  fi
}

# Kiểm tra sử dụng const
check_const_usage() {
  echo "🔍 Kiểm tra sử dụng const"
  non_const_widgets=$(grep -r "Widget build" --include="*.dart" lib/ | grep -v "const" | wc -l)
  if [ $non_const_widgets -gt 0 ]; then
    echo "⚠️ **Non-const widgets**: $non_const_widgets widgets" | tee -a reports/analysis_results.md
  else
    echo "✅ **Const widgets**: Tất cả widgets đều sử dụng const" | tee -a reports/analysis_results.md
  fi
}

# Kiểm tra try-catch cho network requests
check_try_catch() {
  echo "🔍 Kiểm tra try-catch cho network requests"
  http_requests=$(grep -r "\.\(get\|post\|put\|delete\|patch\)(.*)" --include="*.dart" lib/ | wc -l)
  try_catch=$(grep -r "try {" --include="*.dart" lib/ | wc -l)
  echo "⚠️ **Network requests**: $http_requests yêu cầu tiềm năng, $try_catch khối try-catch" | tee -a reports/analysis_results.md
}

# Kiểm tra dependencies
check_outdated_dependencies() {
  echo "🔍 Kiểm tra dependencies"
  flutter pub outdated
}

# Kiểm tra biến môi trường
check_environment_variables() {
  echo "🔍 Kiểm tra biến môi trường"
  env_vars=$(grep -r "API_KEY=" --include="*.dart" lib/ || echo "")
  if [ -n "$env_vars" ]; then
    echo "❌ **Environment variables**: Tìm thấy biến môi trường trong code" | tee -a reports/analysis_results.md
    echo "$env_vars"
  else
    echo "✅ **Environment variables**: Không tìm thấy biến môi trường hard-coded" | tee -a reports/analysis_results.md
  fi
}

# Kiểm tra vấn đề hiệu suất
check_performance_issues() {
  echo "🔍 Kiểm tra vấn đề hiệu suất"

  # Tìm kiếm các widget lồng nhau quá nhiều
  deep_nesting=$(grep -r "children:" --include="*.dart" lib/ | wc -l)
  echo "⚠️ **Deep nesting**: $deep_nesting tiềm năng" | tee -a reports/analysis_results.md

  # Tìm kiếm hardcoded sizes
  hardcoded_sizes=$(grep -r "width: [0-9]" --include="*.dart" lib/ | wc -l)
  if [ $hardcoded_sizes -gt 0 ]; then
    echo "⚠️ **Hardcoded sizes**: $hardcoded_sizes kích thước cứng" | tee -a reports/analysis_results.md
  else
    echo "✅ **Hardcoded sizes**: Không tìm thấy" | tee -a reports/analysis_results.md
  fi

  # Tìm kiếm hardcoded colors
  hardcoded_colors=$(grep -r "color: Color(" --include="*.dart" lib/ | wc -l)
  if [ $hardcoded_colors -gt 0 ]; then
    echo "⚠️ **Hardcoded colors**: $hardcoded_colors màu cứng" | tee -a reports/analysis_results.md
  else
    echo "✅ **Hardcoded colors**: Không tìm thấy" | tee -a reports/analysis_results.md
  fi

  # Tìm widgets có thể gây rebuild không cần thiết
  stateful_widgets=$(grep -r "class.*extends StatefulWidget" --include="*.dart" lib/ | wc -l)
  build_context_watch=$(grep -r "context.watch" --include="*.dart" lib/ | wc -l)
  build_context_select=$(grep -r "context.select" --include="*.dart" lib/ | wc -l)
  echo "⚠️ **State management**: $stateful_widgets StatefulWidget, $build_context_watch context.watch(), $build_context_select context.select()" | tee -a reports/analysis_results.md
}

# Chạy toàn bộ kiểm tra
run_all_checks() {
  init_report
  setup_dependencies
  generate_code
  analyze_code
  check_spelling
  check_naming_conventions
  check_commented_code
  check_print_statements
  check_switch_cases
  check_line_length
  check_package_imports
  check_flutter_lints
  run_tests
  check_const_usage
  check_try_catch
  check_outdated_dependencies
  check_environment_variables
  check_performance_issues
  
  echo "✅ Debug workflow hoàn tất. Báo cáo chi tiết đã được lưu trong reports/analysis_results.md"
  cat reports/analysis_results.md
}

# Menu chọn chức năng
while true; do
  echo ""
  echo "🧰 === Debug Workflow Menu ==="
  echo "1. 📦 Cài đặt dependencies"
  echo "2. 🔄 Tạo models và locale"
  echo "3. 🔍 Phân tích code"
  echo "4. 🔠 Kiểm tra lỗi chính tả"
  echo "5. 🏷️ Kiểm tra quy tắc đặt tên"
  echo "6. 💬 Kiểm tra commented-out code"
  echo "7. 🖨️ Kiểm tra print statements"
  echo "8. 🔀 Kiểm tra switch cases"
  echo "9. 📏 Kiểm tra độ dài dòng code"
  echo "10. 📦 Kiểm tra package imports"
  echo "11. 🔧 Kiểm tra flutter_lints"
  echo "12. 🧪 Chạy tests"
  echo "13. 🧱 Kiểm tra sử dụng const"
  echo "14. 🌐 Kiểm tra try-catch cho network requests"
  echo "15. 📚 Kiểm tra dependencies"
  echo "16. 🔑 Kiểm tra biến môi trường"
  echo "17. ⚡ Kiểm tra vấn đề hiệu suất"
  echo "18. 🚀 Chạy tất cả kiểm tra"
  echo "0. ❌ Thoát"
  echo "==========================="
  read -p "Chọn một tùy chọn: " choice

  case $choice in
    1) setup_dependencies ;;
    2) generate_code ;;
    3) init_report && analyze_code ;;
    4) init_report && check_spelling ;;
    5) init_report && check_naming_conventions ;;
    6) init_report && check_commented_code ;;
    7) init_report && check_print_statements ;;
    8) init_report && check_switch_cases ;;
    9) init_report && check_line_length ;;
    10) init_report && check_package_imports ;;
    11) init_report && check_flutter_lints ;;
    12) init_report && run_tests ;;
    13) init_report && check_const_usage ;;
    14) init_report && check_try_catch ;;
    15) check_outdated_dependencies ;;
    16) init_report && check_environment_variables ;;
    17) init_report && check_performance_issues ;;
    18) run_all_checks ;;
    0)
      echo "Tạm biệt 👋"
      exit 0
      ;;
    *) echo "Tùy chọn không hợp lệ 🥲" ;;
  esac
done
