#!/bin/bash

usage="usage: $(basename "$0") [-c] [-h] -v

This script will build the Go bindings for HELICS using swig in a temporary
Docker image to avoid having to install build dependencies locally.

where:
    -c      clean generated files
    -h      show this help text
    -v      version of HELICS to build bindings for"


clean=f
version=


# loop through positional options/arguments
while getopts ':chv:' option; do
    case "$option" in
        c)  clean=t                ;;
        h)  echo -e "$usage"; exit ;;
        v)  version="$OPTARG"      ;;
        \?) echo -e "illegal option: -$OPTARG\n" >$2
            echo -e "$usage" >&2
            exit 1 ;;
    esac
done


if [ "$clean" = "t" ]; then
  echo "Deleting helics.go and helics_wrap.cxx..."
  rm helics.go helics_wrap.cxx
  exit
fi


which docker &> /dev/null

if (( $? )); then # this will get run inside the build container
  swig -go -cgo -c++ -intgosize 64 -I/usr/include/helics/shared_api_library helics.i

  sed -i 's/\#include \"ValueFederate\.h\"/\#include \"helics\/shared_api_library\/ValueFederate\.h\"/'     helics_wrap.cxx
  sed -i 's/\#include \"MessageFederate\.h\"/\#include \"helics\/shared_api_library\/MessageFederate\.h\"/' helics_wrap.cxx
  sed -i 's/\#include \"MessageFilters\.h\"/\#include \"helics\/shared_api_library\/MessageFilters\.h\"/'   helics_wrap.cxx

  exit
fi


if [ -z "$version" ]; then
  echo "Must provide HELICS version to build bindings for (-v)"
  exit 1
fi


major=$(cut -d '.' -f 1 <<< "$version")

if (( $major != 2 )); then
  echo "This build script is for version 2 of HELICS only"
  exit 1
fi


USER_UID=$(id -u)
USERNAME=builder


docker build -t go-helics:builder -f - . <<EOF
FROM golang:1.16

RUN groupadd --gid $USER_UID $USERNAME \
  && useradd -s /bin/bash --uid $USER_UID --gid $USER_UID -m $USERNAME

RUN apt update \
  && apt install -y swig

RUN curl -L -o helics.tgz \
    https://github.com/GMLC-TDC/HELICS/releases/download/v${version}/Helics-${version}-Linux-x86_64.tar.gz \
  && tar -C /usr --strip-components=1 -xzf helics.tgz \
  && rm helics.tgz

ENV PKG_CONFIG_PATH /usr/lib64/pkgconfig:${PKG_CONFIG_PATH}
ENV LD_LIBRARY_PATH /usr/lib64:${LD_LIBRARY_PATH}
EOF

docker run -it --rm -v $(pwd):/go-helics -w /go-helics -u $USERNAME go-helics:builder bash build.sh
