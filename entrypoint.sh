#!/bin/bash
set -euo pipefail

# Setup Catalina Opts
: ${CATALINA_CONNECTOR_PROXYNAME:=}
: ${CATALINA_CONNECTOR_PROXYPORT:=}
: ${CATALINA_CONNECTOR_SCHEME:=http}
: ${CATALINA_CONNECTOR_SECURE:=false}

: ${CATALINA_OPTS:=}

CATALINA_OPTS="${CATALINA_OPTS} -DcatalinaConnectorProxyName=${CATALINA_CONNECTOR_PROXYNAME}"
CATALINA_OPTS="${CATALINA_OPTS} -DcatalinaConnectorProxyPort=${CATALINA_CONNECTOR_PROXYPORT}"
CATALINA_OPTS="${CATALINA_OPTS} -DcatalinaConnectorScheme=${CATALINA_CONNECTOR_SCHEME}"
CATALINA_OPTS="${CATALINA_OPTS} -DcatalinaConnectorSecure=${CATALINA_CONNECTOR_SECURE}"

export CATALINA_OPTS
#added new functions
function setConfluenceConfigurationProperty() {
  local configurationProperty=$1
  local configurationValue=$2
  if [ -n "${configurationProperty}" ]; then
    local propertyCount=$(xmlstarlet sel -t -v "count(//property[@name='${configurationProperty}'])" ${CONFLUENCE_HOME}/confluence.cfg.xml)
    if [ "${propertyCount}" = '0' ]; then
      # Element does not exist, we insert new property
      xmlstarlet ed --pf --inplace --subnode '//properties' --type elem --name 'property' --value "${configurationValue}" -i '//properties/property[not(@name)]' --type attr --name 'name' --value "${configurationProperty}" ${CONFLUENCE_HOME}/confluence.cfg.xml
    else
      # Element exists, we update the existing property
      xmlstarlet ed --pf --inplace --update "//property[@name='${configurationProperty}']" --value "${configurationValue}" ${CONFLUENCE_HOME}/confluence.cfg.xml
    fi
  fi
}

function processConfluenceConfigurationSettings() {
  local counter=1
  if [ -f "${CONFLUENCE_HOME}/confluence.cfg.xml" ]; then
    for (( counter=1; ; counter++ ))
    do
      VAR_CONFLUENCE_CONFIG_PROPERTY="CONFLUENCE_CONFIG_PROPERTY$counter"
      VAR_CONFLUENCE_CONFIG_VALUE="CONFLUENCE_CONFIG_VALUE$counter"
      if [ -z "${!VAR_CONFLUENCE_CONFIG_PROPERTY}" ]; then
        break
      fi
      setConfluenceConfigurationProperty ${!VAR_CONFLUENCE_CONFIG_PROPERTY} ${!VAR_CONFLUENCE_CONFIG_VALUE}
    done
  fi
}

# end of new functions

# Support Arbitrary User IDs (Reference: OpenShift Container Platform 3.9 Image Creation Guide):
if ! whoami &> /dev/null; then
  if [ -w /etc/passwd ]; then
    #echo "${RUN_USER:-default}:x:$(id -u):0:${RUN_USER:-default} user:${CONFLUENCE_HOME}:/sbin/nologin" >> /etc/passwd
    echo "${RUN_USER:-default}:x:$(id -u):$(id -u):${RUN_USER:-default} user:${CONFLUENCE_HOME}:/sbin/nologin" >> /etc/passwd
  fi
  if [ -w /etc/group ]; then
    cp /etc/group /tmp/group
    sed -i "1s/.*/root:x:0:root,$(id -u),${RUN_USER:-default}/" /tmp/group
    > /etc/group
    cat /tmp/group >> /etc/group
  fi
fi
# End of Support Arbitrary User IDs

processConfluenceConfigurationSettings

# Purge of confluence home:
# https://confluence.atlassian.com/confkb/confluence-does-not-start-due-to-there-may-be-a-configuration-problem-in-your-confluence-cfg-xml-file-241568568.html
# rm -rf ${CONFLUENCE_HOME}/*
rm -rf ${CONFLUENCE_HOME}/confluence.cfg.xml
cp ${CONFLUENCE_INSTALL_DIR}/confluence/WEB-INF/confluence-cfg/confluence.cfg.xml ${CONFLUENCE_HOME}/confluence.cfg.xml
# Start Confluence as the correct user
if [ "${UID}" -eq 0 ]; then
    echo "User is currently root. Will change directory ownership to ${RUN_USER}:${RUN_GROUP}, then downgrade permission to ${RUN_USER}"
    PERMISSIONS_SIGNATURE=$(stat -c "%u:%U:%a" "${CONFLUENCE_HOME}")
    EXPECTED_PERMISSIONS=$(id -u ${RUN_USER}):${RUN_GROUP}:775
    if [ "${PERMISSIONS_SIGNATURE}" != "${EXPECTED_PERMISSIONS}" ]; then
        chmod -R 775 "${CONFLUENCE_HOME}" &&
        chown -R "${RUN_USER}:${RUN_GROUP}" "${CONFLUENCE_HOME}"
    fi
    # Now drop privileges
    exec su -s /bin/bash "${RUN_USER}" -c "$CONFLUENCE_INSTALL_DIR/bin/start-confluence.sh $@"
else
    echo "User is not root"
    echo "User is ${RUN_USER}"
    exec "$CONFLUENCE_INSTALL_DIR/bin/start-confluence.sh" "$@"
fi

