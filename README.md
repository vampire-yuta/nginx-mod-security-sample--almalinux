# nginx-mod-security-sample

## インストール手順

### 1. rootユーザーへの切り替え

```bash
sudo su -
```

### 2. 前提パッケージのインストール

AlmaLinux 9向けのパッケージリスト:

```bash
dnf update -y
dnf install epel-release -y
dnf install dnf-plugins-core -y
dnf config-manager --set-enabled crb
dnf groupinstall "Development Tools" -y
dnf install gcc-c++ flex bison curl httpd-devel doxygen yajl-devel ssdeep lua-devel pcre pcre-devel libtool autoconf automake libcurl-devel libxml2 libxml2-devel git lmdb-devel pkgconf zlib-devel openssl-devel wget vim -y
```

### 3. ModSecurity v3のビルドとインストール

```bash
cd ~
wget https://github.com/SpiderLabs/ModSecurity/releases/download/v3.0.14/modsecurity-v3.0.14.tar.gz
tar -xvzf modsecurity-v3.0.14.tar.gz
cd modsecurity-v3.0.14
./build.sh
./configure
make
make install
```

### 4. ModSecurity-nginx Connectorの取得

```bash
cd ~
git clone https://github.com/SpiderLabs/ModSecurity-nginx.git
```

### 5. nginxのビルドとインストール

```bash
wget https://nginx.org/download/nginx-1.28.0.tar.gz
tar xvzf nginx-1.28.0.tar.gz
useradd -r -M -s /sbin/nologin -d /usr/local/nginx nginx
cd nginx-1.28.0
./configure --user=nginx --group=nginx --with-pcre-jit --with-debug --with-compat --with-http_ssl_module --with-http_realip_module --with-stream --add-dynamic-module=/root/ModSecurity-nginx --http-log-path=/var/log/nginx/access.log --error-log-path=/var/log/nginx/error.log

make
make modules
make install

ln -s /usr/local/nginx/sbin/nginx /usr/local/sbin/

nginx -V
```

**出力結果の確認:**

```
nginx version: nginx/1.28.0
built by gcc 11.5.0 20240719 (Red Hat 11.5.0-5) (GCC)
built with OpenSSL 3.2.2 4 Jun 2024
TLS SNI support enabled
configure arguments: --user=nginx --group=nginx --with-pcre-jit --with-debug --with-compat --with-http_ssl_module --with-http_realip_module --with-stream --add-dynamic-module=/root/ModSecurity-nginx --http-log-path=/var/log/nginx/access.log --error-log-path=/var/log/nginx/error.log
```

### 6. ModSecurity設定ファイルの配置

```bash
cp ~/modsecurity-v3.0.14/modsecurity.conf-recommended /usr/local/nginx/conf/modsecurity.conf
cp ~/modsecurity-v3.0.14/unicode.mapping /usr/local/nginx/conf/

cp /usr/local/nginx/conf/nginx.conf{,.bak}
```

### 7. nginx.confの設定

```bash
vim /usr/local/nginx/conf/nginx.conf
```

以下のコンフィグで上書きする:

```nginx
load_module modules/ngx_http_modsecurity_module.so;
user  nginx;
worker_processes  1;
pid        /run/nginx.pid;
events {
    worker_connections  1024;
}
http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;
    server {
        listen       80;
        server_name  nginx.example.com;
        modsecurity  on;
        modsecurity_rules_file  /usr/local/nginx/conf/modsecurity.conf;
        access_log  /var/log/nginx/access_example.log;
        error_log  /var/log/nginx/error_example.log;
        location / {
            root   html;
            index  index.html index.htm;
        }
        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }
    }
}
```

### 7-1. streamモジュールの使用（オプション）

nginxのstreamモジュールを使用してTCP/UDPプロキシを行うことができる。

**注意**: ModSecurityはHTTP/HTTPSリクエストに対してのみ動作する。streamモジュールで処理されるTCP/UDPトラフィックにはModSecurityは適用されない。

stream設定の例:

