#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Writes the SideStore / AltStore source JSON (v2: apps[].versions[]) for an IPA.

    make-source.py --ipa FILE --version 0.1.0 --build 7 --tag ios-nightly \
                   --repo ninmiao/OrangeBrain-Input-AI-Assistance --commit SHA --out source.json

Field names follow the model SideStore decodes (Source / StoreApp / AppVersion
in SideStore/AltStore sources): the source needs name and apps; each app needs
name, bundleIdentifier, developerName, localizedDescription and iconURL; each
version needs version, date (ISO 8601), downloadURL and size.
"""
import argparse
import datetime
import hashlib
import json
import pathlib

SOURCE_ID = "io.github.ninmiao.orangecell.source"
APP_ID = "io.github.ninmiao.orangecell"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ipa", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--tag", default="ios-nightly")
    parser.add_argument("--repo", required=True)
    parser.add_argument("--commit", default="")
    parser.add_argument("--entitlements-json", required=True,
                        help="entitlements.json written by make-ipa.sh (what the signed binaries carry)")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    ipa = pathlib.Path(args.ipa)
    # SideStore refuses to install an app whose entitlements are not declared in the source.
    entitlements = json.loads(pathlib.Path(args.entitlements_json).read_text(encoding="utf8"))
    assert isinstance(entitlements, list) and all(isinstance(item, str) for item in entitlements)
    sha256 = hashlib.sha256(ipa.read_bytes()).hexdigest()
    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    base = f"https://github.com/{args.repo}"
    icon = f"https://raw.githubusercontent.com/{args.repo}/main/docs/images/orangecell-logo.png"
    note = f"iOS 预览版 {args.version}，提交 {args.commit[:12]}：拼音输入与万象词库可用，在线 AI 候选在后续版本加入。"

    source = {
        "name": "橘脑一颗 OrangeCell（iOS 预览）",
        "identifier": SOURCE_ID,
        "subtitle": "橘脑一颗 iOS 版的夜间预览包",
        "description": "由 GitHub Actions 构建的未签名 IPA，用 SideStore 以免费 Apple ID 安装。",
        "iconURL": icon,
        "website": base,
        "tintColor": "#F28C28",
        "apps": [
            {
                "name": "橘脑一颗",
                "bundleIdentifier": APP_ID,
                "developerName": "ninmiao",
                "subtitle": "拼音输入法 + 在线 AI 候选",
                "localizedDescription": "橘脑一颗 OrangeCell 的 iOS 版：Rime 拼音输入法键盘加在线 AI 纠错与助手候选。当前为 M1 预览：拼音输入可用，AI 候选稍后加入。",
                "iconURL": icon,
                "tintColor": "#F28C28",
                "category": "utilities",
                "screenshots": [],
                "versions": [
                    {
                        "version": args.version,
                        "buildVersion": str(args.build),
                        "date": now,
                        "localizedDescription": note,
                        "downloadURL": f"{base}/releases/download/{args.tag}/{ipa.name}",
                        "size": ipa.stat().st_size,
                        "sha256": sha256,
                        "minOSVersion": "17.0",
                    }
                ],
                "appPermissions": {"entitlements": entitlements, "privacy": {}},
            }
        ],
        "news": [],
    }
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    print(f"wrote {out} ({ipa.name}, {ipa.stat().st_size} bytes, sha256 {sha256})")


if __name__ == "__main__":
    main()
