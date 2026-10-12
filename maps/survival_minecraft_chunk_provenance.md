# Minecraft · Chunk — source and adaptation

Real downloaded Teardown community map: **Small Minecraft Chunk**, by **The_Wolfian**.

- Author/source page: https://steamcommunity.com/sharedfiles/filedetails/?id=2652603687
- Public download page: https://dlcfun.com/en/teardown/small-minecraft-chunk-mod
- Download date: 2026-10-12 UTC
- Raw archive: ignored `.cache/survival-map-sources/minecraft-2652603687.zip`
- Archive SHA-256: `b2db060c30f373ac78a3d32f27596f56245a34811b27a27e575affedb044b86a`
- BFM SHA-256: `b3b94851bc48b0fc1270f7ceec1f4e9d3ae8128665a375bbcb2221e6ed261db7`
- Preview SHA-256: `96138104a1a251b64945f394dab149ec485fbda2621fd599d58d8900eca4f3c8`; code-rendered from the converted map.

No separate redistribution/adaptation license found in source archive or inspected pages. Original author and underlying game rights retained; not repository MIT.

This record attributes the source and records the adaptation; it does not assert an author-granted reuse license. The author/title come from the pinned archive’s `info.txt`, and the Workshop identity from `id.txt`. Minecraft rights belong to Mojang/Microsoft; Among Us rights belong to Innersloth. No affiliation is claimed. The same source rights apply to the geometry-derived preview.

## Geometry changes

- Original version; only the upper chunk is retained.
- Ground plane, underground stone/cave/mine and plank roof are removed.
- The shaft/farm depressions and map-edge apron are filled to one standing floor.
- Upper tree foliage is cropped at 23.2 source meters; house, farm and tree retain source geometry.

Dimensions [92, 30, 48] (X/Y/Z); 0.4 source meters per game block. 97 original primitives and 1,875,041 occupied source samples retained before coarsening. 1,858,944 samples use actual source VOX brush colors. 8 supported emergence sectors share 2890 clear connected floor columns.

No downloaded code is executed. Lua, sounds, animated actors and mission logic are not imported. Source voxagons/polygons are omitted; source materials become opaque destructible colored blocks. Source editor brush phase/offset and PBR are simplified. Derived XML repairs are recorded inside BFM metadata.

## Reproduction

`python tools/prepare_survival_maps.py --download --map minecraft_chunk`

The download helper uses the public page-provided archive URL without retaining signed query parameters, then verifies the pinned SHA-256. A changed archive requires explicit review before the pin is updated. ZIP paths, symlinks, member count and expanded bytes are bounded.

## Source file SHA-256

- `2652603687/Entitys/Chicken.xml`: `287876365a4a35d1ed9c6c7bd6726e825ae3590916902eb3fbaf8d8cb8616816`
- `2652603687/Entitys/Cow.xml`: `9eae91e3ebf32bff95c3b6c2f7c7e07272b48ab43be64c526cd47fdf21a75a1e`
- `2652603687/Entitys/Pig.xml`: `6fbde42b2c5e3fda7174eb0bd56810ce3e32e5a3c0a983548827cdb114c03253`
- `2652603687/Entitys/Zombie.xml`: `e51ca9da06ac4bbcd9c55ff5a97659651a376135363ad38057e9dad768c6ee79`
- `2652603687/Entitys/chicken.vox`: `1fb34ea0a0dac10284864957b26c4b0b4dfdcd50315026569ad9a7061521d82f`
- `2652603687/Entitys/cow.vox`: `197bfaffbf5f62d0f16dd69890b38375aa5cde68a1e2367c9760294ea19c341b`
- `2652603687/Entitys/pig.vox`: `a32a010045f5c13132d10ec61765e186b85d7244d2dddddb31ea8d5aa19979e4`
- `2652603687/Entitys/zombie.vox`: `ca304c445a63489c7f5c0b2175ae6d1eff29e781ce8418f218a28bea92415aa4`
- `2652603687/Objects/House.xml`: `f3c0d19fde6337129ee67f6e4c7d9524a83df37cd62a94b1600b4784fb2da61e`
- `2652603687/Objects/Tree.xml`: `26f08726d08e01aafa71ae0c4c11eb4867f0e86b74f7a35d2e38cb105e6ae295`
- `2652603687/Objects/mcobjects.vox`: `ad79e3f34e1172c94d12820ce48b08156dd1412aa2993dc7a9962f8a9b9f1979`
- `2652603687/Objects/mcobjects2.vox`: `5e498e39a38a7bc619216233f86697128a83439280c799a38a3d88301cc89f75`
- `2652603687/Objects/minecart.vox`: `d979ebe493cd030526e8488d3678cbea9976bdfde1bcce02ef3933e99713ca03`
- `2652603687/Objects/spawnerblock.vox`: `beb481dbfaa80ea4fc3502515324df48c36205feba65c6b13f63d4e5d6edeecb`
- `2652603687/Objects/tools.vox`: `d5ef15d28e0c29101736ffc2c6bac0e99cb17ada4e0fe1dfac0a8db650fe5f30`
- `2652603687/Scripts/menu.lua`: `8f68b65a5394c1f18aff91c8662a7b99023c7933a5671c4cc1409d3ca63f406e`
- `2652603687/brush/Solid.vox`: `10aeae744db0e8b7c6d9d99289a523f0e67b333d1e42e618e1e8fdf504b8b7ca`
- `2652603687/brush/StoneandOre.vox`: `f0e59e3eb060716ade1a75a6b1158286c18ce6b6ce630afbf07eece39e40e736`
- `2652603687/brush/blocks.vox`: `eb7373e97848a8a5d6c7b6016e301492c5df54c9f1fd6a931b17929b54bb6275`
- `2652603687/default.xml`: `cf3e23ed62749fb64e232655acd002b0ae0e47cfdb66f140d531797be8402afc`
- `2652603687/extended.xml`: `e19bb838dc63febca0470ee4b597edb4dbfae973400811a640a298bcd68542d7`
- `2652603687/id.txt`: `a49ff4556d7e5ed572cd640132c718c3fa30b283e8bf3ad008f2876416e45bab`
- `2652603687/info.txt`: `52cfe3533b53ce75005633bf657382c2b7aff526b2cc7f912c455545bc211ed4`
- `2652603687/main.lua`: `df2aa05dc99b0e53acb90dd0d896b8093be86ef61bb2649d4b6049e353d337f1`
- `2652603687/main.xml`: `a075525a70059ba0bda89b1ac10a5b613d0b8d9ed5c69f47da3a4e62fd89b081`
- `2652603687/original.xml`: `578689d23e0dfa8b23cb878e27340984e90b53cdc1865e47739393626c3b9072`
- `2652603687/preview.jpg`: `bfef6df0c8ea324a20b2e54f67dad9f35e126ede447de970ea52f8ca6f539e47`
