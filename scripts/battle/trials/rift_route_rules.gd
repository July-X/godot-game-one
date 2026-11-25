extends RefCounted
## Shared route descriptions and authored timing for the two post-draft waves.

const ORIGINAL := "原版航道 · 第二波换边"
const REMIX := "变奏航道 · 第二波同侧，纵列先发"
const REMIX_BUILD_HINT := "第二波同侧，纵列先发 · 中路可绕行"

static func description(remix: bool) -> String:
	return REMIX if remix else ORIGINAL
