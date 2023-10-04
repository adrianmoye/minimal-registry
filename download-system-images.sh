#!/usr/bin/env bash
#
# Downloads and moves k3s images and puts them into
# an image registry directory tree to be served by
# a minimalist registry server.
#


REGISTRY_DIR="registry"
VERSION=""
PLATFORM="linux/amd64"
EXTRA_CONTAINERS=""
NO_TRIM=""
SKIP_K3S=""
IMAGE_LIST=""

# takes a full image name, and process it. It then creates a 
# directory tree in a registry format, and downloads the image
# in oci format, it then calls the process_blob function to
# move the blobs into the correct location.
function pull_image()
{
  local IMAGE="$1"

  # get the repo name and tag
  local TAG=$( echo "${IMAGE}" | sed 's/.*://' )
  local REPO=$( echo "${IMAGE}" | sed 's/:.*//' )

  # if the start of the repo name before the first "/" has a "." in it, assume it's
  # a domain and strip it off
  if [[ "$( echo "${REPO}" | grep  ^'[^\.]*/' )" = "" ]] && [[ "${NO_TRIM}" = "" ]]; then
    REPO=$( echo "${REPO}" | sed 's|^[^/]*/||' )
  fi

  # make directory layout
  mkdir -p "${REGISTRY_DIR}/${REPO}/manifests"
  mkdir -p "${REGISTRY_DIR}/blobs"

  # put symlinks for the blob directory so they all
  # use a common one
  local C="${REGISTRY_DIR}/${REPO}"
  while echo "${C}" | grep -q "/"; do
    ln -sf ../blobs "${C}/"
    C=$( echo "${C}" | sed 's|/[^/]*$||' )
  done

  # cleanout temp folder and download container image
  rm -rf "${REGISTRY_DIR}/tmp"
  mkdir -p "${REGISTRY_DIR}/tmp"
  crane pull "${IMAGE}" "${REGISTRY_DIR}/tmp" --format=oci --platform="${PLATFORM}"

  # process container image, moving blobs into the correct place

  local TAG_FILE="$(awk -F\" '{if($2=="digest")print$4}' ${REGISTRY_DIR}/tmp/index.json)"
  local ITEM=""
  local SHA=""
  local MEDIA_TYPE=""
  # place a symlink for the tag
  ln -sf "${TAG_FILE}" "${REGISTRY_DIR}/${REPO}/manifests/${TAG}"

  ###### move the blobs to the right place
  # we should use jq here, and walk the manifest tree, but this is easier
  # considering complexity, potential object sizes, and the jq dependency.
  #  local SOURCE_MEDIA_TYPE=$( jq -r '.mediaType' "${SOURCE_FILE}" )
  #  ...
  #    jq -jr '.manifests[]?|(.mediaType, " ", .digest,"\n") ' "${SOURCE_FILE}"
  #  } | while read MEDIA_TYPE DIGEST CONFIG; do

  for ITEM in "${REGISTRY_DIR}/tmp/blobs/sha256"/*; do
    SHA=$(echo "${ITEM}" | sed 's|.*/||' )
    MEDIA_TYPE=$(head "${ITEM}" | awk -F\" '/mediaType/{if(!n)n=$4}END{print n}' )
    if [[ "${MEDIA_TYPE}" = "" ]]; then
      # it's a blob
      mv "${ITEM}" "${REGISTRY_DIR}/blobs/sha256:${SHA}"
    else
      mv "${ITEM}" "${REGISTRY_DIR}/${REPO}/manifests/sha256:${SHA}"
    fi
  done

  # cleanup
  rm -rf "${REGISTRY_DIR}/tmp"
}

function usage()
{
  cat <<EOF
Usage: $0 \\
          [-v <k3s version string (default=stable)>] \\
          [-d <registry directory (default=./registry)>] \\
          [-f <extra images list file>] \\
          [-p <platform (default=linux/amd64)>] \\
          [-n] \\
          [-s] \\
          [-h]

	-v|--version    The k3s version you wish to download images for, this
                        defaults to the value for the stable channel.

	-d|--directory  The directory name to download all of the images to.

	-f|--file       A file containing a list of additional containers images
                        to also download to the registry.

	-n|--no-trim    Disables trimming of the registry domain from the
                        repo name.

	-p|--platform   Platform to download the containers for, can use "all".

        -s|--skip-k3s   Skip downloading k3s

        -h|--help       This help.
EOF
}

# get the command line arguments
while (( $# > 0 )); do
  case "$1" in
    -d|--directory) shift ; REGISTRY_DIR="$1" ; shift ;;
    -f|--file) shift ; EXTRA_CONTAINERS="$1" ; shift ;;
    -n|--no-trim) NO_TRIM="$1" ; shift ;;
    -p|--platform) shift ; PLATFORM="$1" ; shift ;;
    -v|--version) shift ; VERSION="$1" ; shift ;;
    -s|--skip-k3s) SKIP_K3S="$1" ; shift ;;
    -h|--help) usage ; exit ;;
     *) echo "Error, unknown argument [$1]!" >&2 ; usage >&2 ; exit 1 ;;
  esac
done

# trim trailing slashes of registry dir
REGISTRY_DIR=$( echo "${REGISTRY_DIR}" | sed 's|/*$||' )

# this is how the install script gets the version, I just copied it.
# if a version isn't specified set the version
if [[ "${SKIP_K3S}" = "" ]] && [[ "${VERSION}" = "" ]]; then
	VERSION=$( curl -w '%{url_effective}' -L -s -S https://update.k3s.io/v1-release/channels/stable -o /dev/null | sed -e 's|.*/||' )
fi

# if we only want to download the extras image list, we skip adding them
if [[ "${SKIP_K3S}" = "" ]]; then
	echo "Downloading image list for ${VERSION}"
	IMAGE_LIST=$( curl -Ls https://github.com/k3s-io/k3s/releases/download/${VERSION}/k3s-images.txt )
fi

# add any extra containers to the list
if [ -f "${EXTRA_CONTAINERS}" ]; then
  IMAGE_LIST="${IMAGE_LIST} $(cat ${EXTRA_CONTAINERS})"
fi

# finally loop through the image list and pull the images
for IMAGE in ${IMAGE_LIST}; do
  echo pull_image "${IMAGE}"
  pull_image "${IMAGE}"
done


exit 0

