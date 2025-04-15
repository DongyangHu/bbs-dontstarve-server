#!/bin/bash

# set -e

split_line="============================================================================"
script_dir=$(cd "$(dirname "$0")" && pwd)
# 安裝libs的结果日志文件
install_libs_log_file=$script_dir/install_libs.log
download_steamcmd_url=https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
log_path=$script_dir/log
klei_token_url=https://accounts.klei.com/login
max_players_limited=1000
max_players_def=6
github_link="https://github.com/DongyangHu/bbs-dontstarve-server"
cluster_name_def="[BBS] DST Server $(date +%s)"
cluster_desc_def="This server is powered by BBS_BEAUTIFUL.[$github_link]"
start_success_log_key="Sim paused"
master_ps_key="dontstarve.*Master"
caves_ps_key="dontstarve.*Caves"
# 启动超时时间，单位秒
start_timeout_unit=240

# 打印信息方法
# 用法：
#   print_info "INFO" "这是一条信息"
#   print_info "ERROR" "出错了"
#   print_info "SUCCESS" "操作成功"
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

function print_mark() {
    local mark_sign=$1
    local message=$2
    printf "\033[1;34m$mark_sign \033[0m%s\n" "$message"
}

function print_blue() {
    local message=$1
    printf "\033[1;34m%s\033[0m\n" "$message"
}

function print_green() {
    local message=$1
    printf "\033[1;32m%s\033[0m\n" "$message"
}

# 执行完命令后等待用户输入
function pause_at_end() {
    read -r -p "按 Enter 键继续..."
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
    # 检查日志文件中是否有成功的执行记录
    if [ -f "$install_libs_log_file" ]; then
        SUCCESS=$(cat "$install_libs_log_file")
    else
        SUCCESS=-1
    fi

    # 如果日志中没有成功记录，执行更新
    if [ "$SUCCESS" -ne 0 ]; then
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
            # 如果更新成功，写入日志文件
            echo "0" >"$install_libs_log_file"
            print_info "SUCCESS" "软件包安装/更新成功!"
        else
            # 如果更新失败，写入日志文件
            echo "-1" >"$install_libs_log_file"
            print_info "ERROR" "系统更新和软件包安装失败!"
            exit 1
        fi
    else
        print_info "SUCCESS" "软件包安装/更新已经执行过,跳过执行"
    fi
}

# 准备参数
function prepare_args() {
    # 安装基础目录，不存在则报错
    game_install_base_dir="$script_dir"
    if [ ! -d "$game_install_base_dir" ]; then
        print_info "ERROR" "用户home目录不存在,请检查用户home目录是否存在"
        exit 1
    fi
    # steamcmd安装目录，不存在则创建
    steamcmd_install_dir="$game_install_base_dir"/steamcmd
    if [ ! -d "$steamcmd_install_dir" ]; then
        print_info "INFO" "steamcmd安装目录不存在,创建目录"
        mkdir -p "$steamcmd_install_dir"
    fi
    steamcmd_exec_path="$steamcmd_install_dir"/steamcmd.sh
    # 游戏安装目录，不存在则创建
    game_install_dir="$game_install_base_dir"/dontstarve
    if [ ! -d "$game_install_dir" ]; then
        print_info "INFO" "游戏安装目录不存在,创建目录"
        mkdir -p "$game_install_dir"
    fi
    # 游戏配置目录，不存在则创建
    game_config_dir="$game_install_base_dir"/dontstarve-config
    if [ ! -d "$game_config_dir" ]; then
        print_info "INFO" "游戏配置目录不存在,创建目录"
        mkdir -p "$game_config_dir"
    fi
}

# 安装steamcmd
function install_steamcmd() {
    # 安装steamcmd
    if [ ! -e "$steamcmd_exec_path" ]; then
        print_info "INFO" "steamcmd.sh不存在,安装steamcmd..."
        cd "$steamcmd_install_dir"
        print_info "INFO" "开始下载steamcmd..."
        wget -O steamcmd_linux.tar.gz "$download_steamcmd_url"
        if [ $? -ne 0 ]; then
            print_info "ERROR" "steamcmd安装失败,请重试!"
            exit 1
        fi
        tar -xvzf steamcmd_linux.tar.gz
        rm -f steamcmd_linux.tar.gz
        print_info "SUCCESS" "steamcmd安装成功!"
    else
        print_info "SUCCESS" "steamcmd已安装,跳过"
    fi
}

# 备份mod
function backup_mod() {
    set -e
    local mod_file="${game_install_dir}/mods/dedicated_server_mods_setup.lua"
    if [ -f "$mod_file" ]; then
        local backup_file="${game_install_dir}/mods/dedicated_server_mods_setup.lua.bak"
        cp "$mod_file" "$backup_file"
    fi
    set +e
}

# 恢复mod
function recover_mod() {
    set -e
    local backup_file="${game_install_dir}/mods/dedicated_server_mods_setup.lua.bak"
    if [ -f "$backup_file" ]; then
        local mod_file="${game_install_dir}/mods/dedicated_server_mods_setup.lua"
        rm -f "$mod_file"
        mv "$backup_file" "$mod_file"
    fi
    set +e
}

# 安装游戏
function install_game() {
    print_info "INFO" "开始安装饥荒联机版服务端..."
    backup_mod
    "$steamcmd_exec_path" +force_install_dir "$game_install_dir" +login anonymous +app_update 343050 validate +quit
    if [ $? -eq 0 ]; then
        recover_mod
        print_info "SUCCESS" "饥荒联机版服务端安装成功!"
        while :; do
            print_info "INFO" "是否立即启动服务器? 也可稍后手动启动 [y/n]:"
            read -r -p "$(echo -e "[默认值: y]")" start_server_right_now
            [ -z "$start_server_right_now" ] && start_server_right_now=y
            case $start_server_right_now in
            y | Y | yes | Yes | YES)
                start_server
                break
                ;;
            n | N | no | No | NO)
                break
                ;;
            esac
        done
    else
        print_info "ERROR" "饥荒联机版服务端安装失败，请重试!"
        exit 1
    fi
}

