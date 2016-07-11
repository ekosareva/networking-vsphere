#!/bin/bash
#
# devstack/plugin.sh
# Functions to control the configuration and operation of the OVSvApp solution
# Dependencies:
#
# ``functions`` file
# ``DEST`` must be defined
# ``STACK_USER`` must be defined

# ``stack.sh`` calls the entry points in this order:
#
# - install_ovsvapp_dependency
# - install_networking_vsphere
# - run_ovsvapp_alembic_migration
# - pre_configure_ovsvapp
# - add_ovsvapp_config
# - configure_ovsvapp_config
# - setup_ovsvapp_bridges
# - start_ovsvapp_agent
# - configure_ovsvapp_compute_driver
# - cleanup_ovsvapp_bridges

# Save trace setting
XTRACE=$(set +o | grep xtrace)
set +o xtrace

source $TOP_DIR/lib/neutron_plugins/ovs_base

# DVSvApp Networking-vSphere DIR.
VMWARE_DVS_NETWORKING_DIR=$DEST/networking-vsphere

# Nova VMwareVCDriver DIR
NOVA_VCDRIVER=$NOVA_DIR/nova/virt/vmwareapi/

# DVSvApp patched vif.py
NOVA_VIF=$VMWARE_DVS_NETWORKING_DIR/networking_vsphere/nova/virt/vmwareapi/vif.py

# DVSvApp patched vm_util.py
NOVA_VM_UTIL=$VMWARE_DVS_NETWORKING_DIR/networking_vsphere/nova/virt/vmwareapi/vm_util.py

# Entry Points
# ------------

function add_vmware_dvs_config {
    echo "Networkin-vSphere: add_vmware_dvs_config"
    VMWARE_DVS_CONF_PATH=etc/neutron/plugins/ml2
    VMWARE_DVS_CONF_FILENAME=vmware_dvs_agent.ini
    mkdir -p /$VMWARE_DVS_CONF_PATH
    VMWARE_DVS_CONF_FILE=$VMWARE_DVS_CONF_PATH/$VMWARE_DVS_CONF_FILENAME
    VMWARE_NOVA_CONF_FILE=etc/nova/nova-compute.conf
    echo "Adding configuration file for Vmware_Dvs Agent"
    cp $VMWARE_DVS_NETWORKING_DIR/$VMWARE_DVS_CONF_FILE /$VMWARE_DVS_CONF_FILE
}

function configure_vmware_dvs_config {
    echo "Networkin-vSphere: configure_vmware_dvs_config"
    iniset /$VMWARE_DVS_CONF_FILE DEFAULT host $VMWAREAPI_CLUSTER
    iniset /$VMWARE_DVS_CONF_FILE securitygroup enable_security_group $VMWARE_DVS_ENABLE_SG
    iniset /$VMWARE_DVS_CONF_FILE securitygroup firewall_driver $VMWARE_DVS_FW_DRIVER
    iniset /$VMWARE_DVS_CONF_FILE ml2_vmware vsphere_login $VMWAREAPI_USER
    iniset /$VMWARE_DVS_CONF_FILE ml2_vmware vsphere_hostname $VMWAREAPI_IP
    iniset /$VMWARE_DVS_CONF_FILE ml2_vmware vsphere_password $VMWAREAPI_PASSWORD
    iniset /$VMWARE_DVS_CONF_FILE ml2_vmware network_maps $VMWARE_DVS_CLUSTER_DVS_MAPPING
    iniset /$VMWARE_DVS_CONF_FILE ml2_vmware uplink_maps $VMWARE_DVS_UPLINK_MAPPING
    iniset /$NOVA_CONF DEFAULT host $VMWAREAPI_CLUSTER
}

function configure_DVS_compute_driver {
    echo "Configuring Nova VCDriver for DVS"
    cp $NOVA_VIF $NOVA_VCDRIVER
    cp $NOVA_VM_UTIL $NOVA_VCDRIVER
}

