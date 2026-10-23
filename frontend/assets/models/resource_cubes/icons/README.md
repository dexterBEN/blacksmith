# Service icon sources

The Cloud Storage, Cloud VPN and Cloud Load Balancing glyphs come from Google's
[official product icon library](https://cloud.google.com/icons), specifically the
[legacy console icon collection](https://services.google.com/fh/files/misc/google-cloud-legacy-icons.zip).
This family matches the existing Compute Engine visual language. Google's current
library also offers a newer product-icon system; this preview intentionally uses
the legacy service shapes, not a mixture of the two families.

`official/` preserves the three downloaded SVGs byte-for-byte. Godot rasterizes
them at 256 pixels into `rendered/` for runtime sampling; their geometry, aspect
ratio and colors are not modified. This avoids stretching the 24-pixel default
SVG import over a larger cube face. The PNGs are reproducible source assets,
not Godot import caches; `render_resource_icons.gd` regenerates them.
The earlier white adaptations have been removed, following the user's explicit
choice during the PR #29 review. The cube shader samples the SVG colors directly
and applies its blue-pigment correction only to the body.

The previous pack used a generic bucket for Cloud Storage and a shield/lock for
Cloud VPN. Its Load Balancer tree was also a generic approximation. The corrected
materials substitute the official service artwork, using a separate SVG
sampler and a clean blue gradient on the front face. Source PNGs are unchanged.
Compute Engine continues using its original atlas icon and material.

See `provenance.json` for download URLs, archive entry names and SHA-256 hashes.
Google retains ownership of the original product icon artwork.

## Mapping

| Cube | Runtime icon source | Classification |
| --- | --- | --- |
| Cloud Storage | `official/cloud_storage.svg` → `rendered/cloud_storage.png` | Official legacy console artwork, unchanged |
| Compute Engine | `../source/compute_engine/compute_engine_texture.png` | Original supplied-pack CPU symbol; not represented as official artwork |
| Cloud VPN | `official/cloud_vpn.svg` → `rendered/cloud_vpn.png` | Official legacy console artwork, unchanged |
| Cloud Load Balancing | `official/cloud_load_balancing.svg` → `rendered/cloud_load_balancing.png` | Official legacy console artwork, unchanged |

## Usage review (2026-10-23)

Google's icon library supplies these resources for diagrams, technical
documentation and related projects. Blacksmith uses them to identify services
in a cloud-architecture visualization, not as its own product identity.
Google's [brand guidance](https://about.google/brand-resource-center/guidance/)
and [trademark rules](https://about.google/brand-resource-center/rules/) require
appropriate approved artwork, preservation of brand features and no suggestion
of endorsement or affiliation. The library was not treated as permission to
recolor the icons; that is why the white derivatives were removed.

The downloaded legacy ZIP does not include a standalone open-source license.
These third-party assets are not relicensed under Blacksmith's source-code
license, and this notice grants no additional trademark rights. Product-specific
Google usage/approval requirements continue to apply to distribution and
marketing. Source attribution is not itself a license grant. The supplied-pack
CPU symbol is documented separately rather than claimed as approved Google art.
