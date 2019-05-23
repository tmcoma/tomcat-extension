## Deploy WAR File over SSH Task
The **Deploy WAR File over SSH** Task deploys WAR files to preconfigured Apache Tomcat instances over SSH (obviously).  It assumes that you have already configured an Apache Tomcat instance, that you have public key SSH access to it  and that it can be started and stopped using  `$CATALINA_HOME/bin/startup.sh` and `$CATALINA_HOME/bin/shutdown.sh`

#### Version 4.x (Preview)
* Ignores any WARs under JAVA_HOME
* Removes any existing exploded app dirs (e.g. for `myapp-1.2.3.war`, removes `$CATALINA_HOME/webapps/myapp-1.2.3`) (4.2.x)
* If Tomcat fails to shut down (either because shutdown.sh fails to shut down the java process, or because the process wasn't running in the first place), then the app will not be re-started after deployment.
* Removes "force start" hack; app is restarted if it was running when the deployment occurred.
* "Install SSH Key" support removed
* Uses a [Service Endpoint](https://docs.microsoft.com/en-us/azure/devops/pipelines/library/service-endpoints?view=vsts) connection.  This allows for better security, as the endpoint definition can be restricted to a user a or group, and it can be removed or updated in a single place (per project).  In theory this means that Azure DevOps admins can then use the [REST API](https://docs.microsoft.com/en-us/rest/api/azure/devops/serviceendpoint/endpoints/create?view=azure-devops-rest-5.0) to create and update service endpoints from a single location.
* `Ignore Host Key` boolean added to Advanced options.  This is a workaround for projects which need to test their connections and those connections haven't been added to the Agent's KNOWN_HOSTS file.  There is no support at this time for setting the known hosts entries in the task or endpoint definitions.  If they aren't configured in the Agent's KNOWN_HOSTS, which should be done by the agent admins, then you must select the `Ignore Host Key` checkbox.  In practice, this invokes `ssh` and `scp` with `-o StrictHostKeyChecking=no`.
* There is no parallel support mode here, as we cannot multiplex across multiple connections .  You'll have to add multiple tasks for each ssh target you wish to deploy to, and they will occur serially.  To speed up deployments, you should consider using [deployment groups](https://docs.microsoft.com/en-us/azure/devops/pipelines/process/deployment-group-phases?view=vsts).


Parameters:
* SSH Connection (Service Endppint)
* CatalinaLocation
* WarFile
* TargetFilename
Advanced:
* Timeout
* SuccessString 
* Ignore Host Key

##### Steps this task performs
1. Check to see if tomcat directory exists
2. scp the war file to a tmp location
3. Shut down tomcat
4. Remove existing exploded war dir, if it exists
5. Check to see if tomcat did, in fact, shut down
6. If tomcat did shut down, copy the war file in place (possibly overwriting the existing one) and re-start.  Otherwise leave it shut down and exit with a warning status.

#### Version 2.x (Preview)
* Adds support for parallelism through **Multi-configuration** parameter with a **Multiplier** set.  
* Improves warning/error handling
* Laissez-faire startup mode only: if a tomcat instance is shut down at deploy time, it will not be restarted after deployment

**Deploy to multiple Targets**

If you create a Variable in your pipeline which contains comma-separated deployment locations, you can use it
to deploy your war to multiple tomcat instances.

For example, if you have a release variable `targetz` set to `tomcat@myhost1:/home/tomcat/tomcat01, tomcat@myhost2:/home/tomcat/tomcat01`, 
you can configure the Job with parallelism and it will run concurrently on as many agents are available.

Parameters:
* CatalinaLocation
* WarFile
* TargetFilename
Advanced:
* Timeout
* SuccessString 

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

## Decrypt Files Task
Supports AES, DES, RC2, Rijndael, TripleDES.

This task will search through the directory tree for files and decrypt them using a provided key. 

This is a wrapper for the [RepoCrypto](https://github.com/tmcoma/RepoCrypto) PowerShell module, which can be used for the initial encryption.

#### Version 0.x (Preview)
Provides basic decryption support

Parameters:
- Key as Plaintext or Secure File
- Algorithm 
- Delete Encrypted Files
- Directory

# Troubleshooting

**Required: 'System.AccessToken' task variable**
- Make sure **Allow scripts to access the OAuth token** is enabled.

# License and Attribution
Encryption Icon made by [Freepik](http://www.freepik.com/) from www.flaticon.com.
