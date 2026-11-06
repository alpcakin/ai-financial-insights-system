"""HTTP to addresses users typed in: their RSS feeds and their own model endpoints.

The backend runs next to private services, so such an address must not be able to
reach them (SSRF). Every request, redirects included, resolves the host, refuses
anything that is not a public address and connects to the address it checked, so
DNS cannot answer differently a moment later. A response also has a size limit
and a total deadline, because a read timeout alone restarts with every chunk and
a server sending a byte at a time could hold a worker forever.
"""

import ipaddress
import socket
import time
from dataclasses import dataclass
from urllib.parse import urljoin, urlsplit

import httpx

MAX_REDIRECTS = 3


class BlockedAddress(Exception):
    """The address is not allowed. Callers show a generic error, so the app cannot be used to map a network."""


class ResponseLimitExceeded(httpx.ReadError):
    """The response was too large or took too long."""


def _is_public(address: str) -> bool:
    ip = ipaddress.ip_address(address.split("%")[0])
    if ip.version == 6 and ip.ipv4_mapped:
        ip = ip.ipv4_mapped
    return ip.is_global and not (ip.is_multicast or ip.is_reserved or ip.is_unspecified)


def public_address(host: str) -> str:
    """The address to connect to, or BlockedAddress if the host resolves to anything non-public."""
    try:
        infos = socket.getaddrinfo(host, None, type=socket.SOCK_STREAM)
    except (OSError, UnicodeError) as e:
        raise BlockedAddress from e
    addresses = list(dict.fromkeys(info[4][0] for info in infos))
    if not addresses or not all(_is_public(a) for a in addresses):
        raise BlockedAddress
    return addresses[0]


def check_url(url: str, https_only: bool = False) -> str:
    """The URL if its form is allowed. The address itself is checked on every request."""
    url = url.strip()
    try:
        parts = urlsplit(url)
        host = parts.hostname
        port = parts.port
    except ValueError as e:
        raise BlockedAddress from e
    if parts.scheme.lower() not in (("https",) if https_only else ("http", "https")):
        raise BlockedAddress
    if not host or parts.username or parts.password or port == 0:
        raise BlockedAddress
    return url


class _LimitedStream(httpx.SyncByteStream):
    def __init__(self, stream: httpx.SyncByteStream, max_bytes: int, deadline: float) -> None:
        self._stream = stream
        self._max_bytes = max_bytes
        self._deadline = deadline

    def __iter__(self):
        received = 0
        for chunk in self._stream:
            received += len(chunk)
            if received > self._max_bytes or time.monotonic() > self._deadline:
                raise ResponseLimitExceeded("response limit exceeded")
            yield chunk

    def close(self) -> None:
        self._stream.close()


class PublicOnlyTransport(httpx.HTTPTransport):
    def __init__(self, max_bytes: int, deadline_seconds: float, allow_compressed: bool = True) -> None:
        super().__init__(trust_env=False)
        self._max_bytes = max_bytes
        self._deadline_seconds = deadline_seconds
        self._allow_compressed = allow_compressed

    def handle_request(self, request: httpx.Request) -> httpx.Response:
        deadline = time.monotonic() + self._deadline_seconds
        host = request.url.host
        address = public_address(host)
        if request.url.scheme == "https":
            # The certificate is still checked against the name, not the address.
            request.extensions = {**request.extensions, "sni_hostname": host}
        request.url = request.url.copy_with(host=address)
        response = super().handle_request(request)
        if not self._allow_compressed and response.headers.get("content-encoding", "identity") != "identity":
            response.close()
            raise ResponseLimitExceeded("compressed response refused")
        response.stream = _LimitedStream(response.stream, self._max_bytes, deadline)
        return response


def guarded_client(
    max_bytes: int,
    deadline_seconds: float,
    timeout: float,
    headers: dict[str, str] | None = None,
    allow_compressed: bool = True,
) -> httpx.Client:
    return httpx.Client(
        transport=PublicOnlyTransport(max_bytes, deadline_seconds, allow_compressed),
        timeout=timeout,
        follow_redirects=False,
        trust_env=False,
        headers=headers,
    )


@dataclass(frozen=True)
class Fetched:
    status_code: int
    headers: httpx.Headers
    body: bytes


def fetch(
    client: httpx.Client,
    url: str,
    max_bytes: int,
    deadline_seconds: float,
    headers: dict[str, str] | None = None,
) -> Fetched:
    """GET with redirects checked hop by hop. The limits apply to the whole chain and
    to the decompressed body, so a small compressed response cannot fill the memory."""
    deadline = time.monotonic() + deadline_seconds
    for _ in range(MAX_REDIRECTS + 1):
        check_url(url)
        with client.stream("GET", url, headers=headers) as response:
            if not response.has_redirect_location:
                body = bytearray()
                for chunk in response.iter_bytes():
                    body += chunk
                    if len(body) > max_bytes or time.monotonic() > deadline:
                        raise ResponseLimitExceeded("response limit exceeded")
                return Fetched(response.status_code, response.headers, bytes(body))
            location = response.headers["location"]
        if time.monotonic() > deadline:
            raise ResponseLimitExceeded("response limit exceeded")
        url = urljoin(url, location)
    raise ResponseLimitExceeded("too many redirects")
