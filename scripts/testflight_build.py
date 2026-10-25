"""Read-only App Store Connect build numbering and processing checks."""
import argparse
import os
from pathlib import Path
import time
from update_app_store_listing import AppStoreConnect, sign_token

APP_ID = "6792223291"


def next_build(api, minimum):
    response = api.get(f"/apps/{APP_ID}/builds", {"limit": "200"})
    versions = []
    while True:
        versions.extend(int(build["attributes"]["version"]) for build in response["data"]
                        if build["attributes"]["version"].isdigit())
        url = response.get("links", {}).get("next")
        if not url:
            return max([minimum] + versions) + 1
        # The client owns the API root; only follow pagination on that same root.
        prefix = "https://api.appstoreconnect.apple.com/v1/"
        if not url.startswith(prefix):
            raise RuntimeError("Unexpected App Store pagination URL")
        response = api.get("/" + url[len(prefix):], None)


def processing_state(api, build_number):
    response = api.get("/builds", {"filter[app]": APP_ID, "filter[version]": str(build_number), "limit": "10"})
    if not response["data"]:
        return "NOT_VISIBLE"
    return response["data"][0]["attributes"]["processingState"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["next", "wait"])
    parser.add_argument("build", type=int)
    args = parser.parse_args()
    def client():
        return AppStoreConnect(sign_token(os.environ["APPSTORE_API_KEY_ID"], os.environ["APPSTORE_ISSUER_ID"],
                                         Path(os.environ["APPSTORE_API_PRIVATE_KEY_PATH"])))
    if args.mode == "next":
        print(next_build(client(), args.build))
        return
    deadline = time.monotonic() + 1800
    while time.monotonic() < deadline:
        state = processing_state(client(), args.build)
        print(f"Build {args.build}: {state}", flush=True)
        if state == "VALID":
            return
        if state in ("FAILED", "INVALID"):
            raise SystemExit(f"Apple processing rejected build {args.build}: {state}")
        time.sleep(30)
    raise SystemExit(f"Apple processing still pending for build {args.build} after 30 minutes; inspect TestFlight before retrying upload")


if __name__ == "__main__":
    main()
