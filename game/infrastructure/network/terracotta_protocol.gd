class_name TerracottaProtocol
extends RefCounted
## Public Terracotta v0.4.2 room-code and local endpoint formats.
const ALPHABET := "0123456789ABCDEFGHJKLMNPQRSTUVWXYZ"


static func normalize(code: String) -> String:
	return code.strip_edges().to_upper()


static func valid_code(code: String) -> bool:
	if code.length() != 21 or not code.begins_with("U/"): return false
	if code[6] != "-" or code[11] != "-" or code[16] != "-": return false
	var digits := code.substr(2).replace("-", "")
	var remainder := 0
	# Upstream encodes little-endian base 34 with a divisibility-by-seven checksum.
	for index in range(digits.length() - 1, -1, -1):
		var value := ALPHABET.find(digits[index])
		if value < 0: return false
		remainder = (remainder * 34 + value) % 7
	return remainder == 0


static func new_code() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	var digits := ""
	for value: int in bytes: digits += ALPHABET[value % 34]
	for last in 34:
		var candidate := digits.substr(0, 15) + ALPHABET[last]
		var code := "U/%s-%s-%s-%s" % [candidate.substr(0, 4), candidate.substr(4, 4), candidate.substr(8, 4), candidate.substr(12, 4)]
		if valid_code(code): return code
	return ""


static func endpoint(value: String) -> String:
	var pieces := value.split(":")
	if pieces.size() > 2 or pieces[0] != "127.0.0.1": return ""
	var port := 25565
	if pieces.size() == 2:
		if not pieces[1].is_valid_int() or str(int(pieces[1])) != pieces[1]: return ""
		port = int(pieces[1])
	return "127.0.0.1:%d" % port if port > 0 and port <= 65535 else ""
