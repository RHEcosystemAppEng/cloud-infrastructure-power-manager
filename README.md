# Cloud Infrastructure Power Manager
The Cloud Infrastructure Power Manager creates automatic mechanisms depending on
the cloud provider to power off/on the infrastructure during periods of less
activity and certificate renewal dates

## Run
```sh
# Run the script and follow the selector menus
./power_manager.sh
```

## Get Expiration Timestamp
Configure your `oc` or `kubectl` CLI and run the following command:
```sh
oc -n openshift-kube-apiserver-operator get secret kube-apiserver-to-kubelet-signer -o jsonpath='{.metadata.annotations.auth\.openshift\.io/certificate-not-after}'
```


## Cloud providers Support
### AWS
Using a combination of AWS Lambda and AWS EventBridge creates functions and cron
rules to power on/off the specified cluster.

**Warning!** This requires to have installed the AWS CLI with properly
configured to access the subscription.
### GCP
**NOT SUPPORTED**
### AZURE
**NOT SUPPORTED**
