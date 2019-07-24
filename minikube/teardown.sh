#!/usr/bin/env bash

echo "cleanup files"
rm $(helm home) -rf
rm ca.* tiller.* helm.*