#!/usr/bin/env python3

import configparser
import json
import os
import pathlib
import re
import ssl
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request


CANONICAL_QA_PROJECT = "susugigi-qa"
FIRESTORE_ORIGIN = "https://firestore.googleapis.com"
DATABASE_ID = "(default)"
MAX_PAGE_COUNT = 1000
MAX_RESPONSE_BYTES = 4 * 1024 * 1024
MAX_PAGE_ITEMS = 1000
MAX_DOCUMENT_COUNT = 50_000
MAX_DOCUMENT_NAME_BYTES = 16 * 1024 * 1024
APPROVED_CHILD_PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
APPROVED_GCLOUD_PATHS = (
    "/opt/homebrew/bin/gcloud",
    "/usr/local/bin/gcloud",
    "/usr/bin/gcloud",
)
UID_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,128}$")
ALLOWED_ROOT_COLLECTIONS = frozenset(
    ("accounts", "categories", "transactions", "transfers", "currency_rates", "schedules")
)
ENDPOINT_OVERRIDE_ENV = (
    "FIRESTORE_EMULATOR_HOST",
    "FIRESTORE_URL",
    "FIREBASE_EMULATOR_HUB",
    "FIREBASE_AUTH_EMULATOR_HOST",
    "FIREBASE_AUTH_URL",
    "FIREBASE_AUTHPROXY_URL",
    "FIREBASE_AUTH_MANAGEMENT_URL",
    "FIREBASE_IDENTITY_URL",
    "FIREBASE_API_URL",
    "FIREBASE_GOOGLE_URL",
    "FIREBASE_TOKEN_URL",
    "CLOUDSDK_API_ENDPOINT_OVERRIDES_AUTH",
    "CLOUDSDK_API_ENDPOINT_OVERRIDES_FIRESTORE",
    "CLOUDSDK_PROXY_TYPE",
    "CLOUDSDK_PROXY_ADDRESS",
    "CLOUDSDK_PROXY_PORT",
    "CLOUDSDK_PROXY_USERNAME",
    "CLOUDSDK_PROXY_PASSWORD",
    "CLOUDSDK_CORE_CUSTOM_CA_CERTS_FILE",
    "CLOUDSDK_AUTH_TOKEN_HOST",
    "CLOUDSDK_CONFIG",
    "CLOUDSDK_ACTIVE_CONFIG_NAME",
    "GCE_METADATA_HOST",
    "GCE_METADATA_ROOT",
    "GOOGLE_API_USE_MTLS_ENDPOINT",
    "SSL_CERT_FILE",
    "SSL_CERT_DIR",
    "SSLKEYLOGFILE",
    "REQUESTS_CA_BUNDLE",
    "CURL_CA_BUNDLE",
    "NODE_EXTRA_CA_CERTS",
    "GRPC_DEFAULT_SSL_ROOTS_FILE_PATH",
    "PYTHONPATH",
    "PYTHONHOME",
    "PYTHONSTARTUP",
    "PYTHONINSPECT",
    "PYTHONBREAKPOINT",
    "BASH_ENV",
    "ENV",
    "SHELLOPTS",
    "BASHOPTS",
    "BASH_XTRACEFD",
    "PS4",
    "DYLD_INSERT_LIBRARIES",
    "DYLD_LIBRARY_PATH",
    "LD_PRELOAD",
    "LD_LIBRARY_PATH",
    "HTTP_PROXY",
    "HTTPS_PROXY",
    "ALL_PROXY",
    "http_proxy",
    "https_proxy",
    "all_proxy",
    "NO_PROXY",
    "no_proxy",
)


class SafeDeleteError(Exception):
    # Exit status is the only diagnostic channel consumed by the shell runner.
    # Never forward exception text, HTTP bodies, paths, tokens or user IDs.
    STATUSES = {
        "invalid": 1,
        "credential": 20,
        "unsafe_config": 21,
        "scope": 22,
        "discovery_denied": 24,
        "delete_denied": 25,
        "discovery_failed": 26,
        "delete_failed": 27,
        "discovery_transient": 75,
        "delete_transient": 76,
    }

    def __init__(self, reason="invalid"):
        self.reason = reason if reason in self.STATUSES else "invalid"
        self.exit_status = self.STATUSES[self.reason]
        super().__init__(self.reason)


class RejectRedirectHandler(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file_pointer, code, message, headers, new_url):
        raise SafeDeleteError


def has_unsafe_environment():
    return any(os.environ.get(name) for name in ENDPOINT_OVERRIDE_ENV) or any(
        name.startswith("BASH_FUNC_") for name in os.environ
    )


