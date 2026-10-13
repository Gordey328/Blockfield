# Among Us · Mira HQ — source and adaptation

Real downloaded Teardown community map: **[Alpha] Mira HQ (Among US)**, by **CapnSoda202**.

- Author/source page: https://steamcommunity.com/sharedfiles/filedetails/?id=2905630454
- Public download page: https://dlcfun.com/en/teardown/alpha-mira-hq-among-us-mod
- Download date: 2026-10-12 UTC
- Raw archive: ignored `.cache/survival-map-sources/mira-hq.zip`
- Archive SHA-256: `36f3b034af618adba80b1a1cc2697dd74108bcfd59533996c05bff2f7a58385d`
- BFM SHA-256: `55847987c586c867de91beab3da5d3f966d51e2861d70ebc43c30be0463f9ed8`
- Preview SHA-256: `7a576a4d56c97470276963d083625b855da3113d595c34d2c1c5f6a15f31aa60`; code-rendered from the converted map.

No separate redistribution/adaptation license found in source archive or inspected pages. Original author and underlying game rights retained; not repository MIT.

This record attributes the source and records the adaptation; it does not assert an author-granted reuse license. The author/title come from the pinned archive’s `info.txt`, and the Workshop identity from `id.txt`. Minecraft rights belong to Mojang/Microsoft; Among Us rights belong to Innersloth. No affiliation is claimed. The same source rights apply to the geometry-derived preview.

## Geometry changes

- Cafeteria, janitor room, adjoining eastern corridor and balcony are cropped from the actual map.
- The rest of the station is omitted; the elevated station is translated to a local ground plane.
- A continuous foundation fills small floor gaps and creates a narrow exterior apron.
- Overhead geometry is clipped at 55.3 source meters; polygon primitives are omitted, not replaced with invented walls.

Dimensions [66, 20, 88] (X/Y/Z); 0.6 source meters per game block. 2233 original primitives and 868,019 occupied source samples retained before coarsening. 139,672 samples use actual source VOX brush colors. 8 supported emergence sectors share 3864 clear connected floor columns.

No downloaded code is executed. Lua, sounds, animated actors and mission logic are not imported. Source voxagons/polygons are omitted; source materials become opaque destructible colored blocks. Source editor brush phase/offset and PBR are simplified. Derived XML repairs are recorded inside BFM metadata.

## Reproduction

`python tools/prepare_survival_maps.py --download --map mira_hq`

The download helper uses the public page-provided archive URL without retaining signed query parameters, then verifies the pinned SHA-256. A changed archive requires explicit review before the pin is updated. ZIP paths, symlinks, member count and expanded bytes are bounded.

## Source file SHA-256

- `Bleach.vox`: `2d0a24ae2eb4d9e07c76e5067148aacbc7284df6e5089a44e6854ecfd281733d`
- `CounterTexture1Mira.vox`: `e13d1712c4d9b90c9ccef465c45fac9364d890b36c89024373cfd72ea853e811`
- `CounterTexture2Mira.vox`: `bc13a3d40d8363f3f17693db49b1f6a674a674c58000b70bdece1a87929a58b7`
- `Divert.vox`: `001222ec7a932e7882d786982a92b0c79e8604825e9f30110b2299160233d486`
- `Electrical.vox`: `689a8c786585542142c1b7d223a5f812a0251556ea96c2b9238b027e86af0666`
- `Glass.vox`: `2212426ad29c0b2998cc2b8cb6745217d3d8ba39b3ea1af28249c3f24e7685f6`
- `Glass2.vox`: `5651f48f6c3d07f6c22330503197c9a2018092d2ecee35494452790a98520d28`
- `Keypad.vox`: `096083c527927070e6672d10dc0e4db7c1549b8626751529ae66da1feb886489`
- `MiraHqDropShipTank.vox`: `2dfaa046ed9ab13592f1b2317aacd5ef18771f6b4306255eb1ccff9c8248ac76`
- `Snd.lua`: `2befae9f1ddfdad99980335d7f998986d0141589e2407dd111a638465ca49bcf`
- `Sound.ogg`: `37eaab58ab7708771c529a01ecc2cf7db4bf6046e6fc16f2a3d101c28b908717`
- `Spunge.vox`: `6974da6d65efaa194b5acb330d5e89db489ba5bc339b4746e4e3c59686c2d734`
- `TableTextureMira.vox`: `48329b9ca13611eceb71b2f05c3f284c906c2149049bf3fbdec49b214fcf7509`
- `TileTexture2Mira.vox`: `ded13856a75119211b22cd614cc5836cb8f744cfefc46140fee95ab03149cf56`
- `TileTextureMira.vox`: `3e6725dc8ac9a6860284b080d2e78ff78ca1aae97042dce3774d80a4aa51b172`
- `VendingMachMiraA.vox`: `23966327099fc4c7748444efafe0fe85e03b6c761c32053799164104f8b154cd`
- `VendingMachMiraB.vox`: `d518b273fbcd046a57950d681e3e713b5d2b3396c71068f5eb42b3025ddc4420`
- `WoodtextureMira.vox`: `f99679016d034086c002b700e918159919b6e083048ec902131166f33529b2b1`
- `id.txt`: `b7ce8059e5145af648cc58bd972bdbf505a9214ccc6ea44ac3c04faeb6bfd1fc`
- `info.txt`: `c5dceaa9599cd9729c6f0b88270b3af3df1d22172f5ff435e2822a41f10a0ecc`
- `main.xml`: `c7ef9666dd2d611e0fa4cf831071d52c8637493989e0196bb7840ab0e7ad5da2`
- `preview.jpg`: `53be07f62fb7073ac7d9fce8bb48e88de1cfee43a2d2097b0e5cad2fa6ffa2a0`
- `tv.lua`: `91c33db687ac7e2fbe828340b8065b2be18cd7cf67a93cd1ed76a02eff46597d`
- `tv/img1.jpg`: `4cde1aff5bac101ec9bc62ae061ee4c082451ea4df6dfc9e321cb8ca015d318c`
- `tv/img2.jpg`: `5018a8b08fe5a4835e9422b6ad7b23446b9c166a00bb4bea5cfe82b41b98f445`
- `tv/img3.jpg`: `19d570c4ae7d1ee23d182d2b7b6101b1d8dd17c17dc424aa97dced55fd7dfb08`
- `tv/img4.jpg`: `c10b112e949b67372bbfcd7abb56a5ad84a05a6cab891a702a74862cd56c0613`
- `vt.lua`: `376e9dc9a3447681f474b5094436717de33bc7200a1154f8b3f3cdab0df7df20`
- `vt/img1.jpg`: `29d664751ddef093bcaec8f0d5394c11297898d3a105db123ea105eb0e7ffaaa`
- `vt/img2.jpg`: `e536ac85fed2146e6b347c83cb93f3199902903cf9fe2eab4f95812d73e7d5b6`
- `vt/img3.jpg`: `ee71b5c2ed13314e1488f727532e44e1ca466988bc9882ea6e64f7111df827d1`
- `vt/img4.jpg`: `0374a9c5cabc65e3dc621eb7380c9ba0125f8915b54f8b37423b5672b7ddd6ec`
