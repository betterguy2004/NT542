#!/bin/bash

# =============================================================================
# INCREMENTAL BACKUP + AWS S3 SYNC - MERN E-COMMERCE
# Backup chỉ các file thay đổi và đẩy lên S3
# =============================================================================

set -e

# ============= CẤU HÌNH =============
WEBSITE_DIR="/var/www/mern-ecommerce"
BACKUP_DIR="/var/backups/mern-ecommerce"
INCREMENTAL_DIR="${BACKUP_DIR}/incremental"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="incremental_backup_${TIMESTAMP}"
LOG_FILE="${BACKUP_DIR}/incremental_backup.log"
SNAPSHOT_FILE="${BACKUP_DIR}/.snapshot"

# AWS S3 Configuration
S3_BUCKET="s3://mern-ecommerce-backup-2024/mern-ecommerce-backups"  # ← Thay tên bucket
AWS_REGION="ap-southeast-1"  # ← Thay region (Singapore)
AWS_PROFILE="default"  # ← Thay AWS profile nếu cần

# MongoDB Atlas Configuration
MONGO_URI="mongodb+srv://phunghung146_db_user:uvcA1Hyn7HkFmHDo@cluster0.seoz547.mongodb.net/?retryWrites=true&w=majority&appName=Cluster0"
MONGO_DB="test"

# Retention policy
LOCAL_RETENTION_DAYS=7   # Giữ backup local 7 ngày
S3_RETENTION_DAYS=90     # Giữ backup trên S3 90 ngày

# ============= MÀU SẮC =============
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============= FUNCTIONS =============

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

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

print_s3() {
    echo -e "${CYAN}[S3]${NC} $1"
    log "S3: $1"
}

# Kiểm tra quyền root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Script cần chạy với quyền root (sudo)"
        exit 1
    fi
}

# Kiểm tra AWS CLI
check_aws_cli() {
    print_status "Kiểm tra AWS CLI..."
    
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI chưa được cài đặt!"
        echo ""
        echo "Cài đặt AWS CLI:"
        echo "  curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip'"
        echo "  unzip awscliv2.zip"
        echo "  sudo ./aws/install"
        echo ""
        exit 1
    fi
    
    # Kiểm tra AWS credentials
    if ! aws sts get-caller-identity --profile "$AWS_PROFILE" &>/dev/null; then
        print_error "AWS credentials chưa được cấu hình!"
        echo ""
        echo "Cấu hình AWS:"
        echo "  aws configure --profile $AWS_PROFILE"
        echo ""
        exit 1
    fi
    
    print_success "AWS CLI đã sẵn sàng"
}

# Tạo thư mục
create_directories() {
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$INCREMENTAL_DIR"
    mkdir -p "${INCREMENTAL_DIR}/temp_${TIMESTAMP}"
    chmod 700 "$BACKUP_DIR"
}

# Tìm các file đã thay đổi kể từ lần backup cuối
find_changed_files() {
    print_status "Tìm các file đã thay đổi..."
    
    local temp_dir="${INCREMENTAL_DIR}/temp_${TIMESTAMP}/website"
    mkdir -p "$temp_dir"
    
    # Tạo file snapshot nếu chưa có (lần đầu tiên)
    if [ ! -f "$SNAPSHOT_FILE" ]; then
        print_warning "Lần đầu tiên chạy incremental backup"
        print_status "Tạo snapshot ban đầu..."
        find "$WEBSITE_DIR" -type f -printf "%T@ %p\n" | sort > "$SNAPSHOT_FILE"
        print_success "Snapshot đã được tạo"
    fi
    
    # Tìm files mới hoặc đã thay đổi
    local changed_files="${INCREMENTAL_DIR}/changed_files_${TIMESTAMP}.txt"
    
    find "$WEBSITE_DIR" -type f \
        -newer "$SNAPSHOT_FILE" \
        ! -path "*/node_modules/*" \
        ! -path "*/.git/*" \
        ! -name "*.log" \
        > "$changed_files"
    
    local file_count=$(wc -l < "$changed_files")
    
    if [ "$file_count" -eq 0 ]; then
        print_warning "Không có file nào thay đổi kể từ lần backup cuối"
        echo "skip" > "${INCREMENTAL_DIR}/.skip_flag"
        return 0
    fi
    
    print_success "Tìm thấy $file_count file đã thay đổi"
    
    # Copy các file đã thay đổi với cấu trúc thư mục
    while IFS= read -r file; do
        # Lấy đường dẫn tương đối
        local rel_path="${file#$WEBSITE_DIR/}"
        local dest_file="${temp_dir}/${rel_path}"
        local dest_dir=$(dirname "$dest_file")
        
        mkdir -p "$dest_dir"
        cp -p "$file" "$dest_file"
    done < "$changed_files"
    
    print_success "Đã copy các file thay đổi"
}

