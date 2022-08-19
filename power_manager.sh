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

aws_rt=1
gcp_rt=2
azure_rt=3
error_rt=-1


function provider_menu () {
  PS3='Please select a Cloud Provider: '
  options=("AWS" "GCP" "Azure")
  select provider in "${options[@]}"; do
    case $provider in
      "AWS")
        echo "Selected AWS"
        . ./aws/aws_manager.sh
        return $aws_rt
        ;;
      "GCP")
        echo "Selected GCP"
        echo "Not implemented yet. Exiting..."
        return $error_rt
        ;;
      "Azure")
        echo "Selected Azure"
        echo "Not implemented yet. Exiting..."
        return $error_rt
        ;;
      *)
        echo "Invalid Cloud Provider $REPLY";;
    esac
  done
  unset PS3
}

echo -e "Welcome to Cloud Infrastructure Power Manager\nSelect A cloud provider:"
provider_menu
[[ $? != 0 ]] && { exit $error_rt; }
echo "Done"
