# Third-party notices

This image includes upstream AmneziaWG software. The corresponding license texts are also copied into the runtime image under `/usr/share/licenses/`.

| Component | Version | License | Upstream source |
|---|---|---|---|
| `amneziawg-go` | `v3.1.20261116` | MIT | <https://github.com/amnezia-vpn/amneziawg-go/tree/v3.1.20261116> |
| `amneziawg-tools` | `v3.1.20260812` | GNU GPL version 2 | <https://github.com/amnezia-vpn/amneziawg-tools/tree/v3.1.20260812> |

The license texts are in [`LICENSES/`](LICENSES/). The Dockerfile builds these components from their tagged upstream source. Go module checksums are verified with `go mod verify` during the build.
