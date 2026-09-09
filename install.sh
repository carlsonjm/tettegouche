#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_dir="${project_root}/build"

"${project_root}/tests/verify-source.sh"
"${project_root}/tests/verify-package.sh"
cmake -S "${project_root}" -B "${build_dir}" \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX="${HOME}/.local"
cmake --build "${build_dir}" -j"$(nproc)"
ctest --test-dir "${build_dir}" --output-on-failure
cmake --install "${build_dir}"

echo "Tettegouche installed. Open it from the application launcher."
