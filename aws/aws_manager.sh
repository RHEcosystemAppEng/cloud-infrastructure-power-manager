# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.


#!/bin/bash

error_rt=-1
lambda_function_name="ocp-lab-power-management"
role_name="cloud-infrastructure-power-manager"

# check_aws_cli checks if the AWS CLI is already installed
function check_aws_cli () {
  if [ ! command -v aws &>/dev/null ]; then
    echo "The AWS CLI could not be found"
    exit $error_rt
  fi
}

function power_manager_role () {
  role_arn=$(aws iam get-role \
    --role-name $role_name \
    2>/dev/null \
    | jq -r '.Role.Arn'
  )
  if [[ -z $role_arn ]]; then
    echo "'$role_name' Role doesn't exists... Creating it."
    role_arn="$(aws iam create-role \
      --role-name $role_name \
      --assume-role-policy-document file://role_relationship.json \
      --description "Cloud Infrastructure Power Manager Role" \
      2>/dev/null \
      | jq -r '.Role.Arn'
    )"
  fi

  policy_arn="$(aws iam list-policies \
    | jq -r '
      .Policies[] 
      | select(.PolicyName == "cloud-infrastructure-power-manager") 
      | .Arn
    ' \
    2>/dev/null
  )"
  if [[ -z $policy_arn ]]; then
    policy_arn="$(aws iam create-policy \
      --policy-name $role_name \
      --policy-document file://role_policy.json \
      2>/dev/null \
      | jq -r '.Policy.Arn'
    )"
  fi

  aws iam attach-role-policy \
    --role-name $role_name \
    --policy-arn $policy_arn \
    | jq -r '.Role.Arn'
}

# General function to create selector menus
function _opt_selector() {
  prompt="$1"
  choices=( $2 )

  PS3="$prompt: "
  select choice in "${choices[@]}"; do
    [[ -n $choice ]] || { echo "Invalid option. Please try again." >&2; continue; }
    break # valid choice was made; exit prompt.
  done

  # Split the chosen line into ID and serial number.
  read -r profile sn unused <<<"$choice"
  unset PS3

  echo "$choice"
}

# List the current configured profiles in the AWS CLI
function get_profiles () {
  aws configure list-profiles
}

# List the available regions in AWS EC2
function get_regions() {
  aws ec2 describe-regions | jq -r '.Regions[].RegionName'
}

# List every Cluster Tag for a EC2 region
function get_cluster_tags () {
  aws ec2 describe-instances \
    --output json \
    --profile $profile \
    --region $region | \
    jq -r \
    '
      .Reservations[].Instances[].Tags[] |
      select(.Value == "owned") |
      .Key
    ' | uniq
}

# Ask which AWS profile should be used
function ask_profile () {
  profiles="$(get_profiles)"
  profile=$(_opt_selector "Select a Profile" "$profiles")
}

# Ask which AWS EC2 Region should be used
function ask_region () {
  regions="$(get_regions)"
  region=$(_opt_selector "Select a Region" "$regions")
}

# Ask which AWS EC2 Region should be used
function ask_cluster_tag () {
  cluster_tags="$(get_cluster_tags)"
  cluster_tag=$(_opt_selector "Select a Cluster" "$cluster_tags")
}

# Ask which rule set want to configure
function ask_rule_type () {
  opts="
  Weekends
  Nights
  Weekends-Nights
  None
  "
  rule=$(_opt_selector "Select a rule" "$opts")
}

# Ask every data to select one running cluster
function ask_cluster_data () {
  ask_profile
  ask_region
  ask_cluster_tag
  cluster_tag_name=$(basename $cluster_tag)
  ask_rule_type
}

# Check if the power management function already exists
function lambda_function_exists () {
  aws lambda get-function --function-name $lambda_function_name &>/dev/null
  return $?
}

# Creates every available rule for lambda function in AWS EventBridge
function lambda_rule_create () {
  read \
    -p "Enter the Certification Expiration date: " \
    exp_date

  exp_date_cron=$(date --date "$exp_date -1 day" +"%M %H %d %m ? *")

  cert_on_rule_arn=$(aws events put-rule \
    --name ${lambda_function_name}_cert_on_${cluster_tag_name} \
    --description "OCP lab power manager rule to trigger power on just before Kubelet's cert expiration date" \
    --schedule-expression "cron($exp_date_cron)" \
    --tags "{\"Key\": \"${lambda_function_name}\",\"Value\": \"owned\"}" \
    | jq -r '.RuleArn'
  )

  wk_off_rule_arn=$(aws events put-rule \
    --name ${lambda_function_name}_weekend_off \
    --description "OCP lab power manager rule to trigger power off before weekends" \
    --schedule-expression "cron(00 23 ? * FRI *)" \
    --tags "{\"Key\": \"${lambda_function_name}\",\"Value\": \"owned\"}" \
    | jq -r '.RuleArn'
  )

  wk_on_rule_arn=$(aws events put-rule \
    --name ${lambda_function_name}_weekend_on \
    --description "OCP lab power manager rule to trigger power on after weekends" \
    --schedule-expression "cron(00 07 ? * MON *)" \
    --tags "{\"Key\": \"${lambda_function_name}\",\"Value\": \"owned\"}" \
    | jq -r '.RuleArn'
  )

  ng_off_rule_arn=$(aws events put-rule \
    --name ${lambda_function_name}_night_off \
    --description "OCP lab power manager rule to trigger power off during nights" \
    --schedule-expression "cron(00 23 ? * MON-FRI *)" \
    --tags "{\"Key\": \"${lambda_function_name}\",\"Value\": \"owned\"}" \
    | jq -r '.RuleArn'
  )

  ng_on_rule_arn=$(aws events put-rule \
    --name ${lambda_function_name}_night_on \
    --description "OCP lab power manager rule to trigger power on during days" \
    --schedule-expression "cron(00 07 ? * MON-FRI *)" \
    --tags "{\"Key\": \"${lambda_function_name}\",\"Value\": \"owned\"}" \
    | jq -r '.RuleArn'
  )
}

