#!/bin/bash

set -eu

iaas_configuration=$(cat <<-EOF
{
  "vcenter_host": "$VCENTER_HOST",
  "vcenter_username": "$VCENTER_USR",
  "vcenter_password": "$VCENTER_PWD",
  "datacenter": "$VCENTER_DATA_CENTER",
  "disk_type": "$VCENTER_DISK_TYPE",
  "ephemeral_datastores_string": "$EPHEMERAL_STORAGE_NAMES",
  "persistent_datastores_string": "$PERSISTENT_STORAGE_NAMES",
  "bosh_vm_folder": "$BOSH_VM_FOLDER",
  "bosh_template_folder": "$BOSH_TEMPLATE_FOLDER",
  "bosh_disk_path": "$BOSH_DISK_PATH",
  "ssl_verification_enabled": false
}
EOF
)

az_configuration=$(cat <<-EOF
{
  "availability_zones": [
    {
      "name": "$AZ_1",
      "cluster": "$AZ_1_CLUSTER_NAME",
      "resource_pool": "$AZ_1_RP_NAME"
    }
  ]
}
EOF
)

network_configuration=$(
  echo '{}' |
  jq \
    --argjson icmp_checks_enabled $ICMP_CHECKS_ENABLED \
    --arg infra_network_name "$INFRA_NETWORK_NAME" \
    --arg infra_vcenter_network "$INFRA_VCENTER_NETWORK" \
    --arg infra_network_cidr "$INFRA_NW_CIDR" \
    --arg infra_reserved_ip_ranges "$INFRA_EXCLUDED_RANGE" \
    --arg infra_dns "$INFRA_NW_DNS" \
    --arg infra_gateway "$INFRA_NW_GATEWAY" \
    --arg infra_availability_zones "$INFRA_NW_AZS" \
    '. +
    {
      "icmp_checks_enabled": $icmp_checks_enabled,
      "networks": [
        {
          "name": $infra_network_name,
          "service_network": false,
          "subnets": [
            {
              "iaas_identifier": $infra_vcenter_network,
              "cidr": $infra_network_cidr,
              "reserved_ip_ranges": $infra_reserved_ip_ranges,
              "dns": $infra_dns,
              "gateway": $infra_gateway,
              "availability_zones": ($infra_availability_zones | split(","))
            }
          ]
        },
      ]
    }'
)

director_config=$(cat <<-EOF
{
  "ntp_servers_string": "$NTP_SERVERS",
  "resurrector_enabled": $ENABLE_VM_RESURRECTOR,
  "max_threads": $MAX_THREADS,
  "database_type": "internal",
  "blobstore_type": "local",
  "director_hostname": "$OPS_DIR_HOSTNAME"
}
EOF
)

security_configuration=$(
  echo '{}' |
  jq \
    --arg trusted_certificates "$TRUSTED_CERTIFICATES" \
    '. +
    {
      "trusted_certificates": $trusted_certificates,
      "vm_password_type": "generate"
    }'
)

network_assignment=$(
echo '{}' |
jq \
  --arg infra_availability_zones "$INFRA_NW_AZS" \
  --arg network "$INFRA_NETWORK_NAME" \
  '. +
  {
    "singleton_availability_zone": ($infra_availability_zones | split(",") | .[0]),
    "network": $network
  }'
)

echo "Configuring IaaS and Director..."
om-linux \
  --target https://$OPS_MGR_HOST \
  --skip-ssl-validation \
  --username $OPS_MGR_USR \
  --password $OPS_MGR_PWD \
  configure-bosh \
  --iaas-configuration "$iaas_configuration" \
  --director-configuration "$director_config"

om-linux -t https://$OPS_MGR_HOST -k -u $OPS_MGR_USR -p $OPS_MGR_PWD \
  curl -p "/api/v0/staged/director/availability_zones" \
  -x PUT -d "$az_configuration"

om-linux \
  --target https://$OPS_MGR_HOST \
  --skip-ssl-validation \
  --username $OPS_MGR_USR \
  --password $OPS_MGR_PWD \
  configure-bosh \
  --networks-configuration "$network_configuration" \
  --network-assignment "$network_assignment" \
  --security-configuration "$security_configuration"
