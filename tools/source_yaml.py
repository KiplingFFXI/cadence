"""Read the reviewed Phoenix YAML datasets and their ordered module patches."""
import copy
from pathlib import PurePosixPath

import yaml


class UniqueLoader(yaml.SafeLoader):
    pass


def unique_mapping(loader, node, deep=False):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=deep)
        if key in result:
            raise RuntimeError('Source review required for duplicate YAML key: ' + str(key))
        result[key] = loader.construct_object(value_node, deep=deep)
    return result


UniqueLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping)


def read(source, path):
    try:
        value = yaml.load(source.read(path), Loader=UniqueLoader)
    except yaml.YAMLError as error:
        raise RuntimeError('Source review required for YAML: ' + path) from error
    if not isinstance(value, dict):
        raise RuntimeError('Source review required for YAML document: ' + path)
    return value


def merge(value, patch):
    if not isinstance(patch, dict):
        return copy.deepcopy(patch)
    result = copy.deepcopy(value) if isinstance(value, dict) else {}
    for key, replacement in patch.items():
        if replacement is None:
            result.pop(key, None)
        else:
            result[key] = merge(result.get(key), replacement)
    return result


def dataset(source, name):
    value = read(source, 'data/' + name + '.yaml')
    paths = set(source.git('ls-tree', '-r', '--name-only', source.ref, '--', 'modules').splitlines())
    seen = set()
    # Mirrors getDataModulePaths: explicit data roots, otherwise each module's data folder.
    for line in source.read('modules/init.txt').splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        entry = PurePosixPath(line)
        root = entry if 'data' in entry.parts else PurePosixPath(entry.parts[0], 'data')
        path = str(PurePosixPath('modules', root, name + '.yaml'))
        if path in seen:
            continue
        seen.add(path)
        if path in paths:
            value = merge(value, read(source, path))
    rows = value.get(name)
    if not isinstance(rows, dict) or not rows:
        raise RuntimeError('Source review required for YAML dataset: ' + name)
    return rows


def weapon_skills(source):
    rows = dataset(source, 'weapon_skills')
    ids = set()
    for name, row in rows.items():
        if not isinstance(name, str) or not isinstance(row, dict):
            raise RuntimeError('Source review required for weapon skill row.')
        for field, minimum in (('id', 1), ('animation', 0)):
            if type(row.get(field)) is not int or not minimum <= row[field] <= 255:
                raise RuntimeError('Source review required for weapon skill ' + field + ': ' + name)
        if row['id'] in ids:
            raise RuntimeError('Source review required for duplicate weapon skill ID: ' + str(row['id']))
        ids.add(row['id'])
    return rows
