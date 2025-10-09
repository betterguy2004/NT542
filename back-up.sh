#!/bin/bash

# =============================================================================
# FULL BACKUP SCRIPT - MERN E-COMMERCE
# Sao lưu toàn bộ website với nén tối ưu
# =============================================================================

set -e

# ============= CẤU HÌNH =============
WEBSITE_DIR="/var/www/mern-ecommerce"
BACKUP_DIR="/var/backups/mern-ecommerce"
BACKUP_RETENTION_DAYS=30  # Giữ backup trong 30 ngày
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="full_backup_${TIMESTAMP}"
LOG_FILE="${BACKUP_DIR}/backup.log"

# MongoDB Atlas Configuration
MONGO_URI="mongodb+srv://phunghung146_db_user:uvcA1Hyn7HkFmHDo@cluster0.seoz547.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0"
MONGO_DB="test"  

# ============= MÀU SẮC OUTPUT =============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============= FUNCTIONS =============

# Ghi log
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Hiển thị thông báo màu
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log "INFO: $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log "SUCCESS: $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log "ERROR: $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log "WARNING: $1"
}

# Kiểm tra quyền root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Script cần chạy với quyền root (sudo)"
        exit 1
    fi
}

# Tạo thư mục backup
create_backup_directory() {
    print_status "Tạo thư mục backup..."
    mkdir -p "$BACKUP_DIR"
    mkdir -p "${BACKUP_DIR}/temp_${TIMESTAMP}"
    chmod 700 "$BACKUP_DIR"
}

# Backup website files
backup_website_files() {
    print_status "Đang backup website files..."
    
    local temp_dir="${BACKUP_DIR}/temp_${TIMESTAMP}/website"
    mkdir -p "$temp_dir"
    
    # Copy toàn bộ website
    rsync -az --delete \
        --exclude 'node_modules' \
        --exclude '.git' \
        --exclude '*.log' \
        --exclude '.env' \
        "$WEBSITE_DIR/" "$temp_dir/"
    
    print_success "Website files đã được backup"
}

# Backup MongoDB Atlas database
backup_mongodb() {
    print_status "Đang backup MongoDB Atlas database..."
    
    local temp_dir="${BACKUP_DIR}/temp_${TIMESTAMP}/mongodb"
    mkdir -p "$temp_dir"
    
    if command -v mongodump &> /dev/null; then
        mongodump \
            --uri="$MONGO_URI" \
            --db="$MONGO_DB" \
            --out="$temp_dir" \
            --gzip \
            --quiet
        
        print_success "MongoDB Atlas database đã được backup"
    else
        print_warning "mongodump không được cài đặt"
        print_warning "Cài đặt: sudo apt-get install mongodb-database-tools -y"
    fi
}

# Backup environment variables
backup_env_files() {
    print_status "Đang backup environment files..."
    
    local temp_dir="${BACKUP_DIR}/temp_${TIMESTAMP}/env"
    mkdir -p "$temp_dir"
    
    # Backup .env files (nếu có)
    if [ -f "${WEBSITE_DIR}/backend/.env" ]; then
        cp "${WEBSITE_DIR}/backend/.env" "$temp_dir/backend.env"
    fi
    
    if [ -f "${WEBSITE_DIR}/frontend/.env" ]; then
        cp "${WEBSITE_DIR}/frontend/.env" "$temp_dir/frontend.env"
    fi
    
    print_success "Environment files đã được backup"
}

# Backup Nginx configuration
backup_nginx_config() {
    print_status "Đang backup Nginx configuration..."
    
    local temp_dir="${BACKUP_DIR}/temp_${TIMESTAMP}/nginx"
    mkdir -p "$temp_dir"
    
    if [ -f "/etc/nginx/sites-available/mern-ecommerce" ]; then
        cp "/etc/nginx/sites-available/mern-ecommerce" "$temp_dir/"
    fi
    
    # Backup nginx.conf
    if [ -f "/etc/nginx/nginx.conf" ]; then
        cp "/etc/nginx/nginx.conf" "$temp_dir/"
    fi
    
    print_success "Nginx configuration đã được backup"
}

# Backup PM2 configuration (nếu có)
backup_pm2_config() {
    print_status "Đang backup PM2 configuration..."
    
    local temp_dir="${BACKUP_DIR}/temp_${TIMESTAMP}/pm2"
    mkdir -p "$temp_dir"
    
    if command -v pm2 &> /dev/null; then
        pm2 save --force
        if [ -d "$HOME/.pm2" ]; then
            cp -r "$HOME/.pm2/dump.pm2" "$temp_dir/" 2>/dev/null || true
        fi
        print_success "PM2 configuration đã được backup"
    else
        print_warning "PM2 không được cài đặt, bỏ qua backup PM2"
    fi
}

