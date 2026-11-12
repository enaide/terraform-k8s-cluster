#!/bin/bash
# Bootstrap minimalista — solo descarga y lanza el orquestador
set -euo pipefail

BUCKET="${bucket}"
REGION="${region}"
NODE_ROLE="${node_role}"
SCRIPT_DIR="/opt/k8s-scripts"

mkdir -p "$SCRIPT_DIR/common" "$SCRIPT_DIR/$NODE_ROLE"

# Descargar todos los scripts desde S3
aws s3 cp "s3://$BUCKET/common/"          "$SCRIPT_DIR/common/"   --recursive --region "$REGION"
aws s3 cp "s3://$BUCKET/$NODE_ROLE/"      "$SCRIPT_DIR/$NODE_ROLE/" --recursive --region "$REGION"
aws s3 cp "s3://$BUCKET/init.sh"          "$SCRIPT_DIR/init.sh"   --region "$REGION"

chmod +x "$SCRIPT_DIR/common/"*.sh "$SCRIPT_DIR/$NODE_ROLE/"*.sh "$SCRIPT_DIR/init.sh"

export NODE_ROLE 
bash "$SCRIPT_DIR/init.sh"