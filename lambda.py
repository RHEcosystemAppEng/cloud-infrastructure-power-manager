import boto3
ec2 = None

def lambda_handler(event, context):
    ''' Main event handler function '''
    region = event['region']
    instances = event['instances']
    action = event['action']

    new_ec2_client(region)

    if action == "off":
        power_off(instances)
    elif action == "on":
        power_on(instances)
    else:
        print("Error. Action not recognised...")

def new_ec2_client(region):
    global ec2
    ec2 = boto3.client('ec2', region_name=region)

def power_off(instances):
    ec2.stop_instances(InstanceIds=instances)
    print('Stopping your instances: ' + str(instances))

def power_on(instances):
    ec2.start_instances(InstanceIds=instances)
    print('Starting your instances: ' + str(instances))
