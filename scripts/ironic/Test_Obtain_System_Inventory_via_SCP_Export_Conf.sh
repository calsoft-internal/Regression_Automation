#!/bin/bash
TEST_CASE_NAME="Test obtain system inventory via System Configuration Profile (SCP) export configuration"

if [ $# -ne 2 ]; then
    echo
    echo "WARNING: Usage: Test_Obtain_System_Inventory_via_SCP_Export_Conf.sh <NODE_UUID> <INPUT_JSON>"
    echo
    exit 1
fi

NODE_UUID=$1
INPUT_JSON_FILE=$2

echo "INFO: NODE UUID is: $NODE_UUID"

source ~/devstack/openrc admin

set -x

echo "INFO: Checking node existance"
result=$(openstack baremetal node show $NODE_UUID -c 'uuid' -f value)
if [ -z "$result" ]
then
        echo "ERRRO: Node $NODE_UUID is not present or provided invalid node uuid "
        exit 1
else
        echo "INFO: Preparing node $NODE_UUID for export configuration"
fi

echo "INFO: Checking node provision_state"
provision_state=$(openstack baremetal node show $NODE_UUID -c provision_state -f value)
if [ $provision_state == 'manageable' ]
then
        echo "INFO: Node $NODE_UUID provision_state is ${provision_state}"
else
	echo "ERROR: Invalid Node provision_state $provision_state, it should be manageable"
	exit 1
fi

echo "INFO: Checking node management_interface"
current_interface=$(openstack baremetal node show $NODE_UUID -c "management_interface" -f value)
if [ $current_interface == 'idrac-redfish' ]
then
        echo "INFO: Node $NODE_UUID management_interface is ${current_interface}"
else
        echo "ERROR: Invalid Node $NODE_UUID management_interface $current_interface"
        exit 1
fi

echo "INFO: Gathering swift project details"
username=$(sed -nr "/^\[swift\]/ { :l /^username[ ]*=/ { s/.*=[ ]*//; p; q;}; n; b l;}" /etc/ironic/ironic.conf)
password=$(sed -nr "/^\[swift\]/ { :l /^password[ ]*=/ { s/.*=[ ]*//; p; q;}; n; b l;}" /etc/ironic/ironic.conf)
project_name=$(sed -nr "/^\[swift\]/ { :l /^project_name[ ]*=/ { s/.*=[ ]*//; p; q;}; n; b l;}" /etc/ironic/ironic.conf)


echo "INFO: Source ironic swift project"
source ~/devstack/openrc $username $project_name
export OS_PASSWORD=$password

echo "INFO: Create swift container for configuration molds"
swift post configuration_molds
sleep 10

echo "INFO: Find the swift storage base url"
BASE_URL=$(swift auth | awk -F = '/OS_STORAGE_URL/ {print $2}')

echo "INFO: update the input json"
BASE_URL=${BASE_URL//\//\\/}
NAME="export_output"
sed -i "s/<BASE_URL>\/configuration_molds\/<NAME>.json/$BASE_URL\/configuration_molds\/$NAME.json/g" $INPUT_JSON_FILE

echo "INFO: start the export configurarion via CLI"
baremetal node clean $NODE_UUID --clean-steps $INPUT_JSON_FILE

echo "INFO: Checking the export configuration status"
while :
do
	result=$(openstack baremetal node show $NODE_UUID -c provision_state -f value)
	if [ "$result" == "manageable" ]
	then
		echo "INFO: Executed export configuration clean step successfully on node $NODE_UUID"
		break
	elif [ "$result" == "clean failed" ]
	then
		echo "ERROR: Execution failed for export configuration clean step on node $NODE_UUID"
		exit 1
	else
		echo "INFO: Node $NODE_UUID is in clean wait state"

	fi
	
done

## Check the exported output file in swift container
container_output=$(swift list configuration_molds | grep export_output.json | wc -l)
if [ $container_output == 1 ]
then
	echo "INFO: exported system details successfully on node $NODE_UUID"
else
	echo "ERROR: export configuration failed on node $NODE_UUID"
fi