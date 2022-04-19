#!/bin/bash

#DEPLOY_TOMCAT_KEYSTORE="/etc/tomcat/.keystore"
#DEPLOY_TOMCAT_KEYPASS="mykeypasspasswordstoredinserverxml"
#DEPLOY_TOMCAT_RELOAD="systemctl restart tomcat"
#DEPLOY_KEY_ALIAS="tomcat"

########  Public functions #####################

#domain keyfile certfile cafile fullchain
tomcat_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  _getdeployconf DEPLOY_TOMCAT_KEYSTORE
  _getdeployconf DEPLOY_TOMCAT_KEYPASS
  _getdeployconf DEPLOY_TOMCAT_RELOAD
  _getdeployconf DEPLOY_KEY_ALIAS

  _debug2 DEPLOY_TOMCAT_KEYSTORE "$DEPLOY_TOMCAT_KEYSTORE"
  _debug2 DEPLOY_TOMCAT_KEYPASS "$DEPLOY_TOMCAT_KEYPASS"
  _debug2 DEPLOY_TOMCAT_RELOAD "$DEPLOY_TOMCAT_RELOAD"
  _debug2 DEPLOY_KEY_ALIAS "$DEPLOY_KEY_ALIAS"

  # Space-separated list of environments detected and installed:
  _services_updated=""

  # Default reload commands accumulated as we auto-detect environments:
  _reload_cmd=""
  if [ -z "$DEPLOY_TOMCAT_KEYPASS" ]; then
    _err "Need to set the env variable DEPLOY_TOMCAT_KEYPASS"
    return 1
  fi
  _tomcat_keystore="${DEPLOY_TOMCAT_KEYSTORE:-/etc/tomcat/.keystore}"
  _tomcat_keyalias="${DEPLOY_KEY_ALIAS:-tomcat}"

  if [ -f "$_tomcat_keystore" ]; then
    _info "Installing certificate for Tomcat (Java keystore)"
    _debug _tomcat_keystore "$_tomcat_keystore"
    if ! _exists keytool; then
      _err "keytool not found"
      return 1
    fi
    if [ ! -w "$_tomcat_keystore" ]; then
      _err "The file $_tomcat_keystore is not writable, please change the permission."
      return 1
    fi

    _tomcat_keypass="${DEPLOY_TOMCAT_KEYPASS:-tomcat}"

    _debug "Generate import pkcs12"
    _import_pkcs12="$(_mktemp)"
    _toPkcs "$_import_pkcs12" "$_ckey" "$_ccert" "$_cca" "$_tomcat_keypass" tomcat tomcat
    # shellcheck disable=SC2181
    if [ "$?" != "0" ]; then
      _err "Error generating pkcs12. Please re-run with --debug and report a bug."
      return 1
    fi

    _debug "Import into keystore: $_tomcat_keystore"
    if keytool -importkeystore \
      -deststorepass "$_tomcat_keypass" -destkeypass "$_tomcat_keypass" -destkeystore "$_tomcat_keystore" \
      -srckeystore "$_import_pkcs12" -srcstoretype PKCS12 -srcstorepass "$_tomcat_keypass" \
      -alias $_tomcat_keyalias -noprompt; then
      _debug "Import keystore success!"
      rm "$_import_pkcs12"
    else
      _err "Error importing into Unifi Java keystore."
      _err "Please re-run with --debug and report a bug."
      rm "$_import_pkcs12"
      return 1
    fi

    if systemctl -q is-active tomcat; then
      _reload_cmd="${_reload_cmd:+$_reload_cmd && }systemctl restart tomcat.service"
    fi
    _services_updated="${_services_updated} tomcat"
    _info "Install Tomcat certificate success!"
  elif [ "$DEPLOY_TOMCAT_KEYSTORE" ]; then
    _err "The specified DEPLOY_TOMCAT_KEYSTORE='$DEPLOY_TOMCAT_KEYSTORE' is not valid, please check."
    return 1
  fi

  if [ -z "$_services_updated" ]; then
    # None of the environments were auto-detected, so no deployment has occurred
    # (and none of DEPLOY_TOMCAT_KEYSTORE were set).
    _err "Unable to detect Tomcat environment in standard location."
    _err "(This deploy hook must be run on the Tomcat server, not a remote machine.)"
    _err "For non-standard Tomcat installations, set DEPLOY_TOMCAT_KEYSTORE,"
    _err "DEPLOY_TOMCAT_KEYPASS, and/or DEPLOY_KEY_ALIAS as appropriate."
    return 1
  fi

  _reload_cmd="${DEPLOY_TOMCAT_RELOAD:-$_reload_cmd}"
  if [ -z "$_reload_cmd" ]; then
    _err "Certificates were installed for services:${_services_updated},"
    _err "but none appear to be active. Please set DEPLOY_TOMCAT_RELOAD"
    _err "to a command that will restart the necessary services."
    return 1
  fi
  _info "Reload services (this may take some time): $_reload_cmd"
  if eval "$_reload_cmd"; then
    _info "Reload success!"
  else
    _err "Reload error"
    return 1
  fi

  # Successful, so save all (non-default) config:
  _savedeployconf DEPLOY_TOMCAT_KEYSTORE "$DEPLOY_TOMCAT_KEYSTORE"
  _savedeployconf DEPLOY_TOMCAT_KEYPASS "$DEPLOY_TOMCAT_KEYPASS"
  _savedeployconf DEPLOY_TOMCAT_RELOAD "$DEPLOY_TOMCAT_RELOAD"
  _savedeployconf DEPLOY_KEY_ALIAS "$DEPLOY_KEY_ALIAS"

  return 0
}