```nginx
stream {
    server {
        listen 3306;
        proxy_pass backend_mysql;
        proxy_timeout 1s;
        proxy_responses 1;
    }
    
    upstream backend_mysql {
        server 192.168.1.10:3306;
    }
}
```

上記の例を`nginx.conf`に追加することで、TCPプロキシとして動作する（例: MySQLへのプロキシ）。

### 8. ModSecurityルールエンジンの有効化

```bash
sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /usr/local/nginx/conf/modsecurity.conf
```

### 9. ModSecurityコアルールセット（OWASP CRS）のインストール

```bash
cd /root/
git clone https://github.com/SpiderLabs/owasp-modsecurity-crs.git /usr/local/nginx/conf/owasp-crs

cp /usr/local/nginx/conf/owasp-crs/crs-setup.conf{.example,}

echo -e "Include owasp-crs/crs-setup.conf\nInclude owasp-crs/rules/*.conf" >> /usr/local/nginx/conf/modsecurity.conf

nginx -t
```

### 9-1. OWASP CRSルールリストの確認

OWASP CRSのルールは以下の場所に配置される:

```bash
# ルールファイルの一覧を確認
ls -la /usr/local/nginx/conf/owasp-crs/rules/

# 特定のルールIDを検索（例: 932160）
grep -r "id:932160" /usr/local/nginx/conf/owasp-crs/rules/

# 特定のカテゴリのルールを確認（例: RCE - Remote Command Execution）
cat /usr/local/nginx/conf/owasp-crs/rules/REQUEST-932-APPLICATION-ATTACK-RCE.conf | grep -E "id:|msg:"

# 全てのルールIDとメッセージを抽出
grep -hE "id:[0-9]+|msg:" /usr/local/nginx/conf/owasp-crs/rules/*.conf | grep -A1 "id:" | less
```

**ルールファイルの主なカテゴリ:**

- `REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf` - 除外ルール（CRSの前）
- `REQUEST-901-INITIALIZATION.conf` - 初期化ルール
- `REQUEST-905-COMMON-EXCEPTIONS.conf` - 共通例外
- `REQUEST-910-IP-REPUTATION.conf` - IPレピュテーション
- `REQUEST-911-METHOD-ENFORCEMENT.conf` - メソッド強制
- `REQUEST-912-DOS-PROTECTION.conf` - DoS保護
- `REQUEST-913-SCANNER-DETECTION.conf` - スキャナー検出
- `REQUEST-920-PROTOCOL-ENFORCEMENT.conf` - プロトコル強制
- `REQUEST-921-PROTOCOL-ATTACK.conf` - プロトコル攻撃
- `REQUEST-930-APPLICATION-ATTACK-LFI.conf` - Local File Inclusion
- `REQUEST-931-APPLICATION-ATTACK-RFI.conf` - Remote File Inclusion
- `REQUEST-932-APPLICATION-ATTACK-RCE.conf` - Remote Command Execution
- `REQUEST-933-APPLICATION-ATTACK-PHP.conf` - PHP攻撃
- `REQUEST-934-APPLICATION-ATTACK-NODEJS.conf` - Node.js攻撃
- `REQUEST-941-APPLICATION-ATTACK-XSS.conf` - Cross-Site Scripting
- `REQUEST-942-APPLICATION-ATTACK-SQLI.conf` - SQL Injection
- `REQUEST-943-APPLICATION-ATTACK-SESSION-FIXATION.conf` - セッション固定
- `REQUEST-944-APPLICATION-ATTACK-JAVA.conf` - Java攻撃
- `REQUEST-949-BLOCKING-EVALUATION.conf` - ブロッキング評価
- `RESPONSE-950-DATA-LEAKAGES.conf` - データ漏洩
- `RESPONSE-951-DATA-LEAKAGES-SQL.conf` - SQLデータ漏洩
- `RESPONSE-952-DATA-LEAKAGES-JAVA.conf` - Javaデータ漏洩
- `RESPONSE-953-DATA-LEAKAGES-PHP.conf` - PHPデータ漏洩
- `RESPONSE-954-DATA-LEAKAGES-IIS.conf` - IISデータ漏洩

