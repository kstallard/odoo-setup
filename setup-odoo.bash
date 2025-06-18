#! /bin/bash

if ! [ $(id -u) = 0 ]; then
   echo "The script need to be run as root." >&2
   exit 1
fi

if [ $SUDO_USER ]; then
    real_user=$SUDO_USER
else
    real_user=$(whoami)
fi

script_path=$(dirname $(realpath "$0"))
echo "Script path: $script_path"

# ref: https://askubuntu.com/a/30157/8698
if [ -z $ODOO_HOSTNAME ]; then
    ODOO_HOSTNAME=odoo-staging.mycompany.com
fi

hostnamectl set-hostname $ODOO_HOSTNAME
HOSTNAME=$(hostname)

echo "Hostname $HOSTNAME"

if [ ! -d ".ssh" ]; then
   echo "Creating public/private key pair for odoo-enterprise access...."
   sudo -u $real_user mkdir .ssh
   chmod 700 .ssh
   sudo -u $real_user ssh-keygen -q -f .ssh/odoo_enterprise -t ed25519 -v -N ""
fi

cat .ssh/odoo_enterprise.pub
echo "Copy this public key to your Github account and then press Enter"
read
echo "Continuing..."

mount /dev/cdrom /mnt
/mnt/Linux/install.sh -d centos -m9 -n

sudo -u $real_user  wget https://dl.fedoraproject.org/pub/epel/9/Everything/x86_64/Packages/r/ripgrep-14.1.1-1.el9.x86_64.rpm
rpm -Uvh ripgrep-14.1.1-1.el9.x86_64.rpm

dnf install -y wget yum-utils make gcc openssl-devel bzip2-devel libffi-devel zlib-devel readline-devel libuuid-devel sqlite-devel.x86_64 tk-devel
dnf --enablerepo=crb install -y gdbm-devel

sudo -u $real_user wget https://www.python.org/ftp/python/3.10.16/Python-3.10.16.tgz 
sudo -u $real_user tar xzf Python-3.10.16.tgz 

cd Python-3.10.16

sudo -u $real_user ./configure --with-system-ffi --with-computed-gotos --enable-loadable-sqlite-extensions
sudo -u $real_user make -j 4

make altinstall

#No password will be set at this point.
useradd -m -U -r -d /opt/odoo -s /bin/bash odoo

dnf install -y postgresql-server libpq-devel

dnf install -y python-devel openldap-devel openldap-compat
ln -s /usr/lib64/libldap_r-2.4.so.2 /usr/lib64/libldap_r.so

pvcreate /dev/xvdb
vgcreate vg-odoo-data /dev/xvdb
lvcreate -L 499.99GB -n lv-odoo-data vg-odoo-data
mkfs.xfs /dev/vg-odoo-data/lv-odoo-data

# label the volume
xfs_admin -L odoo-data /dev/vg-odoo-data/lv-odoo-data

fs_uuid=$(blkid -s UUID -o value /dev/vg-odoo-data/lv-odoo-data)

printf "UUID=$fs_uuid /odoo-data      xfs    defaults   0 0\n" >> /etc/fstab
mkdir /odoo-data
mount /odoo-data

