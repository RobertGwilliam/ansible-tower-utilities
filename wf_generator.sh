#!/bin/ksh
#*********************************************************************
#
#       Component:      Ansible Tower Workflow Creator
#
#       Module:         wf_generator.sh
#
#       Purpose:        Provides Tower Workflow Functionality
#
#       External Interfaces:
#
#       Command line parameters:
#
#               Create WF using JTs listed below
#               -t <template name>
#               -o <organisation>
#               -d delete, not add
#               -n no WF survey, for scheduling and non interactive inits
#               -j <job list for WF> filename with/out .conf
#
#       Example:
#               wf_generator.sh -t "Full Server Preparation" -o SDLC-DEV
#
#       Execution Environment:
#               User =
#
#       Assumptions:
#               WF survey contructed from all sub JT surveys
#               each WF node is dependent on the previous, so no parallel jobs
#
#       Amendment History:
#         15 May 19  R.Gwilliam  Initial Version
#
#   SVNBUILD:
#   SVNDATE:
#
#**********************************************************************
#

typeset progNAME=${0}
typeset SW_BASE=/usr/integration/tower

# Generic Vars

typeset mainLOG=${SW_BASE}/logs/$(basename ${progNAME} .sh).log
typeset towerURL="https://$(hostname -s).$(hostname -d)/api/v2"
typeset dummyINVENTORY="Workflow Dummy Inventory"
typeset tmpADDYML=/tmp/add_workflow.$$
typeset surveySCHEMA=/tmp/pre_survey_schema.$$.json
typeset newSURVEY=/tmp/wf_survey_schema.$$.json
typeset surveyENABLED=true
typeset wfACTION=create

# Admin functions

###################
# Function: echoLOG
# Blurb:    echos text into the main log
# Inputs:   $@ - text to echo

function echoLOG
{
        # Variables
        typeset -r theTEXT="$@"

        typeset datestamp=$(date +"%y%m%d %H:%M:%S")
        echo -e "${datestamp}   ${theTEXT}" >> ${mainLOG}
}

###################
# Function: checkRESULT
# Blurb:    checks the result of a command
# Inputs:   $1 - value to check
#               $2 - Error message to display
function checkRESULT
{
        if [[ $1 != 0 ]]
        then
                echoLOG "AN ERROR HAS BEEN DETECTED!"
                echo "ERROR: $2 ($1)" | tee -a ${mainLOG}

                echoLOG "${errorTXT}"
                echo "${errorTXT}"
                echo "Log File: ${mainLOG}"
                exit $1
        fi
}

###################
# Function: doLOG
# Blurb:    Runs a command and appends stdout + stderr to the main log file
#           & returns the result
# Inputs:   $1 - Command to run
# Output:   Return code after running $1

function doLOG
{
        # Variables
        typeset -r theCOMMAND="$1"
        echoLOG "Running command: ${theCOMMAND}"

        ${theCOMMAND} >>${mainLOG} 2>&1
        return $?
}

# Validate Args

typeset -i numberOPTS=0

while getopts :hndo:t:j:i: opt
do
        case ${opt} in
        j)      jobLIST="$(basename ${OPTARG} .conf).conf"
                numberOPTS=${numberOPTS}+1;;

        i)      inventoryNAME="${OPTARG}"
                numberOPTS=${numberOPTS}+1;;

        t)      wftemplateNAME="${OPTARG}"
                numberOPTS=${numberOPTS}+1;;

        o)      organizationNAME="${OPTARG}"
                numberOPTS=${numberOPTS}+1;;

        n)      surveyENABLED=false
                numberOPTS=${numberOPTS}+1;;

        d)      wfACTION=delete
                numberOPTS=${numberOPTS}+1;;

        h)      echo "Tower workflow creator. Usage: ${0} [-h] -t <template name> -o <organizationNAME> -j <joblist file> [-i <inventory name>] [-n] (no survey) [-d] (delete, not add)"
                exit 99;;

        *) echo "Invalid option ${opt}. Use -h for usage instructions"
                exit 99;;

        esac
done

if [[ ${numberOPTS} -lt 2 ]]
then
        checkRESULT 98 "Incorrect command line options specified. Use "-h" for usage instructions"
fi

if [[ -z ${jobLIST} ]]
then
        checkRESULT 99 "Specify job list file"
fi

echoLOG "Starting Workflow {wfACTION}."

# List of Job Template Names to be run from Work Flow
# These are simple typeset of array of tasks
. ${SW_BASE}/${jobLIST}

# Extract admin password, ok, so may need to be root
typeset apw=$(grep password /root/.tower_cli.cfg | awk -F= '{print $2}')
checkRESULT $? "Error extracting admin password"
if [[ -z ${apw} ]]
then
        checkRESULT 1 "Unable to extract admin password"
fi

# Determine organizationID from organization parameter
organizationID=$(tower-cli organization get --name "${organizationNAME}" --format id 2>>${mainLOG})
checkRESULT $? "Failure getting ID of organization: ${organizationNAME}"

# Check that this WFT doesn't already exist
wftemplateID=$(tower-cli workflow get --name "${wftemplateNAME}" --format id 2>/dev/null)
if [[ ! -z ${wftemplateID} ]]
then
        if [[ ${wfACTION} == delete ]]
        then
                # WF exists and we want to delete it, so delete.
                tower-cli workflow delete --name "${wftemplateNAME}" >>${mainLOG} 2>&1
                checkRESULT $? "Failed to delete Workflow: ${wftemplateNAME}"
                echoLOG "Workflow ${wftemplateNAME} deleted"
                exit 0
        else
                checkRESULT 1 "This WF already exists"
        fi
