# Apache Tomcat Extensions for VSTS 
This is an extension to VSTS for managing Apache Tomcat instances.  Currently it supports deploying WAR files to Tomcat instances over SSH/SCP with explicit calls to startup.sh and shutdown.sh.

https://dev.azure.com/prairiegrade/Azure%20DevOps%20Extensions/_apis/build/status/Apache%20Tomcat%20Extensions-CI?branchName=master

https://vsrm.dev.azure.com/prairiegrade/_apis/public/Release/badge/36a01756-a21e-4006-99b6-1ebe42002bd4/3/6

## Developing this Extension
You will need: 
* PowerShell

Optionally, if you wish to publish the task directly, you'll need:
* [NodeJS](https://nodejs.org)
* [tfx-cli](https://docs.microsoft.com/en-us/vsts/extend/publish/command-line?view=vsts) which can be installed with `npm i -g tfx-cli`
* A VSTS Personal Access Token (PAT) with "Manage Extension" rights 
In Windows you may need to add `%AppData%\npm` to your `PATH` in order for Node apps like `tfx` to run.

## Publishing the Extension
There is a VSTS Release Task configured in VSTS which will publish and share this task.  It has a CI trigger which will publish the extension whenever commits are made to the `master` branch.  The patch version will be updated automatically via the `Query Extension Version` task.  You will need to set the `Extension.VersionOverride` variable if you want to bump a major or minor version number.

You will need to manually update *task* versions for changes to a task to be reflected.  Presently there is no auto-update of task versions like there is for the entire vss-extension.

If you need to fork the project and do an initial-install of the extension (for example, if you need to fork a demo version under a different name), use the `Extension.VersionOverride` variable in VSTS.  This will cause the release process to skip querying for a new version number (which will fail for any project which doesn't already exist).

## Roadmap
This extension should be expanded to support the following:

* Parallel/Versioned deployments of WAR files
* Installing and Configuring Apache Tomcat instances
* Mechanisms for setting `CATALINA_OPTS`, `JAVA_HOME`, `settings.xml`, `context.xml`, and log4j files
* Deploying to Windows tomcat instances via WinRCP

## See Also
* https://docs.microsoft.com/en-us/vsts/extend/publish/overview?view=vsts
* https://docs.microsoft.com/en-us/vsts/extend/develop/add-build-task?view=vsts
* https://blogs.msdn.microsoft.com/divman/2017/05/30/adding-release-management-environment-templates-to-your-vss-extension/
* https://github.com/Microsoft/azure-pipelines-tasks/blob/master/docs/authoring/commands.md
* [Powershell VstsTaskSdk](https://github.com/Microsoft/azure-pipelines-task-lib/)
* [task.json schema](https://github.com/Microsoft/azure-pipelines-task-lib/blob/master/tasks.schema.json)

