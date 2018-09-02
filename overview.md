## Deploy WAR File over SSH Task
The **Deploy WAR File over SSH** Task deploys WAR files to preconfigured Apache Tomcat instances over SSH (obviously).  It assumes that you have already configured an Apache Tomcat instance, that you have public key SSH access to it  and that it can be started and stopped using  `$CATALINA_HOME/bin/startup.sh` and `$CATALINA_HOME/bin/shutdown.sh`

#### Version 1.x
This task requires that you use the [Install SSH Key](https://docs.microsoft.com/en-us/vsts/pipelines/tasks/utility/install-ssh-key?view=vsts) task as part of the current phase.
Parameters:
* SshUrl
* CatalinaHome
* WarFile
* TargetFilename
Advanced:
* Timeout
* SuccessString 

This version performs rudimentary checking on parameters to make sure that WarFile exists, CatalinaHome exists, that the TargetFilename is actuall a war file, that the SshUrl is `username@hostname`.  

If WarFile isn't specified, the task will recursively scan for war files and, if it finds a single file, will deploy that one.  If no `TargetFilename` is given, then the original `WarFile` name will be used.

## Install Tomcat Task
This task will download an Apache Tomcat instance from a mirror, verify its checksum, and install it on a remote *nix server.

#### Version 1.x
This task requires that you use the [Install SSH Key](https://docs.microsoft.com/en-us/vsts/pipelines/tasks/utility/install-ssh-key?view=vsts) task as part of the current phase.
Parameters:
* SshUrl
* CatalinaHome
* TomcatVersion 

## Deploy WAR Template
This extension includes a Release Stage Template which includes the required SSH key and Deploy War tasks.  When adding a new Stage to a Release Pipeline, this will appear when you click "+ Add."  You can search for "war" in the Select a template window to find it.  The following environment-scoped Variables will be added to your Release Pipeline when you use this template:
* SshUrl
* CatalinaHome
* TargetFilename

## Contact Info
* [Git Repo](https://neocio.visualstudio.com/ocio-vsts-extensions/_git/ocio-tomcat-vsts-extension)
* [VSTS Project Site](https://neocio.visualstudio.com/ocio-vsts-extensions)

This extension is developed by the tom.mclaughlin@nebraska.gov on behalf of the [Nebraska Office of the CIO](http://www.cio.nebraska.gov).

#### Release Info
* ##RELEASE_RELEASENAME##
* ##RELEASE_RELEASEURI##
