import os
import unittest
from unittest.mock import patch

os.environ.setdefault("AWS_EC2_METADATA_DISABLED", "true")

import main


class PullRequestReviewTests(unittest.TestCase):
    def setUp(self):
        main.REVIEW_API_KEY_SECRET_ARN = "review-key-secret"
        main._secret_cache[main.REVIEW_API_KEY_SECRET_ARN] = "test-review-key"

    def test_rejects_repository_outside_allowlist(self):
        request = main.PullRequestReviewRequest(repository="someone/other", pull_number=1)

        with self.assertRaises(main.HTTPException) as raised:
            main.review_pull_request(request, "test-review-key")

        self.assertEqual(raised.exception.status_code, 403)

    def test_rejects_invalid_review_api_key(self):
        request = main.PullRequestReviewRequest(
            repository="grendach/expense-tracker", pull_number=1
        )

        with self.assertRaises(main.HTTPException) as raised:
            main.review_pull_request(request, "wrong-key")

        self.assertEqual(raised.exception.status_code, 401)

    @patch.object(main, "_store_history")
    @patch.object(main, "_github_request")
    @patch.object(main, "_invoke_bedrock")
    @patch.object(main, "_pull_request_context")
    def test_publishes_comment_review(
        self, pull_context, invoke_bedrock, github_request, _store_history
    ):
        pull_context.return_value = (
            {
                "html_url": "https://github.com/grendach/expense-tracker/pull/7",
                "title": "Fix totals",
                "user": {"login": "developer"},
                "base": {"ref": "main"},
                "head": {"ref": "fix", "sha": "abc123"},
                "changed_files": 1,
                "additions": 2,
                "deletions": 1,
                "body": "Fix calculation",
            },
            "--- app.py ---\n+total = correct_value",
            False,
        )
        invoke_bedrock.return_value = {
            "output": {"message": {"content": [{"text": "## Review\nLooks good."}]}},
            "usage": {"inputTokens": 20, "outputTokens": 5},
        }
        github_request.return_value = {
            "html_url": "https://github.com/grendach/expense-tracker/pull/7#pullrequestreview-1"
        }
        request = main.PullRequestReviewRequest(
            repository="grendach/expense-tracker", pull_number=7
        )

        result = main.review_pull_request(request, "test-review-key")

        self.assertEqual(result.pull_number, 7)
        github_request.assert_called_once_with(
            "/repos/grendach/expense-tracker/pulls/7/reviews",
            method="POST",
            payload={
                "body": "## Review\nLooks good.",
                "event": "COMMENT",
                "commit_id": "abc123",
            },
        )


if __name__ == "__main__":
    unittest.main()
