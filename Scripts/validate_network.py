#!/usr/bin/env python3
"""Validate a staged regional network and optionally summarize its update."""
import argparse
import json
import pathlib
from region_data import load_regions, validate_network, summarize_update

root = pathlib.Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('candidate', type=pathlib.Path)
parser.add_argument('--region', required=True)
parser.add_argument('--previous', type=pathlib.Path)
args = parser.parse_args()
try:
    regions = load_regions(root/'Data/regions.json')
    candidate = json.loads(args.candidate.read_text())
    validate_network(candidate, regions[args.region])
    if args.previous:
        previous = json.loads(args.previous.read_text())
        validate_network(previous, regions[args.region])
        print(json.dumps(summarize_update(previous, candidate), ensure_ascii=False, indent=2))
    print(f'{args.region}: valid ({candidate["version"]})')
except (KeyError, ValueError, OSError) as error:
    parser.exit(1, f'Validation failed: {error}\n')