# 安装服务器
function install_server() {
    local pid
    pid=$(pgrep -f "$master_ps_key")
    if [ -n "$pid" ]; then
        while :; do
            print_info "WARNING" "更新服务器需要停止服务, 是否继续? [y/n]:"
            read -r -p "$(echo -e "[默认值: y]")" stop_server_for_update
            [ -z "$stop_server_for_update" ] && stop_server_for_update=y
            case $stop_server_for_update in
            y | Y | yes | Yes | YES)
                stop_server
                break
                ;;
            n | N | no | No | NO)
                return 0
                ;;
            esac
        done
    fi
    install_steamcmd
    install_game
}

# 停止进程
function kill_process() {
    local process_name=$1
    local pid

    pid=$(pgrep -f "$process_name")

    if [ -n "$pid" ]; then
        print_info "INFO" "正在停止${process_name}进程, PID: ${pid}"
        echo "$pid" | xargs -r kill
        sleep 2s

        while
            pid=$(pgrep -f "$process_name")
            [ -n "$pid" ]
        do
            print_info "INFO" "正在重试停止${process_name}进程, PID: ${pid}"
            echo "$pid" | xargs -r kill
            sleep 5s
        done
    else
        print_info "INFO" "${process_name}进程不存在,跳过"
    fi
}

# 停止服务器
function stop_server() {
    kill_process "$master_ps_key"
    kill_process "$caves_ps_key"
}

# 验证服务器启动状态
function check_start_status() {
    local cur_ps_key=$1
    local cur_log_file=$2
    local cur_server_type=$3
    SECONDS=0

    while :; do
        print_info "INFO" "验证启动${cur_server_type}服务器状态, 耗时:[${SECONDS}s]"
        pid=$(pgrep -f "$cur_ps_key")
        if [ -n "$pid" ]; then
            if grep -q "$start_success_log_key" "$cur_log_file"; then
                print_info "SUCCESS" "${cur_server_type}服务器启动成功! 总耗时:[${SECONDS}s]"
                break
            fi
        fi

        if [ "$SECONDS" -ge "$start_timeout_unit" ]; then
            print_info "ERROR" "${cur_server_type}服务器启动超时，未在 ${start_timeout_unit}s 内成功启动"
            stop_server
            break
        fi
        sleep 1s
    done
}

# 启动地面服务器
function start_master() {
    print_info "INFO" "正在启动地面服务器..."
    cd "$game_install_dir"/bin
    local master_command=(./dontstarve_dedicated_server_nullrenderer)
    master_command+=(-console)
    master_command+=(-persistent_storage_root "$game_config_dir")
    master_command+=(-conf_dir clusters)
    master_command+=(-cluster MyDediServer)
    master_command+=(-shard Master)

    mkdir -p "$log_path"
    setsid "${master_command[@]}" >"$log_path"/master.log 2>&1 &

    # 验证启动地面服务器状态
    check_start_status "$master_ps_key" "$log_path"/master.log "地面"
}

# 启动洞穴服务器
function start_caves() {
    print_info "INFO" "启动洞穴服务器..."
    cd "$game_install_dir"/bin
    local caves_command=(./dontstarve_dedicated_server_nullrenderer)
    caves_command+=(-console)
    caves_command+=(-persistent_storage_root "$game_config_dir")
    caves_command+=(-conf_dir clusters)
    caves_command+=(-cluster MyDediServer)
    caves_command+=(-shard Caves)
    mkdir -p "$log_path"
    setsid "${caves_command[@]}" >"$log_path"/caves.log 2>&1 &

    # 验证启动洞穴服务器状态
    check_start_status "$caves_ps_key" "$log_path"/caves.log "洞穴"
}

# 初始化服务器token
function write_klei_token() {
    print_info "INFO" "初始化饥荒服务器令牌..."
    print_info "INFO" "请输入服务器令牌, 需要从游戏官方获取,网址为:$klei_token_url获取"
    read -r -p ">>> " klei_token
    mkdir -p "$game_config_dir"/clusters/MyDediServer
    echo "$klei_token" >"$game_config_dir"/clusters/MyDediServer/cluster_token.txt
    if [ $? -eq 0 ]; then
        print_info "SUCCESS" "初始化饥荒服务器令牌成功!"
    else
        print_info "ERROR" "初始化饥荒服务器令牌失败,请重试!"
        write_cluster_config
    fi
}

