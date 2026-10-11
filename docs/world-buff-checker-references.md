# World Buff Checker v1: evidence and compatibility

Research date: 2026-10-11. Target: Classic Hardcore 1.15.9, build 70003.

## Blizzard API evidence

The Blizzard UI export [commit 8165d4cd6e48d606369336cc3a7977902310e81e](https://github.com/Gethe/wow-ui-source/commit/8165d4cd6e48d606369336cc3a7977902310e81e) identifies itself as `1.15.9 (70003)`. Gethe hosts an export of Blizzard's client source, rather than a Blizzard-maintained repository.

Its generated [UnitAuraDocumentation.lua](https://github.com/Gethe/wow-ui-source/blob/8165d4cd6e48d606369336cc3a7977902310e81e/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua) declares `C_UnitAuras.GetAuraDataByIndex(unit, index, filter)` with a nullable `AuraData` result. It specifies no fixed maximum index. The related `GetUnitAuraBySpellID` documentation explicitly warns that an invisible unit, including a party member on another map, can produce nil. This supports treating unavailable unit data as unknown, although it is not a completeness guarantee for the index API.

Blizzard's [AuraUtil.lua](https://github.com/Gethe/wow-ui-source/blob/8165d4cd6e48d606369336cc3a7977902310e81e/Interface/AddOns/Blizzard_FrameXMLUtil/AuraUtil.lua) starts indexed searching at 1, increments until nil, and unpacks `auraData.points`. It warns that aura names are localized and nonunique. It also supports slot enumeration with continuation tokens. A defensive local scan limit is therefore an implementation guard: reaching that limit must not prove absence. No universal 32- or 40-aura maximum was established by this source.

## Spell catalog and alias evidence

The author's distribution is [Venomisto's Nova World Buffs](https://www.curseforge.com/wow/addons/nova-world-buffs). Source inspection used [hippuli's explicitly unofficial repackaging](https://github.com/hippuli/NovaWorldBuffs), pinned to `69eb01d1dde27ceba65b9e8bc0e63038fa99bc9e`. This is implementation evidence, not Blizzard certification or a fresh Hardcore observation. No source code was copied into CLM.

The [NWB.spellTypes catalog](https://github.com/hippuli/NovaWorldBuffs/blob/69eb01d1dde27ceba65b9e8bc0e63038fa99bc9e/Modules/DB.lua) defines:

| Buff | Canonical spell ID | Additional supported ID |
| --- | --- | --- |
| Rallying Cry of the Dragonslayer | 22888 | 355363 |
| Spirit of Zandalar | 24425 | 355365 |
| Songflower Serenade | 15366 | None established |
| Fengus' Ferocity | 22817 | None established |
| Mol'dar's Moxie | 22818 | None established |
| Slip'kik's Savvy | 22820 | None established |
| Warchief's Blessing | 16609 | 355366 |
| Sayge: Strength | 23735 | None established |
| Sayge: Agility | 23736 | None established |
| Sayge: Stamina | 23737 | None established |
| Sayge: Spirit | 23738 | None established |
| Sayge: Intelligence | 23766 | None established |
| Sayge: Armor | 23767 | None established |
| Sayge: Damage | 23768 | None established |
| Sayge: Resistance | 23769 | None established |

The three additional IDs are annotated as a 2021 hotfix in that catalog. They are also used outside combat-log dispatch: [NovaWorldBuffs.lua](https://github.com/hippuli/NovaWorldBuffs/blob/69eb01d1dde27ceba65b9e8bc0e63038fa99bc9e/NovaWorldBuffs.lua) binds `spellTypes = NWB.spellTypes`; `syncBuffsWithCurrentDuration()` reads `UnitBuff` spell IDs and resolves them through this table. Accepting these IDs as aliases is supported by the active-aura implementation. Their actual appearance through the modern API in build 70003 still needs an Ingame test. Season-specific buffs and unrelated game-version IDs are not inferred as Hardcore aliases.

## Chronoboon: user-provided direct observations

The following evidence comes from the user's development request, independently of the external references above. The user reports matching structured `points` data with stored buffs and tooltips in Hardcore 1.15.9/build 70003, for storage aura `349981`:

| Field | Interpretation | Evidence status |
| --- | --- | --- |
| points[1] | Fengus remaining seconds | User validated |
| points[2] | Mol'dar remaining seconds | User validated |
| points[3] | Slip'kik remaining seconds | User validated |
| points[4] | Dragonslayer remaining seconds | User validated |
| points[5] | Warchief remaining seconds | User subsequently validated: 3538 seconds and tooltip Warchief's Blessing (59m) on another raid member |
| points[6] | Zandalar remaining seconds | User validated |
| points[7] | Songflower remaining seconds | User validated |
| points[8] | DMF remaining seconds | User validated |
| points[9] | DMF spell ID | 23768 and 23769 observed |

The external API sources do not document this spell-specific positional schema. They cannot establish the spell-specific storage fields or portability to another build; those rely on the direct user observations below. The remaining six DMF variants are catalog-supported; their appearance in stored `points[9]` remains an Ingame test obligation.

## Implementation conclusions

These are conservative project decisions derived from the evidence, not additional API guarantees:

- Enable the positional storage decoder only for Classic 1.15.9/build 70003. Other builds keep concrete active observations but cannot assert storage absence from an unconfirmed schema.
- Validate each field independently. A finite positive value in a validated slot can prove that individual stored buff even when other slots are unavailable. Missing, malformed, or inaccessible values must not become zero.
- Require a recognized DMF spell ID together with positive DMF duration for a concrete stored DMF variant. Preserve disagreement or missing fields as uncertainty.
- Decode positive slot 5 as stored Warchief following the user's follow-up validation. Keep Warchief optional in both v1 profiles; validation of detection does not decide the requirement policy.
- Stored seconds remain frozen; the expiration of the container aura is not an individual stored buff timer.
- Treat connection, visibility, API errors, interrupted enumeration, and schema access as separate completeness concerns. Preserve positive observations even when a unit cannot be fully assessed. Exhausting an index range on an invisible unit does not establish missing buffs.

The requested fixtures are regression examples based on the user's observations. They do not replace real multiplayer checks for distance, visibility, loading transitions, alias IDs, stored DMF variants, or GUI behavior.

## Follow-up direct observations

The user's follow-up positively validates slot 5 on another raid member: 3538 seconds accompanied by a Chronoboon tooltip showing Warchief's Blessing (59m). This supersedes the initial unvalidated status of that slot.

The same follow-up reports an invisible player (VISIBLE=false) with readable Chronoboon aura, relevant points and tooltip. Eight unique players were scanned: five had positive stored-buff evidence; three had no demonstrated Chronoboon. No trustworthy complete negative data was supplied for those three, so the fixture represents them as UNKNOWN.

Visibility never gates aura enumeration or positive detection. It only constrains negative claims. The scanner additionally rechecks visibility and connection after enumeration to avoid treating a unit that became inaccessible during the scan as conclusively missing buffs.