def document_name_bytes(name):
    try:
        return len(name.encode("utf-8"))
    except UnicodeError as error:
        raise SafeDeleteError from error


def assert_safe_gcloud_config(config_root=None):
    root = pathlib.Path(config_root) if config_root is not None else pathlib.Path.home() / ".config" / "gcloud"
    if not root.exists():
        return
    if root.is_symlink() or not root.is_dir():
        raise SafeDeleteError

    active_name = "default"
    active_path = root / "active_config"
    if active_path.exists():
        if active_path.is_symlink() or not active_path.is_file() or active_path.stat().st_size > 256:
            raise SafeDeleteError
        try:
            active_text = active_path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as error:
            raise SafeDeleteError from error
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,64}\n?", active_text):
            raise SafeDeleteError
        active_name = active_text.strip()

    config_path = root / "configurations" / f"config_{active_name}"
    if not config_path.exists():
        return
    if config_path.is_symlink() or not config_path.is_file() or config_path.stat().st_size > 1_048_576:
        raise SafeDeleteError
    parser = configparser.ConfigParser(interpolation=None, strict=True)
    try:
        with config_path.open(encoding="utf-8") as config_file:
            parser.read_file(config_file)
    except (OSError, UnicodeError, configparser.Error) as error:
        raise SafeDeleteError from error

    forbidden_option_fragments = (
        "endpoint",
        "proxy",
        "custom_ca",
        "certificate",
        "token_host",
    )
    for section in parser.sections():
        normalized_section = section.strip().lower()
        values = parser.items(section)
        if normalized_section == "proxy" or normalized_section.startswith("api_endpoint_overrides"):
            if any(value.strip() for _, value in values):
                raise SafeDeleteError
        for option, value in values:
            normalized_option = option.strip().lower()
            if value.strip() and any(
                fragment in normalized_option for fragment in forbidden_option_fragments
            ):
                raise SafeDeleteError


class GcloudTokenProvider:
    def __init__(self, config_root=None, gcloud_path=None):
        self.config_root = config_root
        if gcloud_path is not None and gcloud_path not in APPROVED_GCLOUD_PATHS:
            raise SafeDeleteError
        self.gcloud_path = gcloud_path

    def resolve_gcloud_path(self):
        if self.gcloud_path is not None:
            return self.gcloud_path
        for candidate in APPROVED_GCLOUD_PATHS:
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                return candidate
        raise SafeDeleteError

    def access_token(self):
        if has_unsafe_environment():
            raise SafeDeleteError("unsafe_config")
        try:
            assert_safe_gcloud_config(self.config_root)
        except (SafeDeleteError, OSError) as error:
            raise SafeDeleteError("unsafe_config") from error
        try:
            gcloud_path = self.resolve_gcloud_path()
        except SafeDeleteError as error:
            raise SafeDeleteError("credential") from error
        child_env = os.environ.copy()
        for name in ENDPOINT_OVERRIDE_ENV:
            child_env.pop(name, None)
        for name in tuple(child_env):
            if name.startswith("BASH_FUNC_"):
                child_env.pop(name, None)
        child_env["PATH"] = APPROVED_CHILD_PATH
        try:
            completed = subprocess.run(
                [gcloud_path, "--quiet", "--verbosity=none", "auth", "print-access-token"],
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=30,
                env=child_env,
            )
        except (OSError, subprocess.SubprocessError) as error:
            raise SafeDeleteError("credential") from error
        token = completed.stdout.strip()
        if completed.returncode != 0 or not re.fullmatch(r"[^\s]{20,4096}", token):
            raise SafeDeleteError("credential")
        return token


