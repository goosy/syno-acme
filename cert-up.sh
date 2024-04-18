#!/bin/bash

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

SYNCTHING_PATH=/volume1/@appdata/syncthing
# Before DSM 7.0, use the following instead:
#SYNCTHING_PATH=/var/packages/syncthing/target/var
SYNCTHING_USER=sc-syncthing
SYNCTHING_GROUP=synocommunity

if [ ! -d ${ACME_BIN_PATH} ]; then
  mkdir ${ACME_BIN_PATH}
fi
if [ ! -d ${ACME_CRT_PATH} ]; then
  mkdir ${ACME_CRT_PATH}
fi

set_config() {
  if [ -n "$config_dir" ]; then
    echo "export ACME_CONF_PATH=${BASE_ROOT}/${config_dir}" > "${BASE_CONF}"
  fi
  if [ -f ${BASE_CONF} ]; then
    . ${BASE_CONF}
    CONFIG_FILE=${ACME_CONF_PATH}/config
    if [ -f ${CONFIG_FILE} ]; then
      . ${CONFIG_FILE}
      has_config=true
    elif [ $command != "config" ]; then
      echo "The config file is not initialized, please run \`cert-up.sh config\` first"
      echo "The above operation only needs to be run once"
      echo "and the program will remember the configuration."
      exit 10
    fi
  else
      echo "There are no saved config."
      echo "Please provide \`-c|--config config_dir\` to set new config."
      echo "The above operation only needs to be run once"
      echo "and the program will remember the configuration."
      exit 10
  fi
}

edit_config() {
  if [ ! -f ${CONFIG_FILE} ]; then
    mkdir -p ${ACME_CONF_PATH}
    cp ${BASE_ROOT}/config.template ${CONFIG_FILE}
  fi
  vim ${CONFIG_FILE}
  echo "please check ${CONFIG_FILE} file, if correct, run \`cert-up.sh setup\` again to complete setup."
}

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
    echo 'download failed'
    exit 1
  fi
  SRC_NAME=$(tar -tzf ${SRC_TAR_NAME} | head -1 | cut -f1 -d"/")
  tar zxvf ${SRC_TAR_NAME}
  if [ ! -d ${TEMP_PATH}/${SRC_NAME} ]; then
    echo 'the file downloaded incorrectly'
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
  emailpara="--accountemail \"${EMAIL}\""
  cd ${SRC_NAME}
  ./acme.sh --install --nocron ${emailpara} \
    --home ${ACME_BIN_PATH} \
    --config-home ${ACME_CONF_PATH} \
    --cert-home ${ACME_CRT_PATH}
  echo 'done install_acme'
  rm -rf ${TEMP_PATH}/{${SRC_NAME},${SRC_TAR_NAME}}
  echo "It is recommended to add \`. ${ACME_BIN_PATH}/acme.sh.env\` to the .bashrc file"
  return 0
}

register_account() {
  echo 'begin register email'
  cd ${ACME_BIN_PATH}
  ./acme.sh --config-home ${ACME_CONF_PATH} --register-account -m "${EMAIL}"
  if [ $? -ne 0 ]; then
    echo 'register_account failed!!'
    return 1
  fi
  echo 'done register_account'
  return 0
}

