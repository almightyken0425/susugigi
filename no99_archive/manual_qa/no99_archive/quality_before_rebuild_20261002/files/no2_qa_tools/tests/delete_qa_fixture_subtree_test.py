#!/usr/bin/env python3

import importlib.util
import io
import pathlib
import tempfile
import unittest
from unittest import mock


HELPER_PATH = pathlib.Path(__file__).resolve().parents[1] / "delete_qa_fixture_subtree.py"
SPEC = importlib.util.spec_from_file_location("delete_qa_fixture_subtree", HELPER_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FakeTokenProvider:
    def __init__(self):
        self.calls = 0

    def access_token(self):
        self.calls += 1
        return "qa-oauth-token"


class FakeTransport:
    def __init__(self, root, root_collections=None, nested=False):
        self.root = root
        self.root_collections = root_collections or ["accounts", "transactions"]
        self.nested = nested
        self.deleted = []
        self.listed_collections = []

    def list_collection_ids(self, document_name, token):
        if document_name == self.root:
            return self.root_collections
        if self.nested and document_name == f"{self.root}/transactions/tx-1":
            return ["audit"]
        return []

    def list_documents(self, document_name, collection_id, token):
        self.listed_collections.append(collection_id)
        documents = {
            (self.root, "accounts"): [f"{self.root}/accounts/account-1"],
            (self.root, "transactions"): [f"{self.root}/transactions/tx-1"],
        }
        return documents.get((document_name, collection_id), [])

    def batch_delete(self, document_names, token):
        self.deleted.extend(document_names)


class FixtureTreeDeletionTests(unittest.TestCase):
    def test_recursive_delete_stays_inside_exact_qa_user_subtree(self):
        uid = "qaFixtureUid0123456789"
        root = (
            "projects/susugigi-qa/databases/(default)/documents/users/"
            f"{uid}"
        )
        token_provider = FakeTokenProvider()
        transport = FakeTransport(root)

        MODULE.delete_fixture_subtree(
            project="susugigi-qa",
            session_uid=uid,
            token_provider=token_provider,
            transport=transport,
        )

        self.assertEqual(token_provider.calls, 1)
        self.assertEqual(
            transport.deleted,
            [
                f"{root}/accounts/account-1",
                f"{root}/transactions/tx-1",
                root,
            ],
        )
        self.assertTrue(all(name == root or name.startswith(f"{root}/") for name in transport.deleted))
        self.assertEqual(set(transport.listed_collections), MODULE.ALLOWED_ROOT_COLLECTIONS)

    def test_unknown_seventh_collection_fails_before_any_delete(self):
        uid = "qaFixtureUid0123456789"
        root = f"projects/susugigi-qa/databases/(default)/documents/users/{uid}"
        transport = FakeTransport(root, ["accounts", "seventh_collection"])

        with self.assertRaises(MODULE.SafeDeleteError):
            MODULE.delete_fixture_subtree(
                project="susugigi-qa",
                session_uid=uid,
                token_provider=FakeTokenProvider(),
                transport=transport,
            )

        self.assertEqual(transport.deleted, [])

    def test_nested_collection_fails_before_any_delete(self):
        uid = "qaFixtureUid0123456789"
        root = f"projects/susugigi-qa/databases/(default)/documents/users/{uid}"
        transport = FakeTransport(root, nested=True)

        with self.assertRaises(MODULE.SafeDeleteError):
            MODULE.delete_fixture_subtree(
                project="susugigi-qa",
                session_uid=uid,
                token_provider=FakeTokenProvider(),
                transport=transport,
            )

        self.assertEqual(transport.deleted, [])

    def test_batch_delete_rejects_any_missing_or_nonzero_status(self):
        transport = MODULE.FirestoreRestTransport.__new__(MODULE.FirestoreRestTransport)
        transport.documents_root = "projects/susugigi-qa/databases/(default)/documents"
        transport.request_json = mock.Mock(
            return_value={"writeResults": [{}, {}], "status": [{}, {"code": 7}]}
        )

        with self.assertRaises(MODULE.SafeDeleteError):
            transport.batch_delete(["one", "two"], "qa-oauth-token")

    def test_redirect_handler_never_follows_location(self):
        handler = MODULE.RejectRedirectHandler()
        with self.assertRaises(MODULE.SafeDeleteError):
            handler.redirect_request(None, None, 302, "Found", {}, "https://example.invalid")

    def test_response_body_over_limit_fails_closed_after_bounded_read(self):
        class OversizedResponse:
            def __enter__(self):
                return self

            def __exit__(self, exception_type, exception, traceback):
                return False

            def read(self, size=-1):
                self.asserted_size = size
                return b"x" * size

        response = OversizedResponse()
        transport = MODULE.FirestoreRestTransport.__new__(MODULE.FirestoreRestTransport)
        transport.opener = mock.Mock()
        transport.opener.open.return_value = response

        with self.assertRaises(MODULE.SafeDeleteError):
            transport.request_json(
                "GET",
                "https://firestore.googleapis.com/v1/projects/susugigi-qa",
                "qa-oauth-token",
            )

        self.assertEqual(response.asserted_size, MODULE.MAX_RESPONSE_BYTES + 1)

    def test_proxy_override_rejects_before_oauth(self):
        stdout = io.StringIO()
        stderr = io.StringIO()

        with mock.patch.dict(MODULE.os.environ, {"HTTPS_PROXY": "http://127.0.0.1:8888"}):
            status = MODULE.main(
                ["--project", "susugigi-qa", "--session-uid-stdin"],
                stdin=io.StringIO("qaFixtureUid0123456789\n"),
                stdout=stdout,
                stderr=stderr,
            )

        self.assertEqual(status, 2)
        self.assertEqual(stdout.getvalue(), "")
        self.assertEqual(stderr.getvalue(), "QA_FIXTURE_DELETE_REJECTED\n")

    def test_repeated_collection_page_token_fails_closed(self):
        transport = MODULE.FirestoreRestTransport.__new__(MODULE.FirestoreRestTransport)
        transport.request_json = mock.Mock(
            side_effect=[
                {"collectionIds": ["accounts"], "nextPageToken": "repeat"},
                {"collectionIds": ["categories"], "nextPageToken": "repeat"},
            ]
        )

        with self.assertRaises(MODULE.SafeDeleteError):
            transport.list_collection_ids("projects/susugigi-qa/databases/(default)/documents/users/u", "token")

    def test_duplicate_collection_id_across_pages_fails_closed(self):
        transport = MODULE.FirestoreRestTransport.__new__(MODULE.FirestoreRestTransport)
        transport.request_json = mock.Mock(
            side_effect=[
                {"collectionIds": ["accounts"], "nextPageToken": "page-2"},
                {"collectionIds": ["accounts"]},
            ]
        )

        with self.assertRaises(MODULE.SafeDeleteError):
            transport.list_collection_ids("projects/susugigi-qa/databases/(default)/documents/users/u", "token")

    def test_document_pagination_has_finite_upper_bound(self):
        transport = MODULE.FirestoreRestTransport.__new__(MODULE.FirestoreRestTransport)
        transport.request_json = mock.Mock(
            side_effect=[
                {"documents": [{"name": "doc-1"}], "nextPageToken": "page-2"},
                {"documents": [{"name": "doc-2"}], "nextPageToken": "page-3"},
            ]
        )

        with mock.patch.object(MODULE, "MAX_PAGE_COUNT", 2):
            with self.assertRaises(MODULE.SafeDeleteError):
                transport.list_documents(
                    "projects/susugigi-qa/databases/(default)/documents/users/u",
                    "accounts",
                    "token",
                )

    def test_duplicate_document_name_across_pages_fails_closed(self):
        transport = MODULE.FirestoreRestTransport.__new__(MODULE.FirestoreRestTransport)
        transport.request_json = mock.Mock(
            side_effect=[
                {"documents": [{"name": "doc-1"}], "nextPageToken": "page-2"},
                {"documents": [{"name": "doc-1"}]},
            ]
        )

        with self.assertRaises(MODULE.SafeDeleteError):
            transport.list_documents(
                "projects/susugigi-qa/databases/(default)/documents/users/u",
                "accounts",
                "token",
            )

    def test_document_page_item_limit_accepts_boundary(self):
        transport = MODULE.FirestoreRestTransport.__new__(MODULE.FirestoreRestTransport)
        transport.request_json = mock.Mock(
            return_value={"documents": [{"name": "a"}, {"name": "b"}]}
        )

        with mock.patch.object(MODULE, "MAX_PAGE_ITEMS", 2), \
             mock.patch.object(MODULE, "MAX_DOCUMENT_COUNT", 2), \
             mock.patch.object(MODULE, "MAX_DOCUMENT_NAME_BYTES", 2):
            result = transport.list_documents(
                "projects/susugigi-qa/databases/(default)/documents/users/u",
                "accounts",
                "token",
            )

        self.assertEqual(result, ["a", "b"])

    def test_document_page_item_limit_rejects_overflow(self):
        transport = MODULE.FirestoreRestTransport.__new__(MODULE.FirestoreRestTransport)
        transport.request_json = mock.Mock(
            return_value={
                "documents": [{"name": "a"}, {"name": "b"}, {"name": "c"}]
            }
        )

        with mock.patch.object(MODULE, "MAX_PAGE_ITEMS", 2):
            with self.assertRaises(MODULE.SafeDeleteError):
                transport.list_documents(
                    "projects/susugigi-qa/databases/(default)/documents/users/u",
                    "accounts",
                    "token",
                )

    def test_total_document_limit_rejects_cross_page_overflow(self):
        transport = MODULE.FirestoreRestTransport.__new__(MODULE.FirestoreRestTransport)
        transport.request_json = mock.Mock(
            side_effect=[
                {
                    "documents": [{"name": "a"}, {"name": "b"}],
                    "nextPageToken": "page-2",
                },
                {"documents": [{"name": "c"}]},
            ]
        )

        with mock.patch.object(MODULE, "MAX_PAGE_ITEMS", 2), \
             mock.patch.object(MODULE, "MAX_DOCUMENT_COUNT", 2):
            with self.assertRaises(MODULE.SafeDeleteError):
                transport.list_documents(
                    "projects/susugigi-qa/databases/(default)/documents/users/u",
                    "accounts",
                    "token",
                )

    def test_total_document_name_bytes_rejects_overflow(self):
        transport = MODULE.FirestoreRestTransport.__new__(MODULE.FirestoreRestTransport)
        transport.request_json = mock.Mock(
            return_value={"documents": [{"name": "ab"}]}
        )

        with mock.patch.object(MODULE, "MAX_DOCUMENT_NAME_BYTES", 1):
            with self.assertRaises(MODULE.SafeDeleteError):
                transport.list_documents(
                    "projects/susugigi-qa/databases/(default)/documents/users/u",
                    "accounts",
                    "token",
                )

    def test_subtree_total_document_limit_rejects_cross_collection_overflow(self):
        uid = "qaFixtureUid0123456789"
        root = f"projects/susugigi-qa/databases/(default)/documents/users/{uid}"
        transport = FakeTransport(root)

        with mock.patch.object(MODULE, "MAX_DOCUMENT_COUNT", 1):
            with self.assertRaises(MODULE.SafeDeleteError):
                MODULE.delete_fixture_subtree(
                    project="susugigi-qa",
                    session_uid=uid,
                    token_provider=FakeTokenProvider(),
                    transport=transport,
                )

        self.assertEqual(transport.deleted, [])

    def test_unsafe_gcloud_config_rejects_before_subprocess(self):
        with tempfile.TemporaryDirectory() as directory:
            config_root = pathlib.Path(directory)
            (config_root / "configurations").mkdir()
            (config_root / "active_config").write_text("default\n", encoding="utf-8")
            (config_root / "configurations" / "config_default").write_text(
                "[proxy]\naddress = 127.0.0.1\n",
                encoding="utf-8",
            )
            run = mock.Mock()

            with mock.patch.object(MODULE.subprocess, "run", run):
                with self.assertRaises(MODULE.SafeDeleteError):
                    MODULE.GcloudTokenProvider(config_root=config_root).access_token()

            run.assert_not_called()

    def test_gcloud_token_provider_discards_child_stderr(self):
        completed = subprocess_result = mock.Mock()
        subprocess_result.returncode = 0
        subprocess_result.stdout = "a" * 20

        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(MODULE.subprocess, "run", return_value=completed) as run:
                token = MODULE.GcloudTokenProvider(
                    config_root=directory,
                    gcloud_path="/usr/local/bin/gcloud",
                ).access_token()

        self.assertEqual(token, "a" * 20)
        kwargs = run.call_args.kwargs
        self.assertIs(kwargs["stdout"], MODULE.subprocess.PIPE)
        self.assertIs(kwargs["stderr"], MODULE.subprocess.DEVNULL)
        self.assertNotIn("capture_output", kwargs)
        self.assertTrue(pathlib.Path(run.call_args.args[0][0]).is_absolute())
        self.assertEqual(kwargs["env"]["PATH"], MODULE.APPROVED_CHILD_PATH)
        self.assertFalse(
            any(name.startswith("BASH_FUNC_") for name in kwargs["env"])
        )

    def test_imported_bash_function_environment_rejects_before_delete(self):
        stdout = io.StringIO()
        stderr = io.StringIO()
        delete = mock.Mock()

        with mock.patch.dict(
            MODULE.os.environ,
            {"BASH_FUNC_python3%%": "() { return 0; }"},
        ), mock.patch.object(MODULE, "delete_fixture_subtree", delete):
            status = MODULE.main(
                ["--project", "susugigi-qa", "--session-uid-stdin"],
                stdin=io.StringIO("qaFixtureUid0123456789\n"),
                stdout=stdout,
                stderr=stderr,
            )

        self.assertEqual(status, 2)
        self.assertEqual(stdout.getvalue(), "")
        self.assertEqual(stderr.getvalue(), "QA_FIXTURE_DELETE_REJECTED\n")
        delete.assert_not_called()

    def test_non_qa_project_rejects_before_oauth_or_transport(self):
        token_provider = FakeTokenProvider()
        transport = FakeTransport("unused")

        with self.assertRaises(MODULE.SafeDeleteError):
            MODULE.delete_fixture_subtree(
                project="susugigi-c4fb1",
                session_uid="qaFixtureUid0123456789",
                token_provider=token_provider,
                transport=transport,
            )

        self.assertEqual(token_provider.calls, 0)
        self.assertEqual(transport.deleted, [])

    def test_cli_failure_is_only_fixed_safe_code(self):
        stdout = io.StringIO()
        stderr = io.StringIO()

        status = MODULE.main(
            ["--project", "susugigi-c4fb1", "--session-uid-stdin"],
            stdin=io.StringIO("qaFixtureUid0123456789\n"),
            stdout=stdout,
            stderr=stderr,
        )

        self.assertEqual(status, 2)
        self.assertEqual(stdout.getvalue(), "")
        self.assertEqual(stderr.getvalue(), "QA_FIXTURE_DELETE_REJECTED\n")

    def test_typed_errors_cross_cli_as_status_only(self):
        for reason, expected in MODULE.SafeDeleteError.STATUSES.items():
            with self.subTest(reason=reason):
                stdout, stderr = io.StringIO(), io.StringIO()
                with mock.patch.object(MODULE, "delete_fixture_subtree",
                                       side_effect=MODULE.SafeDeleteError(reason)):
                    status = MODULE.main(
                        ["--project", "susugigi-qa", "--session-uid-stdin"],
                        stdin=io.StringIO("qaFixtureUid0123456789\n"),
                        stdout=stdout, stderr=stderr,
                    )
                self.assertEqual(status, expected)
                self.assertEqual(stdout.getvalue(), "")
                self.assertEqual(stderr.getvalue(), "QA_FIXTURE_DELETE_FAILED\n")

    def test_unexpected_exception_never_prints_credentials_or_traceback(self):
        stdout, stderr = io.StringIO(), io.StringIO()
        with mock.patch.object(MODULE, "delete_fixture_subtree",
                               side_effect=RuntimeError("raw-token-and-uid-secret")):
            status = MODULE.main(
                ["--project", "susugigi-qa", "--session-uid-stdin"],
                stdin=io.StringIO("qaFixtureUid0123456789\n"),
                stdout=stdout, stderr=stderr,
            )
        self.assertEqual(status, 1)
        self.assertEqual(stdout.getvalue(), "")
        self.assertEqual(stderr.getvalue(), "QA_FIXTURE_DELETE_FAILED\n")

    def test_http_failures_have_phase_specific_retry_statuses(self):
        for suffix, denied, transient, failed in (
            (":listCollectionIds", 24, 75, 26), (":batchWrite", 25, 76, 27),
        ):
            for http_status, expected in (
                (401, denied), (403, denied), (429, transient),
                (503, transient), (400, failed), (404, failed),
            ):
                with self.subTest(suffix=suffix, http_status=http_status):
                    transport = MODULE.FirestoreRestTransport.__new__(MODULE.FirestoreRestTransport)
                    transport.opener = mock.Mock()
                    transport.opener.open.side_effect = MODULE.urllib.error.HTTPError(
                        "https://firestore.googleapis.com/private", http_status,
                        "raw-secret", {}, None,
                    )
                    with self.assertRaises(MODULE.SafeDeleteError) as raised:
                        transport.request_json(
                            "POST", "https://firestore.googleapis.com/v1/test" + suffix,
                            "raw-token-secret",
                        )
                    self.assertEqual(raised.exception.exit_status, expected)

    def test_partial_batch_failure_only_retries_transient_codes(self):
        for codes, expected in (
            ([0, 14], 76), ([14, 7], 25), ([14, 3], 27),
            ([True, 0], 27), (["0", 0], 27), ([0, 16], 25),
        ):
            with self.subTest(codes=codes):
                transport = MODULE.FirestoreRestTransport.__new__(MODULE.FirestoreRestTransport)
                transport.documents_root = "projects/susugigi-qa/databases/(default)/documents"
                transport.request_json = mock.Mock(return_value={
                    "writeResults": [{}, {}], "status": [{"code": code} for code in codes],
                })
                with self.assertRaises(MODULE.SafeDeleteError) as raised:
                    transport.batch_delete(["one", "two"], "fake-token")
                self.assertEqual(raised.exception.exit_status, expected)

    def test_missing_credentials_are_not_retryable(self):
        with tempfile.TemporaryDirectory() as directory, \
             mock.patch.object(MODULE.subprocess, "run", side_effect=OSError("secret")):
            with self.assertRaises(MODULE.SafeDeleteError) as raised:
                MODULE.GcloudTokenProvider(
                    config_root=directory, gcloud_path="/usr/local/bin/gcloud",
                ).access_token()
        self.assertEqual(raised.exception.exit_status, 20)

    def test_tls_failure_is_not_retryable(self):
        transport = MODULE.FirestoreRestTransport.__new__(MODULE.FirestoreRestTransport)
        transport.opener = mock.Mock()
        transport.opener.open.side_effect = MODULE.urllib.error.URLError(
            MODULE.ssl.SSLCertVerificationError("fake certificate failure")
        )
        with self.assertRaises(MODULE.SafeDeleteError) as raised:
            transport.request_json("GET", "https://firestore.googleapis.com/v1/test", "fake-token")
        self.assertEqual(raised.exception.exit_status, 26)

    def test_retry_rediscovers_only_remaining_documents_in_same_subtree(self):
        uid = "qaFixtureUid0123456789"
        root = f"projects/susugigi-qa/databases/(default)/documents/users/{uid}"
        class PartialTransport(FakeTransport):
            failed_once = False

            def list_documents(self, parent, collection_id, token):
                return [name for name in super().list_documents(parent, collection_id, token)
                        if name not in self.deleted]

            def batch_delete(self, names, token):
                if names and not self.failed_once:
                    self.deleted.append(names[0])
                    self.failed_once = True
                    raise MODULE.SafeDeleteError("delete_transient")
                super().batch_delete(names, token)

        transport = PartialTransport(root)
        with self.assertRaises(MODULE.SafeDeleteError):
            MODULE.delete_fixture_subtree("susugigi-qa", uid, FakeTokenProvider(), transport)
        self.assertNotIn(root, transport.deleted)
        MODULE.delete_fixture_subtree("susugigi-qa", uid, FakeTokenProvider(), transport)
        self.assertEqual(transport.deleted, [
            f"{root}/accounts/account-1", f"{root}/transactions/tx-1", root,
        ])


if __name__ == "__main__":
    unittest.main()
