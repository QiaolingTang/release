#!/bin/bash

set -o nounset
set -o errexit
set -o pipefail

CONSOLE_URL=$(cat $SHARED_DIR/console.url)
API_URL="https://api.${CONSOLE_URL#"https://console-openshift-console.apps."}:6443"
export CONSOLE_URL
export API_URL
export gauge_reports_dir=${ARTIFACT_DIR}
export overwrite_reports=false
export KUBECONFIG=$SHARED_DIR/kubeconfig
export GOPROXY="https://proxy.golang.org/"

# Add timeout to ignore runner connection error
gauge config runner_connection_timeout 600000 && gauge config runner_request_timeout 300000

# login for interop
if test -f ${SHARED_DIR}/kubeadmin-password
then
  OCP_CRED_USR="kubeadmin"
  export OCP_CRED_USR
  OCP_CRED_PSW="$(cat ${SHARED_DIR}/kubeadmin-password)"
  export OCP_CRED_PSW
  oc login -u kubeadmin -p "$(cat $SHARED_DIR/kubeadmin-password)" "${API_URL}" --insecure-skip-tls-verify=true
else #login for ROSA & Hypershift platforms
  eval "$(cat "${SHARED_DIR}/api.login")"
fi

echo "Running olm.spec to install operator"
CATALOG_SOURCE=redhat-operators CHANNEL=${OLM_CHANNEL} gauge run --log-level=debug --verbose --tags install specs/olm.spec || true
