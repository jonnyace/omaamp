"""Client for the Winamp Skin Museum's public GraphQL API.

https://api.webamp.org/graphql -- unauthenticated, ~102k classic skins.
Skin files and screenshots are served straight from r2.webampskins.org.

Note: the CDN rejects Python's default urllib user-agent with a 403, so every
request here goes out with an identifying one.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from dataclasses import dataclass

API = "https://api.webamp.org/graphql"
USER_AGENT = "cliamp-skinner/0.1 (+https://github.com/jonnyace/omaamp)"

_SKIN_FIELDS = "md5 filename nsfw download_url screenshot_url museum_url"


@dataclass
class SkinRef:
    md5: str
    filename: str
    nsfw: bool
    download_url: str
    screenshot_url: str
    museum_url: str

    @classmethod
    def from_json(cls, d: dict) -> "SkinRef":
        return cls(
            md5=d.get("md5") or "",
            filename=d.get("filename") or "",
            nsfw=bool(d.get("nsfw")),
            download_url=d.get("download_url") or "",
            screenshot_url=d.get("screenshot_url") or "",
            museum_url=d.get("museum_url") or "",
        )


def _request(url: str, data: bytes | None = None, headers: dict | None = None, timeout: int = 40) -> bytes:
    req = urllib.request.Request(url, data, {"User-Agent": USER_AGENT, **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def query(gql: str, variables: dict | None = None, timeout: int = 40) -> dict:
    payload = json.dumps({"query": gql, "variables": variables or {}}).encode()
    raw = _request(API, payload, {"Content-Type": "application/json"}, timeout)
    doc = json.loads(raw)
    if "errors" in doc:
        raise RuntimeError(f"museum API: {doc['errors'][0].get('message')}")
    return doc["data"]


def total_skins() -> int:
    return query("{statistics{unique_classic_skins_count}}")["statistics"][
        "unique_classic_skins_count"
    ]


def search(term: str, first: int = 40, offset: int = 0, *, include_nsfw: bool = False) -> list[SkinRef]:
    data = query(
        f'query($q:String!,$n:Int!,$o:Int!){{search_skins(query:$q,first:$n,offset:$o){{{_SKIN_FIELDS}}}}}',
        {"q": term, "n": first, "o": offset},
    )
    return _filter(data["search_skins"], include_nsfw)


def browse(first: int = 40, offset: int = 0, *, include_nsfw: bool = False) -> list[SkinRef]:
    # `skins` returns a connection (count + nodes), unlike the search fields
    # which return a bare list. sort:MUSEUM is the museum's own curated
    # ranking -- the site's front-page order, hand-picked classics first --
    # so browsing without a query starts at the good stuff.
    data = query(
        f"query($n:Int!,$o:Int!){{skins(sort:MUSEUM,first:$n,offset:$o){{nodes{{{_SKIN_FIELDS}}}}}}}",
        {"n": first, "o": offset},
    )
    return _filter(data["skins"]["nodes"], include_nsfw)


def _filter(rows: list[dict], include_nsfw: bool) -> list[SkinRef]:
    refs = [SkinRef.from_json(r) for r in rows if r]
    # The museum flags ~1.5k skins as NSFW. Excluded unless asked for, since
    # this feeds a picker that renders every result as a screenshot.
    return refs if include_nsfw else [r for r in refs if not r.nsfw]


def download(ref: SkinRef | str, timeout: int = 60) -> bytes:
    url = ref if isinstance(ref, str) else ref.download_url
    return _request(url, timeout=timeout)
