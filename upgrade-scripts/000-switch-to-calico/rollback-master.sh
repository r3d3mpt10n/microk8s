#!/bin/bash
set -ex

echo "Rolling back calico upgrade on master"

source $SNAP/actions/common/utils.sh


if [ -e "$SNAP_DATA/args/cni-network/cni.yaml" ]; then
  KUBECTL="$SNAP/kubectl --kubeconfig=${SNAP_DATA}/credentials/client.config"
  $KUBECTL delete -f "$SNAP_DATA/args/cni-network/cni.yaml"
fi

BACKUP_DIR="$SNAP_DATA/var/tmp/upgrades/000-switch-to-calico"

if [ -e "$BACKUP_DIR/args/cni-network/flannel.conflist" ]; then
  find "$SNAP_DATA"/args/cni-network/* -not -name '*multus*' -exec rm -f {} \;
  cp -rf "$BACKUP_DIR"/args/cni-network/* "$SNAP_DATA/args/cni-network/"
fi

echo "Restarting kubelet"
if [ -e "$BACKUP_DIR/args/kubelet" ]; then
  cp "$BACKUP_DIR"/args/kubelet "$SNAP_DATA/args/"
fi

echo "Restarting kube-proxy"
if [ -e "$BACKUP_DIR/args/kube-proxy" ]; then
  cp "$BACKUP_DIR"/args/kube-proxy "$SNAP_DATA/args/"
fi

echo "Restarting kube-apiserver"
if [ -e "$BACKUP_DIR/args/kube-apiserver" ]; then
  cp "$BACKUP_DIR"/args/kube-apiserver "$SNAP_DATA/args/"
fi

if [ -e "$SNAP_DATA"/var/lock/lite.lock ]
then
  snapctl restart ${SNAP_NAME}.daemon-kubelite
else
  snapctl restart ${SNAP_NAME}.daemon-apiserver
  snapctl restart ${SNAP_NAME}.daemon-kubelet
  snapctl restart ${SNAP_NAME}.daemon-proxy
fi

${SNAP}/microk8s-status.wrapper --wait-ready --timeout 30

echo "Restarting flannel"
set_service_expected_to_start flanneld
remove_vxlan_interfaces
snapctl start ${SNAP_NAME}.daemon-flanneld

echo "Restarting kubelet"
if grep -qE "bin_dir.*SNAP_DATA}\/" $SNAP_DATA/args/containerd-template.toml; then
  echo "Restarting containerd"
  "${SNAP}/bin/sed" -i 's;bin_dir = "${SNAP_DATA}/opt;bin_dir = "${SNAP}/opt;g' "$SNAP_DATA/args/containerd-template.toml"
  snapctl restart ${SNAP_NAME}.daemon-containerd
fi

echo "Calico rolledback"
