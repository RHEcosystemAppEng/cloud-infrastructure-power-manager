
exp_date_cron=$(date -u --date "+2 minute" +"%M %H ? * %a *")
arn=$(aws events put-rule \
  --name test-pou-test-fsdvf \
  --description "pou-test-fsdvf" \
  --schedule-expression "cron($exp_date_cron)" \
  | jq -r '.RuleArn'
)



target_ec2_ids_json='{
  "region": "eu-west-1",
  "instances": ["i-0e76af057046e83f9", "i-0dbb56026b59c77a4", "i-011635e8bc52456a8", "i-0fe60c2a45186e0b1"],
  "action": "on"
}'
target_ec2_ids_json_action_on=$(echo "$target_ec2_ids_json" | sed 's/"/\\"/g')

aws events put-targets \
  --rule test-pou-test-fsdvf \
  --targets "Id"="pou-test-fsdvf","Arn"="arn:aws:lambda:eu-west-1:790531666491:function:ocp-lab-power-management","Input"="$(echo "\"$target_ec2_ids_json_action_on\"")" \

aws lambda add-permission \
  --function-name ocp-lab-power-management \
  --action 'lambda:InvokeFunction' \
  --statement-id "$(basename $(awk -F ":" '{print $6}' <<< $arn))" \
  --principal events.amazonaws.com \
  --source-arn $arn
