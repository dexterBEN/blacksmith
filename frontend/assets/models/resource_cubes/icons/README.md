# Service icon provenance

The source artwork for Cloud Storage, Cloud VPN and Cloud Load Balancing comes
from Google's [product icon library](https://cloud.google.com/icons), specifically
the [legacy console collection](https://services.google.com/fh/files/misc/google-cloud-legacy-icons.zip).
`official/` preserves the three downloaded SVGs byte-for-byte.

`white/` contains adaptations restored **exactly from commit `5d26367`** at the
user's explicit request during PR #29 cleanup. They use white fills and a
256-pixel SVG canvas for the cube shader. They are modified derivatives, not
unmodified or Google-approved official artwork. Godot imports these SVGs
directly; the redundant colored PNGs and their rasterization tool are removed.

| Cube | Runtime icon | Classification |
| --- | --- | --- |
| Cloud Storage | `white/cloud_storage.svg` | White adaptation of the legacy service glyph |
| Compute Engine | `../source/compute_engine/compute_engine_texture.png` | Supplied-pack CPU symbol; not claimed as official artwork |
| Cloud VPN | `white/cloud_vpn.svg` | White adaptation of the legacy service glyph |
| Cloud Load Balancing | `white/load_balancer.svg` | White adaptation of the legacy service glyph |

[provenance.json](provenance.json) records source/archive URLs, SHA-256 hashes,
the selected visual baseline and the distinction between originals and derivatives.
The original pack atlases remain unchanged.

## Ownership and usage status

Google retains ownership of the original service artwork. The downloaded legacy
ZIP does not include a standalone open-source license. No separate permission
covering these white adaptations has been established; the user's visual choice
does not establish such permission. Attribution does not grant additional rights
or relicense third-party artwork under Blacksmith's code license.

The earlier usage review referenced Google's
[brand guidance](https://about.google/brand-resource-center/guidance/) and
[trademark rules](https://about.google/brand-resource-center/rules/).
The permission status of the modified artwork remains unresolved for distribution.
Do not describe these derivatives as approved artwork or imply Google endorsement.
