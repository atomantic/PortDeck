"""Pin build-number compatibility across Apple records and the local project."""
import unittest
from testflight_build import next_build, processing_state


class FakeAPI:
    def __init__(self, responses):
        self.responses = iter(responses)

    def get(self, path, params):
        assert path.startswith("/"), "AppStoreConnect paths must start with a slash"
        return next(self.responses)


class TestFlightTests(unittest.TestCase):
    def test_next_build_checks_all_pages_and_local_minimum(self):
        api = FakeAPI([
            {"data": [{"attributes": {"version": "15"}}], "links": {"next": "https://api.appstoreconnect.apple.com/v1/builds?cursor=next"}},
            {"data": [{"attributes": {"version": "20"}}, {"attributes": {"version": "1.2"}}]},
        ])
        self.assertEqual(next_build(api, 14), 21)
        self.assertEqual(next_build(FakeAPI([{"data": []}]), 25), 26)

    def test_processing_distinguishes_not_visible_from_apple_result(self):
        self.assertEqual(processing_state(FakeAPI([{"data": []}]), 21), "NOT_VISIBLE")
        self.assertEqual(processing_state(FakeAPI([{"data": [{"attributes": {"processingState": "VALID"}}]}]), 21), "VALID")
