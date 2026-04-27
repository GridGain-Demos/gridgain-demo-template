> This is really the READ.me for your project. It is suggested that you delete the following section, up to but not including the last paragragh, once you have set up the project. This information is 
> available in the [plugin READ.me](https://github.com/GridGain-Demos/gridgain-demo-gradle-plugin)

## GridGain Demo Template
This repo contains a minimal shell that is preconfigured for creating a new GridGain demo project driven by the
[`gridgain-demo-gradle-plugin`](https://github.com/GridGain-Demos/gridgain-demo-gradle-plugin). 
To get started, clone this repo into a directory with your p, rename it, drop in your own code and
configuration, and the plugin's tasks (e.g. `validateRequirements`,
`launchPluginUi`) will be available immediately.



## Prerequisites
- Java 17 (the Gradle toolchain will download it if missing).

You will need access to a GridGain cloud account. If you do not have this, please request it
via the [Support Portal](https://support.gridgain.com/)

The plugin **DOES NOT** handle the permutations and combinations of setting up cloud CLIs and logging in.
Please do that before using the tool.

- For AWS
    - For GridGain, from a Chrome browser logged into your corporate account, open the Google Apps window
      (the 'nine dot' menu beside your profile). You should see an AWS Access option.
      For SEs, SAs and TAMs, this is a shared account, and we should all have the administrative permissions needed.
      The shared account number is `930793918939`. Otherwise, the account number should be available from a dropdown
      in the top-right corner of the console page.
    - Create a user in the [IAM Dashboard] (https://console.aws.amazon.com/iam/home) The user must have the following
      permissions (at a minimum)
        - AmazonVPCFullAccess
        - AWSCloudFormationFullAccess
        - IAMFullAccess
        - On the IAM user's Permissions tab, select Add Permissions -> Create inline policy -> JSON and paste the following:
          `{                                                                                                                                                                                                                           
          "Version": "2012-10-17",                                   
          "Statement": [                                               
          {                                                         
          "Sid": "EksUserActions",
          "Effect": "Allow",                                                                                                                                                                                                    
          "Action": [
          "eks:CreateCluster",                                                                                                                                                                                                
          "eks:DescribeCluster",                               
          "eks:ListClusters",                                                                                                                                                                                                 
          "eks:UpdateClusterConfig",                            
          "eks:UpdateClusterVersion",                                                                                                                                                                                         
          "eks:DeleteCluster",                                                                                                                                                                                                
          "eks:CreateNodegroup",
          "eks:DescribeNodegroup",                                                                                                                                                                                            
          "eks:ListNodegroups",                                
          "eks:UpdateNodegroupConfig",                                                                                                                                                                                        
          "eks:UpdateNodegroupVersion",                         
          "eks:DeleteNodegroup",                                                                                                                                                                                              
          "eks:CreateAddon",                                   
          "eks:DescribeAddon",                                                                                                                                                                                                
          "eks:DescribeAddonVersions",                          
          "eks:ListAddons",                                                                                                                                                                                                   
          "eks:UpdateAddon",                                   
          "eks:DeleteAddon",                                                                                                                                                                                                  
          "eks:DescribeUpdate",                                 
          "eks:ListUpdates",                                                                                                                                                                                                  
          "eks:TagResource",                                   
          "eks:UntagResource",                                                                                                                                                                                                
          "eks:ListTagsForResource",                            
          "eks:AssociateIdentityProviderConfig",                                                                                                                                                                              
          "eks:DescribeIdentityProviderConfig",                                                                                                                                                                               
          "eks:DisassociateIdentityProviderConfig"
          ],                                                                                                                                                                                                                    
          "Resource": "*"                                        
          }                                                                                                                                                                                                                       
          ]                                                           
          }
          `
          
          Select 'next' and give this profile a name, (suggested) `eksctl`
    - On the Security credentials tab of the new user's info, create and save an access key of type Command Line Interface (CLI)
    - Install the AWS CLI `brew install awscli`
    - Install eksctl `brew install eksctl`
    - Install kubectl `brew install kubectl`
    - Configure an AWS CLI profile  `aws configure --profile <my-demo-profile>`
        - Supply it with the AWS Access Key (from above)
        - Supply it with the AWS Secret Access Key (from above)
        - Supply it with a default region (e.g. `us-west-2`)
        - Supply it with a default output format (e.g. `json`)

    - Capture the account number — 12-digit AWS account ID ()

    - **not yet supported** roleArn (optional) — plugin will assume this role at run time via aws sts assume-role
    - **not yet supported** externalId (optional) — paired with roleArn
    - The profile name and account number must be added to an infrastructure account entry in the `demo-configuration.yaml` file.

- For GCP
    - A GCP account and project
    - Install the gcloud CLI `brew install --cask gcloud-cli`
    - Install kubectl `brew install kubectl`
    - Install additional components ` gcloud components install gke-gcloud-auth-plugin gcloud-crc32c kubectl`
    - Run `gcloud components update`
    - Incorporate this into your ~/.rshrc `export PATH="/opt/homebrew/share/google-cloud-sdk/bin:$PATH"`
    - Run `gcloud init` to login

## Quickstart

```bash
# 1. Copy this directory to your new project location.
cp -r gridgain-demo-template ../my-demo
cd ../my-demo

# 2. Initialize names and seed the config file.
./rename-demo.sh my-demo com.example.mydemo

# 3. Copy src/main/resources/demo-config.yaml.template to demo-config.yaml and replace the <YOUR_...>
#    placeholders with your account, licenses, namespaces, etc.

# 4. Verify the plugin is wired in correctly:
./gradlew tasks

# 5. When you want a fresh git history:
rm -rf .git && git init && git add . && git commit -m "Initial commit"
```

## What's in here

| Path | Purpose |
|------|---------|
| `settings.gradle.kts` | Sets `rootProject.name`; resolves the plugin and UI from GridGain Maven repos. |
| `build.gradle.kts` | Applies `com.gridgain.demo.plugin`; depends on GridGain 9 runtime + the UI project. |
| `gradle.properties` | Points the plugin at `src/main/resources/demo-config.yaml`. |
| `rename-demo.sh` | Updates `rootProject.name` and (optionally) `group`; seeds `demo-config.yaml`. |
| `src/main/resources/demo-config.yaml.template` | Starter configuration. Copy to `demo-config.yaml` and edit. |
| `.gitignore` | Ignores `demo-config.yaml`, license files, build outputs, IDE files. |

## Manual rename (if you can't run the script)

Three edit points:

1. `settings.gradle.kts` — `rootProject.name = "..."`.
2. `build.gradle.kts` — `group = "..."` (and `version` if desired).
3. The containing directory name on disk.

Then `cp src/main/resources/demo-config.yaml.template src/main/resources/demo-config.yaml`
and edit the copy.

## Secrets handling

`demo-config.yaml` is **gitignored**. It will typically contain account emails,
admin passwords, and cloud credentials, so it must never be committed. The
tracked `demo-config.yaml.template` has only placeholders and is safe to commit.
License files (`**/gridgain-license.json`, `**/controlcenter-license.json`) are
also gitignored.

## Further reading

See the [plugin's own documentation](https://github.com/GridGain-Demos/gridgain-demo-gradle-plugin)
for the full list of tasks, configuration schema, and processing-pipeline details.


> It is recommended that you delete everything above this section and replace it with the READ.me contents of your demo.
> Leave the section below for its links back to the plugin project.

## gridgain-demo-template
This project was created using the [gridgain-demo-template](https://github.com/GridGain-Demos/gridgain-demo-template)
Information on installing and using the plugin may be found in it's
[READ.me](https://github.com/GridGain-Demos/gridgain-demo-gradle-plugin)






