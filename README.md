# Dynamic environments

⚠️ WARNING ⚠️ 
Creating an eks cluster comes with costs. 
The base setup it's pretty cheap but can potentially escalate very fast depending on the usage. 
It's possible to test the GitHub workflow and the Dynamic environment demo by using whatever other kind of kubernetes cluster it's available. 
I will try to provide a generic kubernetes terraform setup as soon as I can.

## Objective:

The object of this demo is to create an infrastructure that support the deploy of dockerized web applications directly from Github.

At the end of the demo you should be able to deploy a new docker image directly inside an EKS cluster, using Github actions, and have it easily accessible by executing a kubectl port-forward.


## Requirements:

### Tools:

- AWS Cli https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

- Kubectl https://kubernetes.io/docs/tasks/tools/

- Terraform https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli

- Helm https://helm.sh/docs/intro/install/


### User / Tokens:

- An AWS user with enough permissions to be able to create IAM, EKS, EC2, VPC and sub topic objects like subnets and security groups. Expecting this demo to be use only with an educational purpose and only in "risk-free" environment I would suggest to use an admin level user to avoid going crazy in massaging all the required permissions.
- A PAT to enable the github action runner controller to connect to your private repository/organisation. Please refer to this link for more details regarding the required permissions https://github.com/actions-runner-controller/actions-runner-controller/blob/master/docs/detailed-docs.md#deploying-using-pat-authentication

## Infrastructure

### Terraform

Inside the terraform folder create a new file  **terraform.tfvars** with the personal variables, like:

```
github_arc_token = <insert the PAT that will be use by the Action runner controller>
repository = <repository from which we want to use the runner>
```
Because we are using the helm and kubernetes provider and we want to apply changes in the cluster from the same terraform apply we need to expose the AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY as environment variables so that we can use the aws cli to connect the provider. It's possible to obtain similar result with aws credentials or aws sso settings.

```
expose AWS_ACCESS_KEY_ID=<AWS_ACCESS_KEY_ID>
expose AWS_SECRET_ACCESS_KEY=<AWS_SECRET_ACCESS_KEY>
```

Then run:
- `terraform init`
- `terraform apply` With a clean installation it should setup 76 new object. Once verified that the objects are what expected type yes.

At the end of the terraform apply you should have a new EKS cluster running in a dedicated VPC.
From the Settings -> Actions -> Runners of the github repository configured for the runner you should be able to see a new runner labelled 'base-runners' in idle status.

*Known bug*: During a terraform destroy sometimes fails on deleting the kubernetes_namespace.runners object and timeout. This error is usually because on kubernetes the namespace get stuck in terminating status as some of its resources are not correctly deleted. This problem is caused by the usage of terraform kubernetes_manifest resources that aren't able to correctly catch the status of the resources it creates. Typical case: base-runners pod are still in terminating, terraform try to terminate the namespace, both pod and namespace ends up stuck in terminating status.
To fix this you can try to repeat the terraform destroy, hoping that meanwhile the namespaces and pods got actually terminated, or manually access the cluster and terminate them. The important part is that you have already tried to run a terraform destroy as this will enable to maintain a "clean" status with terraform. Basically it has already gave the termination command so the fact that the command needs to be manually enforce it's not its problem.

**Note:**
- Some old aws account doesn't have the service-linked role named AWSServiceRoleForEC2Spot which is required to enable karpenter to use spot instances as nodes. Please refer to this documentation to create it https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-requests.html#service-linked-roles-spot-instance-requests
- As this infrastructure has been create with the only purpose of acting as Proof of concept and showcase of how easy can it be to create new environments with kubernetes and a lot of requirements to make this infrastructure production ready has been left out, like: remote backend, persistent volume, monitoring, dns-auto-record, backup, application load balancer and so on. PLEASE DO NOT USE THIS SOLUTION FOR ANYTHING MORE THEN DEMO PURPOSE OR BASE STARTING POINT FOR MORE COMPLETE SOLUTIONS.

### Helm

