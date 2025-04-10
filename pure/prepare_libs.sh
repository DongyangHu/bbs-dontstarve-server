#!/bin/bash

# 打印信息
function print_info() {
    local level=$1
    local message=$2

    case "$level" in
    INFO)
        printf "\033[1;34m[INFO] >>> \033[0m%s\n" "$message"
        ;;
    SUCCESS)
        printf "\033[1;32m[SUCCESS] >>> \033[0m%s\n" "$message"
        ;;
    WARNING)
        printf "\033[1;33m[WARNING] >>> \033[0m%s\n" "$message"
        ;;
    ERROR)
        printf "\033[1;31m[ERROR] >>> \033[0m%s\n" "$message"
        ;;
    *)
        printf "%s %s\n" "$level" "$message"
        ;;
    esac
}

# 检查用户权限
function checkuser() {
    if [ "$EUID" -eq 0 ]; then
        print_info "SUCCESS" "当前用户为root用户"
    elif sudo -l >/dev/null 2>&1; then
        print_info "SUCCESS" "当前用户有sudo权限"
    else
        print_info "ERROR" "当前用户无权限执行脚本,请使用sudo或root用户执行脚本"
        exit 1
    fi
}

# 安装libs
function install_libs() {
    print_info "INFO" "正在执行软件包安装和更新..."
    checkuser

    sudo add-apt-repository multiverse
    sudo dpkg --add-architecture i386
    sudo apt-get -y update
    # 安装 steamcmd 所需的库
    sudo apt-get -y install lib32gcc-s1
    # 安装 dontstarve 所需的库
    sudo apt-get -y install libstdc++6:i386 libgcc1:i386 libcurl4-gnutls-dev:i386
    # 安装 htop
    sudo apt-get -y install htop

    # 检查命令的退出状态码
    if [ $? -eq 0 ]; then
        print_info "SUCCESS" "软件包安装/更新成功!"
    else
        print_info "ERROR" "系统更新和软件包安装失败!"
        exit 1
    fi
}