#Create the directories for postgres SQL 
mkdir /odoo-data/postgres
mkdir /odoo-data/postgres/backups
mkdir /odoo-data/postgres/data
chown -R postgres /odoo-data/*

#Need to udpate the postgresql.service file so postgresql knows where the data now lives.
cp /usr/lib/systemd/system/postgresql.service /usr/lib/systemd/system/postgresql.service.bak
sed -i.bak 's|^Environment=PGDATA=.*$|Environment=PGDATA=/odoo-data/postgres/data|' /usr/lib/systemd/system/postgresql.service 

sudo -u postgres postgresql-setup --initdb --unit postgresql

#SE Linux is being used so we need to update some metadata to allow 
#the postgresql service access to these files
semanage fcontext -a -s system_u -t var_t "/odoo-data"
restorecon -Rv /odoo-data

semanage fcontext -a -s system_u -t postgresql_db_t "/odoo-data/postgres(/.*)?"
restorecon -Rv /odoo-data/postgres
chcon -u system_u -R /odoo-data/postgres

systemctl enable postgresql
systemctl start postgresql

sudo -u postgres createuser -s odoo

#Requirment for odoo
#TODO: Need to capture these packages and store them indefinently so we don't loose them
dnf -y install https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox-0.12.6.1-2.almalinux9.x86_64.rpm

cd /opt/odoo
sudo -u odoo mkdir .ssh
chmod 700 .ssh

cp /home/$real_user/.ssh/odoo_enterprise /opt/odoo/.ssh/
chown odoo:odoo /opt/odoo/.ssh/*

sudo -u odoo mkdir odoo-server
cd odoo-server
sudo -u odoo python3 -m venv odoo_venv

sudo -u odoo git clone https://github.com/odoo/odoo.git --depth 1 odoo-community
sudo -u odoo git clone -c core.sshCommand="ssh -i ~/.ssh/odoo_enterprise -o StrictHostKeyChecking=no" git@github.com:odoo/enterprise.git --depth 1 odoo-enterprise

echo "Installing Python Odoo dependencies"

su - odoo bash -c "source ~/odoo-server/odoo_venv/bin/activate && pip install setuptools wheel && pip install -r ~/odoo-server/odoo-community/requirements.txt"

pip install rlpycairo
pip3 install pdfminer.six

sudo dnf install -y https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox-0.12.6.1-2.almalinux9.x86_64.rpm

mkdir /var/log/odoo
chown odoo:odoo /var/log/odoo
chmod 777 /var/log/odoo

cat << 'EOF' > /etc/odoo.conf
[options]
; This is the password that allows odoo database operations:
;admin_passwd = <put a password here, it will be necessary when creating or importing a new odoo database>
db_user = odoo
addons_path = /opt/odoo/odoo-server/odoo-enterprise,/opt/odoo/odoo-server/odoo-community/addons
logfile = /var/log/odoo/odoo-server.log
EOF

cat << 'EOF' > /etc/systemd/system/odoo.service
[Unit]
Description=Odoo
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=odoo
PermissionsStartOnly=true
User=odoo
Group=odoo
ExecStart=/opt/odoo/odoo-server/start-odoo.bash 
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

cat << 'EOF' > /opt/odoo/odoo-server/start-odoo.bash
#!/bin/bash

#Should be run as user odoo

source ~/odoo-server/odoo_venv/bin/activate

python3 ~/odoo-server/odoo-community/odoo-bin -c /etc/odoo.conf

deativate
EOF

chown odoo:odoo /opt/odoo/odoo-server/start-odoo.bash
chmod ug+x /opt/odoo/odoo-server/start-odoo.bash

systemctl daemon-reload
systemctl enable --now odoo

dnf install -y nginx
mkdir -p /etc/letsencrypt/live/$HOSTNAME

echo "Script Path: $script_path"
cd $script_path
sudo -u $real_user ./convertPfx.bash

cp $script_path/fullchain.pem /etc/letsencrypt/live/$HOSTNAME
cp $script_path/privkey.pem /etc/letsencrypt/live/$HOSTNAME

# Create group for ssl access
groupadd ssl-cert

#Add nginx user to the group
usermod -aG ssl-cert nginx

#Change group ownership of cert files
chgrp ssl-cert /etc/letsencrypt/live/$HOSTNAME/{fullchain.pem,privkey.pem}

#Set Permissions: owner (root) read/write, group (ssl-cert) read
chmod 640 /etc/letsencrypt/live/$HOSTNAME/{fullchain.pem,privkey.pem}

#Ensure the directory is accessible
chmod 750 /etc/letsencrypt/live/$HOSTNAME
chgrp ssl-cert /etc/letsencrypt/live/$HOSTNAME

#Create the odoo.conf file for nginx
cat << 'EOF' > /etc/nginx/conf.d/odoo.conf
upstream odoo {
 server 127.0.0.1:8069;
}

upstream odoo-chat {
 server 127.0.0.1:8072;
}

server {
    server_name $HOSTNAME;
    return 301 https://$HOSTNAME/$request_uri;
}

server {
   listen 443 ssl http2;
   server_name $HOSTNAME;
   access_log /var/log/nginx/odoo.access.log;
   error_log /var/log/nginx/odoo.error.log;


   ssl_certificate /etc/letsencrypt/live/$HOSTNAME/fullchain.pem;
   ssl_certificate_key /etc/letsencrypt/live/$HOSTNAME/privkey.pem;
   
   proxy_read_timeout 720s;
   proxy_connect_timeout 720s;
   proxy_send_timeout 720s;
   proxy_set_header X-Forwarded-Host $host;
   proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
   proxy_set_header X-Forwarded-Proto $scheme;
   proxy_set_header X-Real-IP $remote_addr;

   client_body_buffer_size 200M;
   client_max_body_size 200M;

  location / {
     proxy_redirect off;
     proxy_pass http://odoo;
   }

   location /longpolling {
       proxy_pass http://odoo-chat;
   }

   location ~* /web/static/ {
       proxy_cache_valid 200 90m;
       proxy_buffering    on;
       expires 864000;
       proxy_pass http://odoo;
  }

  # gzip
  gzip_types text/css text/less text/plain text/xml application/xml application/json application/javascript;
  gzip on;
}
EOF

firewall-cmd --zone=public --add-service=https --permanent
firewall-cmd --reload

setsebool -P httpd_can_network_connect 1
systemctl enable nginx
systemctl restart nginx