generate_cert() {
  echo 'begin generate_cert'
  echo 'begin updating default cert by acme.sh tool'
  cd ${ACME_BIN_PATH}
  ./acme.sh --force --log --issue \
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

update_service() {
  echo 'begin update_service'

  CRT_PATH_NAME=$(sudo cat ${ARCHIEV_PATH}/DEFAULT)
  CRT_PATH=${ARCHIEV_PATH}/${CRT_PATH_NAME}
  services=()
  info=$(sudo cat "$INFO_FILE_PATH")
  if [ -z "$info" ]; then
    echo "Failed to read file: $INFO_FILE_PATH"
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
      display_name=$(echo "$service" | base64 --decode | jq -r '.display_name')
      isPkg=$(echo "$service" | base64 --decode | jq -r '.isPkg')
      subscriber=$(echo "$service" | base64 --decode | jq -r '.subscriber')
      service_name=$(echo "$service" | base64 --decode | jq -r '.service')

      echo "Copy cert for $display_name"
      if [[ $isPkg == true ]]; then
        CP_TO_DIR="${PKG_CRT_BASE_PATH}/${subscriber}/${service_name}"
      else
        CP_TO_DIR="${CRT_BASE_PATH}/${subscriber}/${service_name}"
      fi
      for f in "${CERT_FILES[@]}"; do
        src="$CRT_PATH/$f"
        des="$CP_TO_DIR/$f"
        if [[ -e "$des" ]]; then
          sudo rm -fr "$des"
        fi
        sudo cp -v "$src" "$des" || echo "[WRN] copy from $src to $des fail"
      done
    done
    if [ "$SYNCTHING" = true ]; then
      echo 'Copy cert for Syncthing'
      sudo cp -v --preserve=timestamps ${CRT_PATH}/cert.pem ${SYNCTHING_PATH}/https-cert.pem
      sudo cp -v --preserve=timestamps ${CRT_PATH}/privkey.pem ${SYNCTHING_PATH}/https-key.pem
      sudo chmod 664 ${SYNCTHING_PATH}/https-cert.pem
      sudo chmod 600 ${SYNCTHING_PATH}/https-key.pem
      sudo chown ${SYNCTHING_USER}:${SYNCTHING_GROUP} ${SYNCTHING_PATH}/https-cert.pem
      sudo chown ${SYNCTHING_USER}:${SYNCTHING_GROUP} ${SYNCTHING_PATH}/https-key.pem
    fi
    echo 'done update_service'
  else
    echo "no cert files, pls run: $0 generate_cert"
  fi
}

reload_webservice() {
  echo 'begin reload_webservice'

  # Not all Synology NAS webservice are the same.
  # Write code according to your configuration.
  #echo 'reloading new cert...'
  #/usr/syno/etc/rc.sysv/nginx.sh reload
  #echo 'relading Apache 2.2'
  #stop pkg-apache22
  #start pkg-apache22
  #reload pkg-apache22
  #echo 'done reload_webservice'

  if [ "$SYNCTHING" = true ]; then
    curl -k -X POST -H "X-API-Key: ${SYNCTHING_API_KEY}" https://localhost:8384/rest/system/restart
  fi
}

revert_cert() {
  echo 'begin revert_cert'
  BACKUP_PATH=${BASE_ROOT}/backup/$1
  if [ -z $command ]; then
    BACKUP_PATH=$(cat ${BASE_ROOT}/backup/latest)
  fi
  if [ ! -d "${BACKUP_PATH}" ]; then
    echo "[ERR] backup path: ${BACKUP_PATH} not found."
    return 1
  fi
  echo "${BACKUP_PATH}/certificate ${CRT_BASE_PATH}"
  sudo cp -rf ${BACKUP_PATH}/certificate/* ${CRT_BASE_PATH}
  echo "${BACKUP_PATH}/package_cert ${PKG_CRT_BASE_PATH}"
  sudo cp -rf ${BACKUP_PATH}/package_cert/* ${PKG_CRT_BASE_PATH}
  reload_webservice
  echo 'done revert_cert'
}

show_help() {
  echo "Usage: ${this_script} [options] <command>"
  echo "The following commands are available:"
  echo "  config         edit config file"
  echo "  setup          install acme.sh and register account"
  echo "  update         update certificate & service"
  echo ""
  echo "Some more advanced commands:"
  echo "  uptools        update acme.sh"
  echo "  backup_cert    backup certificate"
  echo "  update_cert    update certificate"
  echo "  update_service update service"
  echo "  revert         revert certificate"
  echo ""
  echo "The following options are available:"
  echo "  -c|--config    config directory path"
}

OPTIONS="c:"
LONGOPTS="config:"
this_script="$0"
command=""
config_dir=""
PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [ $? -ne 0 ]; then
  exit 1
fi
eval set -- "$PARSED"
while true; do
  case "$1" in
  -c|--config)
    config_dir="$2"
    shift 2
    ;;
  --)
    shift
    command="$1"
    paras="$@"
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
cd ${ACME_BIN_PATH}
. acme.sh.env

case "$command" in
config)
  echo "------ edit config ------"
  edit_config
  ;;

setup)
  echo "------ setup ------"
  install_acme
  if [ "$has_config" = "true" ]; then
    register_account
  else
    echo "config file not found, pls run: ${this_script} config -c <config_directory>"
  fi
  ;;

uptools)
  echo "------ update script ------"
  install_acme
  ;;

register)
  echo "------ register account ------"
  register_account
  ;;

backup_cert)
  echo "------ backup certificate ------"
  backup_cert
  ;;

update_cert)
  echo "------ update certificate ------"
  # backup_cert
  generate_cert
  ;;

update_service)
  echo "------ update service ------"
  update_service
  reload_webservice
  ;;

update)
  echo '------ update certificate & service ------'
  backup_cert
  generate_cert
  update_service
  reload_webservice
  ;;

revert)
  echo "------ revert ------"
  revert_cert $2{paras}
  ;;

*)
  show_help
  exit 1
  ;;
esac