**ルールIDの見方:**

ログに表示されるルールID（例: `932160`）は、対応するルールファイル内で定義されている。各ルールには以下の情報が含まれる:

- `id`: ルールID（例: 932160）
- `msg`: ルールの説明メッセージ
- `tag`: 攻撃タイプのタグ
- `severity`: 深刻度（0-9）
- `rev`: リビジョン番号

### 9-2. 特定のルールの除外

特定のルールIDやタグのルールを除外する方法:

#### 方法1: nginx.conf内で除外（推奨）

特定のlocationやserverブロックでルールを除外する場合:

```nginx
server {
    listen 80;
    server_name example.com;
    modsecurity on;
    modsecurity_rules_file /usr/local/nginx/conf/modsecurity.conf;
    
    location /api {
        # このlocationのみ特定のルールを除外
        modsecurity_rules '
          SecRuleRemoveById 932160
          SecRuleRemoveById 942100
        ';
    }
}
```

#### 方法2: modsecurity.confに除外ルールを追加

全てのリクエストに対して特定のルールを除外する場合:

```bash
vim /usr/local/nginx/conf/modsecurity.conf
```

ファイルの末尾に以下を追加:

```nginx
# 特定のルールIDを除外
SecRuleRemoveById 932160

# 複数のルールIDを除外
SecRuleRemoveById 932160 932161 932162

# タグで除外（例: PHP関連のルールを全て除外）
SecRuleRemoveByTag attack-php

# メッセージパターンで除外
SecRuleRemoveByMsg "Remote Command Execution"
```

**注意**: 特定のパス（URI）での除外は、nginx.confの`location`ブロック内で`modsecurity_rules`を使用する方法（方法1）を推奨する。

#### 方法3: 除外設定ファイルを作成

除外ルールを別ファイルに分離して管理する場合:

```bash
vim /usr/local/nginx/conf/custom-exclusions.conf
```

除外ルールを記述:

```nginx
# カスタム除外ルール
SecRuleRemoveById 932160
SecRuleRemoveById 942100

# 特定のパラメータをチェック対象から除外
SecRuleUpdateTargetById 942100 "!ARGS:legacy_param"
```

`modsecurity.conf`でインクルード:

```bash
echo "Include custom-exclusions.conf" >> /usr/local/nginx/conf/modsecurity.conf
```

**主要な除外ディレクティブ:**

- `SecRuleRemoveById <id>` - ルールIDで除外
- `SecRuleRemoveByTag <tag>` - タグで除外
- `SecRuleRemoveByMsg <pattern>` - メッセージパターンで除外
- `SecRuleUpdateTargetById <id> <targets>` - ルールIDのターゲットを変更
- `SecRuleRemoveByTx <variable>` - トランザクション変数で除外

**注意事項:**

- ルールを除外する前に、なぜそのルールが発火したのかを確認する必要がある
- 除外は必要最小限に留め、セキュリティリスクを評価する必要がある
- 除外設定の変更後は`nginx -t`で設定を確認し、nginxをリロードする必要がある

### 10. systemdサービスの設定

```bash
vim /etc/systemd/system/nginx.service
```

以下の内容を設定:

```ini
[Unit]
Description=A high performance web server and a reverse proxy server
Documentation=man:nginx(8)
After=network.target nss-lookup.target

[Service]
Type=forking
PIDFile=/run/nginx.pid
ExecStartPre=/usr/local/nginx/sbin/nginx -t -q -g 'daemon on; master_process on;'
ExecStart=/usr/local/nginx/sbin/nginx -g 'daemon on; master_process on;'
ExecReload=/usr/local/nginx/sbin/nginx -g 'daemon on; master_process on;' -s reload
ExecStop=-/sbin/start-stop-daemon --quiet --stop --retry QUIT/5 --pidfile /run/nginx.pid
TimeoutStopSec=5
KillMode=mixed

[Install]
WantedBy=multi-user.target
```

