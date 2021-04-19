#!/usr/bin/env bash

# Script to execute on all the sites to generate the right files
# before a run of dev-install.

# Variables:
export OS_CLOUD=upshift-sos

root_dir=$PWD
tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)

if [ ! -d "scripts" ]; then
    echo "Script must be run from the root dir, usage: ./scripts/init.sh <site_name> (central or edgeX)" 
    exit 1
fi
[[ "$#" -ne 1 ]] && echo "Missing argument, usage: ./scripts/init.sh <site_name> (central or edgeX)" && exit 1
site=$1

function check_host_ping {
        ((count = 100))
        host=$1
        while [[ $count -ne 0 ]] ; do
            ping -c 1 $host &>/dev/null
            rc=$?
            if [[ $rc -eq 0 ]] ; then
                ((count = 1))
            fi
            ((count = count - 1))
        done
        if [[ $rc -eq 0 ]] ; then
            echo "$host is now reachable."
        else
            echo "$host is not reachable."
            return 1
        fi
}

function deploy_central {
    # To run against PSI
    read -p "Host will be removed, are you sure? (Press ENTER if yes, otherwise abort with CTRL+C)" -n 1 -r
    echo "Destroying dcn-central.macchi.pro..."
    openstack server delete dcn-central.macchi.pro &>/dev/null
    echo "Creating dcn-central.macchi.pro..."
    openstack server create --wait --flavor m1.xlarge --port dcn-central.macchi.pro --image RHEL-8.4.0-x86_64-latest --key-name emacchi --security-group edge-poc dcn-central.macchi.pro
    sleep 60
    echo "Checking dcn-central.macchi.pro connectivity..."
    check_host_ping dcn-central.macchi.pro || echo "Failed to reach dcn-central.macchi.pro after 100 attempts"; exit 1
    echo "dcn-central.macchi.pro was successfuly deployed!"
}

function config_central {
    mkdir -p $tmp_dir/central
    cp $root_dir/ansible/dev-install-overrides-common.yaml $tmp_dir/central/local-overrides.yaml
    cat $root_dir/ansible/dev-install-overrides-central.yaml >>$tmp_dir/central/local-overrides.yaml
    cat $tmp_dir/central/local-overrides.yaml
    cp $root_dir/environments/central.yaml $tmp_dir/central
    scp $tmp_dir/central/central.yaml cloud-user@dcn-central.macchi.pro:/tmp/central.yaml
}

function run_central {
}

if [[ "${site}" == "central" ]]; then
    deploy_central
    config_central
    run_central
fi