# cluster.ini
function write_cluster_ini() {
    set -e
    print_info "INFO" "开始初始化cluster配置..."
    # 游戏模式
    while :; do
        print_info "INFO" "请选择游戏模式: 1.生存 2.轻松 3.无尽 4.荒野 5.暗无天日:"
        read -r -p "$(echo -e "[默认值: 生存] >>> ")" game_mode
        [ -z "$game_mode" ] && game_mode=1
        case $game_mode in
        1)
            game_mode="survival"
            break
            ;;
        2)
            game_mode="relaxed"
            break
            ;;
        3)
            game_mode="endless"
            break
            ;;
        4)
            game_mode="wilderness"
            break
            ;;
        5)
            game_mode="lights_out"
            break
            ;;
        esac
    done
    print_info "SUCCESS" "设置的游戏模式为: $game_mode"

    # 最大玩家数
    while :; do
        print_info "INFO" "请输入最大玩家数(1-${max_players_limited}):"
        read -r -p "$(echo -e "[默认值: ${max_players_def}] >>> ")" max_players
        [ -z "$max_players" ] && max_players=${max_players_def}
        if [[ "$max_players" =~ ^[0-9]+$ ]] && [ "$max_players" -ge 1 ] && [ "$max_players" -le "$max_players_limited" ]; then
            break
        else
            print_info "ERROR" "输入无效，请输入一个介于 6 和 ${max_players_limited} 之间的数字"
        fi
    done
    print_info "SUCCESS" "设置的最大玩家数是：$max_players"

    # 是否开启pvp
    while :; do
        print_info "INFO" "是否开启PVP? [y/n]:"
        read -r -p "$(echo -e "[默认值: n] >>> ")" enable_pvp
        [ -z "$enable_pvp" ] && enable_pvp=n
        case $enable_pvp in
        y | Y | yes | Yes | YES)
            enable_pvp="true"
            break
            ;;
        n | N | no | No | NO)
            enable_pvp="false"
            break
            ;;
        esac
    done
    print_info "SUCCESS" "设置的PVP状态为: $enable_pvp"

    # 集群空时是否暂停
    while :; do
        print_info "INFO" "请选择服务器无人时是否暂停? [y/n]:"
        read -r -p "$(echo -e "[默认值: y] >>> ")" enable_pause
        [ -z "$enable_pause" ] && enable_pause=y
        case $enable_pause in
        y | Y | yes | Yes | YES)
            enable_pause="true"
            break
            ;;
        n | N | no | No | NO)
            enable_pause="false"
            break
            ;;
        esac
    done
    print_info "SUCCESS" "设置的服务器无人时是否暂停为: $enable_pause"

    # 服务器名称
    print_info "INFO" "请输入服务器名称:"
    read -r -p "$(echo -e "[默认值: $cluster_name_def]")" cluster_name
    [ -z "$cluster_name" ] && cluster_name="$cluster_name_def"
    print_info "SUCCESS" "设置的服务器名称为: $cluster_name"

    # 服务器描述
    print_info "INFO" "请输入服务器描述:"
    read -r -p "$(echo -e "[默认值: $cluster_desc_def]")" cluster_desc
    [ -z "$cluster_desc" ] && cluster_desc="$cluster_desc_def"
    print_info "SUCCESS" "设置的服务器描述为: $cluster_desc"

    # 服务器密码
    print_info "INFO" "请输入服务器密码:"
    read -r -p "$(echo -e "[默认值: 不设置密码]")" cluster_password
    print_info "SUCCESS" "设置的服务器密码为: $cluster_password"

    # 游戏模式
    while :; do
        print_info "INFO" "请选择游戏模式: 1.社交 2.合作 3.竞争 4.疯狂:"
        print_info "INFO" "社交模式: 适合休闲玩家,强调社交和合作,通常资源较为丰富,怪物强度适中"
        print_info "INFO" "合作模式: 默认选项,鼓励玩家合作生存,游戏难度适中"
        print_info "INFO" "竞争模式: 强调玩家之间的竞争,可能启用 PvP元素,资源相对稀缺"
        print_info "INFO" "疯狂模式: 极高难度,敌人更多更强,环境极端,适合挑战玩家"
        read -r -p "$(echo -e "[默认值: 合作]")" cluster_intention
        [ -z "$cluster_intention" ] && cluster_intention=2
        case $cluster_intention in
        1)
            cluster_intention=social
            break
            ;;
        2)
            cluster_intention=cooperative
            break
            ;;
        3)
            cluster_intention=competitive
            break
            ;;
        4)
            cluster_intention=madness
            break
            ;;
        esac
    done
    print_info "SUCCESS" "设置的游戏模式为: $cluster_intention"

    # 是否开启控制台
    while :; do
        print_info "INFO" "请选择服务器是否开启控制台? [y/n]:"
        read -r -p "$(echo -e "[默认值: n]")" enable_console
        [ -z "$enable_console" ] && enable_console=n
        case $enable_console in
        y | Y | yes | Yes | YES)
            enable_console="true"
            break
            ;;
        n | N | no | No | NO)
            enable_console="false"
            break
            ;;
        esac
    done
    print_info "SUCCESS" "设置的控制台状态为: $enable_console"

    # 是否开启洞穴
    while :; do
        print_info "INFO" "请选择服务器是否开启洞穴世界? [y/n]:"
        print_info "INFO" "开启洞穴需要更多资源,请确认服务器配置足够的情况下开启!"
        read -r -p "$(echo -e "[默认值: n]")" enable_caves
        [ -z "$enable_caves" ] && enable_caves=n
        case $enable_caves in
        y | Y | yes | Yes | YES)
            enable_caves="true"
            break
            ;;
        n | N | no | No | NO)
            enable_caves="false"
            break
            ;;
        esac
    done
    print_info "SUCCESS" "设置的洞穴世界状态为: $enable_caves"

    # 写入文件cluster.ini
    mkdir -p "$game_config_dir"/clusters/MyDediServer
    cat <<EOF >"$game_config_dir/clusters/MyDediServer/cluster.ini"
[GAMEPLAY]
game_mode = $game_mode
max_players = $max_players
pvp = $enable_pvp
pause_when_empty = $enable_pause

[NETWORK]
cluster_name = $cluster_name
cluster_description = $cluster_desc
cluster_password = $cluster_password
cluster_intention = $cluster_intention

[MISC]
console_enabled = $enable_console

