#!/bin/sh
# =============================================================================
# Hermes Agent Installer for Alpine Linux
# =============================================================================
# 专门针对 Alpine Linux 优化的安装脚本
# 使用系统包管理器安装依赖，全局安装 Python 包
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/52fancy/hermes-agent/main/install-alpine.sh | sh
#
# =============================================================================

set -e

# 检测是否为 root 用户
if [ "$(id -u)" -ne 0 ]; then
	log_error "This script must be run as root on Alpine Linux"
	log_info "Use: sudo sh install-alpine.sh"
	exit 1
fi

REPO_URL_HTTPS="https://github.com/NousResearch/hermes-agent.git"
BRANCH="main"
HERMES_HOME="${HERMES_HOME:-/usr/local/hermes}"
INSTALL_DIR="${INSTALL_DIR:-$HERMES_HOME/hermes-agent}"

print_banner() {
    echo ""
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│            Hermes Agent Installer (Alpine)              │"
    echo "├─────────────────────────────────────────────────────────┤"
    echo "│      An open source AI agent by Nous Research.          │"
    echo "└─────────────────────────────────────────────────────────┘"
}

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        [ "$ID" = "alpine" ]
	else
		echo "This script is designed for Alpine Linux only"
		exit 1
	fi

    echo "Detected: $ID"
}


# 安装系统依赖
install_system_dependencies() {
    echo "Updating package index..."
    apk update
    
    echo "Installing essential build tools and dependencies..."
    apk add --no-cache \
        build-base \
        git \
		python3 \
		py3-pip \
		python3-dev \
		libffi-dev \
		openssl-dev
		 
    echo "System dependencies installed"
}

clone_repo() {
    echo "Creating installation directory: $INSTALL_DIR"
	if [ -d "$INSTALL_DIR" ]; then
		echo "Directory already exists, skipping clone"
		return 1
	else
		mkdir -p $(dirname "$INSTALL_DIR")
	fi
	if ! git clone --branch "$BRANCH" "$REPO_URL_HTTPS" "$INSTALL_DIR"; then
		echo "Error: Failed to clone repository"
		return 1
	fi
    
	cd "$INSTALL_DIR"
    echo "Repository ready"
}

# 安装 Python 依赖
install_python_dependencies() {
    echo "Installing Python dependencies globally..."
	
	# 设置全局pip参数
    echo "[global]" > /etc/pip.conf
	echo "break-system-packages = true" >> /etc/pip.conf
	echo "index-url = https://pypi.tuna.tsinghua.edu.cn/simple" >> /etc/pip.conf
	echo "trusted-host = pypi.tuna.tsinghua.edu.cn" >> /etc/pip.conf
	echo "root-user-action = ignore" >> /etc/pip.conf
	
	# 升级 pip 和 setuptools
    pip install --upgrade pip setuptools wheel
    
    # 安装主包及其依赖
    if pip install -e ".[all]"; then
        echo "All Python dependencies installed successfully"
    else
        echo "Full install (.[all]) failed, trying base install..."
        if pip install -e "."; then
            echo "Base Python dependencies installed"
        else
            echo "Failed to install Python dependencies"
            echo "Please check if all build dependencies are installed"
            return 1
        fi
    fi
}

# 配置模板和目录结构
setup_config_templates() {
    echo "Setting up configuration directory structure..."
	
	# 创建符号链接
    if [ -f "/usr/local/bin/hermes" ]; then
        rm -f /usr/local/bin/hermes
    fi
    ln -sf "$INSTALL_DIR"/hermes /usr/local/bin/hermes
	
	# 设置默认配置目录
	sed -i '/if __name__ == "__main__":/i import os' "$INSTALL_DIR"/hermes
	sed -i "/if __name__ == \"__main__\":/i\\os.environ[\"HERMES_HOME\"] = \"$HERMES_HOME\"" "$INSTALL_DIR"/hermes
    
    # 创建 HERMES_HOME 目录结构
	mkdir -p "$HERMES_HOME/cron" \
             "$HERMES_HOME/sessions" \
             "$HERMES_HOME/logs" \
             "$HERMES_HOME/pairing" \
             "$HERMES_HOME/hooks" \
             "$HERMES_HOME/image_cache" \
             "$HERMES_HOME/audio_cache" \
             "$HERMES_HOME/memories" \
             "$HERMES_HOME/skills"
    
    # 创建 .env 文件
    if [ ! -f "$HERMES_HOME/.env" ]; then
        if [ -f "$INSTALL_DIR/.env.example" ]; then
            cp "$INSTALL_DIR/.env.example" "$HERMES_HOME/.env"
            echo "Created $HERMES_HOME/.env from template"
        else
            touch "$HERMES_HOME/.env"
            echo "Created $HERMES_HOME/.env"
        fi
    fi
    
    # 创建 config.yaml
    if [ ! -f "$HERMES_HOME/config.yaml" ]; then
        if [ -f "$INSTALL_DIR/cli-config.yaml.example" ]; then
            cp "$INSTALL_DIR/cli-config.yaml.example" "$HERMES_HOME/config.yaml"
            echo "Created $HERMES_HOME/config.yaml from template"
        fi
    fi
    
    # 创建 SOUL.md 人格文件
    if [ ! -f "$HERMES_HOME/SOUL.md" ]; then
        cat > "$HERMES_HOME/SOUL.md" << 'SOUL_EOF'
# Hermes Agent Persona

<!--
This file defines the agent's personality and tone.
The agent will embody whatever you write here.
Edit this to customize how Hermes communicates with you.

Examples:
  - "You are a warm, playful assistant who uses kaomoji occasionally."
  - "You are a concise technical expert. No fluff, just facts."
  - "You speak like a friendly coworker who happens to know everything."

This file is loaded fresh each message -- no restart needed.
Delete the contents (or this file) to use the default personality.
-->
SOUL_EOF
        echo "Created $HERMES_HOME/SOUL.md (edit to customize personality)"
    fi
    
    echo "Configuration directory ready: $HERMES_HOME/"
}

# 打印成功信息
print_success() {
    echo ""
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│               Installation Complete!                    │"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""
    
    # 显示文件位置
    echo ""
    echo -e "   Config:    $HERMES_HOME/config.yaml"
    echo -e "   API Keys:  $HERMES_HOME/.env"
    echo -e "   Data:      $HERMES_HOME/cron/, sessions/, logs/"
    echo -e "   Code:      $INSTALL_DIR"
    echo ""
    
    echo -e "─────────────────────────────────────────────────────────"
    echo ""
    echo -e "   hermes               Start chatting"
    echo -e "   hermes setup         Configure API keys & settings"
    echo -e "   hermes config        View/edit configuration"
    echo -e "   hermes gateway       Start messaging gateway"
    echo -e "   hermes update        Update to latest version"
    echo ""
    
    echo -e "─────────────────────────────────────────────────────────"
    echo ""
    echo -e "⚡ Hermes Agent is now installed and ready to use!"
    echo ""
    echo -e "Note:All components are installed system-wide for Alpine Linux"
    echo -e "      Configuration is stored in $HERMES_HOME/"
    echo ""
}

# 主函数
main() {
    print_banner
    detect_os
    install_system_dependencies
    clone_repo
    install_python_dependencies
    setup_config_templates
    print_success
	hermes setup
}

main "$@"