# Backup MongoDB incremental (dump toàn bộ vì MongoDB không support incremental native)
backup_mongodb_incremental() {
    print_status "Backup MongoDB database..."
    
    local temp_dir="${INCREMENTAL_DIR}/temp_${TIMESTAMP}/mongodb"
    mkdir -p "$temp_dir"
    
    if command -v mongodump &> /dev/null; then
        mongodump \
            --uri="$MONGO_URI" \
            --db="$MONGO_DB" \
            --out="$temp_dir" \
            --gzip \
            --quiet
        
        print_success "MongoDB backup hoàn tất"
    else
        print_warning "mongodump không có, bỏ qua MongoDB backup"
    fi
}

# Backup configs đã thay đổi
backup_changed_configs() {
    print_status "Backup configurations..."
    
    local temp_dir="${INCREMENTAL_DIR}/temp_${TIMESTAMP}/configs"
    mkdir -p "$temp_dir"
    
    # Backup .env nếu thay đổi
    [ -f "${WEBSITE_DIR}/backend/.env" ] && \
        [ "${WEBSITE_DIR}/backend/.env" -nt "$SNAPSHOT_FILE" ] && \
        cp "${WEBSITE_DIR}/backend/.env" "$temp_dir/backend.env"
    
    [ -f "${WEBSITE_DIR}/frontend/.env" ] && \
        [ "${WEBSITE_DIR}/frontend/.env" -nt "$SNAPSHOT_FILE" ] && \
        cp "${WEBSITE_DIR}/frontend/.env" "$temp_dir/frontend.env"
    
    # Backup Nginx config nếu thay đổi
    [ -f "/etc/nginx/sites-available/mern-ecommerce" ] && \
        [ "/etc/nginx/sites-available/mern-ecommerce" -nt "$SNAPSHOT_FILE" ] && \
        cp "/etc/nginx/sites-available/mern-ecommerce" "$temp_dir/"
    
    print_success "Config backup hoàn tất"
}

# Tạo metadata
create_metadata() {
    local metadata_file="${INCREMENTAL_DIR}/temp_${TIMESTAMP}/BACKUP_INFO.txt"
    
    # Đọc thông tin từ changed_files
    local changed_files="${INCREMENTAL_DIR}/changed_files_${TIMESTAMP}.txt"
    local file_count=0
    [ -f "$changed_files" ] && file_count=$(wc -l < "$changed_files")
    
    cat > "$metadata_file" << EOF
===========================================
INCREMENTAL BACKUP INFORMATION
===========================================
Backup Date: $(date)
Backup Type: INCREMENTAL
Hostname: $(hostname)
Changed Files: $file_count

===========================================
LAST FULL BACKUP
===========================================
$(stat -c "Last Full: %y" "$SNAPSHOT_FILE" 2>/dev/null || echo "No previous backup")

===========================================
CHANGED FILES LIST
===========================================
$([ -f "$changed_files" ] && cat "$changed_files" | head -20 || echo "No changes")
$([ "$file_count" -gt 20 ] && echo "... and $(($file_count - 20)) more files")

===========================================
SYSTEM STATUS
===========================================
Disk Usage:
$(df -h | grep -E '^/dev/')

Memory:
$(free -h)
EOF
    
    print_success "Metadata created"
}

# Nén backup
compress_backup() {
    # Kiểm tra flag skip
    if [ -f "${INCREMENTAL_DIR}/.skip_flag" ]; then
        rm -f "${INCREMENTAL_DIR}/.skip_flag"
        print_warning "Bỏ qua nén vì không có thay đổi"
        return 0
    fi
    
    print_status "Nén incremental backup..."
    
    local temp_dir="${INCREMENTAL_DIR}/temp_${TIMESTAMP}"
    local compressed_file="${INCREMENTAL_DIR}/${BACKUP_NAME}.tar.gz"
    
    # Hiển thị size
    local size_before=$(du -sh "$temp_dir" | cut -f1)
    print_status "Size trước nén: $size_before"
    
    # Nén với pigz nếu có
    if command -v pigz &> /dev/null; then
        tar -I pigz -cf "$compressed_file" -C "${INCREMENTAL_DIR}" "temp_${TIMESTAMP}"
    else
        tar -czf "$compressed_file" -C "${INCREMENTAL_DIR}" "temp_${TIMESTAMP}"
    fi
    
    local size_after=$(du -sh "$compressed_file" | cut -f1)
    print_success "Size sau nén: $size_after"
    
    # Tạo checksum
    sha256sum "$compressed_file" > "${compressed_file}.sha256"
    
    # Xóa temp
    rm -rf "$temp_dir"
    rm -f "${INCREMENTAL_DIR}/changed_files_${TIMESTAMP}.txt"
    
    print_success "Backup đã được nén: ${BACKUP_NAME}.tar.gz"
}

