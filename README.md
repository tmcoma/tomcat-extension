# Apache Tomcat Extensions for VSTS 
This is an extension to VSTS for managing Apache Tomcat instances.  Currently it supports deploying WAR files to Tomcat instances over SSH/SCP with explicit calls to startup.sh and shutdown.sh.

## Requirements 
* Node.js
* `tfx-cli`, which can be installed with `npm i -g tfx-cli`

In Windows you may need to add `%AppData%\npm` to your `PATH` in order for Node apps like `tfx` to run.

You'll also need a VSTS Personal Access Token (PAT).

## Publishing
```
tfx extension publish --share-with neocio --rev-version
```

Note that you can let tfx manage your login this way:
```
tfx login -u https://neocio.visualstudio.com  -t <YOUR PAT>
```

## GUIDs
You can use PowerShell to create a guid for the task.json's id using
```
[guid]::NewGuid()
```

## Roadmap
This extension should be expanded to support the following

* Parallel deployments of WAR files
* Installing and Configuring Apache Tomcat instances

## Publishing
There is a VSTS Release Task configured in VSTS which will publish and share this task.  It has a CI trigger which will publish the extension whenever commits are made to the `master` branch.  The patch version will be updated automatically via the `Query Extension Version` task.  You will need to set the `Extension.VersionOverride` variable if you want to bump a major or minor version number.

You will need to manually update *task* versions for changes to a task to be reflected.  Presently there is no auto-update of task versions like there is for the entire vss-extension.

## See Also
https://docs.microsoft.com/en-us/vsts/extend/publish/overview?view=vsts
https://docs.microsoft.com/en-us/vsts/extend/develop/add-build-task?view=vsts
https://marketplace.visualstudio.com/manage/publishers/neocio-web?auth_redirect=True
