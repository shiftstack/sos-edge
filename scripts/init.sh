#!/usr/bin/env bash

# Script to execute on all the sites to generate the right files
# before a run of dev-install.

# Variables:
export OS_CLOUD=upshift-sos

root_dir=$PWD
tmp_dir=$(mktemp -d -t ci-XXXXXXXXXX)
git clone https://github.com/shiftstack/dev-install $tmp_dir/dev-install &>/dev/null

if [ ! -d "scripts" ]; then
    echo "Script must be run from the root dir, usage: ./scripts/init.sh <site_name> (central or edgeX)" 
    exit 1
fi
[[ "$#" -ne 1 ]] && echo "Missing argument, usage: ./scripts/init.sh <site_name> (central or edgeX)" && exit 1
site=$1

# Check host connectivity with ICMP (ping).
# It'll try 100 times to ping a specific host
# which is given as the only argument of this function.
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
    read -p "Host will be removed, are you sure? (Press ENTER if yes, otherwise abort with CTRL+C)" -n 1 -r
    echo "Destroying dcn-central.macchi.pro..."
    openstack server delete --wait dcn-central.macchi.pro &>/dev/null
    echo "Creating dcn-central.macchi.pro..."
    openstack server create --wait --flavor m1.xlarge --port dcn-central.macchi.pro --image RHEL-8.4.0-x86_64-latest --key-name emacchi --security-group edge-poc dcn-central.macchi.pro
    sleep 60
    echo "Checking dcn-central.macchi.pro connectivity..."
    if ! check_host_ping dcn-central.macchi.pro; then
            echo "Failed to reach dcn-central.macchi.pro after 100 attempts"
            return 1
    fi
    echo "dcn-central.macchi.pro was successfuly deployed!"
}

function config_central {
    echo "Preparing configuration files to deploy OpenStack in ${tmp_dir}/central ..."
    mkdir -p $tmp_dir/central
    cp $root_dir/ansible/dev-install-overrides-common.yaml $tmp_dir/central/ansible-overrides.yaml
    cat $root_dir/ansible/dev-install-overrides-central.yaml >>$tmp_dir/central/ansible-overrides.yaml
    cp $root_dir/environments/central.yaml $tmp_dir/central
    scp $tmp_dir/central/central.yaml cloud-user@dcn-central.macchi.pro:/tmp/central.yaml &>/dev/null
}

function config_edge {
    site=$1
    echo "Preparing configuration files to deploy OpenStack in ${tmp_dir}/edge${site} ..."
    mkdir -p $tmp_dir/edge${site}
    scp $root_dir/roles/StandaloneEdge.yaml stack@dcn-edge${site}.macchi.pro: &>/dev/null
    cp $root_dir/ansible/dev-install-overrides-common.yaml $tmp_dir/edge${site}/ansible-overrides.yaml
    cat $root_dir/ansible/dev-install-overrides-edge${site}.yaml >>$tmp_dir/edge${site}/ansible-overrides.yaml
    cp $root_dir/environments/edge${site}.yaml $tmp_dir/edge${site}
    scp $tmp_dir/edge${site}/edge${site}.yaml stack@dcn-edge${site}.macchi.pro: &>/dev/null
    scp -r cloud-user@dcn-central.macchi.pro:/tmp/export_control_plane $tmp_dir &>/dev/null
    scp -r $tmp_dir/export_control_plane stack@dcn-edge${site}.macchi.pro: &>/dev/null
}

function run_edge {
    site=$1
    pushd $tmp_dir/dev-install
    make config host=dcn-edge${site}.macchi.pro user=stack &>/dev/null
    echo "Running the OpenStack deployment on dcn-edge${site}.macchi.pro..."
    make osp_full ansible_args="-e @${tmp_dir}/edge${site}/ansible-overrides.yaml"
    popd
}

function run_central {
    pushd $tmp_dir/dev-install
    make config host=dcn-central.macchi.pro user=cloud-user &>/dev/null
    echo "Running the OpenStack deployment on dcn-central.macchi.pro..."
    make osp_full ansible_args="-e @${tmp_dir}/central/ansible-overrides.yaml"
    popd
}

if [[ "${site}" == "central" ]]; then
    deploy_central
    config_central
    run_central
    echo "Deployment of central site has finished!"
fi

if [[ "${site}" =~ "edge" ]]; then
    number="${site: -1}"
    config_edge $number
    run_edge $number
    echo "Deployment of edge${number} site has finished!"
fi
