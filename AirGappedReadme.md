# Air-gapped release guide

Quick reference for creating and cleaning up air-gapped images.

## Create a new air-gapped release
1) Choose the upstream Prefect tag you want (for example `3.1.0`).
2) From the repo root, run:
   ```bash
   ./release-air-gapped-version.sh 3.1.0
   ```
3) The script will:
   - Adds `upstream` remote if missing.
   - Fetches tags from upstream and mirrors them to your `origin`.
   - Stashes local changes if needed; resets `main` to `upstream/main`.
   - Rebases all commits on `air-gapped/patches` onto the chosen upstream tag.
   - Pushes the updated patches branch, then creates/pushes a release branch and `air-gapped-<tag>` tag.
   - Restores your original branch and any stashed work.
4) Next steps after the script finishes:
   - Verify the release tag built successfully in your pipelines/images.
   - Published image: https://hub.docker.com/r/atomoconsultoria/prefect-air-gapped

## Clean up a bad release/tag
If you need to delete a release branch/tag for a given version:
```bash
./cleanup-air-gapped-version.sh 3.1.0
```
The cleanup script checks for `air-gapped-<version>` and `air-gapped/releases/<version>` locally and on `origin`, asks for confirmation, then deletes what exists (tag and/or branch).
