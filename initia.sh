#!/bin/bash

# 检查是否以root用户运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以root用户权限运行。"
    echo "请尝试使用 'sudo -i' 命令切换到root用户，然后再次运行此脚本。"
    exit 1
fi

# 检查并安装 Node.js 和 npm
function install_nodejs_and_npm() {
    if command -v node > /dev/null 2>&1; then
        echo "Node.js 已安装"
    else
        echo "Node.js 未安装，正在安装..."
        curl -fsSL https://deb.nodesource.com/setup_16.x | bash -
        apt-get install -y nodejs
    fi

    if command -v npm > /dev/null 2>&1; then
        echo "npm 已安装"
    else
        echo "npm 未安装，正在安装..."
        apt-get install -y npm
    fi
}

# 检查并安装 PM2
function install_pm2() {
    if command -v pm2 > /dev/null 2>&1; then
        echo "PM2 已安装"
    else
        echo "PM2 未安装，正在安装..."
        npm install pm2@latest -g
    fi
}

# 检查Go环境
function check_go_installation() {
    if command -v go > /dev/null 2>&1; then
        echo "Go 环境已安装"
        return 0 
    else
        echo "Go 环境未安装，正在安装..."
        return 1 
    fi
}

# 节点安装功能
function install_node() {
    install_nodejs_and_npm
    install_pm2
    pm2 del all
    # Back up priv_validator_state.json if needed
    #cp ~/.initia/data/priv_validator_state.json  ~/.initia/priv_validator_state.json
    rm -rf ~/initia
    # 更新和安装必要的软件
    apt update && apt upgrade -y
    apt install -y curl iptables build-essential git wget jq make gcc nano tmux htop nvme-cli pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev lz4 snapd

    # 安装 Go
    if ! check_go_installation; then
        rm -rf /usr/local/go
        curl -L https://go.dev/dl/go1.22.0.linux-amd64.tar.gz | tar -xzf - -C /usr/local
        echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile
        source $HOME/.bash_profile
        go version
    fi

    # 安装所有二进制文件
    git clone https://github.com/initia-labs/initia
    cd initia
    git pull
    git checkout v0.2.14
    make install
    initiad version

    # 配置initiad
    initiad init "Moniker" --chain-id initiation-1
    initiad config set client chain-id initiation-1

    # 获取初始文件和地址簿
    wget -O $HOME/.initia/config/genesis.json https://initia.s3.ap-southeast-1.amazonaws.com/initiation-1/genesis.json
    wget -O $HOME/.initia/config/addrbook.json https://rpc-initia-testnet.trusted-point.com/addrbook.json
    sed -i -e "s|^minimum-gas-prices *=.*|minimum-gas-prices = \"0.15uinit,0.01uusdc\"|" $HOME/.initia/config/app.toml

    # 配置节点
    PEERS="a96694150ccd37f224059b3307dfcf6c38859c9c@65.21.109.183:26656,5c5441d80d686129b9c3fe62830ee5fc732bdce4@138.201.196.246:26656,8c63f08b951f7680a443caa1144b720d2a666261@65.108.232.174:17956,878a184ea897412f9823e3190b8ef1c81e263508@65.108.60.2:26656,37a683597dc1807c57550b5f10e8238bc5c81994@195.201.58.101:26656,22d15dd14042fe37356d5c21ada139d753c770db@65.109.49.248:26656,b3202f401aee2ad59afae9d4f671647005538059@168.119.235.140:17956,769b90d0c4c4cedb5d0b8d6a3627a5792b4c8519@5.78.98.32:17956,4e33a90e043ce7c80f0ccff86bffa0c921b9a1e7@116.202.243.98:26656,29835dc71444e9a728cb25a12febe67e255dce56@65.108.229.141:26756,e1bc2c4ef45100e12fe49d5999f7b21ff32c64c4@95.217.132.163:26656,d76820c0890379eb75e3c27ea881167f97f3ca70@95.216.43.37:26656" && \
    SEEDS="2eaa272622d1ba6796100ab39f58c75d458b9dbc@34.142.181.82:26656,c28827cb96c14c905b127b92065a3fb4cd77d7f6@testnet-seeds.whispernode.com:25756" && \
    sed -i \
        -e "s/^seeds *=.*/seeds = \"$SEEDS\"/" \
        -e "s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" \
    "$HOME/.initia/config/config.toml"

    # 配置端口
    node_address="tcp://localhost:53457"
    sed -i -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:53458\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:53457\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:53460\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:53456\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":53466\"%" $HOME/.initia/config/config.toml
    sed -i -e "s%^address = \"tcp://localhost:1317\"%address = \"tcp://0.0.0.0:53417\"%; s%^address = \":8080\"%address = \":53480\"%; s%^address = \"localhost:9090\"%address = \"0.0.0.0:53490\"%; s%^address = \"localhost:9091\"%address = \"0.0.0.0:53491\"%; s%:8545%:53445%; s%:8546%:53446%; s%:6065%:53465%" $HOME/.initia/config/app.toml
    echo "export initiad_RPC_PORT=$node_address" >> $HOME/.bash_profile
    source $HOME/.bash_profile   

    # 配置预言机
    git clone https://github.com/skip-mev/slinky.git
    cd slinky

    # checkout proper version
    git checkout v0.4.3
    
    make build

    # 配置预言机启用
    sed -i -e 's/^enabled = "false"/enabled = "true"/' \
       -e 's/^oracle_address = ""/oracle_address = "127.0.0.1:8080"/' \
       -e 's/^client_timeout = "2s"/client_timeout = "500ms"/' \
       -e 's/^metrics_enabled = "false"/metrics_enabled = "false"/' $HOME/.initia/config/app.toml
    
    pm2 start initiad -- start && pm2 save && pm2 startup

    pm2 stop initiad
    
    # 配置快照
    sudo apt install lz4 -y
    initiad tendermint unsafe-reset-all --home $HOME/.initia --keep-addr-book
    curl -L https://snapshots.polkachu.com/testnet-snapshots/initia/initia_237655.tar.lz4 | tar -Ilz4 -xf - -C $HOME/.initia
    #cp ~/.initia/priv_validator_state.json  ~/.initia/data/priv_validator_state.json
    
    pm2 start ./build/slinky -- --oracle-config-path ./config/core/oracle.json --market-map-endpoint 0.0.0.0:53490
    sed -i "s/^indexer *=.*/indexer = \"null\"/" $HOME/.initia/config/config.toml 
    sed -i 's/laddr = "tcp:\/\/127.0.0.1:53457"/laddr = "tcp:\/\/0.0.0.0:53457"/g' $HOME/.initia/config/config.toml
    wget http://95.216.228.91/initia-addrbook.json -O $HOME/.initia/config/addrbook.json
    pm2 restart initiad

    echo '====================== 安装完成,请退出脚本后执行 source $HOME/.bash_profile 以加载环境变量==========================='
}