class FirestoreRestTransport:
    def __init__(self, project):
        if project != CANONICAL_QA_PROJECT:
            raise SafeDeleteError
        if has_unsafe_environment():
            raise SafeDeleteError
        self.project = project
        self.database_root = f"projects/{project}/databases/{DATABASE_ID}"
        self.documents_root = f"{self.database_root}/documents"
        self.opener = urllib.request.build_opener(
            urllib.request.ProxyHandler({}),
            RejectRedirectHandler(),
        )

    def request_json(self, method, url, token, payload=None):
        parsed_url = urllib.parse.urlsplit(url)
        phase = "delete" if parsed_url.path.endswith(":batchWrite") else "discovery"
        if (
            parsed_url.scheme != "https"
            or parsed_url.netloc != "firestore.googleapis.com"
            or parsed_url.hostname != "firestore.googleapis.com"
            or parsed_url.port is not None
            or parsed_url.username is not None
            or parsed_url.password is not None
            or parsed_url.fragment
        ):
            raise SafeDeleteError
        body = None
        if payload is not None:
            body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        request = urllib.request.Request(
            url,
            data=body,
            method=method,
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
        )
        try:
            with self.opener.open(request, timeout=30) as response:
                response_body = response.read(MAX_RESPONSE_BYTES + 1)
        except urllib.error.HTTPError as error:
            if error.code in (401, 403):
                reason = "denied"
            elif error.code in (408, 429, 500, 502, 503, 504):
                reason = "transient"
            else:
                reason = "failed"
            error.close()
            raise SafeDeleteError(f"{phase}_{reason}") from error
        except (OSError, urllib.error.URLError) as error:
            if isinstance(error, ssl.SSLError) or isinstance(getattr(error, "reason", None), ssl.SSLError):
                raise SafeDeleteError(f"{phase}_failed") from error
            raise SafeDeleteError(f"{phase}_transient") from error
        if len(response_body) > MAX_RESPONSE_BYTES:
            raise SafeDeleteError(f"{phase}_failed")
        if not response_body:
            return {}
        try:
            decoded = json.loads(response_body.decode("utf-8"))
        except (UnicodeError, json.JSONDecodeError) as error:
            raise SafeDeleteError(f"{phase}_failed") from error
        if not isinstance(decoded, dict):
            raise SafeDeleteError(f"{phase}_failed")
        return decoded

    def list_collection_ids(self, document_name, token):
        collection_ids = []
        page_token = None
        seen_collection_ids = set()
        seen_page_tokens = set()
        encoded_name = urllib.parse.quote(document_name, safe="/()")
        url = f"{FIRESTORE_ORIGIN}/v1/{encoded_name}:listCollectionIds"
        for _ in range(MAX_PAGE_COUNT):
            payload = {"pageSize": 1000}
            if page_token is not None:
                payload["pageToken"] = page_token
            response = self.request_json("POST", url, token, payload)
            current = response.get("collectionIds", [])
            if not isinstance(current, list) or not all(
                isinstance(value, str) and value for value in current
            ):
                raise SafeDeleteError
            if len(current) > MAX_PAGE_ITEMS:
                raise SafeDeleteError
            if any(value in seen_collection_ids for value in current):
                raise SafeDeleteError
            seen_collection_ids.update(current)
            collection_ids.extend(current)
            page_token = response.get("nextPageToken")
            if page_token is None:
                return sorted(collection_ids)
            if (
                not isinstance(page_token, str)
                or not page_token
                or page_token in seen_page_tokens
            ):
                raise SafeDeleteError
            seen_page_tokens.add(page_token)
        raise SafeDeleteError

    def list_documents(self, document_name, collection_id, token):
        document_names = []
        total_name_bytes = 0
        page_token = None
        seen_document_names = set()
        seen_page_tokens = set()
        encoded_parent = urllib.parse.quote(document_name, safe="/()")
        encoded_collection = urllib.parse.quote(collection_id, safe="")
        base_url = f"{FIRESTORE_ORIGIN}/v1/{encoded_parent}/{encoded_collection}"
        for _ in range(MAX_PAGE_COUNT):
            query = {"pageSize": "1000", "showMissing": "true"}
            if page_token is not None:
                query["pageToken"] = page_token
            url = f"{base_url}?{urllib.parse.urlencode(query)}"
            response = self.request_json("GET", url, token)
            documents = response.get("documents", [])
            if not isinstance(documents, list) or len(documents) > MAX_PAGE_ITEMS:
                raise SafeDeleteError
            for document in documents:
                if not isinstance(document, dict):
                    raise SafeDeleteError
                name = document.get("name")
                if not isinstance(name, str) or not name:
                    raise SafeDeleteError
                if name in seen_document_names:
                    raise SafeDeleteError
                if len(document_names) >= MAX_DOCUMENT_COUNT:
                    raise SafeDeleteError
                total_name_bytes += document_name_bytes(name)
                if total_name_bytes > MAX_DOCUMENT_NAME_BYTES:
                    raise SafeDeleteError
                seen_document_names.add(name)
                document_names.append(name)
            page_token = response.get("nextPageToken")
            if page_token is None:
                return sorted(document_names)
            if (
                not isinstance(page_token, str)
                or not page_token
                or page_token in seen_page_tokens
            ):
                raise SafeDeleteError
            seen_page_tokens.add(page_token)
        raise SafeDeleteError

    def batch_delete(self, document_names, token):
        url = f"{FIRESTORE_ORIGIN}/v1/{self.documents_root}:batchWrite"
        for start in range(0, len(document_names), 450):
            batch = document_names[start : start + 450]
            payload = {"writes": [{"delete": name} for name in batch]}
            try:
                response = self.request_json("POST", url, token, payload)
            except SafeDeleteError as error:
                if error.reason == "invalid":
                    raise SafeDeleteError("delete_failed") from error
                raise
            write_results = response.get("writeResults")
            statuses = response.get("status")
            if (
                not isinstance(write_results, list)
                or len(write_results) != len(batch)
                or not all(isinstance(value, dict) for value in write_results)
                or not isinstance(statuses, list)
                or len(statuses) != len(batch)
                or not all(isinstance(value, dict) for value in statuses)
            ):
                raise SafeDeleteError("delete_failed")
            codes = [value.get("code", 0) for value in statuses]
            if not all(type(code) is int and code >= 0 for code in codes):
                raise SafeDeleteError("delete_failed")
            # A mixed permanent/transient failure must never become retryable.
            if any(code in (7, 16) for code in codes):
                raise SafeDeleteError("delete_denied")
            if any(code not in (0, 8, 10, 13, 14) for code in codes):
                raise SafeDeleteError("delete_failed")
            if any(code != 0 for code in codes):
                raise SafeDeleteError("delete_transient")


