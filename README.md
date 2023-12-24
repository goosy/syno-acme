# syno-acme

通过acme协议更新群晖HTTPS泛域名证书的自动脚本。

本脚本 fork 自 [andyzhshg/syno-acme](https://github.com/andyzhshg/syno-acme)，在它的基础上：

- 将下载工具和更新证书分开
- 支持自动下载最新版本的 acme.sh ，不再依赖 syno-acme 本身来更新
- 自动提示输入 sudo 密码
- 不再使用 python，完全用shell实现
- 支持syncthing

注释掉重启 webservice 部分，因为不通用，有能力者可自行写这部分代码。

## 安装

```bash
# 1. 将脚本复制到 home 文件夹下
cd ~
git clone https://github.com/goosy/syno-acme.git
cd syno-acme
chmod 700 ./cert-up.sh

# 2. 填写配置文件设置环境变量
# 提示你修改 ~/.acme.sh/config 文件
# 填写你的电子邮箱、域名、域名服务商、是否也更新 syncthing 证书等等
./cert-up.sh config

# 3. 更新脚本
./cert-up.sh setup
# 该命令会自动执行下面2小步的内容
# 3.1 更新acme.sh工具 ./cert-up.sh uptools
# 3.2 注册电子邮箱 ./cert-up.sh register
# 可以在以后的维护期间单独执行3.1

# 4. 更新证书及服务
./cert-up.sh update
# 该命令相当于以下2个命令逐步执行。
# 4.1 更新证书 `./cert-up.sh update_cert`
# 4.2 更新NAS对应服务 `./cert-up.sh update_service`

# 1至4.1可在无墙的远程机上进行，远程机获得证书
# 则需要在本地NAS上
# - 复制证书
# - 更新使用证书的服务
./cert-up.sh update_service
```

还有其它命令，比如根据需要回退证书：`./cert-up.sh revert`

## 维护

仅第一次需要从头执行到第4步，以后只需要第3.1步和第4步。

- 第3步的作用仅仅是更新acme.sh工具并注册，建议仅在acme.sh工具有新版时更新，以保证与CA站点的兼容性。
- 第4步是更新证书，建议把第4步命令放入 synology NAS 的定期脚本任务中，周期可设为3个月。

文件位置

- 更新后的证书存放在 ~/certificates/
- acme.sh工具 ~/.acme.sh/

## 网络受限地区

鉴于有些地区无法顺畅地访问相关网络服务，可以2种办法因应：

### 1 NAS端安装科学上网工具

### 2 证书更新部分在远程主机执行

这种办法，要求有一个网络顺畅的远程主机。但NAS端无法实现自动脚本。

远程主机：

- 远程主机初次安装执行1~3
- 远程主机更新证书时执行4.1

本地NAS：

- 本地NAS初次安装执行1~2（其中2仅填写是否有syncthing）
- 将远程的证书目录复制本地NAS对应目录中 (~/certificates/)
- 本地NAS更新服务，执行4.2
