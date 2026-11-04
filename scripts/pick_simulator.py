#!/usr/bin/env python3
"""选择最新的 iOS 模拟器：输出 udid<TAB>version<TAB>name。"""
import json
import re
import subprocess


def main() -> None:
    runtimes = json.loads(
        subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"])
    )["runtimes"]

    def version_key(runtime):
        match = re.match(r"(\d+)(?:\.(\d+))?", runtime.get("version", "0"))
        return (int(match.group(1)), int(match.group(2) or 0)) if match else (0, 0)

    ios = sorted(
        [r for r in runtimes if r.get("isAvailable") and r.get("platform") == "iOS"],
        key=version_key,
        reverse=True,
    )
    if not ios:
        raise SystemExit("no available iOS runtime")

    runtime = ios[0]
    devices = json.loads(
        subprocess.check_output(["xcrun", "simctl", "list", "devices", "-j"])
    )["devices"].get(runtime["identifier"], [])
    phones = [d for d in devices if d.get("isAvailable") and "iPhone" in d["name"]]
    pros = [d for d in phones if "Pro" in d["name"]]
    device = (pros or phones)[0]
    print(f"{device['udid']}\t{runtime['version']}\t{device['name']}")


if __name__ == "__main__":
    main()