[SHARD]
shard_enabled = $enable_caves
bind_ip = 127.0.0.1
master_ip = 127.0.0.1
master_port = 10889
cluster_key = supersecretkey
EOF

    set +e
    print_info "SUCCESS" "cluster配置完成"
}

# cluster配置
function write_cluster_config() {
    while :; do
        print_info "INFO" "====================== cluster配置管理======================"
        print_info "INFO" "[1] 饥荒服务器令牌"
        print_info "INFO" "[2] 服务配置"
        print_info "INFO" "[3] 返回"

        read -r menu_input
        case $menu_input in
        1)
            write_klei_token
            break
            ;;
        2)
            write_cluster_ini
            break
            ;;
        3)
            config_server
            break
            ;;
        esac
    done
}

# 地面配置
function write_master_config() {
    print_info "INFO" "开始初始化地面服务器配置..."
    # 写入文件server.ini
    mkdir -p "$game_config_dir"/clusters/MyDediServer/Master
    cat <<EOF >"$game_config_dir/clusters/MyDediServer/Master/server.ini"
[NETWORK]
server_port = 11000

[SHARD]
is_master = true

[STEAM]
master_server_port = 27018
authentication_port = 8768

[ACCOUNT]
encode_user_path = true
EOF
    # 写入文件worldgenoverride.lua
    cat <<EOF >"$game_config_dir/clusters/MyDediServer/Master/worldgenoverride.lua"
KLEI     1 return {
	override_enabled = true,
	worldgen_preset = "SURVIVAL_TOGETHER",
	settings_preset = "SURVIVAL_TOGETHER",
	overrides = {
	},
}
EOF
    print_info "SUCCESS" "地面配置完成"
}

# 洞穴配置
function write_caves_config() {
    print_info "INFO" "开始初始化洞穴服务器配置..."
    # 写入文件server.ini
    mkdir -p "$game_config_dir"/clusters/MyDediServer/Caves
    cat <<EOF >"$game_config_dir/clusters/MyDediServer/Caves/server.ini"
[NETWORK]
server_port = 11001

[SHARD]
is_master = false
name = Caves
id = 848851246

[STEAM]
master_server_port = 27019
authentication_port = 8769

[ACCOUNT]
encode_user_path = true

EOF
    # 写入文件worldgenoverride.lua
    cat <<EOF >"$game_config_dir/clusters/MyDediServer/Caves/worldgenoverride.lua"
KLEI     1 return {
	override_enabled = true,
	worldgen_preset = "DST_CAVE",
	settings_preset = "DST_CAVE",
	overrides = {
	},
}
EOF
    print_info "SUCCESS" "洞穴配置完成"
}

# 初始化配置
function fast_init_config() {
    print_info "INFO" "初始化配置..."
    rm -rf "$game_config_dir/clusters/MyDediServer"
    write_klei_token
    write_cluster_ini
    write_master_config
    [[ "$enable_caves" == "true" ]] && write_caves_config
    print_info "SUCCESS" "初始化配置完成"
}

# 服务配置管理
function config_server() {
    local pid
    pid=$(pgrep -f "$master_ps_key")
    if [ -n "$pid" ]; then
        while :; do
            print_info "WARNING" "修改配置需要停止服务器, 是否继续? [y/n]:"
            read -r -p "$(echo -e "[默认值: y]")" stop_server_for_config
            [ -z "$stop_server_for_config" ] && stop_server_for_config=y
            case $stop_server_for_config in
            y | Y | yes | Yes | YES)
                stop_server
                break
                ;;
            n | N | no | No | NO)
                return 0
                ;;
            esac
        done
    fi

    while :; do
        print_info "INFO" "====================== 服务器配置管理======================"
        print_info "INFO" "请选择服务器配置管理菜单"
        print_info "INFO" "[1] cluster配置 ------ [集群配置]"
        print_info "INFO" "[2] 地面配置 ------[地面服务器默认配置]"
        print_info "INFO" "[3] 洞穴配置 ------[洞穴服务器默认配置]"
        print_info "INFO" "[4] 恢复默认配置 ------ [会删除所有配置文件,重新配置]"
        print_info "INFO" "[5] 返回"
        read -r -p "请输入菜单序号：" menu_input

        if [[ ! "$menu_input" =~ ^([1-5])$ ]]; then
            print_info "ERROR" "错误:请输入正确的菜单序号!"
            break
        fi

        case $menu_input in
        1)
            write_cluster_config
            break
            ;;
        2)
            write_master_config
            break
            ;;
        3)
            write_caves_config
            break
            ;;
        4)
            fast_init_config
            break
            ;;
        5)
            main
            break
            ;;
        esac
    done
    config_server
}

# 启动服务器
function start_server() {
    print_info "INFO" "检测服务器状态"
    # 是否安装游戏
    if [ ! -e "$game_install_dir/bin/dontstarve_dedicated_server_nullrenderer" ]; then
        print_info "ERROR" "服务器未安装,请先安装服务器!"
        return 0
    fi

    local pid
    pid=$(pgrep -f "$master_ps_key")
    if [ -n "$pid" ]; then
        print_info "INFO" "当前存在运行中的服务,正在关闭..."
        stop_server
    fi

    print_info "INFO" "开始启动服务器"
    if [ ! -d "$game_config_dir/clusters/MyDediServer" ]; then
        print_info "INFO" "存档不存在,初始化配置..."
        fast_init_config
    fi
    echo "====================== 启动地面服务器======================"
    start_master
    if [ -d "$game_config_dir/clusters/MyDediServer/Caves" ]; then
        echo "====================== 启动洞穴服务器======================"
        sleep 2
        start_caves
    fi
}

