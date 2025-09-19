# Description

This custom provider is a copy of mrparkers/keycloak with a minimal adjustment:

The original provider has a problem with multi-valued attributes of users. The Keycloak interface provides these
attributes in an arbitrary order that might change for each request. The provider concatenates all attributes with "##"
and compares the resulting string with the input. As the order of attributes is not stable, this results in unnecessary
deltas in potentially every 'plan' execution.

As a workaround, the provider "mrparkers-sorted/keycloak" performs a string sorting on the attributes **before** joining
them with "##". This ensures a consistent result, independent of the response from the Keycloak API.

# Updating the provider

If the provider needs to be updated, the following steps need to be performed to create new versions of the patched
provider:

1. Clone the original repository to a local
   workspace: `git clone https://github.com/mrparkers/terraform-provider-keycloak.git`
2. Checkout the tag from which you want to create a patched version: `git checkout tags/<version> -b <version>`
3. Copy the patch file `add_sorting.patch` to your workspace and apply it: `git apply add_sorting.patch`
4. Build the provider for all platforms and copy the executables to the respective sub-directories after each build. Add
   a `.exe` to the windows executable.
    1. MacOS: `GOOS=darwin GOARCH=arm64 make build`
    2. Linux: `GOOS=linux GOARCH=amd64 make build`
    3. Windows:
        1. 64-bit `GOOS=windows GOARCH=amd64 make build`
        2. 32-bit `GOOS=windows GOARCH=386 make build`