# Sync to AWS S3
sync_to_s3() {
    print_s3 "Bắt đầu sync lên AWS S3..."
   
    
    # Upload incremental backups
    print_s3 "Uploading incremental backups..."
    aws s3 sync "$INCREMENTAL_DIR" "$S3_BUCKET/incremental/" \
        --profile "$AWS_PROFILE" \
        --region "$AWS_REGION" \
        --storage-class STANDARD_IA \
        --exclude "temp_*" \
        --exclude ".skip_flag" \
        --exclude "changed_files_*" \
        --exclude ".snapshot" \
        --no-progress
    
    print_success "Incremental backups đã upload lên S3"
    
    # Upload full backups (nếu có)
    if [ -d "${BACKUP_DIR}" ] && [ "$(ls -A ${BACKUP_DIR}/full_backup_*.tar.gz 2>/dev/null)" ]; then
        print_s3 "Uploading full backups..."
        aws s3 sync "$BACKUP_DIR" "$S3_BUCKET/full/" \
            --profile "$AWS_PROFILE" \
            --region "$AWS_REGION" \
            --storage-class STANDARD_IA \
            --include "full_backup_*.tar.gz*" \
            --exclude "*" \
            --no-progress
        
        print_success "Full backups đã upload lên S3"
    fi
    
    # Hiển thị S3 storage info
    print_s3 "Thông tin S3 storage:"
    aws s3 ls "$S3_BUCKET/" --recursive --human-readable --summarize \
        --profile "$AWS_PROFILE" | tail -2
}

# Apply lifecycle policy to S3
apply_s3_lifecycle() {
    print_s3 "Áp dụng S3 lifecycle policy..."
    
    local bucket_name=$(echo $S3_BUCKET | cut -d'/' -f3)
    local lifecycle_config=$(cat <<EOF
{
    "Rules": [
        {
            "Id": "DeleteOldIncrementalBackups",
            "Status": "Enabled",
            "Prefix": "mern-ecommerce-backups/incremental/",
            "Expiration": {
                "Days": ${S3_RETENTION_DAYS}
            }
        },
        {
            "Id": "TransitionFullBackupsToGlacier",
            "Status": "Enabled",
            "Prefix": "mern-ecommerce-backups/full/",
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "GLACIER"
                }
            ],
            "Expiration": {
                "Days": 365
            }
        }
    ]
}
EOF
)
    
    echo "$lifecycle_config" > /tmp/s3-lifecycle.json
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$bucket_name" \
        --lifecycle-configuration file:///tmp/s3-lifecycle.json \
        --profile "$AWS_PROFILE" 2>/dev/null || print_warning "Không thể set lifecycle policy"
    
    rm -f /tmp/s3-lifecycle.json
    
    print_success "Lifecycle policy đã được áp dụng"
}

# Xóa backup local cũ
cleanup_local_backups() {
    print_status "Xóa backup local cũ (>$LOCAL_RETENTION_DAYS ngày)..."
    
    find "$INCREMENTAL_DIR" -name "incremental_backup_*.tar.gz" -type f -mtime +$LOCAL_RETENTION_DAYS -delete
    find "$INCREMENTAL_DIR" -name "incremental_backup_*.tar.gz.sha256" -type f -mtime +$LOCAL_RETENTION_DAYS -delete
    
    print_success "Đã xóa backup local cũ"
}

# Update snapshot
update_snapshot() {
    # Chỉ update nếu có backup thành công
    if [ ! -f "${INCREMENTAL_DIR}/.skip_flag" ]; then
        print_status "Cập nhật snapshot..."
        find "$WEBSITE_DIR" -type f -printf "%T@ %p\n" | sort > "$SNAPSHOT_FILE"
        print_success "Snapshot đã được cập nhật"
    fi
}

# Hiển thị báo cáo
show_report() {
    echo ""
    echo -e "${GREEN}=========================================="
    echo "   INCREMENTAL BACKUP HOÀN TẤT!"
    echo -e "==========================================${NC}"
    echo ""
    echo "📦 Local Backup:"
    echo "   Location: $INCREMENTAL_DIR"
    ls -lh "$INCREMENTAL_DIR"/incremental_backup_*.tar.gz 2>/dev/null | tail -3 || echo "   (Không có backup mới)"
    echo ""
    echo "☁️  S3 Backup:"
    echo "   Bucket: $S3_BUCKET"
    echo "   Region: $AWS_REGION"
    echo ""
    echo "📊 Next Backup:"
    echo "   Chỉ backup các file thay đổi kể từ: $(date)"
    echo ""
    echo "📝 Logs: $LOG_FILE"
    echo ""
}

# Main function
main() {
    echo -e "${CYAN}"
    echo "=========================================="
    echo "  INCREMENTAL BACKUP + AWS S3 SYNC"
    echo "=========================================="
    echo -e "${NC}"
    
    local start_time=$(date +%s)
    
    # Checks
    check_root
    check_aws_cli
    create_directories
    
    # Backup process
    find_changed_files
    backup_mongodb_incremental
    backup_changed_configs
    create_metadata
    compress_backup
    
    # S3 sync
    sync_to_s3
    apply_s3_lifecycle
    
    # Cleanup
    cleanup_local_backups
    update_snapshot
    
    # Report
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    show_report
    echo "⏱️  Thời gian: ${duration} giây"
    echo ""
}

# Run
main "$@"
