extends RefCounted
## Owner pose envelope: the pose one player's own client simulates and sends. Fixed width, every byte is part of
## the schema. Structural validation grants no authority, ownership or lifetime permissions.
const MAGIC := 0x53505747 # "GWPS", little endian
const VERSION := 2
const BYTES := 248
const KEYS := ["version","seq","reset_epoch","local_tick","time","transform","velocity","grounded","floor_normal","yaw","acceleration","anchor","flop"]
const UNIT_EPS := .00001

static func rigid_unit(value: Variant) -> bool:
	if not value is Transform3D or not value.is_finite(): return false
	var basis: Basis=value.basis
	for axis: Vector3 in [basis.x,basis.y,basis.z]:
		if absf(axis.length_squared()-1.0)>UNIT_EPS: return false
	return absf(basis.x.dot(basis.y))<=UNIT_EPS and absf(basis.x.dot(basis.z))<=UNIT_EPS and absf(basis.y.dot(basis.z))<=UNIT_EPS and absf(basis.determinant()-1.0)<=UNIT_EPS*3.0

static func valid(pose: Dictionary) -> bool:
	if pose.size()!=KEYS.size(): return false
	for key: Variant in pose:
		if not key is String or key not in KEYS: return false
	if not pose.get("version") is int or pose.version!=VERSION: return false
	for key: String in ["seq","reset_epoch","local_tick","flop"]:
		if not pose.get(key) is int: return false
	if pose.seq<1 or pose.reset_epoch<1 or pose.local_tick<0 or pose.flop<0 or pose.flop>255: return false # flop: seconds of dash flop left in 1/100 s (courier_motion.gd)
	if not pose.get("time") is float or not is_finite(pose.time) or pose.time<0.0: return false
	if not pose.get("yaw") is float or not is_finite(pose.yaw): return false
	if not pose.get("grounded") is bool or not rigid_unit(pose.get("transform")): return false
	for key: String in ["velocity","floor_normal","acceleration","anchor"]:
		if not pose.get(key) is Vector3 or not pose[key].is_finite(): return false
	return true

static func _write_vector(data: PackedByteArray, at: int, value: Vector3) -> void:
	data.encode_double(at,value.x)
	data.encode_double(at+8,value.y)
	data.encode_double(at+16,value.z)

static func _read_vector(data: PackedByteArray, at: int) -> Vector3:
	return Vector3(data.decode_double(at),data.decode_double(at+8),data.decode_double(at+16))

static func encode(pose: Dictionary) -> PackedByteArray:
	if not valid(pose): return PackedByteArray()
	var data := PackedByteArray()
	data.resize(BYTES)
	data.fill(0)
	data.encode_u32(0,MAGIC)
	data.encode_u32(4,VERSION)
	data.encode_s64(8,pose.seq)
	data.encode_s64(16,pose.reset_epoch)
	data.encode_s64(24,pose.local_tick)
	data.encode_double(32,pose.time)
	var transform: Transform3D=pose.transform
	_write_vector(data,40,transform.basis.x)
	_write_vector(data,64,transform.basis.y)
	_write_vector(data,88,transform.basis.z)
	_write_vector(data,112,transform.origin)
	_write_vector(data,136,pose.velocity)
	data[160]=1 if pose.grounded else 0
	data[161]=pose.flop
	#162..167 reserved zero.
	_write_vector(data,168,pose.floor_normal)
	data.encode_double(192,pose.yaw)
	_write_vector(data,200,pose.acceleration)
	_write_vector(data,224,pose.anchor) # the point the painting hangs from; the authority has no rig and derives the painting from it
	return data

static func decode(data: PackedByteArray) -> Dictionary:
	if data.size()!=BYTES or data.decode_u32(0)!=MAGIC or data.decode_u32(4)!=VERSION: return {}
	if data[160]>1: return {}
	for at in range(162,168):
		if data[at]!=0: return {}
	# Validate scalar triples before Vector3 casts can narrow them to engine real_t.
	for at in range(32,BYTES,8):
		if at==160: continue
		var value := data.decode_double(at)
		if not is_finite(value): return {}
	var pose := {"version":VERSION,"seq":data.decode_s64(8),"reset_epoch":data.decode_s64(16),"local_tick":data.decode_s64(24),"time":data.decode_double(32),"transform":Transform3D(Basis(_read_vector(data,40),_read_vector(data,64),_read_vector(data,88)),_read_vector(data,112)),"velocity":_read_vector(data,136),"grounded":data[160]==1,"floor_normal":_read_vector(data,168),"yaw":data.decode_double(192),"acceleration":_read_vector(data,200),"anchor":_read_vector(data,224),"flop":data[161]}
	if not valid(pose): return {}
	# Reject noncanonical scalar encodings that narrow differently (vector components outside this engine's real_t).
	if encode(pose)!=data: return {}
	return pose
