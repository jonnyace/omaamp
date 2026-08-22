"""Client for the Winamp Skin Museum's public GraphQL API.

https://api.webamp.org/graphql -- unauthenticated, ~102k classic skins.
Skin files and screenshots are served straight from r2.webampskins.org.

Note: the CDN rejects Python's default urllib user-agent with a 403, so every
request here goes out with an identifying one.
"""

from __future__ import annotations

import json
import re
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass

API = "https://api.webamp.org/graphql"
USER_AGENT = "cliamp-skinner/0.1 (+https://github.com/jonnyace/omaamp)"

_SKIN_FIELDS = "md5 filename nsfw download_url screenshot_url museum_url"

# Everything the API hands back is untrusted input. URLs are only followed to
# these hosts over https (redirects re-checked hop by hop), identifiers must
# be literal md5 hex before they touch a filesystem path, and responses are
# read against a hard cap instead of trusting Content-Length.
ALLOWED_HOSTS = frozenset({
    "api.webamp.org",
    "r2.webampskins.org",
    "raw.githubusercontent.com",
})
MAX_RESPONSE_BYTES = 32 * 1024 * 1024  # largest legitimate object: a .wsz

MD5_RE = re.compile(r"^[0-9a-f]{32}$")
SKIN_PATH_RE = re.compile(r"^/skin/([0-9a-f]{32})/?$", re.I)


def valid_md5(value: str) -> bool:
    return bool(MD5_RE.match(str(value or "").lower()))


def skin_md5(value: str) -> str:
    """Return the skin id from a museum link or a literal md5.

    Museum links are user-pasted input. Parse the URL instead of looking for
    a convenient 32-character substring, so a different host cannot disguise
    itself as a Skin Museum link.
    """
    value = str(value or "").strip()
    if valid_md5(value):
        return value.lower()

    try:
        parts = urllib.parse.urlsplit(value)
        port = parts.port
    except ValueError:
        parts = None
        port = None

    if (
        parts
        and parts.scheme.lower() == "https"
        and parts.hostname == "skins.webamp.org"
        and port in (None, 443)
        and parts.username is None
        and parts.password is None
    ):
        match = SKIN_PATH_RE.fullmatch(parts.path)
        if match:
            return match.group(1).lower()

    raise ValueError(
        "paste a https://skins.webamp.org/skin/<id> link "
        "or a 32-character skin id"
    )


class ResponseTooLarge(RuntimeError):
    pass


def _check_url(url: str) -> str:
    parts = urllib.parse.urlsplit(url)
    if parts.scheme != "https":
        raise ValueError(f"refusing non-https URL: {url!r}")
    if parts.hostname not in ALLOWED_HOSTS:
        raise ValueError(f"refusing URL outside allowed hosts: {url!r}")
    return url


class _GuardedRedirects(urllib.request.HTTPRedirectHandler):
    """Redirects are followed only if the target also passes the allowlist."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        _check_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


_OPENER = urllib.request.build_opener(_GuardedRedirects())


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
        md5 = str(d.get("md5") or "").lower()
        return cls(
            md5=md5 if valid_md5(md5) else "",
            filename=d.get("filename") or "",
            nsfw=bool(d.get("nsfw")),
            download_url=d.get("download_url") or "",
            screenshot_url=d.get("screenshot_url") or "",
            museum_url=d.get("museum_url") or "",
        )


def _request(
    url: str,
    data: bytes | None = None,
    headers: dict | None = None,
    timeout: int = 40,
    limit: int = MAX_RESPONSE_BYTES,
) -> bytes:
    _check_url(url)
    req = urllib.request.Request(url, data, {"User-Agent": USER_AGENT, **(headers or {})})
    with _OPENER.open(req, timeout=timeout) as resp:
        body = resp.read(limit + 1)
    if len(body) > limit:
        raise ResponseTooLarge(f"{url} exceeded {limit} bytes")
    return body


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
    # Entries whose md5 failed validation are unusable everywhere downstream
    # (it is the cache key and the only identifier), so they are dropped here.
    refs = [r for r in refs if r.md5]
    # The museum flags ~1.5k skins as NSFW. Excluded unless asked for, since
    # this feeds a picker that renders every result as a screenshot.
    return refs if include_nsfw else [r for r in refs if not r.nsfw]


def download(ref: SkinRef | str, timeout: int = 60) -> bytes:
    url = ref if isinstance(ref, str) else ref.download_url
    return _request(url, timeout=timeout, limit=MAX_RESPONSE_BYTES)
