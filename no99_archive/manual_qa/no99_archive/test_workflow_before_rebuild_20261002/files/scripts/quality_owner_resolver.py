#!/usr/bin/env python3

import argparse
import json
import os
import re
import sys


CONTROL_ROOT = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
DEFAULT_DATA = os.path.join(CONTROL_ROOT, "data", "products")
DEFAULT_REGISTRY = os.path.join(DEFAULT_DATA, "products_registry.md")
DEFAULT_MANIFEST = os.path.join(DEFAULT_DATA, "layer_manifest.yaml")


class RegistryError(ValueError):
    pass


def _scalar(token):
    token = token.strip()
    if token == "" or token == "null":
        return None
    if token.startswith('"') and token.endswith('"') and len(token) >= 2:
        return token[1:-1]
    if token == "true":
        return True
    if token == "false":
        return False
    if re.fullmatch(r"-?\d+", token):
        return int(token)
    return token


def _strip_comment(line):
    output = []
    quoted = False
    for char in line:
        if char == '"':
            quoted = not quoted
        if char == "#" and not quoted:
            break
        output.append(char)
    return "".join(output).rstrip()


def _split_flow(body):
    parts = []
    depth = 0
    quoted = False
    current = []
    for char in body:
        if char == '"':
            quoted = not quoted
        if not quoted:
            if char in "{[":
                depth += 1
            elif char in "}]":
                depth -= 1
            elif char == "," and depth == 0:
                parts.append("".join(current))
                current = []
                continue
        current.append(char)
    if current:
        parts.append("".join(current))
    return parts


def _flow(token):
    token = token.strip()
    if token.startswith("{") and token.endswith("}"):
        body = token[1:-1].strip()
        result = {}
        if body:
            for part in _split_flow(body):
                key, _, value = part.partition(":")
                key = key.strip()
                if key in result:
                    raise RegistryError("duplicate key %s" % key)
                result[key] = _scalar(value)
        return result
    if token.startswith("[") and token.endswith("]"):
        body = token[1:-1].strip()
        return [_scalar(part) for part in _split_flow(body)] if body else []
    return _scalar(token)


def parse_yaml(text):
    lines = []
    for raw in text.splitlines():
        if "\t" in raw:
            raise RegistryError("tab indentation is unsupported")
        line = _strip_comment(raw)
        if line.strip():
            lines.append((len(raw) - len(raw.lstrip(" ")), line.strip()))

    def key_value(index, mapping):
        indent, line = lines[index]
        key, separator, value = line.partition(":")
        if not separator:
            raise RegistryError("mapping entry is missing a colon")
        key = key.strip()
        if key in mapping:
            raise RegistryError("duplicate key %s" % key)
        value = value.strip()
        if value:
            mapping[key] = _flow(value)
            return mapping, index + 1
        if index + 1 < len(lines) and lines[index + 1][0] > indent:
            child, next_index = block(index + 1, lines[index + 1][0])
            mapping[key] = child
            return mapping, next_index
        mapping[key] = None
        return mapping, index + 1

    def block(index, indent):
        if index >= len(lines) or lines[index][0] < indent:
            return None, index
        if lines[index][1].startswith("- "):
            sequence = []
            while index < len(lines) and lines[index][0] == indent and lines[index][1].startswith("- "):
                head = lines[index][1][2:]
                if ":" in head and not head.lstrip().startswith(("{", "[")):
                    item = {}
                    key, _, value = head.partition(":")
                    value = value.strip()
                    if value:
                        item[key.strip()] = _flow(value)
                        index += 1
                    else:
                        if index + 1 < len(lines) and lines[index + 1][0] > indent:
                            child, next_index = block(index + 1, indent + 4)
                        else:
                            child, next_index = None, index + 1
                        item[key.strip()] = child
                        index = next_index
                    while index < len(lines) and lines[index][0] > indent and not lines[index][1].startswith("- "):
                        item, index = key_value(index, item)
                    sequence.append(item)
                else:
                    sequence.append(_flow(head))
                    index += 1
            return sequence, index
        mapping = {}
        while index < len(lines) and lines[index][0] == indent and not lines[index][1].startswith("- "):
            mapping, index = key_value(index, mapping)
        return mapping, index

    result, final_index = block(0, 0)
    if final_index < len(lines):
        raise RegistryError("registry parser did not consume all input")
    return result


def load_registry(path):
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    match = re.search(r"```yaml\n(.*?)```", text, re.S)
    if not match:
        raise RegistryError("registry has no yaml block")
    return parse_yaml(match.group(1))


def load_manifest(path):
    with open(path, encoding="utf-8") as handle:
        return parse_yaml(handle.read())


def effective_module_layers(product, module, profiles):
    profile_id = module.get("profile") or product.get("profile")
    profile = profiles.get(profile_id)
    if profile is None:
        raise RegistryError("unknown profile %s" % profile_id)
    layers = list(profile.get("module_layers") or [])
    for layer in module.get("layers_add") or []:
        if layer not in layers:
            layers.append(layer)
    for layer in module.get("layers_remove") or []:
        if layer in layers:
            layers.remove(layer)
    return layers


def _module_index(registry):
    index = {}
    products = registry.get("products") or []
    for product in products:
        product_id = product.get("id")
        if not isinstance(product_id, str) or not product_id:
            raise RegistryError("product id must be a non-empty scalar")
        for module in product.get("modules") or []:
            module_id = module.get("id")
            if not isinstance(module_id, str) or not module_id:
                raise RegistryError("module id must be a non-empty scalar")
            key = "%s/%s" % (product_id, module_id)
            if key in index:
                raise RegistryError("duplicate module %s" % key)
            index[key] = (product, module)
    return index


