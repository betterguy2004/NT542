#!/bin/bash

# =============================================================================
# SCRIPT PHÂN TÍCH CẤU TRÚC & KIỂU FILE CỦA WEBSITE
# =============================================================================

echo "=========================================="
echo "  PHÂN TÍCH CẤU TRÚC DỰ ÁN"
echo "=========================================="
echo ""

# Đếm tổng số thư mục
total_dirs=$(find . -type d | wc -l)
echo "📁 Tổng số thư mục: $total_dirs"

# Đếm tổng số file
total_files=$(find . -type f | wc -l)
echo "📄 Tổng số file: $total_files"

echo ""
echo "=========================================="
echo "  THỐNG KÊ THEO PHẦN MỞ RỘNG"
echo "=========================================="
echo ""
printf "%-15s %-10s %-15s\n" "LOẠI FILE" "SỐ LƯỢNG" "DUNG LƯỢNG"
echo "----------------------------------------"

# Thống kê theo extension
find . -type f | sed 's/.*\.//' | sort | uniq -c | sort -rn | while read count ext; do
    # Tính tổng dung lượng cho mỗi loại file
    size=$(find . -type f -name "*.$ext" -exec du -ch {} + 2>/dev/null | grep total$ | cut -f1)
    printf "%-15s %-10s %-15s\n" ".$ext" "$count" "$size"
done

echo ""
echo "=========================================="
echo "  TỔNG DUNG LƯỢNG DỰ ÁN"
echo "=========================================="
du -sh . | cut -f1