# 查看initia 服务状态
function check_service_status() {
    pm2 list
}

# initia 节点日志查询
function view_logs() {
    pm2 logs initiad
}

# 卸载节点功能
function uninstall_node() {
    echo "你确定要卸载initia 节点程序吗？这将会删除所有相关的数据。[Y/N]"
    read -r -p "请确认: " response

    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "开始卸载节点程序..."
            pm2 stop initiad && pm2 delete initiad
            rm -rf $HOME/.initiad && rm -rf $HOME/initia $(which initiad) && rm -rf $HOME/.initia
            echo "节点程序卸载完成。"
            ;;
        *)
            echo "取消卸载操作。"
            ;;
    esac
}

# 创建钱包
function add_wallet() {
    initiad keys add wallet
}

# 导入钱包
function import_wallet() {
    initiad keys add wallet --recover
}

# 查询余额
function check_balances() {
    read -p "请输入钱包地址: " wallet_address
    initiad query bank balances "$wallet_address" --node $initiad_RPC_PORT
}

# 查看节点同步状态
function check_sync_status() {
    initiad status --node $initiad_RPC_PORT | jq .sync_info
}

# 创建验证者
function add_validator() {
    read -p "请输入您的钱包名称: " wallet_name
    
    read -p "请输入您想设置的验证者的名字: " validator_name
    
    read -p "请输入您的验证者详情（例如'吊毛资本'）: " details


    initiad tx mstaking create-validator   --amount=1000000uinit   --pubkey=$(initiad tendermint show-validator)   --moniker=$validator_name   --chain-id=initiation-1   --commission-rate=0.05   --commission-max-rate=0.10   --commission-max-change-rate=0.01   --from=$wallet_name   --identity=""   --website=""   --details=""   --gas=2000000 --fees=300000uinit --node $initiad_RPC_PORT 
  
}

