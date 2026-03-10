#!/bin/bash

SCRIPT_VERSION="1.0.0"

CERT_FILES=(
  'cert.pem'
  'privkey.pem'
  'fullchain.pem'
)

# path of this script
BASE_ROOT=$(
  cd "$(dirname "$0")"
  pwd
)
# date time
DATE_TIME=$(date +%Y%m%d%H%M%S)
# base crt path
CRT_BASE_PATH=/usr/syno/etc/certificate
PKG_CRT_BASE_PATH=/usr/local/etc/certificate
ACME_BIN_PATH="${BASE_ROOT}/acme.sh"
ACME_CONF_PATH=""
CONFIG_FILE=""
BASE_CONF="${BASE_ROOT}/SYNO-ACME.config"
ACME_CRT_PATH=~/certificates
TEMP_PATH=~/temp
ARCHIEV_PATH="${CRT_BASE_PATH}/_archive"
INFO_FILE_PATH="${ARCHIEV_PATH}/INFO"
DNS_SLEEP=60

if [ ! -d ${ACME_BIN_PATH} ]; then
  mkdir ${ACME_BIN_PATH}
fi
if [ ! -d ${ACME_CRT_PATH} ]; then
  mkdir ${ACME_CRT_PATH}
fi

# List of commands that do not require a configuration file to run.
NO_CONFIG_CMDS="gettools help showversion"

set_config() {
  # For commands that do not depend on a configuration file, return directly.
  for nc in $NO_CONFIG_CMDS; do
    if [ "$command" = "$nc" ]; then
      return 0
    fi
  done

  local need_config
  if [ "$command" = "config" ] || [ "$command" = "setup" ]; then
    need_config=false
    if [ -n "$config_dir" ]; then
      ACME_CONF_PATH="${BASE_ROOT}/${config_dir}"
      mkdir -p "${ACME_CONF_PATH}"
      # save to BASE_CONF.
      echo "export ACME_CONF_PATH=${ACME_CONF_PATH}" > "${BASE_CONF}"
    elif [ "$command" = "config" ]; then
      # config_dir is required for the config command
      echo "[ERR] No config directory specified. Please provide one, e.g.: cert-up.sh config my_config"
      exit 1
    fi
  else
    need_config=true
  fi

  if [ ! -f "$BASE_CONF" ]; then
    echo "[ERR] No saved configuration found."
    echo "      Please run: cert-up.sh setup <config_dir>"
    exit 10
  fi

  [ -n "$ACME_CONF_PATH" ] || . "${BASE_CONF}"
  CONFIG_FILE="${ACME_CONF_PATH}/config"
  if [ -f "${CONFIG_FILE}" ]; then
    has_config=true
    if [ "$need_config" = true ]; then
      . "${CONFIG_FILE}"
    fi
  elif [ "$need_config" = true ]; then
    echo "[ERR] The config file is not initialized, please run \`cert-up.sh setup <config_dir>\`"
    echo "The above operation only needs to be run once"
    echo "and the program will remember the configuration."
    exit 10
  else
    echo "The config file is not initialized"
    require_edit=true
    cp "${BASE_ROOT}/config.template" "${CONFIG_FILE}"
    echo "[INFO] Config file created from template: ${CONFIG_FILE}"
  fi
}

switch_config() {
  # set_config has already handled the configuration switch
  [ "$require_edit" = true ] && edit_config
}

edit_config() {
  # set_config has already handled the variables
  # such as ACME_CONF_PATH and CONFIG_FILE
  # Preferably use the EDITOR environment variable
  # fallback to vi if not set.
  ${EDITOR:-vi} "${CONFIG_FILE}"
  echo "[INFO] Config file edited: ${CONFIG_FILE}"
  [ "$command" != "setup" ] &&
  echo "       If you have filled in the correct information, please run 'cert-up.sh register' to complete the registration."
}

