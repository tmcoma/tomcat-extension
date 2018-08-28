# Apache Tomcat Extensions for VSTS 

## Requirements 
* Node.js
* `tfx-cli`, which can be installed with `npm i -g tfx-cli`

In Windows you may need to add `%AppData%\npm` to your `PATH` in order for Node apps like `tfx` to run.

You'll also need a VSTS Personal Access Token (PAT) .



## Publishing
You'll need to create a VSIX file by hand and upload the extension manually the first time.  We use `--rev-version` here because
each upload requires a new version:
```
tfx extension create --rev-version
```


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

## See Also
https://docs.microsoft.com/en-us/vsts/extend/publish/overview?view=vsts
https://docs.microsoft.com/en-us/vsts/extend/develop/add-build-task?view=vsts
https://marketplace.visualstudio.com/manage/publishers/neocio-web?auth_redirect=True
