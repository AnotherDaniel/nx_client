#!/bin/bash

helptext="
Nextcloud cli for downloading/uploading/deleting files

<destination> is the location on your nextcloud file server instance, starting from the root folder.
Nextcloud credentials and settings are sourced from ~/.nx_client

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
"

usage() { 
    echo "Usage: $0 [-h] [-c <configfile>] [-u <file> -f | -p | -d | -o] <destination>" 1>&2;
    echo "$helptext"
}

abort() { 
    echo "ERROR: $*. Aborting." >&2
    exit 1
}

CURL_BIN="$(which curl 2>/dev/null)"
if [ ! -x "$CURL_BIN" ]; then
    abort "curl binary not found"
fi

# internal helpers
optc=false
optd=false
optu=false
optf=false
optp=false
opto=false
command="" 

while getopts ":hc:du:o:fp" opt; do
    case "${opt}" in
        h)
            usage
            exit 0
            ;;
        c)
            optc=true
            c=${OPTARG}
            if [[ -z "${c}" ]]; then abort "No config file name provided"; fi
            if [[ ! -f "${c}" ]]; then abort "Provided config file does not exist"; fi
            ;;
        d)
            $optu && abort "Cannot delete (-d) and upload (-u) at the same time"
            $optp && abort "Cannot delete (-d) and create directory (-p) at the same time"
            $opto && abort "Cannot delete (-d) and download (-o) at the same time"
            optd=true
            command="Deleting"
            CURL_CMD="-X DELETE"
            ;;
        u)
            $optd && abort "Cannot upload (-u) and delete (-d) at the same time"
            $optp && abort "Cannot upload (-u) and create directory (-p) at the same time"
            $opto && abort "Cannot upload (-u) and download (-o) at the same time"
            optu=true
            u=${OPTARG}
            if [[ -z "${u}" ]]; then abort "No file to upload provided"; fi
            if [[ ! -f "${u}" ]]; then abort "Upload is not a file"; fi
            command="Uploading $u to"
            CURL_CMD="-T ${u}"
            BASENAME=`basename ${u}`
            ;;
        f)
            optf=true
            ;;
        p)
            $optd && abort "Cannot create directory (-p) and delete (-d) at the same time"
            $optu && abort "Cannot create directory (-p) and upload (-u) at the same time"
            $opto && abort "Cannot create directory (-p) and download (-o) at the same time"
            optp=true
            command="Creating directory"
            CURL_CMD="-X MKCOL"
            ;;
        o)
            $optd && abort "Cannot download (-o) and delete (-d) at the same time"
            $optu && abort "Cannot download (-o) and upload (-u) at the same time"
            $optp && abort "Cannot download (-o) and create directory (-p) at the same time"
            opto=true
            o=${OPTARG}
            if [[ -z "${o}" ]]; then abort "No target filename provided"; fi
            ;;
        :)
            abort "-${OPTARG} requires an argument."
            ;;
        *)
            abort "Something went wrong"
            ;;
    esac
done
shift $((OPTIND-1))

# if no parameter has been set, we're downloading
if [[ -z "$CURL_CMD" ]]; then 
    command="Downloading" 
    if [ $opto = true ]; then 
        echo "$o"
        CURL_CMD="-o $o"
    else
        CURL_CMD="-O"
    fi
fi

# -f(orce) only works alongside -u(pload)
if [ $optf = true ]; then 
    if [ $optu = false ]; then abort "-f must be specified together with -u"; fi
fi

# retrieve nextcloud BASEDIR and CREDS
if [ $optc = true ]; then
    source ${c}
else
    source ~/.nx_client
fi
if [[ -z "$BASEURL" ]]; then abort "No BASEDIR configuration found (check your ~/.nx_client config file)"; fi
if [[ -z "$CREDS" ]]; then abort "No CREDS configuration found (check your ~/.nx_client config file)"; fi

# check for and extract destinationPath
if [[ $# -eq 0 ]]; then abort "destinationPath argument missing"; fi
if [[ $# -gt 1 ]]; then abort "Too many arguments"; fi

URL="$BASEURL/$1"
CURL_OPTS="-f -w httpcode=%{http_code} -m 100"
CURL_RETURN_CODE=0

# enough preamble, let's do this
printf "$command $URL ... "

# check whether file already exists on server (in case -f(orce) is not specified)
if [ $optu = true ] && [ $optf = false ]; then
    if (($("$CURL_BIN" --silent -u "$CREDS" -I "$URL/$BASENAME" | grep -E "^HTTP" | awk -F " " '{print $2}') == 200)); then
        echo "file already exists, skipping"
        exit 0
    fi
fi

CURL_OUTPUT=`${CURL_BIN} ${CURL_OPTS} -u ${CREDS} ${CURL_CMD} ${URL} 2> /dev/null` || CURL_RETURN_CODE=$?

# error handling - per command-type. Dunno if there is a better way to do this
if [[ ${CURL_RETURN_CODE} -lt 0 ]]; then
    echo "failed - curl ${CURL_RETURN_CODE}"
else
    httpCode=$(echo "${CURL_OUTPUT}" | sed -e 's/.*\httpcode=//')
    if [ $optu = true ]; then
        if [[ ${httpCode} -eq 201 ]]; then
            echo "done"
            exit 0
        elif [[ ${httpCode} -eq 204 ]]; then
            echo "done (replaced existing file)"
            exit 0
        elif [[ ${httpCode} -eq 404 ]]; then
            echo "Error: target is not a directory"
            exit 1
        elif [[ ${httpCode} -eq 409 ]]; then
            echo "Error: target directory doesn't exist"
            exit 1
        elif [[ ${httpCode} -eq 423 ]]; then
            echo "Error: destination file exists and is locked"
            exit 1
        else
            echo "failed - http ${httpCode}"
            exit 2
        fi
    elif [ $optd = true ]; then
        if [[ ${httpCode} -eq 204 ]]; then
            echo "done"
            exit 0
        elif [[ ${httpCode} -eq 404 ]]; then
            echo "Error: file/directory doesn't exist"
            exit 1
        elif [[ ${httpCode} -eq 423 ]]; then
            echo "Error: file exists and is locked"
            exit 1
        else
            echo "failed - http ${httpCode}"
            exit 2
        fi
    elif [ $optp = true ]; then
        if [[ ${httpCode} -eq 201 ]]; then
            echo "done"
            exit 0
        elif [[ ${httpCode} -eq 405 ]]; then
            echo "Error: directory already exists"
            exit 1
        else
            echo "failed - http ${httpCode}"
            exit 2
        fi
    else
        if [[ ${httpCode} -eq 000 ]]; then
            echo "Error - did you try to download a directory?"
            exit 1
        elif [[ ${httpCode} -eq 200 ]]; then
            echo "done"
            exit 0
        elif [[ ${httpCode} -eq 404 ]]; then
            echo "Error: file doesn't exist"
            exit 1
        else
            echo "failed - http ${httpCode}"
            exit 2
        fi
    fi
    exit 3
fi