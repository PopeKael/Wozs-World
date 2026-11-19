# Avatar source provenance

The local asset library is intentionally excluded from Git. The acquisition helper fetches commit-pinned upstream archives into ignored folders and verifies their hashes before preserving the original ZIP. Keep each package's included notices alongside its files. A ZIP being downloadable or an IAR being importable does not grant blanket redistribution rights.

## Pinned public source archives

| System | Upstream | Commit | Expected archive SHA-256 | Terms to review |
|---|---|---|---|---|
| Ruth2 | [RuthAndRoth/Ruth2](https://github.com/RuthAndRoth/Ruth2) | `aab3faf9ddb2d5c69cd5746f4bc4233c9d990270` | `99D0D6EF0D66D86CEAE455AA0CE2F25BA0F2A4AD4C3ED663CBAFA3445D75468C` | Repository AGPL notice plus per-component notices |
| Roth2 | [RuthAndRoth/Roth2](https://github.com/RuthAndRoth/Roth2) | `8dfb8b200dd6fdeb40358ac4753b01cc2de15bee` | `58B1E1E65E46AB9D3764D99F134D7C9C701696812C5246F4341D67AF3BC18DB2` | Repository AGPL notice plus per-component notices |
| RuthToo | [ocsean/RuthToo](https://github.com/ocsean/RuthToo) | `95892f99064ae2f4b8648593122c126a6bb1d31e` | `BBBEECABF58CFF8260E91958B0CA9F8048750F5ED1ADC8D787C62C1A6DDC85D5` | Repository AGPL notice; some additions have separate terms |
| RothToo | [ocsean/RothToo](https://github.com/ocsean/RothToo) | `d1f0562d8e4192aad4cf9457483936fc89c0ac9b` | `4E7298F7B5F518D7A507DFF3F02BE9E1398C3708EFA723A3967066DCD050E380` | Repository AGPL notice; check included notices |
| Max | [RuthAndRoth/Max](https://github.com/RuthAndRoth/Max) | `ca27a4bda597c06cdfc6c59490ceff30c38b55b0` | `C23C99AE5E5B5384281CC30E4366FBD338752358C1F9933A7C715B25966296A7` | Mesh notice references CC BY 4.0; package is mixed-component, review before use |
| R3 | [RuthAndRoth/R3](https://github.com/RuthAndRoth/R3) | `2994d5dbf628031ee3db4e8ce120004ca639df02` | `8732246EE53D8865D2B5D62FEB0101B4F9AC246F7EA462AE8EC7F28402AB8AF3` | CC BY-NC 4.0 proposal; non-commercial restriction |
| Skins | [RuthAndRoth/Skins](https://github.com/RuthAndRoth/Skins) | `d07463a6d2f14e7ce998599c0557b5454c3a5644` | `AF4BEFE7ABD0F180A5F40C36286241CAB2543C2898E0A6B5D4F858A43BC477D6` | Mixed creator licenses; review each skin |
| Extras | [RuthAndRoth/Extras](https://github.com/RuthAndRoth/Extras) | `d2a17e7242911dc40a832cc08d7215a919f16501` | `EA26D5C7F3166C21FFA7A2BC2A0A0C41D6E5514F20C770EAE65D07F566A65541` | Mixed creator licenses; review each component |

Hashes are from the locally retained acquisition record for those exact snapshots. The helper stops on a mismatch; do not update a pin just to make a download pass. Verify the upstream commit and package contents first.

## Additional research leads, not auto-installed

R3, Skins and Extras can be retrieved explicitly with the acquisition helper but are not downloaded by default because of non-commercial or mixed component terms. Do not use them as default starter content until each chosen component is reviewed. Skin, eyes, hair, clothing, animations, AO products, and accessories each need their own creator and redistribution review. A product's “free to wear” status on another grid does not imply permission to move, export, or redistribute it.

This record documents source pointers, not an endorsement or legal opinion. Upstream notices shipped with each acquired snapshot control. Before publishing an avatar bundle, make a component-level bill of materials and obtain any missing permissions.