# 卸载服务器
function remove_server() {
    print_info "INFO" "开始卸载服务器..."
    local pid
    pid=$(pgrep -f "$master_ps_key")
    if [ -n "$pid" ]; then
        print_info "INFO" "停止服务器..."
        stop_server
    fi
    print_info "INFO" "删除服务器文件..."
    rm -rf "$game_install_base_dir"/steamcmd
    rm -rf "$game_install_base_dir"/dontstarve
    rm -rf "$game_install_base_dir"/dontstarve-config
    print_info "SUCCESS" "服务器卸载完成"
}

# 获取进程端口
get_ports_by_pid() {
    local pid="$1"
    local result

    result=$(netstat -tunpl 2>/dev/null | grep "$pid" | awk '{
        split($4, a, ":");
        print $1 ":" a[length(a)]
    }' | xargs)
    echo "$result"
}

# 查看服务器状态
function show_server_status() {
    local steamcmd_status
    if [ -e "$steamcmd_exec_path" ]; then
        steamcmd_status="已安装"
    else
        steamcmd_status="未安装"
    fi
    local game_status
    if [ -e "$game_install_base_dir"/dontstarve/bin/dontstarve_dedicated_server_nullrenderer ]; then
        game_status="已安装"
    else
        game_status="未安装"
    fi

    local master_pid
    local master_port
    master_pid=$(pgrep -f "$master_ps_key")
    if [ -n "$master_pid" ]; then
        master_port=$(get_ports_by_pid "$master_pid")
    else
        master_port=""
    fi

    local caves_pid
    local caves_port
    caves_pid=$(pgrep -f "$caves_ps_key")
    if [ -n "$caves_pid" ]; then
        caves_port=$(get_ports_by_pid "$caves_pid")
    else
        caves_port=""
    fi

    print_info "$split_line"
    print_mark "SteamCMD状态" " ------ [$steamcmd_status]"
    print_mark "游戏状态" " ------ [$game_status]"
    print_mark "服务器状态: " ""
    printf "%-8s | %-8s | %-12s | %-32s\n" "类型" "状态" "pid" "端口"
    print_info "$split_line"
    if [ -n "$master_pid" ]; then
        printf "%-8s | \033[32m%-8s\033[0m | %-12s | %-32s\n" "地面" "运行" "$master_pid" "$master_port"
    else
        printf "%-8s | \033[31m%-8s\033[0m | %-12s | %-32s\n" "地面" "停止" "-" "-"
    fi
    if [ -n "$caves_pid" ]; then
        printf "%-8s | \033[32m%-8s\033[0m | %-12s | %-32s\n" "洞穴" "运行" "$caves_pid" "$caves_port"
    else
        printf "%-8s | \033[31m%-8s\033[0m | %-12s | %-32s\n" "洞穴" "停止" "-" "-"
    fi
    print_info "$split_line"
    pause_at_end
}

# 管理员列表
function show_admin_list() {
    local admin_file="$game_config_dir"/clusters/MyDediServer/adminlist.txt
    if [ -f "$admin_file" ]; then
        print_info "INFO" "管理员列表:"
        cat "$admin_file"
    else
        print_info "INFO" "管理员列表为空"
    fi
    pause_at_end
}

# 添加管理员
function add_admin() {
    local admin_klei_id
    print_info "INFO" "请输入管理员Klei ID:"

    # 等待用户输入管理员Klei ID
    while true; do
        read -r admin_klei_id
        # 判断用户输入是否为空
        if [ -z "$admin_klei_id" ]; then
            print_info "ERROR" "错误:管理员ID不能为空!"
        else
            break
        fi
    done

    # 创建管理员文件夹
    mkdir -p "$game_config_dir"/clusters/MyDediServer
    local admin_file="$game_config_dir"/clusters/MyDediServer/adminlist.txt

    # 检查管理员ID是否已经存在
    if ! grep -q "$admin_klei_id" "$admin_file"; then
        echo "$admin_klei_id" >>"$admin_file"
        print_info "SUCCESS" "管理员ID[$admin_klei_id]已成功添加"
    else
        print_info "SUCCESS" "管理员ID [$admin_klei_id] 已存在"
    fi
}

# 删除管理员
function del_admin() {
    local admin_klei_id
    print_info "INFO" "请输入要删除的管理员Klei ID:"

    # 等待用户输入管理员Klei ID
    while true; do
        read -r admin_klei_id
        # 判断用户输入是否为空
        if [ -z "$admin_klei_id" ]; then
            print_info "ERROR" "错误:管理员ID不能为空!"
        else
            break
        fi
    done

    local admin_file="$game_config_dir"/clusters/MyDediServer/adminlist.txt
    if [ -f "$admin_file" ]; then
        if grep -q "^$admin_klei_id$" "$admin_file"; then
            sed -i "/^$admin_klei_id$/d" "$admin_file"
            print_info "SUCCESS" "klei ID[$admin_klei_id]已从管理员列表删除"
        else
            print_info "ERROR" "管理员ID: [$admin_klei_id]不存在"
        fi
    else
        print_info "WARNING" "管理员列表为空,不需要删除"
    fi
}

# 管理员配置
function manage_admin() {
    while :; do
        print_info "INFO" "====================== 管理员配置======================"
        print_info "INFO" "[1] 查看当前管理员"
        print_info "INFO" "[2] 添加管理员"
        print_info "INFO" "[3] 删除管理员"
        print_info "INFO" "[4] 返回"
        print_green ">>> 请选择服务器管理菜单:"
        read -r menu_input

        if [[ ! "$menu_input" =~ ^([1-4])$ ]]; then
            print_info "ERROR" "错误:请输入正确的菜单序号!"
            break
        fi

        case $menu_input in
        1)
            show_admin_list
            break
            ;;
        2)
            add_admin
            break
            ;;
        3)
            del_admin
            break
            ;;
        4)
            manage_special_list
            break
            ;;
        esac
    done
    manage_admin
}