```bash
systemctl daemon-reload

systemctl start nginx
systemctl enable nginx
```

### 11. サービス状態の確認

```bash
systemctl status nginx
```

**出力例:**

``` bash
● nginx.service - A high performance web server and a reverse proxy server
     Loaded: loaded (/etc/systemd/system/nginx.service; enabled; preset: disabled)
     Active: active (running) since Sat 2025-11-15 08:23:55 UTC; 6s ago
       Docs: man:nginx(8)
   Main PID: 97164 (nginx)
      Tasks: 2 (limit: 24432)
     Memory: 19.6M
        CPU: 193ms
     CGroup: /system.slice/nginx.service
             ├─97164 "nginx: master process /usr/local/nginx/sbin/nginx -g daemon on; master_process on;"
             └─97165 "nginx: worker process"

Nov 15 08:23:54 almalinux9-nginx-mod-security systemd[1]: Starting A high performance web server and a reverse proxy server...
Nov 15 08:23:55 almalinux9-nginx-mod-security systemd[1]: Started A high performance web server and a reverse proxy server.
```

### 12. 動作確認

コマンドインジェクション攻撃のテスト:

```bash
curl localhost?doc=/bin/ls
```

**レスポンス:**

```
<html>
<head><title>403 Forbidden</title></head>
<body>
<center><h1>403 Forbidden</h1></center>
<hr><center>nginx/1.28.0</center>
</body>
</html>
```

ModSecurityの監査ログを確認:

```bash
tail /var/log/modsec_audit.log
```

**ログ出力例:**

```
---qZZXOeQw---H--
ModSecurity: Warning. Matched "Operator `PmFromFile' with parameter `unix-shell.data' against variable `ARGS:doc' (Value: `/bin/ls' ) [file "/usr/local/nginx/conf/owasp-crs/rules/REQUEST-932-APPLICATION-ATTACK-RCE.conf"] [line "496"] [id "932160"] [rev ""] [msg "Remote Command Execution: Unix Shell Code Found"] [data "Matched Data: bin/ls found within ARGS:doc: /bin/ls"] [severity "2"] [ver "OWASP_CRS/3.2.0"] [maturity "0"] [accuracy "0"] [tag "application-multi"] [tag "language-shell"] [tag "platform-unix"] [tag "attack-rce"] [tag "paranoia-level/1"] [tag "OWASP_CRS"] [tag "OWASP_CRS/WEB_ATTACK/COMMAND_INJECTION"] [tag "WASCTC/WASC-31"] [tag "OWASP_TOP_10/A1"] [tag "PCI/6.5.2"] [hostname "localhost"] [uri "/"] [unique_id "176225081053.834961"] [ref "o1,6v10,7t:urlDecodeUni,t:cmdLine,t:normalizePath,t:lowercase"]
ModSecurity: Access denied with code 403 (phase 2). Matched "Operator `Ge' with parameter `5' against variable `TX:ANOMALY_SCORE' (Value: `5' ) [file "/usr/local/nginx/conf/owasp-crs/rules/REQUEST-949-BLOCKING-EVALUATION.conf"] [line "80"] [id "949110"] [rev ""] [msg "Inbound Anomaly Score Exceeded (Total Score: 5)"] [data ""] [severity "2"] [ver "OWASP_CRS/3.2.0"] [maturity "0"] [accuracy "0"] [tag "application-multi"] [tag "language-multi"] [tag "platform-multi"] [tag "attack-generic"] [hostname "localhost"] [uri "/"] [unique_id "176225081053.834961"] [ref ""]

---qZZXOeQw---I--

---qZZXOeQw---J--

---qZZXOeQw---Z--
```

## 参考リンク

- https://linux-jp.org/?p=12951
- [OWASP ModSecurity Core Rule Set (CRS)](https://github.com/coreruleset/coreruleset) - OWASP CRS公式リポジトリ
- [OWASP CRS Documentation](https://coreruleset.org/) - OWASP CRS公式ドキュメント
# nginx-mod-security-sample--almalinux