reset_config() {
  echo "begin reset"
  # Remove acme.sh generated account/CA files under the conf-home
  # but keep the config.
  find "${ACME_CONF_PATH}" -mindepth 1 ! -name "config" -exec rm -rf {} + 2>/dev/null || true
  echo "done reset — acme.sh status has been cleared, config file has been preserved."
  echo "Please re-run: cert-up.sh register"
}

install_acme() {
  echo 'begin install_acme'
  mkdir -p ${TEMP_PATH}
  rm -rf ${TEMP_PATH}/acme.sh
  cd ${TEMP_PATH}
  echo 'begin downloading acme.sh tool...'
  LATEST_URL=$(curl -Ls -o /dev/null -w %{url_effective} https://github.com/acmesh-official/acme.sh/releases/latest 2>&1)
  ACME_SH_ADDRESS=${LATEST_URL//releases\/tag\//archive\/}.tar.gz
  SRC_TAR_NAME=acme.sh.tar.gz
  curl -L -o ${SRC_TAR_NAME} ${ACME_SH_ADDRESS}
  if [ ! -f ${TEMP_PATH}/${SRC_TAR_NAME} ]; then
    echo '[ERR] download failed'
    exit 1
  fi
  SRC_NAME=$(tar -tzf ${SRC_TAR_NAME} | head -1 | cut -f1 -d"/")
  tar zxvf ${SRC_TAR_NAME}
  if [ ! -d ${TEMP_PATH}/${SRC_NAME} ]; then
    echo '[ERR] the file downloaded incorrectly'
    exit 1
  fi
  # OR git master
  #git clone https://github.com/acmesh-official/acme.sh.git
  #if [ $? -ne 0 ]; then
  #  echo "download failed"
  #  exit 1;
  #fi
  #SRC_NAME=acme.sh
  echo 'begin installing acme.sh tool...'
  cd ${SRC_NAME}
  ./acme.sh --install --nocron \
    --home ${ACME_BIN_PATH} \
    --cert-home ${ACME_CRT_PATH}
  echo 'done install_acme'
  rm -rf ${TEMP_PATH}/${SRC_NAME} ${TEMP_PATH}/${SRC_TAR_NAME}
  echo "It is recommended to add \`. ${ACME_BIN_PATH}/acme.sh.env\` to the .bashrc file"
  return 0
}

register_account() {
  echo 'begin register_account'
  cd ${ACME_BIN_PATH}
  ./acme.sh --config-home ${ACME_CONF_PATH} --server "${SERVER}" --register-account -m "${EMAIL}"
  if [ $? -ne 0 ]; then
    echo '[ERR] register_account failed!!'
    return 1
  fi
  echo 'done register_account'
  return 0
}

# ──────────────────────────────────────────────
# Certificate operations
# ──────────────────────────────────────────────

backup_cert() {
  echo 'begin backup_cert'
  BACKUP_PATH=~/cert_backup/${DATE_TIME}
  mkdir -p ${BACKUP_PATH}
  sudo cp -r ${CRT_BASE_PATH} ${BACKUP_PATH}
  sudo cp -r ${PKG_CRT_BASE_PATH} ${BACKUP_PATH}/package_cert
  echo ${BACKUP_PATH} >~/cert_backup/latest
  echo 'done backup_cert'
  return 0
}

generate_cert() {
  echo 'begin generate_cert'
  echo 'begin updating default cert by acme.sh tool'
  cd ${ACME_BIN_PATH}
  ./acme.sh --force --log --issue \
    --server "${SERVER}" \
    --dnssleep ${DNS_SLEEP} \
    --config-home ${ACME_CONF_PATH} \
    --cert-home ${ACME_CRT_PATH} \
    --dns ${DNS} \
    -d "${DOMAIN}" -d "*.${DOMAIN}"
  #  --cert-file ${ACME_CRT_PATH}/cert.pem \
  #  --key-file ${ACME_CRT_PATH}/privkey.pem \
  #  --ca-file ${ACME_CRT_PATH}/chain.pem \
  #  --fullchain-file ${ACME_CRT_PATH}/fullchain.pem
  if [ $? -eq 0 ] && [ -s ${ACME_CRT_PATH}/${DOMAIN}_ecc/ca.cer ]; then
    echo 'done generate_cert'
    return 0
  else
    echo '[ERR] fail to generate_cert'
    exit 1
  fi
}

apply_cert() {
  echo 'begin apply_cert'

  local CRT_PATH_NAME=$(sudo cat ${ARCHIEV_PATH}/DEFAULT)
  CRT_PATH=${ARCHIEV_PATH}/${CRT_PATH_NAME}
  local services=()
  local info=$(sudo cat "$INFO_FILE_PATH")
  if [ -z "$info" ]; then
    echo "[ERR] Failed to read file: $INFO_FILE_PATH"
    exit 1
  else
    services=($(echo "$info" | jq -r ".$CRT_PATH_NAME.services[] | @base64"))
  fi
  if [[ ${#services[@]} -eq 0 ]]; then
    echo "[ERR] load INFO file - $INFO_FILE_PATH fail"
    exit 1
  fi

  if [ -e ${ACME_CRT_PATH}/${DOMAIN}_ecc/ca.cer ] && [ -s ${ACME_CRT_PATH}/${DOMAIN}_ecc/ca.cer ]; then
    sudo cp -v ${ACME_CRT_PATH}/${DOMAIN}_ecc/ca.cer ${CRT_PATH}/chain.pem
    sudo cp -v ${ACME_CRT_PATH}/${DOMAIN}_ecc/fullchain.cer ${CRT_PATH}/fullchain.pem
    sudo cp -v ${ACME_CRT_PATH}/${DOMAIN}_ecc/${DOMAIN}.cer ${CRT_PATH}/cert.pem
    sudo cp -v ${ACME_CRT_PATH}/${DOMAIN}_ecc/${DOMAIN}.key ${CRT_PATH}/privkey.pem
    for service in "${services[@]}"; do
      local display_name=$(echo "$service" | base64 --decode | jq -r '.display_name')
      local isPkg=$(echo "$service" | base64 --decode | jq -r '.isPkg')
      local subscriber=$(echo "$service" | base64 --decode | jq -r '.subscriber')
      local service_name=$(echo "$service" | base64 --decode | jq -r '.service')

      echo "Copy cert for $display_name"
      local CP_TO_DIR
      if [[ $isPkg == true ]]; then
        CP_TO_DIR="${PKG_CRT_BASE_PATH}/${subscriber}/${service_name}"
      else
        CP_TO_DIR="${CRT_BASE_PATH}/${subscriber}/${service_name}"
      fi
      for f in "${CERT_FILES[@]}"; do
        local src="$CRT_PATH/$f"
        local des="$CP_TO_DIR/$f"
        if [[ -e "$des" ]]; then
          sudo rm -fr "$des"
        fi
        sudo cp -v "$src" "$des" || echo "[WRN] copy from $src to $des fail"
      done
    done
    echo 'done apply_cert'
  else
    echo "[ERR] no cert files, pls run: $0 update_cert"
  fi
}

reload_webservice() {
  echo 'begin reload_webservice'
  # @todo:
  # Not all Synology NAS webservice are the same.
  # Write code according to your configuration.
  #echo 'reloading new cert...'
  #/usr/syno/etc/rc.sysv/nginx.sh reload
  #echo 'relading Apache 2.2'
  #stop pkg-apache22
  #start pkg-apache22
  #reload pkg-apache22
  #echo 'done reload_webservice'
}

revert_cert() {
  echo 'begin revert_cert'
  local target="$1"
  local BACKUP_PATH
  if [ -z "$target" ]; then
    if [ -f ~/cert_backup/latest ]; then
      BACKUP_PATH=$(cat ~/cert_backup/latest)
    else
      echo "[ERR] No backup record file found: ~/cert_backup/latest"
      return 1
    fi
  else
    BACKUP_PATH=~/cert_backup/${target}
  fi
  if [ ! -d "${BACKUP_PATH}" ]; then
    echo "[ERR] backup path: ${BACKUP_PATH} not found."
    return 1
  fi
  echo "restoring from ${BACKUP_PATH} ..."
  sudo cp -rf ${BACKUP_PATH}/certificate/* ${CRT_BASE_PATH}
  sudo cp -rf ${BACKUP_PATH}/package_cert/* ${PKG_CRT_BASE_PATH}
  reload_webservice
  echo 'done revert_cert'
}

# ──────────────────────────────────────────────
# Syncthing
# ──────────────────────────────────────────────

declare -A SYNCTHING_CONFIG_MAP=(
    ["/volume1/@appdata/syncthing/config.xml"]="/volume1/@appdata/syncthing"
    ["/var/packages/syncthing/var/config.xml"]="/var/packages/syncthing/target/var"
    ["$HOME/.config/syncthing/config.xml"]="$HOME/.config/syncthing"
    ["/volume1/docker/syncthing/config.xml"]="/volume1/docker/syncthing"
    ["/volume2/docker/syncthing/config.xml"]="/volume2/docker/syncthing"
    ["/volume3/docker/syncthing/config.xml"]="/volume3/docker/syncthing"
)

extract_syncthing_config_vars() {
    local config_file="$1"
    SYNCTHING_USER=$(sudo stat -c '%U' "$config_file")
    SYNCTHING_GROUP=$(sudo stat -c '%G' "$config_file")
    SYNCTHING_API_KEY=$(sudo grep -o '<apikey>[^<]*</apikey>' "$config_file" \
        | sed 's/<[^>]*>//g')
}

find_syncthing_config() {
    local config_file=""

    for path in "${!SYNCTHING_CONFIG_MAP[@]}"; do
        if sudo test -f "$path"; then
            config_file="$path"
            break
        fi
    done

    if [[ -z "$config_file" ]]; then
        echo "[INFO] searching for Syncthing config.xml..." >&2
        config_file=$(sudo find / -name "config.xml" 2>/dev/null \
            | xargs sudo grep -l "<apikey>" 2>/dev/null \
            | head -n 1)
        if [[ -n "$config_file" ]]; then
            SYNCTHING_DIR=$(dirname "$config_file")
        fi
    else
        SYNCTHING_DIR=${SYNCTHING_CONFIG_MAP[$config_file]}
    fi

    if [[ -z "$config_file" ]]; then
        echo "[WRN] Syncthing config.xml not found" >&2
        return 1
    fi

    extract_syncthing_config_vars "$config_file"
    return 0
}

apply_syncthing_cert() {
  [ "$SYNCTHING" = true ] || return 0
  echo 'begin apply_syncthing_cert'

  # First call, set all variables
  if [[ -z "$SYNCTHING_DIR" ]]; then
    find_syncthing_config || {
      echo "[ERR] cannot locate Syncthing config, skipping"
      return 1
    }
  else
    # User has set SYNCTHING_DIR, verify if the directory exists
    if ! sudo test -d "$SYNCTHING_DIR"; then
      echo "[ERR] SYNCTHING_DIR: $SYNCTHING_DIR not found, skipping"
      return 1
    fi
    local config_file="$SYNCTHING_DIR/config.xml"
    if sudo test -f "$config_file"; then
      extract_syncthing_config_vars "$config_file"
    else
      echo "[ERR] config.xml not found in $SYNCTHING_DIR, cannot determine USER/GROUP"
      return 1
    fi
  fi

  echo "Copy cert for Syncthing (path: ${SYNCTHING_DIR})"
  sudo cp -v ${ACME_CRT_PATH}/${DOMAIN}_ecc/${DOMAIN}.cer ${SYNCTHING_DIR}/https-cert.pem
  sudo cp -v ${ACME_CRT_PATH}/${DOMAIN}_ecc/${DOMAIN}.key ${SYNCTHING_DIR}/https-key.pem
  sudo chmod 664 ${SYNCTHING_DIR}/https-cert.pem
  sudo chmod 600 ${SYNCTHING_DIR}/https-key.pem
  sudo chown ${SYNCTHING_USER}:${SYNCTHING_GROUP} ${SYNCTHING_DIR}/https-cert.pem
  sudo chown ${SYNCTHING_USER}:${SYNCTHING_GROUP} ${SYNCTHING_DIR}/https-key.pem

  if [[ -n "${SYNCTHING_API_KEY}" ]]; then
    curl -k -X POST -H "X-API-Key: ${SYNCTHING_API_KEY}" https://localhost:8384/rest/system/restart
  else
    echo "[WRN] SYNCTHING_API_KEY not found, skipping restart"
  fi

  echo 'done apply_syncthing_cert'
}

# ──────────────────────────────────────────────
# Jellyfin
# ──────────────────────────────────────────────

JELLYFIN_SEARCH_DIRS=(
  "/volume1/@appdata/jellyfin"
  "/volume1/docker/jellyfin"
  "/volume2/docker/jellyfin"
  "/volume3/docker/jellyfin"
)

extract_jellyfin_config_vars() {
  local network_xml="$1"
  local jellyfin_config_dir=$(dirname "$network_xml")
  local jellyfin_dir=$(dirname "$jellyfin_config_dir")
  if
    [[ "$(basename "$jellyfin_config_dir")" == "config" ]] &&
    [[ "$(basename "$jellyfin_dir")" == "config" ]]
  then
    jellyfin_dir=$(dirname "$jellyfin_dir")
  fi

  JELLYFIN_CERT_USER=$(sudo stat -c '%U' "$jellyfin_dir")
  JELLYFIN_CERT_GROUP=$(sudo stat -c '%G' "$jellyfin_dir")
  # Read the certificate path and password from network.xml
  if sudo test -f "$network_xml"; then
    JELLYFIN_CERT_PATH=$(sudo grep -o '<CertificatePath>[^<]*</CertificatePath>' "$network_xml" \
      | sed 's/<[^>]*>//g')
    JELLYFIN_CERT_PASSWORD=$(sudo grep -o '<CertificatePassword>[^<]*</CertificatePassword>' "$network_xml" \
      | sed 's/<[^>]*>//g')
  fi

  # If the certificate path is not specified in the configuration, use the default value
  if [[ -z "$JELLYFIN_CERT_PATH" ]]; then
    JELLYFIN_CERT_PATH="${jellyfin_dir}/certificate.p12"
    echo "[INFO] CertificatePath not set in network.xml, will use default: $JELLYFIN_CERT_PATH"
  fi

  # Determine the restart method: synopkg or Docker
  JELLYFIN_RESTART_MODE=""
  if synopkg status jellyfin &>/dev/null; then
    JELLYFIN_RESTART_MODE="synopkg"
    JELLYFIN_CONTAINER_NAME=""
  else
    # Try to find the running jellyfin container
    local container
    container=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i jellyfin | head -n 1)
    if [[ -n "$container" ]]; then
      JELLYFIN_RESTART_MODE="docker"
      JELLYFIN_CONTAINER_NAME="$container"
    fi
  fi
}

find_jellyfin_config() {
  # User specified JELLYFIN_DIR through configuration file
  if [ -n "$JELLYFIN_DIR" ] && ! sudo test -d "$JELLYFIN_DIR"; then
    echo "[ERR] JELLYFIN_DIR: $JELLYFIN_DIR not found, skipping"
    return 1
  fi
  # If JELLYFIN_DIR is set, use it first and try to find network.xml in two config sub-paths.
  for path in ${JELLYFIN_DIR:+"$JELLYFIN_DIR"} "${JELLYFIN_SEARCH_DIRS[@]}"; do
    for subpath in "config/network.xml" "config/config/network.xml"; do
      if sudo test -f "$path/$subpath"; then
        extract_jellyfin_config_vars "$path/$subpath"
        return 0
      fi
    done
  done

  echo "[INFO] searching for Jellyfin network.xml..." >&2
  local network_xml=$(sudo find / -name "network.xml" 2>/dev/null \
      | xargs sudo grep -l "<CertificatePath>\|<RequireHttps>" 2>/dev/null \
      | head -n 1)

  if [[ -z "$network_xml" ]]; then
    echo "[WRN] Jellyfin network.xml not found" >&2
    return 1
  fi

  extract_jellyfin_config_vars "$network_xml"
  return 0
}

apply_jellyfin_cert() {
  [ "$JELLYFIN" = true ] || return 0
  echo 'begin apply_jellyfin_cert'

  find_jellyfin_config || {
    echo "[ERR] cannot locate Jellyfin config, skipping"
    return 1
  }

  local src_cert="${ACME_CRT_PATH}/${DOMAIN}_ecc/${DOMAIN}.cer"
  local src_key="${ACME_CRT_PATH}/${DOMAIN}_ecc/${DOMAIN}.key"

  if ! sudo test -f "$src_cert" || ! sudo test -f "$src_key"; then
    echo "[ERR] Source cert/key not found, run generate_cert first"
    return 1
  fi

  local pfx_password="${JELLYFIN_CERT_PASSWORD:-}"
  local tmp_pfx
  tmp_pfx=$(mktemp /tmp/jellyfin_cert_XXXXXX.p12)

  echo "Converting PEM to PKCS#12 for Jellyfin (path: ${JELLYFIN_CERT_PATH})"
  if ! openssl pkcs12 -export \
    -inkey "$src_key" \
    -in "$src_cert" \
    -certfile "${ACME_CRT_PATH}/${DOMAIN}_ecc/fullchain.cer" \
    -out "$tmp_pfx" \
    -passout "pass:${pfx_password}"
  then
    echo "[ERR] openssl pkcs12 conversion failed"
    rm -f "$tmp_pfx"
    return 1
  fi

  sudo mv "$tmp_pfx" "$JELLYFIN_CERT_PATH"
  sudo chmod 640 "$JELLYFIN_CERT_PATH"
  sudo chown "${JELLYFIN_CERT_USER}:${JELLYFIN_CERT_GROUP}" "$JELLYFIN_CERT_PATH"

  case "$JELLYFIN_RESTART_MODE" in
    synopkg)
      echo "Restarting Jellyfin via synopkg..."
      sudo synopkg restart jellyfin
      ;;
    docker)
      echo "Restarting Jellyfin container: ${JELLYFIN_CONTAINER_NAME}..."
      docker restart "$JELLYFIN_CONTAINER_NAME"
      ;;
    *)
      echo "[WRN] Cannot determine Jellyfin restart method; please restart manually"
      ;;
  esac

  echo 'done apply_jellyfin_cert'
}

# ──────────────────────────────────────────────
# Version
# ──────────────────────────────────────────────

showversion() {
  echo "cert-up.sh version ${SCRIPT_VERSION}"
  if [ -f "${ACME_BIN_PATH}/acme.sh" ]; then
    echo "acme.sh version $("${ACME_BIN_PATH}/acme.sh" --version 2>&1 | head -1)"
  else
    echo "acme.sh: not installed"
  fi
}

# ──────────────────────────────────────────────
# Help
# ──────────────────────────────────────────────

show_help() {
  echo "Usage: ${this_script} [options] <command> [config_name]"
  echo ""
  echo "The following commands are mainly used"
  echo "  gettools              install or update acme.sh tool"
  echo "  setup [config_name] [-e|--edit]"
  echo "                        Create or switch configuration, edit and register account immediately"
  echo "  update                Update certificate and restart all related services (full process)"
  echo "  update_service        Apply certificate and restart service"
  echo "                        suitable for scenarios where certificate has been updated by remote machine"
  echo "  help                  Show help information"
  echo ""
  echo "Fine-grained commands:"
  echo "  config <config_name>  Create or switch configuration directory"
  echo "  edit                  Edit current configuration file"
  echo "  register              Register ACME account"
  echo "  reset                 Reset ACME account status (preserve config file)"
  echo "  backup_cert           Backup current NAS certificate"
  echo "  update_cert           Apply for/update certificate (equivalent to generate_cert)"
  echo "  apply_cert            Apply certificate to NAS system"
  echo "  reload                Reload Web service to make certificate effective"
  echo "  syncthing             Update Syncthing certificate and restart"
  echo "  jellyfin              Update Jellyfin certificate and restart"
  echo "  revert [datetime]     Revert certificate to specified backup (default latest backup)"
  echo ""
  echo "Options:"
  echo "  -e, --edit            Force open editor when setting up"
  echo "  -V, --version         Show version information"
  echo ""
}

# ──────────────────────────────────────────────
# Parse command line arguments
# ──────────────────────────────────────────────

OPTIONS="eV"
LONGOPTS="edit,version"
this_script="$0"
command=""
config_dir=""
require_edit=false

PARSEDPARA=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [ $? -ne 0 ]; then
  show_help
  exit 1
fi
eval set -- "$PARSEDPARA"
while true; do
  case "$1" in
  -e|--edit)
    require_edit=true
    shift
    ;;
  -V|--version)
    command="showversion"
    break
    ;;
  --)
    shift
    command="${1:-help}"
    config_dir="${2:-}"
    break
    ;;
  *)
    echo "Internal error!"
    exit 1
    ;;
  esac
done

has_config=false
set_config

ACME_ENV="${ACME_BIN_PATH}/acme.sh.env"
if [ -f "${ACME_ENV}" ]; then
  . "${ACME_ENV}"
fi

# ──────────────────────────────────────────────
# Command dispatch
# ──────────────────────────────────────────────

case "$command" in

showversion)
  showversion
  ;;

gettools)
  echo "------ install/update acme.sh ------"
  install_acme
  ;;

config)
  echo "------ switch/create config ------"
  switch_config
  ;;

edit)
  echo "------ edit config ------"
  edit_config
  ;;

setup)
  # setup = config + (edit if needed) + register
  echo "------ setup ------"
  switch_config
  if [ -f "${CONFIG_FILE}" ]; then
    . "${CONFIG_FILE}"
    has_config=true
  fi
  if [ "$has_config" = true ]; then
    register_account
  else
    echo "[ERR] config file not found, pls run: ${this_script} config <config_dir>"
    exit 1
  fi
  ;;

register)
  echo "------ register account ------"
  register_account
  ;;

reset)
  echo "------ reset acme config ------"
  reset_config
  ;;

backup_cert)
  echo "------ backup certificate ------"
  backup_cert
  ;;

update_cert)
  echo "------ update certificate ------"
  generate_cert
  ;;

apply_cert)
  echo "------ apply certificate ------"
  apply_cert
  ;;

reload)
  echo "------ reload webservice ------"
  reload_webservice
  ;;

syncthing)
  echo "------ apply syncthing certificate ------"
  apply_syncthing_cert
  ;;

jellyfin)
  echo "------ apply jellyfin certificate ------"
  apply_jellyfin_cert
  ;;

update)
  echo '------ update certificate & service ------'
  backup_cert
  generate_cert
  apply_cert
  reload_webservice
  apply_syncthing_cert
  apply_jellyfin_cert
  ;;

update_service)
  echo '------ update service only ------'
  apply_cert
  reload_webservice
  apply_syncthing_cert
  apply_jellyfin_cert
  ;;

revert)
  echo "------ revert ------"
  revert_cert "${config_dir}"   # config_dir here is reused as an optional backup timestamp parameter
  ;;

help|--help|-h)
  show_help
  ;;

*)
  echo "[ERR] Unknown command: $command"
  show_help
  exit 1
  ;;
esac