# 白名单列表
function show_white_list() {
    local white_file="$game_config_dir"/clusters/MyDediServer/whitelist.txt
    if [ -f "$white_file" ]; then
        print_info "INFO" "白名单列表:"
        cat "$white_file"
    else
        print_info "INFO" "白名单列表为空"
    fi
    pause_at_end
}

# 添加白名单
function add_white() {
    local white_klei_id
    print_info "INFO" "请输入白名单Klei ID:"

    # 等待用户输入白名单Klei ID
    while true; do
        read -r white_klei_id
        # 判断用户输入是否为空
        if [ -z "$white_klei_id" ]; then
            print_info "ERROR" "错误:白名单ID不能为空!"
        else
            break
        fi
    done

    # 创建白名单文件夹
    mkdir -p "$game_config_dir"/clusters/MyDediServer
    local white_file="$game_config_dir"/clusters/MyDediServer/whitelist.txt

    # 检查白名单ID是否已经存在
    if ! grep -q "$white_klei_id" "$white_file"; then
        echo "$white_klei_id" >>"$white_file"
        print_info "SUCCESS" "白名单ID[$white_klei_id]已成功添加"
    else
        print_info "SUCCESS" "白名单ID [$white_klei_id] 已存在"
    fi
}

# 删除白名单
function del_white() {
    local white_klei_id
    print_info "INFO" "请输入要删除的白名单Klei ID:"

    # 等待用户输入白名单Klei ID
    while true; do
        read -r white_klei_id
        # 判断用户输入是否为空
        if [ -z "$white_klei_id" ]; then
            print_info "ERROR" "错误:白名单ID不能为空!"
        else
            break
        fi
    done

    local white_file="$game_config_dir"/clusters/MyDediServer/whitelist.txt
    if [ -f "$white_file" ]; then
        if grep -q "^$white_klei_id$" "$white_file"; then
            sed -i "/^$white_klei_id$/d" "$white_file"
            print_info "SUCCESS" "klei ID[$white_klei_id]已从白名单列表删除"
        else
            print_info "ERROR" "白名单ID: [$white_klei_id]不存在"
        fi
    else
        print_info "WARNING" "白名单列表为空,不需要删除"
    fi
}

# 白名单配置
function manage_white() {
    while :; do
        print_info "INFO" "====================== 白名单配置======================"
        print_info "INFO" "[1] 查看当前白名单"
        print_info "INFO" "[2] 添加白名单"
        print_info "INFO" "[3] 删除白名单"
        print_info "INFO" "[4] 返回"
        print_green ">>> 请选择服务器管理菜单:"
        read -r menu_input

        if [[ ! "$menu_input" =~ ^([1-4])$ ]]; then
            print_info "ERROR" "错误:请输入正确的菜单序号!"
            break
        fi

        case $menu_input in
        1)
            show_white_list
            break
            ;;
        2)
            add_white
            break
            ;;
        3)
            del_white
            break
            ;;
        4)
            manage_special_list
            break
            ;;
        esac
    done
    manage_white
}

# 黑名单列表
function show_black_list() {
    local black_file="$game_config_dir"/clusters/MyDediServer/blacklist.txt
    if [ -f "$black_file" ]; then
        print_info "INFO" "黑名单列表:"
        cat "$black_file"
    else
        print_info "INFO" "黑名单列表为空"
    fi
    pause_at_end
}

# 添加黑名单
function add_black() {
    local black_klei_id
    print_info "INFO" "请输入黑名单Klei ID:"

    # 等待用户输入黑名单Klei ID
    while true; do
        read -r black_klei_id
        # 判断用户输入是否为空
        if [ -z "$black_klei_id" ]; then
            print_info "ERROR" "错误:黑名单ID不能为空!"
        else
            break
        fi
    done

    # 创建黑名单文件夹
    mkdir -p "$game_config_dir"/clusters/MyDediServer
    local black_file="$game_config_dir"/clusters/MyDediServer/blacklist.txt

    # 检查黑名单ID是否已经存在
    if ! grep -q "$black_klei_id" "$black_file"; then
        echo "$black_klei_id" >>"$black_file"
        print_info "SUCCESS" "黑名单ID[$black_klei_id]已成功添加"
    else
        print_info "SUCCESS" "黑名单ID [$black_klei_id] 已存在"
    fi
}

# 删除黑名单
function del_black() {
    local black_klei_id
    print_info "INFO" "请输入要删除的黑名单Klei ID:"

    # 等待用户输入黑名单Klei ID
    while true; do
        read -r black_klei_id
        # 判断用户输入是否为空
        if [ -z "$black_klei_id" ]; then
            print_info "ERROR" "错误:黑名单ID不能为空!"
        else
            break
        fi
    done

    local black_file="$game_config_dir"/clusters/MyDediServer/blacklist.txt
    if [ -f "$black_file" ]; then
        if grep -q "^$black_klei_id$" "$black_file"; then
            sed -i "/^$black_klei_id$/d" "$black_file"
            print_info "SUCCESS" "klei ID[$black_klei_id]已从黑名单列表删除"
        else
            print_info "ERROR" "黑名单ID: [$black_klei_id]不存在"
        fi
    else
        print_info "WARNING" "黑名单列表为空,不需要删除"
    fi
}