# Create the power management lambda function
function lambda_function_create () {
  zip lambda.zip lambda.py

  lambda_function_arn=$(aws lambda create-function \
    --function-name $lambda_function_name \
    --region $region \
    --zip-file fileb://lambda.zip \
    --handler lambda.lambda_handler \
    --runtime python3.9 \
    --tags "{\"Key\": \"${lambda_function_name}\",\"Value\": \"owned\"}" \
    --role $role_arn \
    | jq -r '.FunctionArn'
  )

  if [[ $? -eq 0 ]]; then
    rm lambda.zip
  fi
}

# prints the ARN of the lambda function
function lambda_function_get_arn () {
  lambda_function_arn=$(aws lambda get-function \
    --function-name $lambda_function_name \
    | jq -r '.Configuration.FunctionArn'
  )
}

# Creates the basic JSON input for the EventBridge target
function get_target_ec2_ids_json () {
# Example input:
#{
#  "region": "ZONE",
#  "instances": [
#    "i-XXXXX01",
#    "i-XXXXX02",
#    "i-XXXXX03",
#    "i-XXXXX04"
#  ],
#  "action": "off"
#}
jq \
  --arg region $region \
  -ncR '{"region":$region,"instances":[inputs]}' <<< "$(get_instances_Ids)"
}

# Adds the targets for the Certificate Renewal rule
function lambda_function_trigger_cert_renewal_create () {
  aws events put-targets \
    --rule ${lambda_function_name}_cert_on_${cluster_tag_name} \
    --targets "Id"="$cluster_tag_name","Arn"="$lambda_function_arn","Input"="$(echo "\"$target_ec2_ids_json_action_on\"")" \
    &>/dev/null
  aws lambda add-permission \
    --function-name $lambda_function_name \
    --action 'lambda:InvokeFunction' \
    --statement-id "$(basename $(awk -F ":" '{print $6}' <<< $cert_on_rule_arn))" \
    --principal events.amazonaws.com \
    --source-arn $cert_on_rule_arn \
    &>/dev/null
}

# Deletes the targets for the Certificate Renewal rule
function lambda_function_trigger_cert_renewal_delete () {
  aws events remove-targets \
    --rule ${lambda_function_name}_cert_on_${cluster_tag_name} \
    --ids "$cluster_tag_name" \
    &>/dev/null
  aws lambda remove-permission \
    --function-name $lambda_function_name \
    --statement-id "$(basename $(awk -F ":" '{print $6}' <<< $cert_on_rule_arn))" \
    &>/dev/null
}

# Adds the targets for the weekend rule
function lambda_function_trigger_weekends_create () {
  aws events put-targets \
    --rule ${lambda_function_name}_weekend_off \
    --targets "Id"="$cluster_tag_name","Arn"="$lambda_function_arn","Input"="$(echo "\"$target_ec2_ids_json_action_off\"")" \
    &>/dev/null
  aws lambda add-permission \
    --function-name $lambda_function_name \
    --action 'lambda:InvokeFunction' \
    --statement-id "$(basename $(awk -F ":" '{print $6}' <<< $wk_off_rule_arn))" \
    --principal events.amazonaws.com \
    --source-arn $wk_off_rule_arn \
    &>/dev/null

  aws events put-targets \
    --rule ${lambda_function_name}_weekend_on \
    --targets "Id"="$cluster_tag_name","Arn"="$lambda_function_arn","Input"="$(echo "\"$target_ec2_ids_json_action_on\"")" \
    &>/dev/null
  aws lambda add-permission \
    --function-name $lambda_function_name \
    --action 'lambda:InvokeFunction' \
    --statement-id "$(basename $(awk -F ":" '{print $6}' <<< $wk_on_rule_arn))" \
    --principal events.amazonaws.com \
    --source-arn $wk_on_rule_arn \
    &>/dev/null
}

