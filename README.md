# Deploy a Dev Box service with customized iamge

## Overview

This repository contains code to provision Azure DevBox into Azure. Microsoft Dev Box Preview gives you self-service access to high-performance, preconfigured, and ready-to-code cloud-based workstations called dev boxes. You can set up dev boxes with tools, source code, and prebuilt binaries that are specific to a project, so developers can immediately start work. If you're a developer, you can use dev boxes in your day-to-day workflows.

[![Deploy to Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fluxu-ms%2FDevbox-ADE-Infra%2Fcustomized-image%2Finfra%2Fazuredeploy.json)

This template deploys a Dev Box service with customized image.

## How to deploy

Click the "Deploy to Azure" button to deploy. There will be the deployment page as below:
![Deployment Sample](assets/deployment-page.png)

### Parameters

When deploying this template you can provide parameters to customize the dev box and related resources.

| Parameters | Overview |
| -- | -- |
| Devcenter Name | (Optional) The name of the DevCenter Azure resource. |
| Project Name | (Optional) |
| Network Connection Name | (Optional) |
| User Identity Name | (Optional)|
| Network Vnet Name  | (Optional) |
| Image Gallery Name | (Optional) |
| Existing Subnet Id | If you want to use your existing subnet, please input your subnet resource id. The template won't create new Virtual network and subnet if existing subnet id is proided.|
| User Principal Id | The AAD user id or gorup id that will be granted the role "Devcenter Dev Box User". Please find the user/group's object id under Azure Active Directory. If you don't provide this permission, the developer will not get the permission to access the project in the [Dev Portal](https://devportal.microsoft.com). If it's not provided, mannually you can also go to the project IAM and grant the related permissioin. Please refer to [here](https://learn.microsoft.com/en-us/azure/dev-box/quickstart-configure-dev-box-service?tabs=AzureADJoin#6-provide-access-to-a-dev-box-project). |
| Uer Principal Type | If you want to grant the permission to AAD group, please select "group" instead of "user" |

## Customize your own software and tools

If you want to add your own software and tools, please fork this repo and change the customizedCommand in the core/gallery.bicep
![customized-command](assets/customized-command.png)

## Add other customized image for Base, Java, .Net and Data

After you use this template to generate the customized image, if you want to generate more other types of image, please use the button below to generate customized image to your existing gallery and image definition.
| Image Type | Software and Tools |
| -- | -- |
| Base | Git, Azure CLI, VSCode |
| Java | Git, Azure CLI, VSCode, Maven, OpenJdk11 |
| .Net | Git, Azure CLI, VSCode，.Net SDK, Visual Studio|
| Data | Git, Azure CLI, VSCode，|


[![Deploy to Azure](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazure.svg?sanitize=true)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fluxu-ms%2FDevbox-ADE-Infra%2Fcustomized-image%2Fcustomized-image%2Fcustomized-image.json)