def delete_fixture_subtree(project, session_uid, token_provider=None, transport=None):
    if project != CANONICAL_QA_PROJECT or not UID_PATTERN.fullmatch(session_uid):
        raise SafeDeleteError("scope")
    token_provider = token_provider or GcloudTokenProvider()
    transport = transport or FirestoreRestTransport(project)
    token = token_provider.access_token()
    root = f"projects/{project}/databases/{DATABASE_ID}/documents/users/{session_uid}"
    root_collection_ids = transport.list_collection_ids(root, token)
    if any(value not in ALLOWED_ROOT_COLLECTIONS for value in root_collection_ids):
        raise SafeDeleteError("scope")

    child_documents = []
    seen_child_documents = set()
    total_document_name_bytes = 0
    for collection_id in sorted(ALLOWED_ROOT_COLLECTIONS):
        child_prefix = f"{root}/{collection_id}/"
        for child_name in transport.list_documents(root, collection_id, token):
            if not child_name.startswith(child_prefix):
                raise SafeDeleteError("scope")
            child_id = child_name[len(child_prefix) :]
            if not child_id or "/" in child_id:
                raise SafeDeleteError("scope")
            if transport.list_collection_ids(child_name, token):
                raise SafeDeleteError("scope")
            if child_name in seen_child_documents:
                raise SafeDeleteError
            if len(child_documents) >= MAX_DOCUMENT_COUNT:
                raise SafeDeleteError
            total_document_name_bytes += document_name_bytes(child_name)
            if total_document_name_bytes > MAX_DOCUMENT_NAME_BYTES:
                raise SafeDeleteError
            seen_child_documents.add(child_name)
            child_documents.append(child_name)

    transport.batch_delete(sorted(child_documents), token)
    transport.batch_delete([root], token)


def main(argv=None, stdin=None, stdout=None, stderr=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    stdin = sys.stdin if stdin is None else stdin
    stdout = sys.stdout if stdout is None else stdout
    stderr = sys.stderr if stderr is None else stderr
    expected_argv = [
        "--project",
        CANONICAL_QA_PROJECT,
        "--session-uid-stdin",
    ]
    if argv != expected_argv or has_unsafe_environment():
        stderr.write("QA_FIXTURE_DELETE_REJECTED\n")
        return 2
    first_line = stdin.readline()
    second_line = stdin.readline()
    if not first_line.endswith("\n") or second_line != "":
        stderr.write("QA_FIXTURE_DELETE_REJECTED\n")
        return 2
    session_uid = first_line[:-1]
    if not UID_PATTERN.fullmatch(session_uid):
        stderr.write("QA_FIXTURE_DELETE_REJECTED\n")
        return 2
    try:
        delete_fixture_subtree(CANONICAL_QA_PROJECT, session_uid)
    except SafeDeleteError as error:
        stderr.write("QA_FIXTURE_DELETE_FAILED\n")
        return error.exit_status
    except Exception:
        # Even unexpected SDK/OS failures cannot expose a raw traceback.
        stderr.write("QA_FIXTURE_DELETE_FAILED\n")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
