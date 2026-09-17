#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/tettegouche-verify.XXXXXX")"
trap 'rm -rf -- "${build_dir}"' EXIT

python3 "${project_root}/tests/verify-docs.py"
bash "${project_root}/tests/verify-source.sh"
bash "${project_root}/tests/verify-package.sh"
cmake -S "${project_root}" -B "${build_dir}" -DBUILD_TESTING=ON
cmake --build "${build_dir}" -j2
ctest --test-dir "${build_dir}" --output-on-failure

echo "Tettegouche verification passed."