fi

# Create and Extract dummy inventory id for adding nodes, if inventory not supplied. Set ask inventory flag appropriately.
askINVENTORY=true
if [[ ! -z ${inventoryNAME} ]]
then
        dummyINVENTORY=${inventoryNAME}
        # Set ask inventory to false if inventory passed in
        askINVENTORY=false
fi
tower-cli inventory create --name "${dummyINVENTORY}" --organization ${organizationNAME} >>${mainLOG} 2>&1
checkRESULT $? "Failure adding inventory: ${dummyINVENTORY}"
inventoryID=$(tower-cli inventory get --name "${dummyINVENTORY}" --format id 2>> ${mainLOG})
checkRESULT $? "Failure getting ID of inventory: ${dummyINVENTORY}"

# Unable to modify "ask_inventory_on_launch" from tower-cli (at 3.4.3)
# So use API to insert Workflow directly

echo "---
- name: Add Work Flow Template
  hosts: localhost
  gather_facts: no

  tasks:
    - name: Create Work Flow Template
      uri:
        url: ${towerURL}/workflow_job_templates/
        method: POST
        user: admin
        password:${apw}
        validate_certs: no
        status_code: 201
        force_basic_auth: true
        body:
          name: "${wftemplateNAME}"
          description: "${wftemplateNAME}"
          extra_vars: ""
          organization: ${organizationID}
          survey_enabled: true
          allow_simultaneous: false
          ask_variables_on_launch: true
          inventory: ${inventoryID}
          ask_inventory_on_launch: ${askINVENTORY}
        body_format: json" 2>>${mainLOG} >${tmpADDYML}_wf.yml

echoLOG "Creating Workflow Template"
doLOG "ansible-playbook ${tmpADDYML}_wf.yml"
checkRESULT $? "Unable to create WF ${wftemplateNAME}"

# Extract ID of Workflow template - will need this later
wftemplateID=$(tower-cli workflow get --name "${wftemplateNAME}" --format id 2>>${mainLOG})
checkRESULT $? "Failure getting ID of WF Template: ${wftemplateNAME}"

# Iterate list of Job templates and contruct required WF nodes, linking success association
# to previous job to assure sequential application of jobs.
# Build json list of all Job template surveys for later conversion to WF survey
>${surveySCHEMA}
typeset dependNODE=""
for jobTEMPLATEINDEX in "${!templateLIST[@]}"
do

        # Extract unified job_template Id
        utemplateID=$(tower-cli job_template get --name "${templateLIST[${jobTEMPLATEINDEX}]} ${organizationNAME}" --format id 2>>${mainLOG})
        checkRESULT $? "Failure getting ID of Unified Job Template: ${templateLIST[${jobTEMPLATEINDEX}]} ${organizationNAME}"

        # Pull the survey from the Job Template and append to uber survey file
        tower-cli job_template survey \
                --name="${templateLIST[${jobTEMPLATEINDEX}]} ${organizationNAME}" >> ${surveySCHEMA} 2>>${mainLOG}
        checkRESULT $? "Failed to dump JT survey schema"

        tower-cli node create \
                -W "${wftemplateNAME}" \
                --job-template=${utemplateID} \
                --inventory=${inventoryID} >>${mainLOG} 2>&1
        checkRESULT $? "Failed to create new WF node"

        if [[ ! -z ${dependNODE} ]]
        then
                # Get the node id of this node and set it to only run ehen dependNODE id has succeeded
                thisNODE=$(tower-cli node get --unified-job-template ${utemplateID} --workflow-job-template "${wftemplateNAME}" --format id 2>>${mainLOG})
                tower-cli node associate_success_node ${dependNODE} ${thisNODE} >>${mainLOG} 2>&1
        fi
        dependNODE=$(tower-cli node get --unified-job-template ${utemplateID} --workflow-job-template "${wftemplateNAME}" --format id 2>>${mainLOG} )
        checkRESULT $? "Failed to identify id of dependent node"
done

# Modify survey schema to allow it to be added to WF
# Remove envelope delimiters
sed -i '/\"name\"/d;/\"description\"/d;/^{/d;/^}/d;/\[/d;/\]/d;/\"spec\"/d;/}$/s/}$/},/' ${surveySCHEMA}
checkRESULT $? "Failed to update survey json"

# Remove pesky last line "}"
sed -i '$d' ${surveySCHEMA}

# Add required new envelope data to json specific to this WF
echo "{
  \"description\": \"${wftemplateNAME} Survey\",
  \"name\": \"${wftemplateNAME}\",
  \"spec\": [" > ${newSURVEY}
cat ${surveySCHEMA} >> ${newSURVEY}
echo "    }
  ]
}" >>  ${newSURVEY}

# Modify the WF to insert the new WF survey containing all sub JT survey fields.
tower-cli workflow modify --name="${wftemplateNAME}" \
        --survey-spec=@${newSURVEY} --survey-enabled=${surveyENABLED} >>${mainLOG} 2>&1
checkRESULT $? "Failed to add WF survey to WF"

echoLOG "Workflow created."
doLOG "rm -f ${tmpADDYML}_wf.yml"
doLOG "rm -f $surveySCHEMA"
doLOG "rm -f $newSURVEY"
