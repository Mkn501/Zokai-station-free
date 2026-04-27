#!/bin/bash
# Secrets Management Setup Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Configuration
SECRETS_DIR="./secrets"

# Main function
main() {
    print_step "Setting Up Secrets Management"
    
    # Create secrets directory
    mkdir -p "$SECRETS_DIR"
    chmod 700 "$SECRETS_DIR"
    
    # Check if secrets.txt exists
    if [ -f "$SECRETS_DIR/secrets.txt" ]; then
        print_info "Existing secrets file found."
        read -p "Do you want to update it? (y/N): " UPDATE_SECRETS
        if [[ ! "$UPDATE_SECRETS" =~ ^[Yy]$ ]]; then
            print_info "Keeping existing secrets file."
            return
        fi
    fi
    
    # Create secrets file from template if it doesn't exist
    if [ ! -f "$SECRETS_DIR/secrets.txt" ]; then
        if [ -f "$SECRETS_DIR/secrets.template" ]; then
            cp "$SECRETS_DIR/secrets.template" "$SECRETS_DIR/secrets.txt"
            print_info "Created secrets file from template."
        else
            # Create a basic secrets file
            cat > "$SECRETS_DIR/secrets.txt" << 'EOF'
# API Keys Configuration
# Fill in your actual API keys below
# DO NOT commit this file to version control

# OpenRouter (OpenAI-compatible) API Key
OPENAI_API_KEY=

# Anthropic API Key
ANTHROPIC_API_KEY=

# Tavily Search API Key
TAVILY_API_KEY=

# Raindrop.io API Token
RAINDROP_TOKEN=

# YouTube Data API Key
YOUTUBE_API_KEY=

# GitHub Personal Access Token
GITHUB_TOKEN=

# Google Search API Key (optional)
GOOGLE_API_KEY=

# Google Custom Search Engine ID (optional)
GOOGLE_CX=
EOF
            print_info "Created basic secrets file."
        fi
    fi
    
    # Prompt for API keys
    print_step "Configure API Keys"
    print_info "Press Enter to skip any API key you don't want to configure."
    
    # Function to safely update key in secrets.txt without sed delimiter issues
    update_secret() {
        local key="$1"
        local val="$2"
        if [ -n "$val" ]; then
            # Use Python for a safe, delimiter-agnostic replacement
            python3 -c "
import sys, os
path = sys.argv[1]
key = sys.argv[2]
val = sys.argv[3]
with open(path, 'r') as f: lines = f.readlines()
with open(path, 'w') as f:
    for line in lines:
        if line.startswith(f'{key}='): f.write(f'{key}={val}\\n')
        else: f.write(line)
" "$SECRETS_DIR/secrets.txt" "$key" "$val"
        fi
    }

    # OpenRouter API Key
    read -p "OpenRouter API Key: " OPENAI_API_KEY
    update_secret "OPENAI_API_KEY" "$OPENAI_API_KEY"
    
    # Anthropic API Key
    read -p "Anthropic API Key: " ANTHROPIC_API_KEY
    update_secret "ANTHROPIC_API_KEY" "$ANTHROPIC_API_KEY"
    
    # Tavily API Key
    read -p "Tavily API Key: " TAVILY_API_KEY
    update_secret "TAVILY_API_KEY" "$TAVILY_API_KEY"
    
    # Raindrop Token
    read -p "Raindrop.io API Token: " RAINDROP_TOKEN
    update_secret "RAINDROP_TOKEN" "$RAINDROP_TOKEN"
    
    # YouTube API Key
    read -p "YouTube Data API Key: " YOUTUBE_API_KEY
    update_secret "YOUTUBE_API_KEY" "$YOUTUBE_API_KEY"
    
    # GitHub Token
    read -p "GitHub Personal Access Token: " GITHUB_TOKEN
    update_secret "GITHUB_TOKEN" "$GITHUB_TOKEN"
    
    # Google API Key
    read -p "Google Search API Key (optional): " GOOGLE_API_KEY
    update_secret "GOOGLE_API_KEY" "$GOOGLE_API_KEY"
    
    # Google CX
    read -p "Google Custom Search Engine ID (optional): " GOOGLE_CX
    update_secret "GOOGLE_CX" "$GOOGLE_CX"
    
    # Clean up backup files
    rm -f "$SECRETS_DIR/secrets.txt.bak"
    
    # Create individual secret files for Docker
    print_step "Creating Docker Secret Files"
    
    # Extract API keys from secrets.txt and create individual files
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ ]] && continue
        [[ -z "$line" ]] && continue
        
        # Extract key and value
        if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            
            # Create individual secret file
            # Create individual secret file using printf for raw content integrity
            printf "%s" "$value" > "$SECRETS_DIR/${key,,}.txt"
            chmod 600 "$SECRETS_DIR/${key,,}.txt"
        fi
    done < "$SECRETS_DIR/secrets.txt"
    
    print_step "Secrets Setup Complete"
    print_info "Secrets stored in: $SECRETS_DIR/"
    print_info "Individual secret files created for Docker"
    print_info "Make sure to add $SECRETS_DIR/ to your .gitignore file"
}

# Run main function
main "$@"