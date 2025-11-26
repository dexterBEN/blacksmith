#!/bin/bash
set -e

echo "Restoring .NET dependencies..."
# dotnet restore

echo "Installing gcloud CLI..."
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
apt-get update
apt-get install google-cloud-cli
apt-get install -y google-cloud-sdk

echo "Installation completed."