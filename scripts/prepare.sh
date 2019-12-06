#!/usr/bin/env bash
# Author: Hung Tran
if [ $# -eq 0 ]
then
        echo "Missing options!"
        echo "(run $0 -h for help)"
        echo ""
        exit 0
fi
ENV=""
ECHO="false"

while getopts ":he:p:b:" OPTION; do
        case $OPTION in
                e)
                        ENV="$OPTARG"
                        ;;
                
                b)
                        BUCKET="$OPTARG"
                        ;;

                p)
                        PROJECT_ID="$OPTARG"
                        ;;

                h)
                        echo "Usage: $0 [ -p PROJECT_ID ] [ -e ENVIRONMENT ]" 1>&2
                        echo ""
                        echo "   -p     GCP Project ID"
                        echo "   -e     environment: dev/qa/prod..."
                        echo "   -b     Optional: GCS Bucket as Terraform Backend. Default value: <PROJECT_ID>-tfstate"
                        echo "   -h     help (this output)"
                        exit 0
                        ;;

        esac
done

if [ -z $ENV  ] || [ -z $PROJECT_ID ]; then 
    echo "Error: ENV or PROJECT_ID cannot be empty"
    exit 1
fi

if [ -z $BUCKET ];
then
    BUCKET=$PROJECT_ID-tfstate
    echo "No bucket defined. The bucket named $BUCKET will be selected as Terraform backend"
fi

#BUCKET=$PROJECT_ID-tfstate
gcloud config set project $PROJECT_ID
PROJECT_NUMBER="$(gcloud projects describe ${PROJECT_ID} --format='get(projectNumber)')"
TERRAFORM_SA=terraform
TERRAFORM_SA_EMAIL=${TERRAFORM_SA}@${PROJECT_ID}.iam.gserviceaccount.com

yes '' | sed 2q # Add 2 blank lines
echo "Environment Info"
echo "Environment: ${ENV} "
echo "Project ID: ${PROJECT_ID} "
echo "Terraform GCS Backend: ${BUCKET}"
echo "Project Number: ${PROJECT_NUMBER}"
echo "Terraform IAM Service Account: ${TERRAFORM_SA_EMAIL}"

yes '' | sed 2q # Add 2 blank lines
echo "Enable required APIs"
APIList="cloudbuild.googleapis.com sourcerepo.googleapis.com containeranalysis.googleapis.com"
for api in $APIList
do
    # enabled=$(gcloud services list --enabled --format="value(name)" --filter="name:${api}")
    # if [ -z "$enabled" ]
    if [[ $(gcloud services list --enabled --format="value(NAME)" --filter="NAME:${api}" 2>&1) != "${api}"  ]]
    then   
        echo "Enabling ${api}"
        gcloud services enable $api
    else 
        echo "$api is already enabled"
    fi
done


# # Create Terraform service account
saExisted=$(gcloud iam service-accounts list --format="value(email)" --filter="email:${TERRAFORM_SA_EMAIL}")
if [ -z $saExisted ]
then 
    gcloud iam service-accounts create terraform --description="Service Account for Terraform" --display-name="Terraform service account"
    gcloud projects add-iam-policy-binding ${PROJECT_NUMBER} \
        --member serviceAccount:${TERRAFORM_SA}@${PROJECT_ID}.iam.gserviceaccount.com \
        --role roles/owner > /dev/null
fi


#Create GCS bucket as Terraform Backend
echo "Create/configure a GCS Bucket as Terraform Backend"


AVAIL=$(gsutil ls -p $PROJECT_ID | grep "${BUCKET}" | wc -l )
if [ $AVAIL -eq 0 ]
then 
    gsutil mb -p $PROJECT_ID gs://$BUCKET
    gsutil versioning set on gs://$BUCKET
    gsutil acl ch -u ${TERRAFORM_SA}@${PROJECT_ID}.iam.gserviceaccount.com:W gs://${BUCKET}

else
    echo "Bucket ${BUCKET} already existed"
fi