# Tạo metadata file
create_metadata() {
    print_status "Tạo metadata file..."
    
    local metadata_file="${BACKUP_DIR}/temp_${TIMESTAMP}/BACKUP_INFO.txt"
    
    cat > "$metadata_file" << EOF
===========================================
BACKUP INFORMATION
===========================================
Backup Date: $(date)
Hostname: $(hostname)
System: $(uname -a)
Backup Type: FULL BACKUP

===========================================
BACKUP CONTENTS
===========================================
- Website Files: $WEBSITE_DIR
- MongoDB Database: $MONGO_DB
- Nginx Configuration
- Environment Variables
- PM2 Configuration

===========================================
SYSTEM INFORMATION
===========================================
Disk Usage Before Backup:
$(df -h)

Memory Usage:
$(free -h)

===========================================
EOF
    
    print_success "Metadata file đã được tạo"
}

# Nén backup với tối ưu hóa
compress_backup() {
    print_status "Đang nén backup (có thể mất vài phút)..."
    
    local temp_dir="${BACKUP_DIR}/temp_${TIMESTAMP}"
    local compressed_file="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
    
    # Hiển thị kích thước trước nén
    local size_before=$(du -sh "$temp_dir" | cut -f1)
    print_status "Kích thước trước nén: $size_before"
    
    # Nén với pigz (parallel gzip) nếu có, không thì dùng gzip thường
    if command -v pigz &> /dev/null; then
        tar -I pigz -cf "$compressed_file" -C "${BACKUP_DIR}" "temp_${TIMESTAMP}"
        print_success "Đã nén bằng pigz (parallel gzip)"
    else
        tar -czf "$compressed_file" -C "${BACKUP_DIR}" "temp_${TIMESTAMP}"
        print_success "Đã nén bằng gzip"
    fi
    
    # Hiển thị kích thước sau nén
    local size_after=$(du -sh "$compressed_file" | cut -f1)
    print_success "Kích thước sau nén: $size_after"
    
    # Tính tỷ lệ nén
    local size_before_bytes=$(du -sb "$temp_dir" | cut -f1)
    local size_after_bytes=$(du -sb "$compressed_file" | cut -f1)
    local compression_ratio=$(awk "BEGIN {printf \"%.2f\", (1 - $size_after_bytes/$size_before_bytes) * 100}")
    print_success "Tỷ lệ nén: ${compression_ratio}%"
    
    # Xóa thư mục tạm
    rm -rf "$temp_dir"
    print_success "Đã xóa thư mục tạm"
    
    # Tạo checksum
    print_status "Tạo checksum..."
    sha256sum "$compressed_file" > "${compressed_file}.sha256"
    print_success "Checksum đã được tạo"
}

# Xóa backup cũ
cleanup_old_backups() {
    print_status "Xóa các backup cũ (>$BACKUP_RETENTION_DAYS ngày)..."
    
    find "$BACKUP_DIR" -name "full_backup_*.tar.gz" -type f -mtime +$BACKUP_RETENTION_DAYS -delete
    find "$BACKUP_DIR" -name "full_backup_*.tar.gz.sha256" -type f -mtime +$BACKUP_RETENTION_DAYS -delete
    
    print_success "Đã xóa backup cũ"
}

# Hiển thị danh sách backup
list_backups() {
    print_status "Danh sách các backup hiện có:"
    echo ""
    ls -lh "$BACKUP_DIR"/full_backup_*.tar.gz 2>/dev/null || print_warning "Chưa có backup nào"
    echo ""
}

# Kiểm tra kết quả backup
verify_backup() {
    print_status "Kiểm tra tính toàn vẹn backup..."
    
    local compressed_file="${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
    
    if [ -f "$compressed_file" ]; then
        # Kiểm tra checksum
        if sha256sum -c "${compressed_file}.sha256" &>/dev/null; then
            print_success "Backup hoàn chỉnh và tính toàn vẹn OK!"
        else
            print_error "Checksum không khớp! Backup có thể bị lỗi"
            return 1
        fi
        
        # Kiểm tra có giải nén được không
        if tar -tzf "$compressed_file" &>/dev/null; then
            print_success "File nén hợp lệ"
        else
            print_error "File nén bị lỗi!"
            return 1
        fi
    else
        print_error "Không tìm thấy file backup!"
        return 1
    fi
}

# Main function
main() {
    echo -e "${GREEN}"
    echo "=========================================="
    echo "     FULL BACKUP - MERN E-COMMERCE"
    echo "=========================================="
    echo -e "${NC}"
    
    local start_time=$(date +%s)
    
    # Kiểm tra quyền root
    check_root
    
    # Tạo thư mục backup
    create_backup_directory
    
    # Thực hiện backup
    backup_website_files
    backup_mongodb
    backup_env_files
    backup_nginx_config
    backup_pm2_config
    create_metadata
    
    # Nén và tối ưu
    compress_backup
    
    # Xóa backup cũ
    cleanup_old_backups
    
    # Kiểm tra backup
    verify_backup
    
    # Hiển thị kết quả
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    echo -e "${GREEN}"
    echo "=========================================="
    echo "        BACKUP HOÀN TẤT THÀNH CÔNG!"
    echo "=========================================="
    echo -e "${NC}"
    echo "Thời gian thực hiện: ${duration} giây"
    echo "File backup: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
    echo "Log file: $LOG_FILE"
    echo ""
    
    list_backups
}

# Chạy script
main "$@"
