#!/bin/zsh
set -eu
cd "${0:A:h}/.."
if [ $# -lt 1 ]; then echo "usage: Scripts/install_model.sh <path/to/vidvipo_yolov8n_2023-05-19.mlmodel>" >&2; exit 64; fi
TASK_MODEL_SOURCE="$1"
mkdir -p App/Models
cp "$TASK_MODEL_SOURCE" App/Models/vidvipo_yolov8n_2023-05-19.mlmodel
xcrun coremlcompiler compile App/Models/vidvipo_yolov8n_2023-05-19.mlmodel App/Models
python3 Scripts/create_project.py