# 黑名单配置
function manage_black() {
    while :; do
        print_info "INFO" "====================== 黑名单配置======================"
        print_info "INFO" "[1] 查看当前黑名单"
        print_info "INFO" "[2] 添加黑名单"
        print_info "INFO" "[3] 删除黑名单"
        print_info "INFO" "[4] 返回"
        print_green ">>> 请选择服务器管理菜单:"
        read -r menu_input

        if [[ ! "$menu_input" =~ ^([1-4])$ ]]; then
            print_info "ERROR" "错误:请输入正确的菜单序号!"
            break
        fi

        case $menu_input in
        1)
            show_black_list
            break
            ;;
        2)
            add_black
            break
            ;;
        3)
            del_black
            break
            ;;
        4)
            manage_special_list
            break
            ;;
        esac
    done
    manage_black
}

# 管理特殊名单
function manage_special_list() {
    local pid
    pid=$(pgrep -f "$master_ps_key")
    if [ -n "$pid" ]; then
        while :; do
            print_info "WARNING" "管理名单需要停止服务器, 是否继续? [y/n]:"
            read -r -p "$(echo -e "[默认值: y]")" stop_server_for_special_list
            [ -z "$stop_server_for_special_list" ] && stop_server_for_special_list=y
            case $stop_server_for_special_list in
            y | Y | yes | Yes | YES)
                stop_server
                break
                ;;
            n | N | no | No | NO)
                return 0
                ;;
            esac
        done
    fi

    while :; do
        print_info "INFO" "====================== 特殊名单管理======================"
        print_info "INFO" "[1] 管理员配置 ------ [配置管理员列表]"
        print_info "INFO" "[2] 白名单配置 ------ [配置白名单列表]"
        print_info "INFO" "[3] 黑名单配置 ------ [配置黑名单列表]"
        print_info "INFO" "[4] 返回"
        print_green ">>> 请选择服务器管理菜单:"
        read -r menu_input

        if [[ ! "$menu_input" =~ ^([1-5])$ ]]; then
            print_info "ERROR" "错误:请输入正确的菜单序号!"
            break
        fi

        case $menu_input in
        1)
            manage_admin
            break
            ;;
        2)
            manage_white
            break
            ;;
        3)
            manage_black
            break
            ;;
        4)
            main
            break
            ;;
        esac
    done
    manage_special_list
}

# 模组列表
function show_mod_list() {
    local mod_file="${game_install_dir}/mods/dedicated_server_mods_setup.lua"

    if [[ -f "$mod_file" ]]; then
        local mod_lines
        mod_lines=$(grep '^ServerModSetup' "$mod_file")

        if [[ -n "$mod_lines" ]]; then
            print_info "INFO" "当前已添加的mod列表:"
            echo "$mod_lines" | nl -w2 -s'. '
        else
            print_info "INFO" "mod列表为(空未添加任何mod)"
        fi
    else
        print_info "INFO" "mod文件不存在,未添加任何mod"
    fi

    pause_at_end
}

# 添加mod
function add_mod() {
    local mod_id
    print_info "INFO" "请输入要添加的mod ID:"

    while true; do
        read -r mod_id
        if [[ -z "$mod_id" ]]; then
            print_info "ERROR" "错误: mod ID 不能为空!"
        else
            break
        fi
    done

    local mod_file="${game_install_dir}/mods/dedicated_server_mods_setup.lua"
    if ! grep -qx "ServerModSetup(\"$mod_id\")" "$mod_file" 2>/dev/null; then
        printf 'ServerModSetup("%s")\n' "$mod_id" >>"$mod_file"
        print_info "SUCCESS" "mod [$mod_id] 已成功添加到[$mod_file]"
    else
        print_info "SUCCESS" "mod [$mod_id] 已存在[$mod_file]"
    fi

    # 主世界
    local master_overrides_file="$game_config_dir/clusters/MyDediServer/Master/modoverrides.lua"
    if ! grep -q "$mod_id" "$master_overrides_file" 2>/dev/null; then
        if [ ! -f "$master_overrides_file" ]; then
            printf 'return{\n}' >"$master_overrides_file"
        fi
        sed -i '$d' "$master_overrides_file"
        echo "[\"workshop-$mod_id\"]={ configuration_options={  }, enabled=true }," >>"$master_overrides_file"
        echo "}" >>"$master_overrides_file"
        print_info "SUCCESS" "mod [$mod_id] 已成功添加到[$master_overrides_file]"
    else
        print_info "SUCCESS" "mod [$mod_id] 已存在[$master_overrides_file]"
    fi

    # 洞穴
    if [ -d "$game_config_dir/clusters/MyDediServer/Caves" ]; then
        local caves_overrides_file="$game_config_dir/clusters/MyDediServer/Caves/modoverrides.lua"
        if ! grep -q "$mod_id" "$caves_overrides_file" 2>/dev/null; then
            if [ ! -f "$caves_overrides_file" ]; then
                printf 'return{\n}' >"$caves_overrides_file"
            fi
            sed -i '$d' "$caves_overrides_file"
            echo "[\"workshop-$mod_id\"]={ configuration_options={  }, enabled=true }," >>"$caves_overrides_file"
            echo "}" >>"$caves_overrides_file"
            print_info "SUCCESS" "mod [$mod_id] 已成功添加到[$caves_overrides_file]"
        else
            print_info "SUCCESS" "mod [$mod_id] 已存在[$caves_overrides_file]"
        fi
    fi
}