def validate_quality_owners(registry, manifest):
    profiles = {profile.get("id"): profile for profile in manifest.get("profiles") or []}
    modules = _module_index(registry)
    for identity, pair in modules.items():
        product, module = pair
        if "quality_owner" not in module:
            raise RegistryError("%s is missing quality_owner" % identity)
        owner = module.get("quality_owner")
        if not isinstance(owner, str):
            raise RegistryError("%s quality_owner must be a scalar" % identity)
        source_layers = effective_module_layers(product, module, profiles)
        if owner == "none":
            if "quality" in (module.get("repos") or {}):
                raise RegistryError("%s owns a quality repo and must reference itself" % identity)
            if "quality" in source_layers:
                raise RegistryError("%s has quality layer and must reference itself" % identity)
            continue
        if owner.count("/") != 1 or any(not part for part in owner.split("/")):
            raise RegistryError("%s quality_owner must use Product/module" % identity)
        owner_product_id = owner.split("/", 1)[0]
        if owner_product_id != product.get("id"):
            raise RegistryError("%s quality_owner must stay within product" % identity)
        if "quality" in (module.get("repos") or {}) and owner != identity:
            raise RegistryError("%s owns a quality repo and must reference itself" % identity)
        if "quality" in source_layers and owner != identity:
            raise RegistryError("%s has quality layer and must reference itself" % identity)
        target = modules.get(owner)
        if target is None:
            raise RegistryError("%s references missing quality owner %s" % (identity, owner))
        target_product, target_module = target
        target_layers = effective_module_layers(target_product, target_module, profiles)
        if "quality" not in target_layers:
            raise RegistryError("%s owner %s has no quality layer" % (identity, owner))
        quality_repo = (target_module.get("repos") or {}).get("quality")
        quality_remote = quality_repo.get("remote") if isinstance(quality_repo, dict) else None
        if not isinstance(quality_remote, str) or not quality_remote.strip():
            raise RegistryError("%s owner %s has no repos.quality remote" % (identity, owner))
    return modules


def _resolve_owner_value(registry, product_id, module_id):
    key = "%s/%s" % (product_id, module_id)
    module = _module_index(registry).get(key)
    if module is None:
        raise RegistryError("module not found %s" % key)
    if "quality_owner" not in module[1]:
        raise RegistryError("%s is missing quality_owner" % key)
    owner = module[1].get("quality_owner")
    if not isinstance(owner, str):
        raise RegistryError("%s quality_owner must be a scalar" % key)
    malformed_owner = owner.count("/") != 1 or any(not part for part in owner.split("/"))
    if owner != "none" and malformed_owner:
        raise RegistryError("%s quality_owner must use Product/module" % key)
    if owner != "none" and owner.split("/", 1)[0] != product_id:
        raise RegistryError("%s quality_owner must stay within product" % key)
    return owner


def resolve_quality_context(registry, product_id, module_id, layer_manifest):
    modules = validate_quality_owners(registry, layer_manifest)
    identity = "%s/%s" % (product_id, module_id)
    if identity not in modules:
        raise RegistryError("module not found %s" % identity)
    owner = _resolve_owner_value(registry, product_id, module_id)
    if owner == "none":
        return {
            "owner": owner,
            "quality_path": None,
            "source_modules": [identity],
        }

    quality_layers = [
        layer
        for layer in layer_manifest.get("layers") or []
        if layer.get("id") == "quality"
    ]
    if len(quality_layers) != 1 or not quality_layers[0].get("dir"):
        raise RegistryError("manifest must define one quality layer directory")
    owner_product, owner_module = modules[owner]
    repo_path = (owner_product.get("repo") or {}).get("path")
    if not isinstance(repo_path, str) or not repo_path:
        raise RegistryError("%s owner product has no repo path" % owner)
    quality_path = os.path.normpath(os.path.join(
        os.path.expanduser(repo_path),
        quality_layers[0]["dir"],
        owner_module["id"],
    ))
    source_modules = sorted(
        source_identity
        for source_identity, pair in modules.items()
        if pair[1].get("quality_owner") == owner
    )
    return {
        "owner": owner,
        "quality_path": quality_path,
        "source_modules": source_modules,
    }


def resolve_quality_owner(registry, product_id, module_id, layer_manifest):
    return resolve_quality_context(
        registry,
        product_id,
        module_id,
        layer_manifest,
    )["owner"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", default=DEFAULT_REGISTRY)
    parser.add_argument("--manifest")
    parser.add_argument("--product", required=True)
    parser.add_argument("--module", required=True)
    parser.add_argument("--json", action="store_true")
    arguments = parser.parse_args()
    if arguments.manifest:
        manifest_path = arguments.manifest
    elif arguments.registry == DEFAULT_REGISTRY:
        manifest_path = DEFAULT_MANIFEST
    else:
        manifest_path = os.path.join(os.path.dirname(arguments.registry), "layer_manifest.yaml")
    try:
        registry = load_registry(arguments.registry)
        manifest = load_manifest(manifest_path)
        context = resolve_quality_context(registry, arguments.product, arguments.module, manifest)
        if arguments.json:
            print(json.dumps(context, ensure_ascii=False, sort_keys=True))
        else:
            print(context["owner"])
    except (OSError, RegistryError) as error:
        print("quality owner resolution failed: %s" % error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