# Deletes the targets for the weekend rule
function lambda_function_trigger_weekends_delete () {
  aws events remove-targets \
    --rule ${lambda_function_name}_weekend_off \
    --ids "$cluster_tag_name" \
    &>/dev/null
  aws lambda remove-permission \
    --function-name $lambda_function_name \
    --statement-id "$(basename $(awk -F ":" '{print $6}' <<< $wk_off_rule_arn))" \
    &>/dev/null

  aws events remove-targets \
    --rule ${lambda_function_name}_weekend_on \
    --ids "$cluster_tag_name" \
    &>/dev/null
  aws lambda remove-permission \
    --function-name $lambda_function_name \
    --statement-id "$(basename $(awk -F ":" '{print $6}' <<< $wk_on_rule_arn))" \
    &>/dev/null
}

# Adds the targets for the night rule
function lambda_function_trigger_nights_create () {
  aws events put-targets \
    --rule ${lambda_function_name}_night_off \
    --targets "Id"="$cluster_tag_name","Arn"="$lambda_function_arn","Input"="$(echo "\"$target_ec2_ids_json_action_off\"")" \
    &>/dev/null
  aws lambda add-permission \
    --function-name $lambda_function_name \
    --action 'lambda:InvokeFunction' \
    --statement-id "$(basename $(awk -F ":" '{print $6}' <<< $ng_off_rule_arn))" \
    --principal events.amazonaws.com \
    --source-arn $ng_off_rule_arn \
    &>/dev/null

  aws events put-targets \
    --rule ${lambda_function_name}_night_on \
    --targets "Id"="$cluster_tag_name","Arn"="$lambda_function_arn","Input"="$(echo "\"$target_ec2_ids_json_action_on\"")" \
    &>/dev/null
  aws lambda add-permission \
    --function-name $lambda_function_name \
    --action 'lambda:InvokeFunction' \
    --statement-id "$(basename $(awk -F ":" '{print $6}' <<< $ng_on_rule_arn))" \
    --principal events.amazonaws.com \
    --source-arn $ng_on_rule_arn \
    &>/dev/null
}

# Deletes the targets for the night rule
function lambda_function_trigger_nights_delete () {
  aws events remove-targets \
    --rule ${lambda_function_name}_night_off \
    --ids "$cluster_tag_name" \
    &>/dev/null
  aws lambda remove-permission \
    --function-name $lambda_function_name \
    --statement-id "$(basename $(awk -F ":" '{print $6}' <<< $ng_off_rule_arn))" \
    &>/dev/null

  aws events remove-targets \
    --rule ${lambda_function_name}_night_on \
    --ids "$cluster_tag_name" \
    &>/dev/null
  aws lambda remove-permission \
    --function-name $lambda_function_name \
    --statement-id "$(basename $(awk -F ":" '{print $6}' <<< $ng_on_rule_arn))" \
    &>/dev/null
}

# Ask the desired set of rules, and creates them
function lambda_function_trigger_create () {
  target_ec2_ids_json=$(echo "$(get_target_ec2_ids_json)")
  target_ec2_ids_json_action_off=$(jq -c '. += {"action":"off"}' <<< $target_ec2_ids_json | sed 's/"/\\"/g')
  target_ec2_ids_json_action_on=$(jq -c '. += {"action":"on"}' <<< $target_ec2_ids_json | sed 's/"/\\"/g')

  lambda_function_trigger_weekends_delete
  lambda_function_trigger_nights_delete

  lambda_function_trigger_cert_renewal_delete
  lambda_function_trigger_cert_renewal_create

  case $rule in
    Weekends)
      echo "Creating Lambda Triggers for Weekends"
      lambda_function_trigger_weekends_create
      ;;
    Nights)
      echo "Creating Lambda Triggers for Nights"
      lambda_function_trigger_nights_create
      ;;
    Weekends-Nights)
      echo "Creating Lambda Triggers for Weekends & Nights"
      lambda_function_trigger_weekends_create
      lambda_function_trigger_nights_create
      ;;
    None)
      echo "Deleting every Lambda Trigger"
      ;;
    *)
      echo "Not recognised option"
      ;;
  esac
}

# Manages every step to create and remove Lambda functions
function lambda_function () {
  lambda_function_exists
  if [[ $? -ne 0 ]]; then
    echo "'$lambda_function_name' Lambda function doesn't exists... Creating it."
    lambda_function_create
  else
    lambda_function_get_arn
  fi

  lambda_rule_create
  lambda_function_trigger_create
}

# prints the selected EC2 Ids
function get_instances_Ids() {
  aws ec2 describe-instances \
    --output json \
    --profile $profile \
    --region $region | \
    jq -r --arg cluster "$cluster_tag" \
    '
      .Reservations[].Instances[] |
      select (.Tags[].Key == $cluster) |
      .InstanceId
    '
}




###
# MAIN
###########################################################
echo "Configuring Power Manager for AWS"
## Init
check_aws_cli
power_manager_role

## Getting Info
ask_cluster_data


## Lambda Creation
lambda_function