Because we want to create multiple environments inside our eks cluster we want to define the required kubernetes objects once and reuse them.
Helm cover this requirement as it enable us to transform kubernetes objects in template that we can customise with variables through a values.yaml file.

Inside the helm_chart folder there is a simple helm template that will enable us to deploy our containerised applications.
The deployed application will not be reachable from outside the cluster and to access it you will need to execute a `kubectl port-forward service/<application-release-name> <local port> <service-port>` after you have connected your local kubectl to the cluster. If you have your AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY you can use the following command to automatically add a new kube context to your kube config file `aws eks --region <region of the cluster> update-kubeconfig --name <cluster name>`

Kubectl port-forward makes a specific Kubernetes API request. That means the system running it needs access to the API server, and any traffic will get tunnelled over a single HTTP connection. THIS IS NOT A PRODUCTION READY configuration but it works just fine for debugging purpose or quick testing. To correctly expose your environment you will need to setup **ingress** objects, application load balancer controller (or alternative) and external-dns (https://github.com/kubernetes-sigs/external-dns) to automatically record the new domains.

Inside the **helm_chart** folder you can find a basic helm template that include the following kubernetes objects:
- Deployment
  This object represent the structure of the pod that the kubernetes cluster will have to run. It specify docker image to use, which config map to mount and so on.
- ConfigMap
  This object enable to configure NON-Sensible variables. In our deployment we are mounting this configMap as environment variable so it will be possible to configure the running env variables directly from the values.yaml file inside the repository
- ExternalSecret
  This is a CUSTOM kubernetes object that is added to our cluster by the tool "external-secret"(https://github.com/external-secrets/external-secrets). Inside the terraform - external-secrets.tf we define a ClusterSecretStore where we can store our sensible datas and fetch them directly from the kubernetes cluster. This secret are mounted as environment variables inside the deployment object.
  The secret store configured in terraform is the AWS SecretServiceManager of the same account and region where we create the cluster.
- HorizontalPodAutoscaler
  The horizontal pod autoscaler is the kubernetes' object that define how our pod will scale
- Namespace
  A namespace associate with the new environment
- Service
  As our pod can scale based on the amount of traffic we cannot relay on a single endpoint to contact them. The kubernetes' service object absolve the function of internal load-balancer for the pods and it will be the service we will expose and contact with the `kubectl port-forward` command.
- ServiceAccount
  The service account is the object that Kubernetes utilises to authorise the pod to access specific resources.

### Github Actions

To deploy and delete our new environments the demo provide two different approaches that can be find under the .github/workflows folder.

Both workflows depends on having a dedicate folder per environment under the root folder **environments**.
The folder name must respect the naming convention required by helm for his release names, basically no _ special characters or spaces and it should be fine.
Inside the folder you need to have a values.yaml file describing the configuration for the helm chart that we are going to use.

#### Automate workflow

**To use this workflow you need to add as prefix to your folder name upgrade_ or uninstall_ depending on the kind of operation you want to achieve. Both keyword will be removed during the execution and the final release name will be the folder name without the keyword**

The workflow **environment_synchronizer.yaml** is split in two jobs:
- The first job **changes** identify which file has been modified against the base branch main and IF the folder name include upgrade or uninstall it will trigger new executions of the second job. One per each modified folder with keyword.
- The second job **helm_synch** will execute an helm upgrade or helm uninstall depending on the keyword

#### Manual workflow

The workflows **manual_upgrade.yaml** and **manual_uninstall.yaml** use a trigger call workflow_dispatcher.
This will allow github maintainers or admin of the repo to manually trigger the upgrade or uninstall of a folder that doesn't use the keyword upgrade or uninstall.
To do that you need to:

- Select the **Actions** tab from the home of your github repository
- Select the manual workflows that you want to trigger from the left menu
- On the right you will see a **run workflows** drop-down menu that will enable you to select which branch to use as base ref and to insert the name of the folder to deploy.

Inside the repository you can find two examples of environments, one using the automate workflow and one for the manual.
