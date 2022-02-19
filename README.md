# nx_client

Usage: ```nx_client.sh [-h] [-c <configfile>] [-u <file> -f | -p | -d | -o] <destination>```

Nextcloud cli for downloading/uploading/deleting files

<`destination`> is the location on your nextcloud file server instance, starting from the root folder.
Nextcloud credentials and settings are sourced from ~/.nx_client

``` man
Options:
                no option will download the file at <destination> to the current directory
 -o <file>      download file at <destination> to local <file>
 -u <file>      upload <file> to <destionation>, if it doesn't already exist
 -f             force re-upload of <file> even if it already exists
 -d             delete file or directory at <destionation>
 -p             create <destination> directory
 -c             nextcloud configuration file to use, defaults to ~/.nx_client
 -h             display this help

The configuration file (default: ~/.nx_client) needs to define the variables BASEURL and CREDS - for example:
 BASEURL="https://example.nextcloud.host/remote.php/webdav"
 CREDS="example@user.account:examplePassword"
```
