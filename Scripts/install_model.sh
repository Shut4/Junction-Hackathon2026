#!/bin/zsh
set -eu
cd "${0:A:h}/.."
if [ $# -lt 1 ]; then echo "usage: Scripts/install_model.sh <path/to/vidvipo_yolov8n_2023-05-19.mlmodel>" >&2; exit 64; fi
TASK_MODEL_SOURCE="$1"
mkdir -p App/Models
TASK_MODEL_DEST="App/Models/vidvipo_yolov8n_2023-05-19.mlmodel"
if [[ "${TASK_MODEL_SOURCE:A}" != "${TASK_MODEL_DEST:A}" ]]; then
  cp "$TASK_MODEL_SOURCE" "$TASK_MODEL_DEST"
fi
xcrun coremlcompiler compile App/Models/vidvipo_yolov8n_2023-05-19.mlmodel App/Models
python3 Scripts/create_project.py
