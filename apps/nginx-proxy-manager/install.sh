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
