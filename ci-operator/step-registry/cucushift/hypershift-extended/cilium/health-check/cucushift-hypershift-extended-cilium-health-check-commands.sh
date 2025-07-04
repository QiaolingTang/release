#!/bin/bash

set -euxo pipefail

function cleanup_connectivity_test() {
    oc delete scc cilium-test --ignore-not-found
    oc delete ns cilium-test --ignore-not-found
}

function dump_connectivity_test_namespace() {
    echo "Dumping cilium-test ns at $(date --iso=seconds --utc)"
    local dump_dir="${ARTIFACT_DIR}/cilium-connectivity-test"
    mkdir -p "$dump_dir"
    oc adm inspect ns/cilium-test --dest-dir "$dump_dir" || true
}

if [ -f "${SHARED_DIR}/proxy-conf.sh" ] ; then
  source "${SHARED_DIR}/proxy-conf.sh"
fi

# Target the guest cluster
if [[ -f "${SHARED_DIR}/nested_kubeconfig" ]]; then
    export KUBECONFIG="${SHARED_DIR}/nested_kubeconfig"
fi

echo "Waiting for the guest cluster to be ready"
timeout 30m bash -c "while [[ \$(oc get nodes --no-headers | wc -l) == 0 ]]; do sleep 15; done"
oc wait nodes --all --for=condition=Ready=true --timeout=15m
oc wait clusteroperators --all --for=condition=Available=True --timeout=30m
oc wait clusteroperators --all --for=condition=Progressing=False --timeout=30m
oc wait clusteroperators --all --for=condition=Degraded=False --timeout=30m
oc wait clusterversion/version --for=condition=Available=True --timeout=30m

oc wait --for=condition=Ready pod -n cilium --all --timeout=5m

echo "Performing Cilium connectivity tests"
trap "dump_connectivity_test_namespace; cleanup_connectivity_test" EXIT
oc apply -f - <<EOF
apiVersion: security.openshift.io/v1
kind: SecurityContextConstraints
metadata:
  name: cilium-test
allowHostPorts: true
allowHostNetwork: true
users:
  - system:serviceaccount:cilium-test:default
priority: null
readOnlyRootFilesystem: false
runAsUser:
  type: MustRunAsRange
seLinuxContext:
  type: MustRunAs
volumes: null
allowHostDirVolumePlugin: false
allowHostIPC: false
allowHostPID: false
allowPrivilegeEscalation: false
allowPrivilegedContainer: false
allowedCapabilities: null
defaultAddCapabilities: null
requiredDropCapabilities: null
groups: null
EOF
oc create ns cilium-test
oc label ns cilium-test \
    security.openshift.io/scc.podSecurityLabelSync=false \
    pod-security.kubernetes.io/enforce=privileged \
    pod-security.kubernetes.io/audit=privileged \
    pod-security.kubernetes.io/warn=privileged \
    --overwrite

# Run the test
oc apply -n cilium-test -f "https://raw.githubusercontent.com/cilium/cilium/${CILIUM_VERSION}/examples/kubernetes/connectivity-check/connectivity-check.yaml"
oc wait --for=condition=Ready pod -n cilium-test --all --timeout=10m
sleep "$CILIUM_CONNECTIVITY_TEST_DURATION"

# Error out in case of failing pods
oc wait --for jsonpath="{status.phase}"=Running pods -n cilium-test --all --timeout=5s
