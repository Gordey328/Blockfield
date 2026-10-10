class_name BlockfieldCompatibility
extends RefCounted
## Increment these explicit identities whenever a wire/rule contract changes.
const BUILD_ID := "blockfield-godot-4.7.2-network-4"
const RULES_ID := "blockfield-source-v0.1.3-authority-4"
static func build_hash() -> PackedByteArray: return BUILD_ID.sha256_buffer()
static func rules_hash() -> PackedByteArray: return RULES_ID.sha256_buffer()