# 删除mod
function del_mod() {
    local mod_id
    print_info "INFO" "请输入要删除的 mod ID:"

    while true; do
        read -r mod_id
        if [[ -z "$mod_id" ]]; then
            print_info "ERROR" "错误: mod ID 不能为空!"
        else
            break
        fi
    done

    local mod_file="${game_install_dir}/mods/dedicated_server_mods_setup.lua"
    local match_line="ServerModSetup(\"$mod_id\")"
    if [[ -f "$mod_file" ]]; then
        if grep -Fxq "$match_line" "$mod_file"; then
            sed -i "\|^${match_line}$|d" "$mod_file"
            print_info "SUCCESS" "mod ID [$mod_id] 已从[$mod_file]删除"
        else
            print_info "ERROR" "mod ID [$mod_id] 不存在[$mod_file]"
        fi
    else
        print_info "WARNING" "mod 文件不存在，无需删除"
    fi

    # 主世界
    local master_overrides_file="$game_config_dir/clusters/MyDediServer/Master/modoverrides.lua"
    if [[ -f "$master_overrides_file" ]]; then
        if grep -q "$mod_id" "$master_overrides_file"; then
            sed -i "/$mod_id/d" "$master_overrides_file"
            print_info "SUCCESS" "mod ID [$mod_id] 已从[$master_overrides_file]删除"
        else
            print_info "ERROR" "mod ID [$mod_id] 不存在[$master_overrides_file]"
        fi
    fi

    # 洞穴
    if [ -d "$game_config_dir/clusters/MyDediServer/Caves" ]; then
        local caves_overrides_file="$game_config_dir/clusters/MyDediServer/Caves/modoverrides.lua"
        if [[ -f "$caves_overrides_file" ]]; then
            if grep -q "$mod_id" "$caves_overrides_file"; then
                sed -i "/$mod_id/d" "$caves_overrides_file"
                print_info "SUCCESS" "mod ID [$mod_id] 已从[$caves_overrides_file]删除"
            else
                print_info "ERROR" "mod ID [$mod_id] 不存在[$caves_overrides_file]"
            fi
        fi
    fi
}

# 管理mod
function manage_mod() {
    local pid
    pid=$(pgrep -f "$master_ps_key")
    if [ -n "$pid" ]; then
        while :; do
            print_info "WARNING" "管理mod需要停止服务器, 是否继续? [y/n]:"
            read -r -p "$(echo -e "[默认值: y]")" stop_server_for_mod
            [ -z "$stop_server_for_mod" ] && stop_server_for_mod=y
            case $stop_server_for_mod in
            y | Y | yes | Yes | YES)
                stop_server
                break
                ;;
            n | N | no | No | NO)
                return 0
                ;;
            esac
        done
    fi

    while :; do
        print_info "INFO" "====================== MOD管理 ======================"
        print_info "INFO" "========= 添加/删除mod后需要重启服务器生效 ==========="
        print_info "INFO" "[1] 查看当前mod列表 ------ [查看当前mod]"
        print_info "INFO" "[2] 添加mod ------ [添加mod]"
        print_info "INFO" "[3] 删除mod ------ [删除mod]"
        print_info "INFO" "[4] 返回"
        print_green ">>> 请选择服务器管理菜单:"
        read -r menu_input

        if [[ ! "$menu_input" =~ ^([1-5])$ ]]; then
            print_info "ERROR" "错误:请输入正确的菜单序号!"
            break
        fi

        case $menu_input in
        1)
            show_mod_list
            break
            ;;
        2)
            add_mod
            break
            ;;
        3)
            del_mod
            break
            ;;
        4)
            main
            break
            ;;
        esac
    done
    manage_mod
}

# 入口函数
function main() {
    print_info "$split_line"
    print_info "======================= BBS-饥荒联机版专用服务器管理 ======================="
    print_info "============ ${github_link} ==========="
    print_info "=========================== Ctrl+C 可随时退出脚本 =========================="
    print_info "$split_line"
    while :; do
        print_mark "[1]" "安装/更新服务器 ------ [服务器不存在则安装,存在则更新]"
        print_mark "[2]" "启动/重启服务器 ------ [启动服务器,如果已经启动,则重启]"
        print_mark "[3]" "关闭服务器 ------ [关闭服务器进程]"
        print_mark "[4]" "服务配置 ------ [修改服务器配置,需要停止服务器进程]"
        print_mark "[5]" "MOD管理 ------ [修改MOD配置,需要停止服务器进程]"
        print_mark "[6]" "管理特殊名单 ------ [管理特殊名单,需要停止服务器进程]"
        print_mark "[7]" "卸载服务器 ------ [卸载服务器,删除服务器文件]"
        print_mark "[8]" "服务器状态 ------ [查看服务器状态]"
        print_mark "[Q]" "退出"
        print_green ">>> 请选择服务器管理菜单:"
        read -r menu_input

        if [[ ! "$menu_input" =~ ^([1-8]|q|Q)$ ]]; then
            print_info "ERROR" "请输入正确的菜单序号!"
            main
        fi

        case $menu_input in
        1)
            install_server
            break
            ;;
        2)
            start_server
            break
            ;;
        3)
            stop_server
            break
            ;;
        4)
            config_server
            break
            ;;
        5)
            manage_mod
            break
            ;;
        6)
            manage_special_list
            break
            ;;
        7)
            remove_server
            break
            ;;
        8)
            show_server_status
            break
            ;;
        q | Q)
            print_blue "BBS管理端已退出!"
            exit 0
            ;;
        esac
    done
    main
}

function bbs_run() {
    print_info "$split_line"
    print_info "INFO" "开始检测服务器依赖包"
    # 安装依赖包
    install_libs
    # 创建目录
    print_info "INFO" "初始化服务器参数"
    prepare_args
    print_info "SUCCESS" "初始化完成"
    main
}

if [[ "$1" == "update" ]]; then
    print_info "INFO" "开始更新服务器"
    install_server
    print_info "SUCCESS" "更新完成"
    print_info "INFO" "开始启动服务器"
    start_server
    print_info "SUCCESS" "启动完成"
else
    bbs_run
fi
