cluster_tag="kubernetes.io/cluster/pou-test-fsdvf"
cluster_tag_name=$(basename $cluster_tag)

echo "Weekend ON"
aws events list-targets-by-rule --rule ocp-lab-power-management_weekend_on
echo "Weekend OFF"
aws events list-targets-by-rule --rule ocp-lab-power-management_weekend_off
echo "Night ON"
aws events list-targets-by-rule --rule ocp-lab-power-management_night_on
echo "Night OFF"
aws events list-targets-by-rule --rule ocp-lab-power-management_night_off
echo "Certificate"
aws events list-targets-by-rule --rule ocp-lab-power-management_cert_on_${cluster_tag_name}