# 给自己地址验证者质押
function delegate_self_validator() {
    read -p "请输入质押代币数量,比如你有1个init,请输入1000000，以此类推: " math
    read -p "请输入钱包名称: " wallet_name
    initiad tx mstaking delegate $(initiad keys show wallet --bech val -a) ${math}uinit --from $wallet_name --chain-id initiation-1 --gas=2000000 --fees=300000uinit --node $initiad_RPC_PORT -y
}

function unjail() {
    read -p "请输入钱包名称: " wallet_name
    initiad tx slashing unjail --from $wallet_name --fees=10000amf --chain-id=initiation-1 --node $initiad_RPC_PORT
}

# 导出验证者key
function export_priv_validator_key() {
    echo "====================请将下方所有内容备份到自己的记事本或者excel表格中记录==========================================="
    cat ~/.initia/config/priv_validator_key.json
    
}

function update_node() {
cd $HOME
cd initia
git fetch --tags
latest_tag=$(git describe --tags `git rev-list --tags --max-count=1`)
if [ -z "$latest_tag" ]; then
    echo "未找到最新的标签。"
    exit 1
fi

git checkout $latest_tag
make install
pm2 restart initiad

echo "升级到最新版本 $latest_tag 完成。"

}

# 主菜单
function main_menu() {
    while true; do
        clear
        echo "脚本以及教程由推特用户大赌哥 @y95277777 编写，免费开源，请勿相信收费"
        echo "================================================================"
        echo "节点社区 Telegram 群组:https://t.me/niuwuriji"
        echo "节点社区 Telegram 频道:https://t.me/niuwuriji"
        echo "节点社区 Discord 社群:https://discord.gg/GbMV5EcNWF"
        echo "退出脚本，请按键盘ctrl c退出即可"
        echo "请选择要执行的操作:"
        echo "1. 安装节点"
        echo "2. 创建钱包"
        echo "3. 导入钱包"
        echo "4. 查看钱包地址余额"
        echo "5. 查看节点同步状态"
        echo "6. 查看当前服务状态"
        echo "7. 运行日志查询"
        echo "8. 卸载节点"
        echo "9. 设置快捷键"  
        echo "10. 创建验证者"  
        echo "11. 给自己质押"
        echo "12. 释放出监狱"
        echo "13. 备份验证者私钥" 
        echo "14. 升级节点" 
        read -p "请输入选项（1-12）: " OPTION

        case $OPTION in
        1) install_node ;;
        2) add_wallet ;;
        3) import_wallet ;;
        4) check_balances ;;
        5) check_sync_status ;;
        6) check_service_status ;;
        7) view_logs ;;
        8) uninstall_node ;;
        9) check_and_set_alias ;;
        10) add_validator ;;
        11) delegate_self_validator ;;
        12) unjail ;;
        13) export_priv_validator_key ;;
        14) update_node ;;
        *) echo "无效选项。" ;;
        esac
        echo "按任意键返回主菜单..."
        read -n 1
    done
}

# 显示主菜单
main_menu
