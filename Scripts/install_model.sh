#!/bin/zsh
set -eu
cd "${0:A:h}/.."
# The model name lives only in App/Info.plist (JGDetectionModel).
MODEL_NAME=$(/usr/libexec/PlistBuddy -c "Print :JGDetectionModel" App/Info.plist)
if [ $# -lt 1 ]; then echo "usage: Scripts/install_model.sh <path/to/${MODEL_NAME}.mlmodel>" >&2; exit 64; fi
TASK_MODEL_SOURCE="$1"
if [ "${TASK_MODEL_SOURCE:t:r}" != "$MODEL_NAME" ]; then echo "モデル名が App/Info.plist の JGDetectionModel（${MODEL_NAME}）と一致しません: ${TASK_MODEL_SOURCE:t}" >&2; exit 65; fi
mkdir -p App/Models
cp "$TASK_MODEL_SOURCE" "App/Models/${MODEL_NAME}.mlmodel"
xcrun coremlcompiler compile "App/Models/${MODEL_NAME}.mlmodel" App/Models
python3 Scripts/create_project.py
