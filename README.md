# syno-acme

通过acme协议更新群晖HTTPS泛域名证书的自动脚本。

本脚本 fork 自 [andyzhshg/syno-acme](https://github.com/andyzhshg/syno-acme)，在它的基础上：

- 将下载工具和更新证书分开
- 支持自动下载最新版本的 acme.sh
- 自动提示输入 sudo 密码
- 不再使用 python，完全用shell实现
- 支持多配置，用于不同的证书申请
- 支持syncthing

暂时注释掉 `reload webservice` 部分，因为不通用，有能力者可自行写这部分代码。

## 安装

### 1. 将脚本复制到 home 文件夹下

```bash
cd ~
git clone https://github.com/goosy/syno-acme.git
chmod 700 ./syno-acme/cert-up.sh
```

### 2. 更新 acme 脚本工具

该命令会自动下载和更新 acme.sh 脚本工具。
如果以前执行过该命令，可以跳过，否则它将更新 acme.sh 工具。

```bash
./syno-acme/cert-up.sh gettools
```

### 3. 填写配置文件设置环境变量

config 命令配置基本环境。
命令后可以跟配置目录名，比如 my_config_dir。没有的话延用上一次配置目录。
如果有 -e --edit 标志，脚本会找到 my_config_dir/config 文件，并打开供你修改。在该配置文件中填写你的电子邮箱、域名、域名服务商、syncthing 等等。
如果 my_config_dir 不存在，脚本会建立这个配置目录，并生成一个默认的 my_config_dir/config 文件同时自动打开要求你修改。

可以配置和切换多个配置目录，用于不同的证书申请。

```bash
./syno-acme/cert-up.sh setup [my_config_dir] [-e|--edit]
```

该命令相当于自动执行下面3个小步骤:

- 3.1 新建或切换配置目录
  `./syno-acme/cert-up.sh config <my_config_dir>`
  config 命令的 my_config_dir 参数必填。
  如果 setup 命令没有 my_config_dir 参数，则不会执行这一步。
- 3.2 编辑配置文件
  `./syno-acme/cert-up.sh edit`
  当有 setup 命令有 -e --edit 标志，或首次建立该配置目录时，会执行这一步。
- 3.3 注册账号
  `./syno-acme/cert-up.sh register`

以上3步骤都可以用对应命令单独执行。

有时候因为 acem.sh 更新等原因，如果 3.3 步骤或后续步骤失败，可以执行以下命令重置配置内容。

```bash
./syno-acme/cert-up.sh reset
```

### 4. 更新证书及服务

```bash
./syno-acme/cert-up.sh update
```

该命令相当于以下5个命令逐步执行:

- 4.1 更新证书 `./syno-acme/cert-up.sh update_cert`
- 4.2 应用新证书 `./syno-acme/cert-up.sh apply_cert`
- 4.3 重启NAS服务 `./syno-acme/cert-up.sh reload`
- 4.4 更新 syncthing 证书并重启服务 `./syno-acme/cert-up.sh syncthing`
- 4.5 更新 jellyfin 证书并重启服务 `./syno-acme/cert-up.sh jellyfin`

### 总结

1至4.1可在无墙的远程机上进行，远程机获得证书，需要在本地NAS上
- 复制证书
- 更新使用证书的服务

  ```bash
  ./syno-acme/cert-up.sh update_service
  ```

还有其它命令，请参看 help 命令。
比如根据需要回退证书：`./syno-acme/cert-up.sh revert`

## 维护

仅第一次需要从头执行到第 4 步，以后只需要第 4 步。

可以根据需要执行以下步骤：

- 2 更新acme.sh工具
- 3 修改配置并注册
- register 和 issue 有错误时，可以试着执行 `./syno-acme/cert-up.sh reset`

文件位置

- 更新后的证书存放在 `~/certificates/`
- acme.sh工具位置 `~/syno-acme/acme.sh/`

## 网络受限地区

鉴于有些地区无法顺畅地访问相关网络服务，可以2种办法因应：

### 1 NAS端安装科学上网工具

### 2 证书更新部分在远程主机执行

这种办法，要求有一个网络顺畅的远程主机。缺点是 NAS 端无法实现自动脚本。

远程主机：

- 远程主机初次安装执行 1, 2, 3
- 远程主机更新证书时执行 4.1

本地NAS：

- 本地NAS初次安装执行 1, 2（其中2仅填写是否有syncthing）
- 将远程的证书目录复制本地NAS对应目录中 (~/certificates/)
- 本地NAS更新服务，执行 4.2 4.3 4.4 4.5
