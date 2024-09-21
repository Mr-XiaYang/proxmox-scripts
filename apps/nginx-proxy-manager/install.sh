#!/usr/bin/env bash
echo "v0.0.1";

EPS_BASE_URL=${EPS_BASE_URL:-}
EPS_OS_DISTRO=${EPS_OS_DISTRO:-}
EPS_UTILS_COMMON=${EPS_UTILS_COMMON:-}
EPS_UTILS_DISTRO=${EPS_UTILS_DISTRO:-}
EPS_APP_CONFIG=${EPS_APP_CONFIG:-}
EPS_CLEANUP=${EPS_CLEANUP:-false}
EPS_CT_INSTALL=${EPS_CT_INSTALL:-false}

if [ -z "$EPS_BASE_URL" -o -z "$EPS_OS_DISTRO" -o -z "$EPS_UTILS_COMMON" -o -z "$EPS_UTILS_DISTRO" -o -z "$EPS_APP_CONFIG" ]; then
  printf "Script looded incorrectly!\n\n";
  exit 1;
fi

source <(echo -n "$EPS_UTILS_COMMON")
source <(echo -n "$EPS_UTILS_DISTRO")
source <(echo -n "$EPS_APP_CONFIG")

pms_bootstrap
pms_settraps

if [ $EPS_CT_INSTALL = false ]; then
  pms_header
  pms_check_os
fi

EPS_OS_ARCH=$(os_arch)
EPS_OS_CODENAME=$(os_codename)
EPS_OS_VERSION=${EPS_OS_VERSION:-$(os_version)}

# Check for previous install
if [ -f "$EPS_SERVICE_FILE" ]; then
  step_start "Previous Installation" "Cleaning" "Cleaned"
    svc_stop npm
    svc_stop openresty

    # Remove old installation files
    rm -rf /app \
    /var/www/html \
    /etc/nginx \
    /var/log/nginx \
    /var/lib/nginx \
    /var/cache/nginx \
    /opt/certbot/bin/certbot
fi


step_start "Nginx Proxy Manager" "Downloading" "Downloaded"
  NPM_VERSION=$(os_fetch -O- https://api.github.com/repos/NginxProxyManager/nginx-proxy-manager/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4) }')
  os_fetch -O- https://codeload.github.com/NginxProxyManager/nginx-proxy-manager/tar.gz/v$NPM_VERSION | tar -xz
  cd ./nginx-proxy-manager-$NPM_VERSION
  step_end "Nginx Proxy Manager ${CLR_CYB}v$NPM_VERSION${CLR} ${CLR_GN}Downloaded"

step_start "Enviroment" "Setting up" "Setup"
  # Update NPM version in package.json files
  sed -i "s/\"version\": \"0.0.0\"/\"version\": \"$NPM_VERSION\"/" backend/package.json
  sed -i "s/\"version\": \"0.0.0\"/\"version\": \"$NPM_VERSION\"/" frontend/package.json
  
  # Fix nginx config files for use with openresty defaults
  sed -i 's/user npm/user root/g; s/^pid/#pid/g; s+^daemon+#daemon+g' docker/rootfs/etc/nginx/nginx.conf
  sed -i 's/include-system-site-packages = false/include-system-site-packages = true/g' /opt/certbot/pyvenv.cfg
  _nginxConfigs=$(find ./ -type f -name "*.conf")
  for _nginxConfig in $_nginxConfigs; do
    sed -i 's+include conf.d+include /etc/nginx/conf.d+g' "$_nginxConfig"
  done

  # Copy runtime files
  mkdir -p /var/www/html /etc/nginx/logs
  cp -r docker/rootfs/var/www/html/* /var/www/html/
  cp -r docker/rootfs/etc/nginx/* /etc/nginx/
  cp docker/rootfs/etc/letsencrypt.ini /etc/letsencrypt.ini
  cp docker/rootfs/etc/logrotate.d/nginx-proxy-manager /etc/logrotate.d/nginx-proxy-manager
  ln -sf /etc/nginx/nginx.conf /etc/nginx/conf/nginx.conf
  rm -f /etc/nginx/conf.d/dev.conf

  # Create required folders
  mkdir -p \
	/data/nginx \
	/data/custom_ssl \
	/data/logs \
	/data/access \
	/data/nginx/default_host \
	/data/nginx/default_www \
	/data/nginx/proxy_host \
	/data/nginx/redirection_host \
	/data/nginx/stream \
	/data/nginx/dead_host \
	/data/nginx/temp \
	/data/letsencrypt-acme-challenge \
	/run/nginx \
	/tmp/nginx/body \
	/var/log/nginx \
	/var/lib/nginx/cache/public \
	/var/lib/nginx/cache/private \
	/var/cache/nginx/proxy_temp

  # Set permissions
  touch /var/log/nginx/error.log
  chmod 777 /var/log/nginx/error.log
  chmod -R 777 /var/cache/nginx
  chmod 644 /etc/logrotate.d/nginx-proxy-manager
  chown root /tmp/nginx
  chmod -R 777 /var/cache/nginx

  # Dynamically generate resolvers file, if resolver is IPv6, enclose in `[]`
  echo resolver "$(awk 'BEGIN{ORS=" "} $1=="nameserver" { sub(/%.*$/,"",$2); print ($2 ~ ":")? "["$2"]": $2}' /etc/resolv.conf) valid=10s;" > /etc/nginx/conf.d/include/resolvers.conf

  # Copy app files
  mkdir -p /app/global /app/frontend/images
  cp -r backend/* /app
  cp -r global/* /app/global

step_start "Frontend" "Building" "Built"
  cd ./frontend
  export NODE_ENV=development
  yarn cache clean --silent --force >$__OUTPUT
  yarn install --silent --network-timeout=30000 >$__OUTPUT 
  yarn build >$__OUTPUT 
  cp -r dist/* /app/frontend
  cp -r app-images/* /app/frontend/images

step_start "Backend" "Initializing" "Initialized"
  rm -rf /app/config/default.json &>$__OUTPUT
  if [ ! -f /app/config/production.json ]; then
    _npmConfig="{\n  \"database\": {\n    \"engine\": \"knex-native\",\n    \"knex\": {\n      \"client\": \"sqlite3\",\n      \"connection\": {\n        \"filename\": \"/data/database.sqlite\"\n      }\n    }\n  }\n}"
    printf "$_npmConfig\n" | tee /app/config/production.json >$__OUTPUT
  fi
  cd /app
  export NODE_ENV=development
  yarn install --silent --network-timeout=30000 >$__OUTPUT 

step_start "Services" "Starting" "Started"
  printf "$EPS_SERVICE_DATA\n" | tee $EPS_SERVICE_FILE >$__OUTPUT
  chmod a+x $EPS_SERVICE_FILE

  svc_add openresty
  svc_add npm

step_start "Enviroment" "Cleaning" "Cleaned"
  yarn cache clean --silent --force >$__OUTPUT
  # find /tmp -mindepth 1 -maxdepth 1 -not -name nginx -exec rm -rf '{}' \;
  if [ "$EPS_CLEANUP" = true ]; then
    pkg_del "$EPS_DEPENDENCIES"
  fi
  pkg_clean

step_end "Installation complete"
printf "\nNginx Proxy Manager should be reachable at ${CLR_CYB}http://$(os_ip):81${CLR}\n\n"