function start_vmware_dvs_agent {
    echo "Networkin-vSphere: start_vmware_dvs_agent"
    VMWARE_DVS_AGENT_BINARY="$NEUTRON_BIN_DIR/neutron-dvs-agent"
    echo "Starting Vmware_Dvs Agent"
    run_process vmware_dvs-agent "python $VMWARE_DVS_AGENT_BINARY --config-file $NEUTRON_CONF --config-file /$VMWARE_DVS_CONF_FILE"
}

function setup_vmware_dvs_bridges {
    echo "Networkin-vSphere: setup_vmware_dvs_bridges"
    echo "Adding Bridges for Vmware_Dvs Agent"
    sudo ovs-vsctl --no-wait -- --may-exist add-br $INTEGRATION_BRIDGE
    sudo ovs-vsctl --no-wait -- --may-exist add-br $VMWARE_DVS_PHYSICAL_BRIDGE
    sudo ovs-vsctl --no-wait -- --may-exist add-port $VMWARE_DVS_PHYSICAL_BRIDGE $VMWARE_DVS_PHYSICAL_INTERFACE
}

function cleanup_vmware_dvs_bridges {
    echo "Networkin-vSphere: cleanup_vmware_dvs_bridges"
    echo "Removing Bridges for Vmware_Dvs Agent"
    sudo ovs-vsctl del-br $INTEGRATION_BRIDGE
    sudo ovs-vsctl del-br $VMWARE_DVS_PHYSICAL_BRIDGE
}

function pre_configure_vmware_dvs {
    echo "Networkin-vSphere: pre_configure_vmware_dvs"
    echo "Configuring Neutron for Vmware_Dvs Agent"
    configure_neutron
    _configure_neutron_service
}

function install_vmware_dvs_dependency {
    echo "Networkin-vSphere: install_vmware_dvs_dependency"
    echo "Installing dependencies for VMware_DVS"
    install_nova
    install_neutron
    _neutron_ovs_base_install_agent_packages
    sudo pip install "git+git://github.com/yunesj/suds#egg=suds"
}

function install_networking_vsphere {
    echo "Networkin-vSphere: install_networking_vsphere"
    echo "Installing the Networking-vSphere"
    setup_develop $VMWARE_DVS_NETWORKING_DIR
}

# main loop
if is_service_enabled vmware_dvs-server; then
    if [[ "$1" == "source" ]]; then
        # no-op
        :
    elif [[ "$1" == "stack" && "$2" == "install" ]]; then
        install_vmware_dvs_dependency
        install_networking_vsphere

    elif [[ "$1" == "stack" && "$2" == "post-config" ]]; then
        # no-op
	:
    elif [[ "$1" == "stack" && "$2" == "post-extra" ]]; then
        # no-op
        :
    fi

    if [[ "$1" == "unstack" ]]; then
        # no-op
        :
    fi

    if [[ "$1" == "clean" ]]; then
        # no-op
        :
    fi
fi

if is_service_enabled vmware_dvs-agent; then
    if [[ "$1" == "source" ]]; then
        # no-op
        :
    elif [[ "$1" == "stack" && "$2" == "install" ]]; then
        install_vmware_dvs_dependency
        install_networking_vsphere

    elif [[ "$1" == "stack" && "$2" == "post-config" ]]; then
	add_vmware_dvs_config
        configure_DVS_compute_driver
	configure_vmware_dvs_config
	setup_vmware_dvs_bridges
	start_vmware_dvs_agent
    elif [[ "$1" == "stack" && "$2" == "post-extra" ]]; then
        # no-op
        :
    fi

    if [[ "$1" == "unstack" ]]; then
        cleanup_vmware_dvs_bridges
    fi

    if [[ "$1" == "clean" ]]; then
        cleanup_vmware_dvs_bridges
    fi
fi

# Restore xtrace
$XTRACE

# Tell emacs to use shell-script-mode
## Local variables:
## mode: shell-script
## End:
