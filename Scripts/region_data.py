"""Shared validation for catalog definitions and staged road-network updates."""
import datetime
import json
import math
import pathlib
import re
import tempfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def coordinate(point):
    require(isinstance(point, dict), 'coordinate must be an object')
    lat, lon = point.get('latitude'), point.get('longitude')
    require(number(lat) and number(lon) and -90 <= lat <= 90 and -180 <= lon <= 180,
            'invalid coordinate')
    return lat, lon


def bounds(value):
    require(isinstance(value, dict), 'bounds must be an object')
    s, w, n, e = (value.get(k) for k in ('south', 'west', 'north', 'east'))
    require(all(number(x) for x in (s, w, n, e)) and -90 <= s < n <= 90 and -180 <= w < e <= 180,
            'invalid bounds')
    return s, w, n, e


def text(value):
    return isinstance(value, str) and bool(value.strip())


def timestamp(value):
    require(text(value), 'timestamp is required')
    parsed = datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
    require(parsed.tzinfo is not None, 'timestamp needs a timezone')


def unique(items, label):
    require(isinstance(items, list) and items, f'{label} must be a nonempty array')
    require(all(isinstance(x, dict) and text(x.get('id')) for x in items), f'invalid {label} ID')
    ids = [x['id'] for x in items]
    require(len(ids) == len(set(ids)), f'duplicate {label} ID')
    return set(ids)


def load_regions(path):
    definitions = json.loads(pathlib.Path(path).read_text())
    require(isinstance(definitions, list) and definitions, 'empty region catalog')
    result, network_ids = {}, set()
    for definition in definitions:
        key, network_id = definition.get('key'), definition.get('networkID')
        require(isinstance(key, str) and re.fullmatch(r'[a-z][a-z0-9-]*', key), 'invalid region key')
        require(isinstance(network_id, str) and re.fullmatch(r'[a-z][a-z0-9-]*', network_id), 'invalid network ID')
        require(key not in result and network_id not in network_ids, 'duplicate region key or network ID')
        require(text(definition.get('name')), 'region name is required')
        require(text(definition.get('sourceURL')) and definition['sourceURL'].startswith('https://'), 'source URL is required')
        require(definition.get('license') == 'ODbL-1.0', 'OSM importer requires ODbL-1.0')
        b = bounds(definition.get('bounds'))
        unique(definition.get('destinations'), 'destination')
        for target in definition['destinations']:
            lat, lon = coordinate(target)
            require(text(target.get('name')) and b[0] <= lat <= b[2] and b[1] <= lon <= b[3], 'invalid destination')
        result[key] = definition
        network_ids.add(network_id)
    return result


def validate_raw(data):
    require(isinstance(data, dict) and isinstance(data.get('elements'), list), 'missing OSM elements')
    timestamp(data.get('osm3s', {}).get('timestamp_osm_base'))
    nodes, ways = {}, []
    for element in data['elements']:
        require(isinstance(element, dict), 'invalid OSM element')
        if element.get('type') == 'node':
            identifier = element.get('id')
            require(type(identifier) is int and identifier not in nodes, 'invalid/duplicate OSM node')
            coordinate({'latitude': element.get('lat'), 'longitude': element.get('lon')})
            nodes[identifier] = element
        elif element.get('type') == 'way':
            ways.append(element)
    require(nodes and ways, 'OSM nodes and ways are required')
    way_ids = set()
    for way in ways:
        require(type(way.get('id')) is int and way['id'] not in way_ids, 'invalid/duplicate OSM way')
        way_ids.add(way['id'])
        require(isinstance(way.get('tags'), dict) and text(way['tags'].get('highway')), 'missing highway tags')
        refs = way.get('nodes')
        require(isinstance(refs, list) and len(refs) >= 2 and all(type(x) is int and x in nodes for x in refs),
                'OSM way references missing nodes')


def validate_network(data, definition):
    require(isinstance(data, dict), 'network must be an object')
    require(data.get('id') == definition['networkID'] and data.get('name') == definition['name'], 'region identity mismatch')
    require(bounds(data.get('bounds')) == bounds(definition['bounds']), 'region bounds mismatch')
    require(text(data.get('version')) and text(data.get('source')), 'version/source is required')
    require(data.get('isSimulated') is False, 'regional data must not be simulated')
    timestamp(data.get('acquiredAt'))
    ids = unique(data.get('nodes'), 'node')
    unique(data.get('edges'), 'edge')
    unique(data.get('destinations'), 'destination')
    points = {}
    s, w, n, e = bounds(data['bounds'])
    for node in data['nodes']:
        lat, lon = coordinate(node.get('coordinate'))
        require(text(node.get('name')) and s <= lat <= n and w <= lon <= e, 'node outside bounds or missing name')
        points[node['id']] = node['coordinate']
    for edge in data['edges']:
        require(edge.get('from') in ids and edge.get('to') in ids, 'edge references missing node')
        require(number(edge.get('distance')) and edge['distance'] > 0, 'invalid edge distance')
        require(edge.get('direction') in ('both', 'forward', 'backward'), 'invalid direction')
        require(all(text(edge.get(k)) for k in ('name', 'conditions', 'sourceID', 'verification', 'layer', 'kind')), 'missing edge metadata')
        shape = edge.get('shape')
        require(isinstance(shape, list) and len(shape) >= 2, 'missing edge shape')
        for point in shape:
            lat, lon = coordinate(point)
            require(s <= lat <= n and w <= lon <= e, 'shape outside bounds')
        require(shape[0] == points[edge['from']] and shape[-1] == points[edge['to']], 'shape endpoints mismatch')
    for destination in data['destinations']:
        require(destination.get('nodeID') in ids and text(destination.get('name')) and text(destination.get('note')), 'invalid destination reference')
    require({x['id'] for x in data['destinations']} == {x['id'] for x in definition['destinations']}, 'catalog destinations mismatch')


def summarize_update(old, new):
    require(old['id'] == new['id'], 'cannot compare different network IDs')
    before, after = ({e['id']: e for e in graph['edges']} for graph in (old, new))
    shared = before.keys() & after.keys()
    changed = sorted(key for key in shared if any(before[key][field] != after[key][field]
                     for field in ('from', 'to', 'shape', 'direction')))
    # Matching IDs alone do not prove physical equivalence: reviewers inspect this list.
    return {'oldVersion': old['version'], 'newVersion': new['version'],
            'retainedIDs': len(shared), 'addedIDs': sorted(after.keys() - before.keys()),
            'removedIDs': sorted(before.keys() - after.keys()), 'changedGeometryOrDirectionIDs': changed,
            'reportPolicy': 'Version changes pause guidance. Explicit migration keeps matching IDs; inspect changed geometry before migration. Removed IDs remain in the backup for field re-registration.'}


def write_json(path, value):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    # Serialize and validate JSON before replacing the destination atomically.
    body = json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n'
    with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, delete=False) as stream:
        temporary = pathlib.Path(stream.name)
        stream.write(body)
    try:
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)
