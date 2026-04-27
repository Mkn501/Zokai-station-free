#!/bin/bash
# User Preferences Management Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_step() {
  echo -e "${GREEN}=== $1 ===${NC}"
}

print_info() {
  echo -e "${YELLOW}$1${NC}"
}

print_error() {
  echo -e "${RED}Error: $1${NC}"
}

print_status() {
  echo -e "${BLUE}$1${NC}"
}

# Configuration
VSCODE_SETTINGS_DIR="./data/vscode-settings"
BACKUP_DIR="./data/backups"

# Main functions
backup_preferences() {
    print_step "Backing Up User Preferences"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Create timestamp for backup
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_FILE="$BACKUP_DIR/vscode-settings-backup-$TIMESTAMP.tar.gz"
    
    # Create backup
    if [ -d "$VSCODE_SETTINGS_DIR" ]; then
        tar -czf "$BACKUP_FILE" -C "$VSCODE_SETTINGS_DIR" .
        print_status "✓ Preferences backed up to: $BACKUP_FILE"
    else
        print_info "No VS Code settings directory found to backup"
    fi
}

restore_preferences() {
    print_step "Restoring User Preferences"
    
    # List available backups
    if [ ! -d "$BACKUP_DIR" ]; then
        print_error "No backup directory found"
        return 1
    fi
    
    # Find backup files
    BACKUP_FILES=($(ls "$BACKUP_DIR"/vscode-settings-backup-*.tar.gz 2>/dev/null))
    
    if [ ${#BACKUP_FILES[@]} -eq 0 ]; then
        print_error "No backup files found"
        return 1
    fi
    
    # Display available backups
    print_info "Available backups:"
    for i in "${!BACKUP_FILES[@]}"; do
        FILENAME=$(basename "${BACKUP_FILES[$i]}")
        TIMESTAMP=$(echo "$FILENAME" | sed 's/vscode-settings-backup-\(.*\)\.tar\.gz/\1/')
        FORMATTED_DATE=$(date -d "${TIMESTAMP:0:8} ${TIMESTAMP:9:2}:${TIMESTAMP:11:2}" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$TIMESTAMP")
        echo "  $((i+1))) $FORMATTED_DATE"
    done
    
    # Prompt for selection
    read -p "Select backup to restore (1-${#BACKUP_FILES[@]}): " SELECTION
    
    # Validate selection
    if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt ${#BACKUP_FILES[@]} ]; then
        print_error "Invalid selection"
        return 1
    fi
    
    # Get selected backup file
    SELECTED_FILE="${BACKUP_FILES[$((SELECTION-1))]}"
    
    # Confirm restoration
    read -p "Restore preferences from $(basename "$SELECTED_FILE")? This will overwrite current settings. (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_info "Restore cancelled"
        return 0
    fi
    
    # Create backup of current settings before restoring
    if [ -d "$VSCODE_SETTINGS_DIR" ]; then
        CURRENT_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
        CURRENT_BACKUP="$BACKUP_DIR/vscode-settings-before-restore-$CURRENT_TIMESTAMP.tar.gz"
        tar -czf "$CURRENT_BACKUP" -C "$VSCODE_SETTINGS_DIR" .
        print_status "✓ Current settings backed up to: $CURRENT_BACKUP"
    fi
    
    # Restore settings
    mkdir -p "$VSCODE_SETTINGS_DIR"
    tar -xzf "$SELECTED_FILE" -C "$VSCODE_SETTINGS_DIR"
    
    print_status "✓ Preferences restored successfully"
    print_info "You may need to restart the VS Code container for changes to take effect"
}

export_preferences() {
    print_step "Exporting User Preferences"
    
    # Create export directory
    EXPORT_DIR="./exports"
    mkdir -p "$EXPORT_DIR"
    
    # Create timestamp for export
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    EXPORT_FILE="$EXPORT_DIR/vscode-settings-export-$TIMESTAMP.tar.gz"
    
    # Create export
    if [ -d "$VSCODE_SETTINGS_DIR" ]; then
        tar -czf "$EXPORT_FILE" -C "$VSCODE_SETTINGS_DIR" .
        print_status "✓ Preferences exported to: $EXPORT_FILE"
        print_info "You can share this file with others or import it on another system"
    else
        print_error "No VS Code settings directory found to export"
        return 1
    fi
}

import_preferences() {
    print_step "Importing User Preferences"
    
    # Prompt for import file
    read -p "Enter path to preferences export file: " IMPORT_FILE
    
    # Validate file exists
    if [ ! -f "$IMPORT_FILE" ]; then
        print_error "File not found: $IMPORT_FILE"
        return 1
    fi
    
    # Validate file is a tar.gz archive
    if ! [[ "$IMPORT_FILE" =~ \.tar\.gz$ ]]; then
        print_error "Import file must be a .tar.gz archive"
        return 1
    fi
    
    # Confirm import
    read -p "Import preferences from $(basename "$IMPORT_FILE")? This will overwrite current settings. (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_info "Import cancelled"
        return 0
    fi
    
    # Create backup of current settings before importing
    if [ -d "$VSCODE_SETTINGS_DIR" ]; then
        CURRENT_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
        CURRENT_BACKUP="$BACKUP_DIR/vscode-settings-before-import-$CURRENT_TIMESTAMP.tar.gz"
        mkdir -p "$BACKUP_DIR"
        tar -czf "$CURRENT_BACKUP" -C "$VSCODE_SETTINGS_DIR" .
        print_status "✓ Current settings backed up to: $CURRENT_BACKUP"
    fi
    
    # Import settings
    mkdir -p "$VSCODE_SETTINGS_DIR"
    tar -xzf "$IMPORT_FILE" -C "$VSCODE_SETTINGS_DIR"
    
    print_status "✓ Preferences imported successfully"
    print_info "You may need to restart the VS Code container for changes to take effect"
}

list_preferences() {
    print_step "Listing User Preferences"
    
    if [ ! -d "$VSCODE_SETTINGS_DIR" ]; then
        print_error "VS Code settings directory not found"
        return 1
    fi
    
    print_info "VS Code Settings Directory: $VSCODE_SETTINGS_DIR"
    echo ""
    
    # List settings files
    print_info "Settings Files:"
    find "$VSCODE_SETTINGS_DIR" -type f -name "*.json" | while read -r file; do
        REL_PATH=${file#$VSCODE_SETTINGS_DIR/}
        SIZE=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "unknown")
        MODIFIED=$(stat -c%y "$file" 2>/dev/null || stat -f%Sm "$file" 2>/dev/null || echo "unknown")
        echo "  $REL_PATH ($SIZE bytes, modified: $MODIFIED)"
    done
    
    echo ""
    
    # Show key settings if settings.json exists
    SETTINGS_FILE="$VSCODE_SETTINGS_DIR/User/settings.json"
    if [ -f "$SETTINGS_FILE" ]; then
        print_info "Key Settings:"
        
        # Extract and display key settings
        if command -v jq &> /dev/null; then
            THEME=$(jq -r '.workbench.colorTheme // "Not set"' "$SETTINGS_FILE")
            FONT_SIZE=$(jq -r '.editor.fontSize // "Not set"' "$SETTINGS_FILE")
            AUTO_SAVE=$(jq -r '.files.autoSave // "Not set"' "$SETTINGS_FILE")
            
            echo "  Theme: $THEME"
            echo "  Font Size: $FONT_SIZE"
            echo "  Auto Save: $AUTO_SAVE"
        else
            print_info "Install jq to view detailed settings"
        fi
    fi
    
    echo ""
    
    # List backups
    if [ -d "$BACKUP_DIR" ]; then
        BACKUP_COUNT=$(ls "$BACKUP_DIR"/vscode-settings-backup-*.tar.gz 2>/dev/null | wc -l)
        print_info "Backups: $BACKUP_COUNT backup(s) available"
    fi
}

reset_preferences() {
    print_step "Resetting User Preferences"
    
    # Confirm reset
    read -p "Reset all VS Code preferences to defaults? This cannot be undone. (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_info "Reset cancelled"
        return 0
    fi
    
    # Create backup before resetting
    if [ -d "$VSCODE_SETTINGS_DIR" ]; then
        CURRENT_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
        CURRENT_BACKUP="$BACKUP_DIR/vscode-settings-before-reset-$CURRENT_TIMESTAMP.tar.gz"
        mkdir -p "$BACKUP_DIR"
        tar -czf "$CURRENT_BACKUP" -C "$VSCODE_SETTINGS_DIR" .
        print_status "✓ Current settings backed up to: $CURRENT_BACKUP"
        
        # Remove current settings
        rm -rf "$VSCODE_SETTINGS_DIR"
    fi
    
    print_status "✓ Preferences reset to defaults"
    print_info "You may need to restart the VS Code container for changes to take effect"
}

# Main menu
show_usage() {
    echo "User Preferences Management Script"
    echo ""
    echo "Usage: $0 {backup|restore|export|import|list|reset}"
    echo ""
    echo "Commands:"
    echo "  backup   - Backup current user preferences"
    echo "  restore  - Restore user preferences from a backup"
    echo "  export   - Export user preferences to a shareable file"
    echo "  import   - Import user preferences from a file"
    echo "  list     - List current user preferences and available backups"
    echo "  reset    - Reset all user preferences to defaults"
    echo ""
    echo "Examples:"
    echo "  $0 backup"
    echo "  $0 restore"
    echo "  $0 export"
    echo "  $0 import"
    echo ""
}

# Main execution
case "$1" in
    backup)
        backup_preferences
        ;;
    restore)
        restore_preferences
        ;;
    export)
        export_preferences
        ;;
    import)
        import_preferences
        ;;
    list)
        list_preferences
        ;;
    reset)
        reset_preferences
        ;;
    *)
        show_usage
        exit 1
        ;;
esac